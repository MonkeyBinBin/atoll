import Foundation

/// What to answer a permission dialog with, from the list: the key for its plain "Yes" option and the key
/// for its "No" option, read off the options on screen rather than assumed.
/// Only for layouts `WaitingPreview` recognizes; anything unclear gives nil and the user goes to the panel.
/// "Don't ask again" style options are never offered here.
public struct PermissionChoices: Equatable, Sendable {
    public var allowKey: String
    public var denyKey: String

    public init(allowKey: String, denyKey: String) {
        self.allowKey = allowKey
        self.denyKey = denyKey
    }

    /// Nil for a question option, which a permission dialog never has.
    public func key(for choice: PermissionChoice) -> String? {
        switch choice {
        case .allow: allowKey
        case .deny: denyKey
        case .option: nil
        }
    }

    public static func extract(from screen: String, tool: AgentTool, kind: BlockedKind) -> PermissionChoices? {
        guard kind == .permission || kind == .unspecified else { return nil }
        let lines = OutputFilter.dialogLines(screen)
        let anchor: Array<String>.Index?
        switch tool {
        case .claudeCode:
            guard WaitingPreview.claudePermission(lines) != nil else { return nil }
            anchor = lines.lastIndex { WaitingPreview.trimmed($0).hasPrefix("Do you want to") }
        case .codex:
            guard WaitingPreview.codexApproval(lines) != nil else { return nil }
            anchor = lines.lastIndex {
                let text = WaitingPreview.trimmed($0)
                return text.hasPrefix("Would you like to") && text.hasSuffix("?")
            }
        case .generic:
            return nil
        }
        guard let anchor else { return nil }
        let options = Self.options(after: anchor, in: lines)
        guard let allow = options.first(where: { isPlainYes($0.label) }),
              let deny = options.first(where: { isNo($0.label) }),
              allow.key != deny.key else { return nil }
        return PermissionChoices(allowKey: allow.key, denyKey: deny.key)
    }

    struct Option: Equatable {
        var number: Int
        var label: String
        /// The option's own shortcut shown as a trailing "(y)" / "(esc)", else its number.
        var key: String
    }

    /// The numbered options that follow the question; stops at the first other line once options began.
    static func options(after anchor: Int, in lines: [String]) -> [Option] {
        var found: [Option] = []
        for line in lines[(anchor + 1)...] {
            let text = WaitingPreview.trimmed(line)
            if text.isEmpty { continue }
            if let option = option(text) {
                guard option.number == found.count + 1 else { break }
                found.append(option)
            } else if !found.isEmpty {
                break
            }
        }
        return found
    }

    /// "❯ 1. Yes" / "› 3. No, and tell Codex what to do differently (esc)".
    static func option(_ text: String) -> Option? {
        var rest = Substring(text)
        if let first = rest.first, "❯›>".contains(first) { rest = rest.dropFirst().drop { $0 == " " } }
        let digits = rest.prefix { $0.isNumber }
        guard let number = Int(digits), rest.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        let label = rest.dropFirst(digits.count + 2).trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return nil }
        return Option(number: number, label: label, key: hotkey(label) ?? String(number))
    }

    /// A trailing "(y)" or "(esc)"; longer parentheticals are descriptions, not shortcuts.
    static func hotkey(_ label: String) -> String? {
        guard label.hasSuffix(")"), let open = label.lastIndex(of: "(") else { return nil }
        let inner = label[label.index(after: open)..<label.index(before: label.endIndex)].lowercased()
        if inner == "esc" { return "esc" }
        guard inner.count == 1, let char = inner.first, char.isLetter || char.isNumber else { return nil }
        return inner
    }

    static func withoutHotkey(_ label: String) -> String {
        guard hotkey(label) != nil, let open = label.lastIndex(of: "(") else { return label }
        return label[..<open].trimmingCharacters(in: .whitespaces)
    }

    /// Only the one-off approval. "Yes, and always allow…", "Yes, allow all edits during this session" and
    /// the like change future prompts, so they never match.
    static func isPlainYes(_ label: String) -> Bool {
        ["yes", "yes, proceed"].contains(withoutHotkey(label).lowercased())
    }

    static func isNo(_ label: String) -> Bool {
        let text = withoutHotkey(label).lowercased()
        return text == "no" || text.hasPrefix("no,") || text.hasPrefix("no ")
    }
}

/// An answer given from the list without opening the panel: a permission dialog's Allow / Deny, or one
/// option of a question (`QuestionChoices`).
public enum PermissionChoice: Equatable, Sendable {
    case allow, deny
    case option(QuestionChoices.Option)

    public var label: String {
        switch self {
        case .allow: "Allow"
        case .deny: "Deny"
        case .option(let option): option.label
        }
    }
}

/// Answering a permission dialog or question from the list; per agent, for the episode it was pressed in.
public enum PermissionResponseState: Equatable, Sendable {
    case sending(PermissionChoice)
    case sent(PermissionChoice)
    case failed(PermissionChoice, HerdrError)
    /// The agent had already left that dialog (or moved on to a new one): nothing was sent.
    case noLongerWaiting

    public var label: String {
        switch self {
        case .sending(let choice): "\(choice.label)…"
        case .sent(let choice): "\(choice.label) sent"
        case .failed(let choice, _): "\(choice.label) failed"
        case .noLongerWaiting: "No longer waiting"
        }
    }
}
