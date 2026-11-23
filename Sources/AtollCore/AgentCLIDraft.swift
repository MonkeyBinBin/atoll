import Foundation

/// An agent CLI as the Settings editor holds it: plain text fields, turned into an `AgentCLI` once valid.
public struct AgentCLIDraft: Equatable, Sendable {
    /// How the CLI takes the starting task, as the editor offers it.
    public enum Passing: String, CaseIterable, Sendable {
        case lastArgument, flag, subcommand, unsupported
    }

    public enum Problem: Error, Equatable, Sendable {
        case invalidCommand, reservedCommand, builtInAppWord(String), emptyTitle, invalidFlag, emptySubcommand

        public var message: String {
            switch self {
            case .invalidCommand: "Command: letters, digits, . _ + - only, starting with a letter or digit; not a shell builtin"
            case .reservedCommand: "Names starting with claude or codex are tracked as Claude Code / Codex"
            case .builtInAppWord(let title): "\(title) reports this name; it would take that CLI's agents"
            case .emptyTitle: "Title is empty"
            case .invalidFlag: "Flag: one argument, no spaces (use After arguments for several)"
            case .emptySubcommand: "Arguments before the task are empty"
            }
        }
    }

    public var command = ""
    public var title = ""
    public var passing = Passing.lastArgument {
        // Choosing a passing, even Last argument again, replaces one the editor couldn't show.
        didSet { unshown = nil }
    }
    /// For `.flag`.
    public var flag = ""
    /// For `.subcommand`: arguments before the task, and the arguments used when there's no task;
    /// space-separated.
    public var withTask = ""
    public var withoutTask = ""
    /// Comma- or space-separated.
    public var appWords = ""
    /// Empty: finding the command is enough.
    public var helpSignature = ""
    /// A task passing the editor can't show (`.verbatim`), kept while the picker stays on Last argument.
    private var unshown: TaskPassing?
    /// The catalog command whose definition `followCommand()` filled in, while it still is the command, and the
    /// draft as filled in (to tell whether anything was edited since).
    private var adoptedFrom: String?
    private var adoptedFields: [String]?

    public init() {}

    public init(_ cli: AgentCLI) {
        command = cli.command
        title = cli.title
        switch cli.taskPassing {
        case .lastArgument: passing = .lastArgument
        case .verbatim:
            passing = .lastArgument
            unshown = .verbatim
        case .flag(let flag):
            passing = .flag
            self.flag = flag
        case .arguments(let withTask, let withoutTask):
            passing = .subcommand
            self.withTask = withTask.joined(separator: " ")
            self.withoutTask = withoutTask.joined(separator: " ")
        case .unsupported: passing = .unsupported
        }
        appWords = cli.appWords.joined(separator: ", ")
        helpSignature = cli.helpSignature ?? ""
    }

    /// For a new draft, after each change to the command: one naming a catalog CLI, with nothing else typed yet,
    /// takes that entry's definition, so overriding it starts from the built-in app words and help signature
    /// rather than dropping them. Typing on past it (`pi` → `pixel`) clears what was filled in again, unless
    /// another field was edited meanwhile: then the edits stay and the draft stops following.
    public mutating func followCommand() {
        let typed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if let adoptedFrom, typed.lowercased() != adoptedFrom {
            if fields == adoptedFields {
                self = AgentCLIDraft()
                command = typed
            } else {
                self.adoptedFrom = nil
                adoptedFields = nil
                return
            }
        }
        // Only into an untouched draft: values typed before the command aren't replaced.
        guard adoptedFrom == nil, fields == AgentCLIDraft().fields,
              let entry = AgentCLI.catalog.first(where: { $0.command == typed.lowercased() }) else { return }
        self = AgentCLIDraft(entry)
        command = typed
        adoptedFrom = entry.command
        adoptedFields = fields
    }

    /// Everything but the command.
    private var fields: [String] {
        [title, passing.rawValue, flag, withTask, withoutTask, appWords, helpSignature]
    }

    /// For a command that names a catalog CLI: what the built-in defines that this draft leaves out (app words,
    /// help signature), so the editor can say so before an override drops it. nil when nothing is left out.
    public var builtInLeftOut: String? {
        guard let entry = AgentCLI.catalog.first(where: {
            $0.command == command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }) else { return nil }
        let words = Set(appWords.replacingOccurrences(of: ",", with: " ").split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased() })
        let missing = entry.appWords.filter { !words.contains($0) }
        var parts: [String] = []
        if !missing.isEmpty { parts.append("app words \(missing.joined(separator: ", "))") }
        if let signature = entry.helpSignature,
           helpSignature.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(signature) != .orderedSame {
            parts.append("help signature \"\(signature)\"")
        }
        return parts.isEmpty ? nil : "Built-in \(entry.title) also has " + parts.joined(separator: " and ")
    }

    public var problem: Problem? {
        if case .failure(let problem) = build() { return problem }
        return nil
    }

    public func build() -> Result<AgentCLI, Problem> {
        // Kept as typed (a case-sensitive volume needs it); duplicates are compared without case elsewhere.
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AgentCLI.isValidCommand(command) else { return .failure(.invalidCommand) }
        guard !AgentCLI.isReserved(command) else { return .failure(.reservedCommand) }
        if let owner = AgentCLI.catalogOwningAppWord(command) { return .failure(.builtInAppWord(owner.title)) }
        let title = title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return .failure(.emptyTitle) }
        let taskPassing: TaskPassing
        switch passing {
        case .lastArgument: taskPassing = unshown ?? .lastArgument
        case .flag:
            let flag = flag.trimmingCharacters(in: .whitespaces)
            guard !flag.isEmpty, !flag.contains(where: \.isWhitespace) else { return .failure(.invalidFlag) }
            taskPassing = .flag(flag)
        case .subcommand:
            let withTask = Self.words(withTask)
            guard !withTask.isEmpty else { return .failure(.emptySubcommand) }
            taskPassing = .arguments(withTask: withTask, withoutTask: Self.words(withoutTask))
        case .unsupported: taskPassing = .unsupported
        }
        let signature = helpSignature.trimmingCharacters(in: .whitespaces)
        return .success(AgentCLI(
            command: command, title: title, taskPassing: taskPassing,
            appWords: Self.words(appWords.replacingOccurrences(of: ",", with: " ")).map { $0.lowercased() },
            helpSignature: signature.isEmpty ? nil : signature))
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
