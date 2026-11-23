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
    /// Text `<command> --help` must print (any case) for the command to count as this CLI, for command names
    /// other programs also use (`pi`, `vibe` …). nil: finding the command is enough.
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
        // source: Kilo's default command ("start kilo tui"), Vibe's clap `about`, Pi's usage header.
        AgentCLI(command: "kilo", title: "Kilo Code", taskPassing: .flag("--prompt"), helpSignature: "kilo tui"),
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
    static let pathMarker = "ATOLL_PATH:"

    /// Prints a marked line per command found, with where it resolves, then the shell's PATH last, so shell init
    /// chatter on stdout can't be mistaken for a hit and a script cut short is told apart from one that found
    /// nothing. No variables or `$(…)`, so fish runs it as well as POSIX shells; `printenv` gives PATH
    /// colon-separated in fish too. Each marker starts on a new line in case init chatter left one open.
    static func detectionScript(_ clis: [AgentCLI]) -> String {
        (clis.map { "command -v \($0.command) >/dev/null 2>&1 && printf '\\n\(marker)%s\\t' \($0.command) && command -v \($0.command)" }
            + ["printf '\\n\(pathMarker)'; printenv PATH; true"])
            .joined(separator: "; ")
    }

    struct Found: Equatable {
        /// The CLIs whose command the script reported, in `clis` order.
        var clis: [AgentCLI]
        /// Where each found command resolves (`command -v`: a path, or an alias/function's definition).
        var locations: [String: String]
        /// The login shell's PATH; nil when the script didn't get to its end.
        var searchPath: String?
    }

    static func parseFound(_ output: String, from clis: [AgentCLI]) -> Found {
        var locations: [String: String] = [:]
        var searchPath: String?
        for line in output.split(whereSeparator: \.isNewline) {
            if let range = line.range(of: marker) {
                let fields = line[range.upperBound...].split(separator: "\t", maxSplits: 1)
                guard let command = fields.first else { continue }
                locations[String(command)] = fields.count > 1 ? fields[1].trimmingCharacters(in: .whitespaces) : ""
            } else if let range = line.range(of: pathMarker) {
                searchPath = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return Found(clis: clis.filter { locations[$0.command] != nil }, locations: locations, searchPath: searchPath)
    }

    /// The CLIs whose command the script reported, in `clis` order.
    static func parseDetected(_ output: String, from clis: [AgentCLI]) -> [AgentCLI] {
        parseFound(output, from: clis).clis
    }

    /// Whether help text names the CLI: the signature anywhere in it, ignoring case.
    static func helpMatches(_ help: String, signature: String) -> Bool {
        help.range(of: signature, options: .caseInsensitive) != nil
    }

    /// Asks an interactive login shell — the one launches run in, so nvm/PATH match — which CLIs exist.
    /// nil when the shell fails, doesn't finish within `timeout`, or stops before the end of the script.
    ///
    /// A found CLI with a help signature then has its `--help` run (stdin closed, the shell's PATH so a
    /// `#!/usr/bin/env node` script finds node), all at once, each limited to `helpTimeout`; a detection can
    /// therefore take up to `timeout + helpTimeout` plus `ProcessRunner.terminationGrace`. Only help that
    /// finished without the signature drops a CLI: one that timed out or couldn't start is kept, and an alias
    /// or function (which can't run outside the shell) is trusted. This runs whatever program has that name;
    /// `helpChecks` remembers each outcome per executable so it runs once per binary.
    static func detect(_ clis: [AgentCLI], shell: String, timeout: TimeInterval, helpTimeout: TimeInterval = 3,
                       helpChecks: HelpCheckCache = HelpCheckCache()) async -> [AgentCLI]? {
        guard let output = try? await ProcessRunner.run(shell, ["-lic", detectionScript(clis)], timeout: timeout) else { return nil }
        let found = parseFound(output.stdoutText, from: clis)
        guard let searchPath = found.searchPath else { return nil }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath
        let mismatched = await withTaskGroup(of: String?.self) { group in
            for cli in found.clis {
                guard let signature = cli.helpSignature,
                      let location = found.locations[cli.command], location.hasPrefix("/") else { continue }
                group.addTask { [environment] in
                    let check = await helpChecks.check(location) {
                        guard let help = try? await ProcessRunner.run(location, ["--help"], environment: environment,
                                                                      timeout: helpTimeout) else { return .unknown }
                        return helpMatches(help.stdoutText + help.stderrText, signature: signature) ? .matched : .mismatched
                    }
                    return check == .mismatched ? cli.command : nil
                }
            }
            var mismatched: Set<String> = []
            for await command in group { if let command { mismatched.insert(command) } }
            return mismatched
        }
        return found.clis.filter { !mismatched.contains($0.command) }
    }
}

/// What a CLI's `--help` said about its help signature.
enum HelpCheck: Sendable, Equatable {
    case matched, mismatched
    /// Timed out or couldn't start: no evidence either way.
    case unknown
}

/// Help check outcomes per executable (resolved path and modification date), so detection runs a program's
/// `--help` once rather than on every refresh — also bounding what a timed-out check can leave running.
public actor HelpCheckCache {
    private var outcomes: [String: HelpCheck] = [:]

    public init() {}

    func check(_ path: String, run: @Sendable () async -> HelpCheck) async -> HelpCheck {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let modified = (try? FileManager.default.attributesOfItem(atPath: resolved)[.modificationDate] as? Date)
            .map { String($0.timeIntervalSince1970) } ?? "?"
        let key = resolved + "@" + modified
        if let known = outcomes[key] { return known }
        let outcome = await run()
        outcomes[key] = outcome
        return outcome
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
        let helpChecks = HelpCheckCache()
        self.detect = detect ?? { clis in
            await AgentCLI.detect(clis, shell: shell, timeout: timeout, helpChecks: helpChecks)
        }
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
