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
    /// Other OSC 7501 `app` words the CLI reports besides its command name.
    public var appWords: [String]
    /// Text `<command> --help` must print for the command to count as this CLI, for command names other
    /// programs also use (`pi`, `vibe` …). nil: finding the command is enough.
    public var helpSignature: String?

    public init(command: String, title: String, taskPassing: TaskPassing, appWords: [String] = [],
                helpSignature: String? = nil) {
        self.command = command
        self.title = title
        self.taskPassing = taskPassing
        self.appWords = appWords
        self.helpSignature = helpSignature
    }

    /// Herdr-integrated CLIs whose command name and first-prompt syntax were checked against their docs.
    /// They appear as generic agents; OutputFilter has a layout for some of them (OpenCode, Antigravity CLI).
    public static let catalog: [AgentCLI] = [
        AgentCLI(command: "opencode", title: "OpenCode", taskPassing: .flag("--prompt")),
        AgentCLI(command: "copilot", title: "GitHub Copilot CLI", taskPassing: .flag("-i")),
        AgentCLI(command: "droid", title: "Factory Droid", taskPassing: .lastArgument),
        AgentCLI(command: "qwen", title: "Qwen Code", taskPassing: .flag("-i")),
        // Cursor's primary command is now `agent`; `cursor-agent` is its compatibility alias and, unlike the
        // generic `agent`, can't be mistaken for another program.
        AgentCLI(command: "cursor-agent", title: "Cursor Agent", taskPassing: .lastArgument, appWords: ["cursor"]),
        AgentCLI(command: "kimi", title: "Kimi Code CLI", taskPassing: .unsupported),
        AgentCLI(command: "agy", title: "Antigravity CLI", taskPassing: .flag("-i"), appWords: ["antigravity"]),
        // A bare positional prompt is one-shot for Gemini (outside a TTY), Cline (yolo mode) and Qoder.
        AgentCLI(command: "gemini", title: "Gemini CLI", taskPassing: .flag("-i")),
        AgentCLI(command: "cline", title: "Cline CLI", taskPassing: .flag("-i")),
        AgentCLI(command: "qodercli", title: "Qoder CLI", taskPassing: .flag("-i"), appWords: ["qoder"]),
        // Kilo's positional argument is the project path. The signatures are from each CLI's help text in its
        // source: Kilo's default command, Vibe's clap `about`, Pi's usage header.
        AgentCLI(command: "kilo", title: "Kilo Code", taskPassing: .flag("--prompt"), helpSignature: "start kilo tui"),
        AgentCLI(command: "auggie", title: "Auggie", taskPassing: .lastArgument),
        AgentCLI(command: "vibe", title: "Mistral Vibe", taskPassing: .lastArgument, helpSignature: "Mistral Vibe"),
        AgentCLI(command: "pi", title: "Pi", taskPassing: .lastArgument, helpSignature: "AI coding assistant"),
    ]

    /// The catalog CLI an agent's OSC 7501 `app` word names ("opencode", "copilot-cli", "antigravity" …), if any.
    public static func matching(app: String) -> AgentCLI? {
        let word = app.lowercased()
        return catalog.first { cli in
            ([cli.command] + cli.appWords).contains { word == $0 || word.hasPrefix($0 + "-") }
        }
    }

    static let marker = "ATOLL_FOUND:"

    /// Prints a marked line per command found, so shell init chatter on stdout can't be mistaken for a hit.
    /// A CLI with a help signature also has to print it; stdin is closed so a same-named program can't wait on it.
    static func detectionScript(_ clis: [AgentCLI]) -> String {
        clis.map { cli in
            var checks = ["command -v \(cli.command) >/dev/null 2>&1"]
            if let signature = cli.helpSignature {
                checks.append("\(cli.command) --help </dev/null 2>&1 | grep -qF \(shellQuoted(signature))")
            }
            return (checks + ["printf '\(marker)%s\\n' \(cli.command)"]).joined(separator: " && ")
        }
        .joined(separator: "; ") + "; true"
    }

    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
