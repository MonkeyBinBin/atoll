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
        guard let output = try? await ProcessRunner.run(shell, ["-lic", detectionScript(clis)], timeout: timeout) else { return nil }
        return parseDetected(output.stdoutText, from: clis)
    }
}

/// Remembers the last detection so the launch form can show installed CLIs at once, refreshing in the background.
public actor AgentCLIDetector {
    public typealias Detect = @Sendable ([AgentCLI]) async -> [AgentCLI]?

    private let clis: [AgentCLI]
    private let detect: Detect
    private let onDetected: @Sendable ([String]) -> Void
    private var running: Task<[AgentCLI]?, Never>?
    /// The last successful detection; nil until one succeeds.
    public private(set) var lastKnown: [AgentCLI]?

    /// `saved`: the commands a previous launch of the app detected, shown until the first refresh.
    /// `onDetected` gets the commands whenever a successful detection differs from `lastKnown`, for the app to save.
    /// `detect` replaces the login-shell detection (tests).
    public init(clis: [AgentCLI] = AgentCLI.catalog, saved: [String]? = nil,
                onDetected: @escaping @Sendable ([String]) -> Void = { _ in },
                shell: String? = nil, timeout: TimeInterval = 5, detect: Detect? = nil) {
        self.clis = clis
        self.onDetected = onDetected
        let shell = shell ?? ProcessRunner.loginShell()
        self.detect = detect ?? { clis in await AgentCLI.detect(clis, shell: shell, timeout: timeout) }
        lastKnown = saved.map { commands in clis.filter { commands.contains($0.command) } }
    }

    /// Detects again (joining a detection already running). nil when it failed; `lastKnown` is then kept.
    public func refresh() async -> [AgentCLI]? {
        if let running { return await running.value }
        let task = Task { [clis, detect] in await detect(clis) }
        running = task
        let result = await task.value
        running = nil
        if let result, result != lastKnown {
            lastKnown = result
            onDetected(result.map(\.command))
        }
        return result
    }
}
