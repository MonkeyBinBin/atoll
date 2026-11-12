import Foundation

/// The last one or two lines an agent wrote at the end of its turn, pulled from its screen for the list,
/// hover card and bubble when the source gave no `statusMessage`. Display only, like `OutputFilter`;
/// layouts it doesn't recognize, and turns that end on a tool call, give nil.
public struct TurnFinalMessage: Equatable, Sendable {
    /// At most two lines, each cut to `maxLineLength` before it is kept in memory.
    public var lines: [String]

    public static let maxLineLength = WaitingPreview.maxLineLength

    public init(lines: [String]) {
        self.lines = lines.suffix(2).map { OutputFilter.cut($0, limit: Self.maxLineLength) }
    }

    public var text: String { lines.joined(separator: "\n") }

    public static func extract(from screen: String, tool: AgentTool) -> TurnFinalMessage? {
        let all = OutputFilter.lines(screen)
        let block: [String]?
        switch tool {
        // Without the input box at the bottom the screen isn't a settled conversation: don't guess.
        case .claudeCode: block = OutputFilter.claudeMessagesAboveInput(all).flatMap(claudeReply)
        case .codex: block = OutputFilter.codexMessagesAboveInput(all).flatMap(codexReply)
        case .generic: block = nil
        }
        let text = (block ?? []).map(trimmed).filter { !$0.isEmpty }
        return text.isEmpty ? nil : TurnFinalMessage(lines: text)
    }

    // MARK: Claude Code

    /// ❯ the prompt
    /// ⏺ First line of the reply
    ///   more lines…
    /// A last `⏺ Tool(args)` block (with `⎿` output rows) means the turn ended on a tool call.
    static func claudeReply(_ lines: [String]) -> [String]? {
        guard let start = lines.lastIndex(where: { $0.hasPrefix("⏺") || $0.hasPrefix("❯") }),
              lines[start].hasPrefix("⏺") else { return nil }
        let header = trimmed(String(lines[start].dropFirst()))
        let rest = lines[(start + 1)...]
        if header.range(of: #"^[A-Za-z][\w.:-]*\("#, options: .regularExpression) != nil { return nil }
        if rest.contains(where: { trimmed($0).hasPrefix("⎿") }) { return nil }
        return [header] + rest
    }

    // MARK: Codex

    /// Single-word headers of Codex's tool blocks ("• Explored", "• Edited").
    static let codexToolHeaders: Set<String> = ["Explored", "Edited", "Added", "Deleted", "Waited", "Searched", "Read", "Listed"]

    /// › the prompt
    /// • First line of the reply
    ///   more lines…
    ///   └ Tip: …                 (sometimes; not part of the reply)
    ///   Worked for 5s • 2:14 PM
    /// Tool blocks draw their details under `└` / `│` right below the header.
    static func codexReply(_ lines: [String]) -> [String]? {
        var lines = lines.filter { !trimmed($0).hasPrefix("└ Tip:") }
        while let last = lines.last, trimmed(last).isEmpty || isCodexWorkedRow(last) {
            lines.removeLast()
        }
        guard let start = lines.lastIndex(where: { $0.hasPrefix("•") || $0.hasPrefix("›") }),
              lines[start].hasPrefix("•") else { return nil }
        let header = trimmed(String(lines[start].dropFirst()))
        let rest = lines[(start + 1)...]
        if codexToolHeaders.contains(header) || header == "Updated Plan" { return nil }
        if let first = rest.map(trimmed).first(where: { !$0.isEmpty }), first.hasPrefix("└") || first.hasPrefix("│") {
            return nil
        }
        return [header] + rest
    }

    static func trimmed(_ line: String) -> String { line.trimmingCharacters(in: .whitespaces) }

    /// "Worked for 5s • 2:14 PM", sometimes drawn inside a `─` rule.
    static func isCodexWorkedRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: CharacterSet(charactersIn: "─ "))
        return t.hasPrefix("Worked for ")
    }
}
