import Foundation

/// What a source knows about an agent's session, to find its transcript: a path or session id the source was told
/// (cmux hooks, herdr's `agent_session`), or the agent process's pid.
public struct SessionHint: Equatable, Sendable {
    public var pid: Int?
    public var sessionID: String?
    public var transcriptPath: String?

    public init(pid: Int? = nil, sessionID: String? = nil, transcriptPath: String? = nil) {
        self.pid = pid
        self.sessionID = sessionID
        self.transcriptPath = transcriptPath
    }

    /// Labels sources set on a terminal for its session.
    public static let idLabel = "atoll.session.id"
    public static let pathLabel = "atoll.session.path"

    public init(labels: [String: String], pid: Int?) {
        self.init(pid: pid, sessionID: labels[Self.idLabel].flatMap { $0.isEmpty ? nil : $0 },
                  transcriptPath: labels[Self.pathLabel].flatMap { $0.isEmpty ? nil : $0 })
    }
}

/// Finds an agent's transcript file from its `SessionHint`. Only certain links are followed: what the agent process
/// itself says (Claude Code's pid session file, the rollout file Codex has open), then what the source was told (a
/// path or session id). Nothing is guessed from the working directory or file times, since two agents can share a
/// working tree and showing another agent's conversation is worse than showing none.
public struct TranscriptLocator: Sendable {
    public let home: URL
    /// When a process started, and the files it has open (tests fake them).
    let processStart: @Sendable (Int) -> Date?
    let openFiles: @Sendable (Int) -> [String]

    public init(home: URL = URL(fileURLWithPath: NSHomeDirectory()),
                processStart: @escaping @Sendable (Int) -> Date? = { ProcessInspector.startTime(Int32($0)) },
                openFiles: @escaping @Sendable (Int) -> [String] = { ProcessInspector.openFiles(Int32($0)) }) {
        self.home = home
        self.processStart = processStart
        self.openFiles = openFiles
    }

    /// Where a transcript may be: a file, or a session id to look up.
    public enum Candidate: Equatable, Sendable {
        case file(URL)
        case id(String)
    }

    /// The first candidate that leads to a file. `byID` looks a session id up (default: `transcript(tool:id:cwd:)`,
    /// which may scan folders; the reader passes a cached one).
    public func locate(tool: AgentTool, hint: SessionHint, cwd: String, byID: ((String) -> URL?)? = nil) -> URL? {
        let lookup = byID ?? { transcript(tool: tool, id: $0, cwd: cwd) }
        for candidate in candidates(tool: tool, hint: hint, cwd: cwd) {
            switch candidate {
            case .file(let url): return url
            case .id(let id): if let url = lookup(id) { return url }
            }
        }
        return nil
    }

    /// Candidates in order of how current they are. The process's own record, when there is one, is the only candidate:
    /// Claude Code rewrites its pid session file on `/clear` (the new session's file appears with its first message, and
    /// until then there is nothing to show, not the old one), Codex has its current rollout open. Otherwise what the
    /// source was told, which can be stale (reported once, at start) or not the tool's own (cmux reports `cmux-…` ids
    /// for sessions it restored). Cheap; re-read on every refresh.
    public func candidates(tool: AgentTool, hint: SessionHint, cwd: String) -> [Candidate] {
        var list: [Candidate] = []
        switch tool {
        case .claudeCode:
            if let pid = hint.pid, let id = claudeSessionID(pid: pid) { return [.id(id)] }
        case .codex:
            if let url = openTranscript(tool: tool, hint: hint) { return [.file(url)] }
        case .generic:
            return []
        }
        if let url = explicitPath(hint) { list.append(.file(url)) }
        if let id = hint.sessionID, !list.contains(.id(id)) { list.append(.id(id)) }
        return list
    }

    /// Codex keeps its rollout file open while it runs: the agent process's own open file.
    func openTranscript(tool: AgentTool, hint: SessionHint) -> URL? {
        guard tool == .codex, let pid = hint.pid else { return nil }
        let root = (home.appendingPathComponent(".codex/sessions").path as NSString).standardizingPath + "/"
        let path = openFiles(pid).first { path in
            let normalized = (path as NSString).standardizingPath
            return normalized.hasPrefix(root) && (normalized as NSString).lastPathComponent.hasPrefix("rollout-")
                && normalized.hasSuffix(".jsonl")
        }
        return path.map { URL(fileURLWithPath: $0) }
    }

