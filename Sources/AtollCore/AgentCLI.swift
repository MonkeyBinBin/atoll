import Foundation

/// How a tool takes the launch form's starting task.
public enum TaskPassing: Hashable, Sendable {
    /// `tool <task>` (Claude Code, Codex, templates).
    case lastArgument
    /// `tool <flag> <task>`, for CLIs whose positional argument means something else.
    case flag(String)
    /// The CLI has no way to open an interactive session with a first prompt.
    case unsupported

    /// The argv and task to launch with; an empty task adds nothing.
    public func apply(argv: [String], task: String) -> (argv: [String], task: String) {
        switch self {
        case .lastArgument: (argv, task)
        case .flag(let flag): (task.isEmpty ? argv : argv + [flag], task)
        case .unsupported: (argv, "")
        }
    }
}

/// A coding-agent CLI the launch form offers only when the login shell finds its command. Claude Code and Codex
/// are always offered and aren't listed here.
public struct AgentCLI: Equatable, Sendable {
    public var command: String
    public var title: String
    public var taskPassing: TaskPassing

    public init(command: String, title: String, taskPassing: TaskPassing) {
        self.command = command
        self.title = title
        self.taskPassing = taskPassing
    }

    /// Herdr-integrated CLIs whose command name and first-prompt syntax were checked against their docs.
    /// Atoll has no screen parser for them, so they appear as generic agents.
    public static let catalog: [AgentCLI] = [
        AgentCLI(command: "opencode", title: "OpenCode", taskPassing: .flag("--prompt")),
        AgentCLI(command: "copilot", title: "GitHub Copilot CLI", taskPassing: .flag("-i")),
        AgentCLI(command: "droid", title: "Factory Droid", taskPassing: .lastArgument),
        AgentCLI(command: "qwen", title: "Qwen Code", taskPassing: .flag("-i")),
        AgentCLI(command: "cursor-agent", title: "Cursor Agent", taskPassing: .lastArgument),
        AgentCLI(command: "kimi", title: "Kimi Code CLI", taskPassing: .unsupported),
    ]

    /// The catalog CLI an agent's OSC 7501 `app` word names ("opencode", "copilot-cli" …), if any.
    public static func matching(app: String) -> AgentCLI? {
        let word = app.lowercased()
        return catalog.first { word == $0.command || word.hasPrefix($0.command + "-") }
    }

    static let marker = "ATOLL_FOUND:"

    /// Prints a marked line per command found, so shell init chatter on stdout can't be mistaken for a hit.
    static func detectionScript(_ clis: [AgentCLI]) -> String {
        clis.map { "command -v \($0.command) >/dev/null 2>&1 && printf '\(marker)%s\\n' \($0.command)" }
            .joined(separator: "; ") + "; true"
    }

    /// The CLIs whose command the script reported, in `clis` order.
    static func parseDetected(_ output: String, from clis: [AgentCLI]) -> [AgentCLI] {
        let found = Set(output.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let line = line.trimmingCharacters(in: .whitespaces)
            return line.hasPrefix(marker) ? String(line.dropFirst(marker.count)) : nil
        })
        return clis.filter { found.contains($0.command) }
    }

    /// Asks an interactive login shell — the one launches run in, so nvm/PATH match — which CLIs exist.
    /// nil when the shell fails or doesn't finish within `timeout`.
    static func detect(_ clis: [AgentCLI], shell: String, timeout: TimeInterval) async -> [AgentCLI]? {
        let script = detectionScript(clis)
        let output = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: run(shell, ["-lic", script], timeout: timeout))
            }
        }
        return output.map { parseDetected($0, from: clis) }
    }

    /// Runs a program and returns its stdout, or nil if it can't start or outlives `timeout`. Stdout goes to a
    /// file, not a pipe: a background child of the shell (gitstatusd, a daemon) keeping a pipe open would block
    /// reading it to EOF long after the shell itself exits.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> String? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-detect-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let output = try? FileHandle(forWritingTo: url) else { return nil }
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: url)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return nil }
        guard exited.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        return (try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// Remembers the last detection so the launch form can show installed CLIs at once, refreshing in the background.
public actor AgentCLIDetector {
    public static let shared = AgentCLIDetector()

    private let clis: [AgentCLI]
    private let shell: String
    private let timeout: TimeInterval
    private var running: Task<[AgentCLI]?, Never>?
    /// The last successful detection; nil until one succeeds.
    public private(set) var lastKnown: [AgentCLI]?

    public init(clis: [AgentCLI] = AgentCLI.catalog, shell: String? = nil, timeout: TimeInterval = 5) {
        self.clis = clis
        self.shell = shell ?? CoreRPCAdapter.loginShell()
        self.timeout = timeout
    }

    /// Detects again (joining a detection already running). nil when it failed; `lastKnown` is then kept.
    public func refresh() async -> [AgentCLI]? {
        if let running { return await running.value }
        let task = Task { [clis, shell, timeout] in await AgentCLI.detect(clis, shell: shell, timeout: timeout) }
        running = task
        let result = await task.value
        running = nil
        if let result { lastKnown = result }
        return result
    }
}
