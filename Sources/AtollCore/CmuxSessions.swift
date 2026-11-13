import Darwin
import Foundation

/// Folds cmux `agent.hook.*` and sidebar events into per-session agent state.
///
/// Sessions are keyed by Claude/Codex `session_id`, not surface: processes started from a
/// cmux surface (e.g. a herdr server) inherit its CMUX_SURFACE_ID, so several sessions can
/// report under one surface. Pure and deterministic; the adapter feeds it event JSON.
public struct CmuxSessions: Sendable {
    public struct Session: Equatable, Sendable {
        public var sessionID: String
        public var surfaceID: String
        public var workspaceID: String?
        public var cwd: String
        public var app: String
        public var pid: Int32?
        public var lastHook: String
        /// Tool of the last PreToolUse (AskUserQuestion means a question is open).
        public var lastTool: String?
        /// When the last state-changing hook happened (ms since epoch), from `occurred_at`.
        public var lastHookMs: UInt64?
        public var ended = false
        /// Order of the last update, to pick the newest session of a process.
        public var touched = 0
    }

    public private(set) var bootID: String?
    public private(set) var sessions: [String: Session] = [:]
    /// Workspaces whose sidebar says an agent is waiting for input.
    public private(set) var waitingWorkspaces: Set<String> = []
    private var clock = 0

    public init() {}

    public static let addressPrefix = "cmux:"

    /// Applies one event frame (already JSON-decoded). Frames from another cmux boot reset state.
    public mutating func apply(_ frame: [String: Any]) {
        guard (frame["type"] as? String) == "event", let name = frame["name"] as? String else { return }
        if let boot = frame["boot_id"] as? String, boot != bootID {
            bootID = boot
            sessions = [:]
            waitingWorkspaces = []
        }
        let payload = frame["payload"] as? [String: Any] ?? [:]
        if name.hasPrefix("agent.hook.") {
            applyHook(String(name.dropFirst("agent.hook.".count)), payload: payload, frame: frame)
        } else if name == "sidebar.metadata.updated" {
            applySidebar(payload)
        }
    }

    private mutating func applyHook(_ hook: String, payload: [String: Any], frame: [String: Any]) {
        guard let sessionID = payload["session_id"] as? String,
              let surfaceID = (payload["surface_id"] as? String) ?? (frame["surface_id"] as? String) else { return }
        var session = sessions[sessionID] ?? Session(
            sessionID: sessionID, surfaceID: surfaceID, workspaceID: nil, cwd: "/",
            app: Self.appName(payload["_source"] as? String ?? frame["source"] as? String), pid: nil, lastHook: hook
        )
        session.surfaceID = surfaceID
        if let workspace = (payload["workspace_id"] as? String) ?? (frame["workspace_id"] as? String) { session.workspaceID = workspace }
        if let cwd = payload["cwd"] as? String, !cwd.isEmpty { session.cwd = cwd }
        if let pid = (payload["_ppid"] as? NSNumber)?.int32Value { session.pid = pid }
        switch hook {
        case "SessionEnd":
            session.ended = true
        case "SubagentStart", "SubagentStop", "PreCompact", "Notification", "AskUserQuestion":
            // Sub-agent and housekeeping hooks don't change the main agent's state. Notification
            // follows a PermissionRequest, or is an idle reminder: either way keep the state.
            // cmux's own AskUserQuestion hook repeats the PreToolUse(AskUserQuestion) before it.
            break
        default:
            session.lastHook = hook
            session.lastTool = hook == "PreToolUse" ? payload["tool_name"] as? String : nil
            session.ended = false
            if let occurred = frame["occurred_at"] as? String, let date = Self.parseDate(occurred) {
                session.lastHookMs = UInt64(date.timeIntervalSince1970 * 1000)
            }
        }
        clock += 1
        session.touched = clock
        sessions[sessionID] = session
    }

