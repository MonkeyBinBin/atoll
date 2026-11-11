import Foundation

/// Why a Needs-you agent is waiting, pulled from its screen for the list: "Bash: rm -rf dist" plus a
/// detail line (the tool's description, Codex's reason, or a question's options).
/// Display only, like `OutputFilter`: never used to infer state. Layouts it doesn't recognize give nil.
public struct WaitingPreview: Equatable, Sendable {
    public var title: String
    public var detail: String?

    /// Each line is cut to this many characters before it is kept in memory.
    public static let maxLineLength = 200

    public init(title: String, detail: String? = nil) {
        self.title = Self.cut(title)
        self.detail = detail.map(Self.cut)
    }

    /// Full text for a tooltip.
    public var help: String { [title, detail].compactMap { $0 }.joined(separator: "\n") }

    public static func extract(from screen: String, tool: AgentTool, kind: BlockedKind) -> WaitingPreview? {
        let lines = OutputFilter.clean(screen).components(separatedBy: "\n")
        switch (tool, kind) {
        case (.claudeCode, .permission): return claudePermission(lines)
        case (.claudeCode, .question): return claudeQuestion(lines)
        case (.claudeCode, .unspecified): return claudePermission(lines) ?? claudeQuestion(lines)
        case (.codex, .permission), (.codex, .unspecified): return codexApproval(lines)
        default: return nil
        }
    }

    // MARK: Claude Code

    /// ─────
    ///  Bash command
    ///  Tip: …                      (optional)
    ///  Create empty hello.txt      (description)
    /// ╌╌╌╌╌
    ///  touch hello.txt
    /// ╌╌╌╌╌
    ///  Do you want to proceed?
    static func claudePermission(_ lines: [String]) -> WaitingPreview? {
        guard let ask = lines.lastIndex(where: { trimmed($0).hasPrefix("Do you want to") }),
              let start = lines[..<ask].lastIndex(where: { isRule($0, "─") }) else { return nil }
        let body = lines[(start + 1)..<ask].filter { !trimmed($0).isEmpty && !trimmed($0).hasPrefix("Tip:") }
        guard let header = body.first.map(trimmed) else { return nil }
        let tool = header.hasSuffix(" command") ? String(header.dropLast(" command".count)) : header
        let rest = Array(body.dropFirst())
        let dashed = rest.indices.filter { isRule(rest[$0], "╌") }
        let content: String?
        let description: [String]
        if dashed.count >= 2 {
            content = rest[(dashed[0] + 1)..<dashed[1]].map(trimmed).first
            description = rest[..<dashed[0]].map(trimmed)
        } else {
            let plain = rest.filter { !isRule($0, "╌") }.map(trimmed)
            content = plain.first
            description = Array(plain.dropFirst().prefix(1))
        }
        guard let content, !content.isEmpty else { return WaitingPreview(title: tool, detail: description.first) }
        return WaitingPreview(title: "\(tool): \(content)", detail: description.first)
    }

    /// ☐ Button color
    ///
    /// Which color do you prefer for the button, red or blue?
    ///
    /// ❯ 1. Red
    ///      Use red for the button.
    ///   2. Blue
    ///   3. Type something.
    static func claudeQuestion(_ lines: [String]) -> WaitingPreview? {
        guard let header = lines.lastIndex(where: { trimmed($0).first.map { "☐☒✔".contains($0) } ?? false }) else { return nil }
        var question: String?
        var options: [String] = []
        for line in lines[(header + 1)...] {
            let text = trimmed(line)
            if text.isEmpty { continue }
            if isRule(line, "─") { break }
            if let option = numberedOption(text, marker: "❯") {
                if option != "Type something." && option != "Chat about this" { options.append(option) }
            } else if question == nil {
                question = text
            }
        }
        guard let question, !options.isEmpty else { return nil }
        return WaitingPreview(title: question, detail: options.joined(separator: " · "))
    }

    // MARK: Codex

    ///   Would you like to run the following command?
    ///   Environment: local
    ///   Reason: …
    ///   $ touch hello2.txt
    /// › 1. Yes, proceed (y)
    static func codexApproval(_ lines: [String]) -> WaitingPreview? {
        guard let ask = lines.lastIndex(where: { trimmed($0).hasPrefix("Would you like to") && trimmed($0).hasSuffix("?") }) else { return nil }
        var reason: String?
        var command: String?
        var other: String?
        for line in lines[(ask + 1)...] {
            let text = trimmed(line)
            if text.isEmpty { continue }
            if numberedOption(text, marker: "›") != nil { break }
            if text.hasPrefix("Reason:") {
                reason = trimmed(String(text.dropFirst("Reason:".count)))
            } else if text.hasPrefix("$ ") {
                command = command ?? String(text.dropFirst(2))
            } else if !text.hasPrefix("Environment:") {
                other = other ?? text
            }
        }
        if let command { return WaitingPreview(title: "Run: \(command)", detail: reason) }
        let asked = trimmed(lines[ask])
        return WaitingPreview(title: other.map { "\(asked) \($0)" } ?? asked, detail: reason)
    }

    // MARK: Helpers

    /// "❯ 1. Red" / "2. Blue" → the label; nil for anything else.
    static func numberedOption(_ text: String, marker: Character) -> String? {
        var rest = Substring(text)
        if rest.first == marker { rest = rest.dropFirst().drop { $0 == " " } }
        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty, rest.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        let label = rest.dropFirst(digits.count + 2).trimmingCharacters(in: .whitespaces)
        return label.isEmpty ? nil : label
    }

    static func isRule(_ line: String, _ glyph: Character) -> Bool {
        let text = trimmed(line)
        return text.count >= 10 && text.allSatisfy { $0 == glyph }
    }

    static func trimmed(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespaces)
    }

    static func cut(_ text: String) -> String {
        text.count > maxLineLength ? String(text.prefix(maxLineLength - 1)) + "…" : text
    }
}
