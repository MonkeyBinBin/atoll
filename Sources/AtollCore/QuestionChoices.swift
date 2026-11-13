import Foundation

/// The options of a Claude Code `AskUserQuestion` prompt, to answer it straight from the list or panel.
/// Read off the screen like `PermissionChoices`; layouts it doesn't recognize give nil and the user answers
/// in the panel as before.
public struct QuestionChoices: Equatable, Sendable {
    public struct Option: Equatable, Sendable {
        public var label: String
        /// The line under the option, when it has one.
        public var detail: String?
        /// What selects it: the option's number, which Claude Code takes as an immediate answer.
        public var key: String

        public init(label: String, detail: String? = nil, key: String) {
            self.label = label
            self.detail = detail
            self.key = key
        }
    }

    public var options: [Option]

    public init(options: [Option]) {
        self.options = options
    }

    /// The free-text rows Claude Code appends to every question.
    static let freeText: Set<String> = ["Type something.", "Type something", "Chat about this"]

    ///  ☐ Header
    ///  Question?
    /// ❯ 1. Label
    ///      Detail
    ///   2. Label
    ///   3. Type something.
    /// ─────
    public static func extract(from screen: String, tool: AgentTool, kind: BlockedKind) -> QuestionChoices? {
        guard tool == .claudeCode, kind == .question || kind == .unspecified else { return nil }
        let lines = OutputFilter.dialogLines(screen)
        guard let header = lines.lastIndex(where: { WaitingPreview.trimmed($0).first.map { "☐☒✔".contains($0) } ?? false })
        else { return nil }
        var options: [Option] = []
        for line in lines[(header + 1)...] {
            let text = WaitingPreview.trimmed(line)
            if text.isEmpty { continue }
            if WaitingPreview.isRule(line, "─") { break }
            if let label = WaitingPreview.numberedOption(text, marker: "❯") {
                if freeText.contains(label) { continue }
                options.append(Option(label: label, key: String(options.count + 1)))
            } else if let last = options.indices.last, options[last].detail == nil {
                options[last].detail = text
            }
        }
        return options.isEmpty ? nil : QuestionChoices(options: options)
    }
}