    /// A path the source was told, when it is a transcript that exists.
    func explicitPath(_ hint: SessionHint) -> URL? {
        guard let path = hint.transcriptPath, path.hasSuffix(".jsonl"), FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// The transcript of a session id; may scan folders, so callers cache it. Claude Code and Codex session ids are
    /// UUIDs; anything else (cmux's own `cmux-…` ids) is never a transcript's name, so no folder is scanned for it.
    func transcript(tool: AgentTool, id: String, cwd: String) -> URL? {
        guard UUID(uuidString: id) != nil else { return nil }
        return switch tool {
        case .claudeCode: claudeTranscript(id: id, cwd: cwd)
        case .codex: codexTranscript(id: id)
        case .generic: nil
        }
    }

    // MARK: Claude Code

    var claudeProjects: URL { home.appendingPathComponent(".claude/projects") }

    /// Claude Code keeps `~/.claude/sessions/<pid>.json` with the process's current session id. The file must belong
    /// to this process, not an earlier one with a reused pid: its `startedAt` within a short while of the process's
    /// start (measured 0.3–1.6 s apart).
    func claudeSessionID(pid: Int) -> String? {
        let url = home.appendingPathComponent(".claude/sessions/\(pid).json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["sessionId"] as? String, !id.isEmpty else { return nil }
        // A running process's start time can always be read: none means it is gone, and its file is stale.
        guard let started = (object["startedAt"] as? NSNumber)?.doubleValue, let processStart = processStart(pid) else { return nil }
        return abs(started / 1000 - processStart.timeIntervalSince1970) <= 30 ? id : nil
    }

    /// `~/.claude/projects/<cwd with every non-alphanumeric as "-">/<id>.jsonl`: one check, cheap enough for every poll.
    func directTranscript(tool: AgentTool, id: String, cwd: String) -> URL? {
        guard tool == .claudeCode, UUID(uuidString: id) != nil else { return nil }
        let direct = claudeProjects.appendingPathComponent(Self.claudeFolder(cwd)).appendingPathComponent("\(id).jsonl")
        return FileManager.default.fileExists(atPath: direct.path) ? direct : nil
    }

    /// The cwd's project folder, else any project folder holding `<id>.jsonl`.
    func claudeTranscript(id: String, cwd: String) -> URL? {
        guard Self.isSafeName(id) else { return nil }
        let fm = FileManager.default
        if let direct = directTranscript(tool: .claudeCode, id: id, cwd: cwd) { return direct }
        guard let folders = try? fm.contentsOfDirectory(atPath: claudeProjects.path) else { return nil }
        for folder in folders {
            let candidate = claudeProjects.appendingPathComponent(folder).appendingPathComponent("\(id).jsonl")
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    static func claudeFolder(_ cwd: String) -> String {
        String(cwd.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        })
    }

    // MARK: Codex

    /// `~/.codex/sessions/YYYY/MM/DD/rollout-<time>-<id>.jsonl`, newest days first.
    func codexTranscript(id: String) -> URL? {
        guard Self.isSafeName(id) else { return nil }
        let fm = FileManager.default
        let root = home.appendingPathComponent(".codex/sessions")
        let suffix = "-\(id).jsonl"
        func children(_ url: URL) -> [String] {
            ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted(by: >)
        }
        for year in children(root) {
            for month in children(root.appendingPathComponent(year)) {
                for day in children(root.appendingPathComponent(year).appendingPathComponent(month)) {
                    let folder = root.appendingPathComponent(year).appendingPathComponent(month).appendingPathComponent(day)
                    if let name = children(folder).first(where: { $0.hasSuffix(suffix) }) {
                        return folder.appendingPathComponent(name)
                    }
                }
            }
        }
        return nil
    }

    // MARK: Helpers

    /// Session ids are uuids or similar: never a path.
    static func isSafeName(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128 && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}