    /// `set_status` args look like `claude_code Waiting --icon=… --color=… --tab=<workspace uuid>`.
    private mutating func applySidebar(_ payload: [String: Any]) {
        guard (payload["command"] as? String) == "set_status", let args = payload["args"] as? String else { return }
        let tokens = args.split(separator: " ").map(String.init)
        guard tokens.count >= 2, ["claude_code", "codex"].contains(tokens[0]),
              let tab = tokens.first(where: { $0.hasPrefix("--tab=") })?.dropFirst("--tab=".count) else { return }
        if tokens[1] == "Waiting" {
            waitingWorkspaces.insert(String(tab))
        } else {
            waitingWorkspaces.remove(String(tab))
        }
    }

    static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    static func appName(_ source: String?) -> String {
        switch source?.lowercased() {
        case "claude": "claude-code"
        case let other?: other
        case nil: "agent"
        }
    }

    /// The status word a session maps to.
    public func status(of session: Session) -> String {
        switch session.lastHook {
        case "SessionStart": return "idle"
        case "PreToolUse" where session.lastTool == "AskUserQuestion": return "blocked"
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure": return "working"
        case "PermissionRequest": return "blocked"
        case "Stop": return "done"
        default: return "unknown"
        }
    }

    /// The blocked kind, when known.
    public func kind(of session: Session) -> String? {
        if session.lastHook == "PermissionRequest" { return "permission" }
        if session.lastHook == "PreToolUse", session.lastTool == "AskUserQuestion" { return "question" }
        return nil
    }

    /// Live sessions as terminals. `include` drops sessions whose process is gone or belongs
    /// to another backend (herdr CLI, herdr-core).
    public func terminals(include: (Session) -> Bool = { _ in true }) -> [TerminalInfo] {
        // One agent per process: `/clear` starts a new session in the same Claude, which must
        // keep its character, colour and open panel. The newest session of a process wins.
        var newest: [String: Session] = [:]
        for session in sessions.values where !session.ended && include(session) {
            let key = Self.agentKey(session)
            if let existing = newest[key], existing.touched > session.touched { continue }
            newest[key] = session
        }
        return newest.values
            .sorted { Self.agentKey($0) < Self.agentKey($1) }
            .map { session in
                var info = TerminalInfo(
                    address: Self.addressPrefix + Self.agentKey(session),
                    cwd: session.cwd,
                    state: "live",
                    status: CoreStatus(state: status(of: session), app: session.app, kind: kind(of: session)),
                    statusMs: session.lastHookMs,
                    reported: true,
                    labels: ["atoll.cmux.surface": session.surfaceID]
                )
                info.foreground = CoreForeground(pid: session.pid.map(Int.init), cwd: session.cwd)
                return info
            }
    }

    /// Stable per agent process; falls back to the session id when the pid is unknown.
    static func agentKey(_ session: Session) -> String {
        session.pid.map { "pid\($0)" } ?? session.sessionID
    }
}

/// Environment of another process owned by this user (sysctl KERN_PROCARGS2).
public enum ProcessInspector {
    public static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    public static func environment(of pid: Int32) -> [String: String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        // Skip the executable path and its padding NULs.
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        // Skip argv.
        var skipped: Int32 = 0
        while index < size, skipped < argc {
            while index < size, buffer[index] != 0 { index += 1 }
            index += 1
            skipped += 1
        }
        var env: [String: String] = [:]
        while index < size, buffer[index] != 0 {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            if let entry = String(bytes: buffer[start..<index], encoding: .utf8), let eq = entry.firstIndex(of: "=") {
                env[String(entry[..<eq])] = String(entry[entry.index(after: eq)...])
            }
            index += 1
        }
        return env
    }

    /// The process runs inside herdr (CLI/TUI) or herdr-core, which report it themselves.
    public static func belongsToHerdr(_ pid: Int32) -> Bool {
        guard let env = environment(of: pid) else { return false }
        return env["HERDR_PANE_ID"] != nil || env["HC_TERMINAL_ID"] != nil
    }
}
