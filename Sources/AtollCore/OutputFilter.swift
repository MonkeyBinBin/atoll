import Foundation

/// Display-only trimming of a terminal screen down to the conversation: drops the tool's
/// input box, status lines and decoration rows (mods). Never used to infer state.
public enum OutputFilter {
    /// Full screen text, with each row's padding and trailing blank rows removed.
    public static func clean(_ text: String) -> String {
        trimTrailingBlankLines(lines(text)).joined(separator: "\n")
    }

    /// Cleaned rows with any side panel cut off: what dialog parsers (`WaitingPreview`, `PermissionChoices`,
    /// `QuestionChoices`) read, so a panel's text never ends up in a label and rules still look like rules.
    static func dialogLines(_ text: String) -> [String] {
        stripSidePanel(trimTrailingBlankLines(lines(text)))
    }

    /// Only the messages, for tools whose layout is known; others are returned cleaned. `app` is the agent's
    /// OSC 7501 word, which tells generic agents with a known layout (OpenCode, Antigravity CLI) apart.
    /// Falls back to the cleaned full screen if filtering would leave nothing.
    public static func messages(_ text: String, tool: AgentTool, app: String? = nil) -> String {
        let all = lines(text)
        var kept: [String]
        switch tool {
        case .claudeCode: kept = claudeMessages(all)
        case .codex: kept = codexMessages(all)
        case .generic: kept = genericMessages(all, app: app) ?? all
        }
        kept = kept.filter { !isDecorationRow($0) }
        kept = trimTrailingBlankLines(kept)
        return kept.contains(where: { !$0.isEmpty }) ? kept.joined(separator: "\n") : clean(text)
    }

    // MARK: Activity fingerprint

    /// A hash of what the agent has put on screen, for "no output for 10m": the input box, status lines,
    /// spinners, statusline art and elapsed-time / token counters are left out first, or the screen would
    /// always look changed. Only the hash is kept; the text is dropped right away.
    public static func activityFingerprint(_ text: String, tool: AgentTool, app: String? = nil) -> Int {
        // FNV-1a: stable across launches, cheap, and nothing but this number is kept.
        var hash: UInt64 = 0xcbf29ce484222325
        for line in activityLines(text, tool: tool, app: app) {
            for byte in line.utf8 {
                hash = (hash ^ UInt64(byte)) &* 0x100000001b3
            }
            hash = (hash ^ 10) &* 0x100000001b3
        }
        return Int(truncatingIfNeeded: hash)
    }

    /// The rows the fingerprint is taken over, counters already blanked.
    static func activityLines(_ text: String, tool: AgentTool, app: String? = nil) -> [String] {
        let all = lines(text)
        var kept: [String]
        switch tool {
        case .claudeCode: kept = withoutToolTitles(claudeMessages(all))
        case .codex: kept = codexMessages(all).filter { !isCodexWorkingRow($0) }
        case .generic:
            kept = isAntigravity(app: app)
                ? antigravityMessages(all).filter { !isAntigravitySpinnerRow($0) }
                : all
        }
        kept = kept.filter { !isDecorationRow($0) && !isBrailleArt($0.trimmingCharacters(in: .whitespaces)) }
        return trimTrailingBlankLines(kept).map(withoutCounters)
    }

    /// Claude Code's tool rows: the title right above the `⎿` output ("Running 1 shell command…") is rewritten
    /// into a summary every couple of minutes while the tool runs; only the output below it is the tool's.
    static func withoutToolTitles(_ lines: [String]) -> [String] {
        lines.indices.compactMap { index in
            let next = index + 1 < lines.count ? lines[index + 1].trimmingCharacters(in: .whitespaces) : ""
            return next.hasPrefix("⎿") ? nil : lines[index]
        }
    }

    /// "• Working (12s • esc to interrupt)" (its bullet may blink off).
    static func isCodexWorkingRow(_ line: String) -> Bool {
        var t = Substring(line.trimmingCharacters(in: .whitespaces))
        if t.first == "•" || t.first == "◦" { t = t.dropFirst().drop { $0 == " " } }
        return t.hasPrefix("Working (")
    }

    /// Elapsed times ("12s", "1m 40s", "1m40s", "250ms") and token counts ("12,345 tokens", "1.2k tokens") tick
    /// on their own, and a running tool row's leading dot blinks ("⏺ Running…" / "  Running…").
    static func withoutCounters(_ line: String) -> String {
        var line = line
        if let first = line.first, first == "⏺" || first == "•" || first == "◦" {
            line = " " + line.dropFirst()
        }
        return line
            .replacingOccurrences(of: #"\d[\d.,]*\s?[kKmM]?\s*tokens\b"#, with: "#", options: .regularExpression)
            .replacingOccurrences(of: #"(?<![\w.])(\d+(\.\d+)?\s?(ms|h|m|s)){1,3}(?![A-Za-z])"#, with: "#", options: .regularExpression)
            // "1m 40s" and "12s" are the same counter.
            .replacingOccurrences(of: #"#(\s+#)+"#, with: "#", options: .regularExpression)
    }

    // MARK: Tool layouts

    /// Claude Code: the prompt box is a pair of full-width `─` rules around `❯`, followed by
    /// status lines. Cut from the upper rule of the last pair.
    static func claudeMessages(_ input: [String]) -> [String] {
        claudeMessagesAboveInput(input) ?? stripBanner(stripSidePanel(input))
    }

    /// The messages above Claude Code's input box, or nil when no input box sits near the bottom.
    static func claudeMessagesAboveInput(_ input: [String]) -> [String]? {
        let lines = stripBanner(stripSidePanel(input))
        let rules = lines.indices.filter { isRule(lines[$0]) }
        guard rules.count >= 2 else { return nil }
        let upper = rules[rules.count - 2]
        // Only treat it as the input box when it sits near the bottom of the screen.
        guard lines.count - upper <= 12 else { return nil }
        var kept = Array(lines[..<upper])
        // Peel the footer zone between the last message and the prompt box, bottom-up,
        // stopping at the first real content line.
        while let last = kept.last, isClaudeFooterRow(last) { kept.removeLast() }
        return kept
    }

    /// Hint phrases Claude Code prints right above its prompt box.
    static let claudeHints = [
        "/clear to save", "esc to interrupt", "update installed", "restart to update", "new task?",
        "? for shortcuts", "ctrl+t to", "ctrl+o to", "ctrl+b to run in background", "shift+tab to cycle",
    ]

    /// Spinner glyphs Claude Code cycles through on its "Thinking…" line.
    static let claudeSpinners: Set<Character> = ["·", "✢", "✳", "✶", "✻", "✽", "*", "∗"]

    static func isClaudeFooterRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || isDecorationRow(line) || isBrailleArt(t) || isBlockArt(t) { return true }
        // Statusline widgets: right-aligned rows ("✎ changed  ↻ turn", "· +1 XP").
        let leading = line.prefix { $0 == " " }.count
        if leading >= 40 { return true }
        // Key hint bars: several "^G editor"-style entries.
        if t.components(separatedBy: "^").count - 1 >= 2 { return true }
        // Token / context breakdowns: several "12.3k" counts on one row.
        if t.range(of: #"(\d+(\.\d+)?k\b.*){3,}"#, options: .regularExpression) != nil { return true }
        if let first = t.unicodeScalars.first, ["📜", "💬", "🧠"].contains(String(first)) { return true }
        // Collapse toggles like "[-]" / "[+]".
        if t.count <= 4, t.hasPrefix("["), t.hasSuffix("]") { return true }
        let lower = t.lowercased()
        if claudeHints.contains(where: { lower.contains($0) }) { return true }
        // "✻ Pondering… (12s · ↑ 1.2k tokens)" and the turn summary "✻ Worked for 7s · done".
        if let first = t.first, claudeSpinners.contains(first),
           t.contains("…") || t.range(of: #" for \d+(m \d+)?s\b"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// Mostly block elements (▀▄█▐▌…): statusline pixel art, not text.
    static func isBlockArt(_ trimmed: String) -> Bool {
        let visible = trimmed.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard visible.count >= 3 else { return false }
        let blocks = visible.filter { (0x2580...0x259F).contains($0.value) }.count
        return Double(blocks) / Double(visible.count) >= 0.5
    }

    /// Claude Code's start banner (logo rows "▐▛███▜▌ Claude Code v…") near the top.
    static func stripBanner(_ lines: [String]) -> [String] {
        var result = lines
        let logo: Set<Character> = ["▐", "▛", "▜", "▝", "▘", "▗", "▖", "▙", "▟", "█", "▀", "▄", "▌"]
        guard let start = result.prefix(10).firstIndex(where: { line in
            line.trimmingCharacters(in: .whitespaces).first.map(logo.contains) ?? false
        }) else { return result }
        // Remove the contiguous banner block (logo rows plus the blank / path rows right after).
        var end = start
        while end < result.count {
            let t = result[end].trimmingCharacters(in: .whitespaces)
            let isLogo = t.first.map(logo.contains) ?? false
            if isLogo || (end > start && (t.isEmpty || t.hasPrefix("~"))) {
                end += 1
                if !isLogo, t.isEmpty { break }
            } else {
                break
            }
        }
        result.removeSubrange(start..<end)
        // Leading blank rows left above the first message.
        while let first = result.first, first.trimmingCharacters(in: .whitespaces).isEmpty { result.removeFirst() }
        return result
    }

    /// Terminal display width of a character (CJK and emoji take two cells).
    static func cellWidth(_ ch: Character) -> Int {
        guard let v = ch.unicodeScalars.first?.value else { return 1 }
        if ch.unicodeScalars.first?.properties.generalCategory == .nonspacingMark { return 0 }
        switch v {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60,
             0xFFE0...0xFFE6, 0x1F300...0x1F64F, 0x1F900...0x1F9FF, 0x1FA70...0x1FAFF, 0x20000...0x3FFFD:
            return 2
        default:
            return 1
        }
    }

    /// A side panel drawn to the right of the conversation: most rows have a `│` at the same
    /// display column in the right part of the screen. Cut every row there.
    static func stripSidePanel(_ lines: [String]) -> [String] {
        var counts: [Int: Int] = [:]
        var rowsWithText = 0
        let width = lines.map { $0.reduce(0) { $0 + cellWidth($1) } }.max() ?? 0
        guard width >= 80 else { return lines }
        for line in lines where !line.isEmpty {
            rowsWithText += 1
            var column = 0
            for ch in line {
                if ch == "│", column >= width * 55 / 100 { counts[column, default: 0] += 1 }
                column += cellWidth(ch)
            }
        }
        // The panel may draw its own right edge on every row too: on a tie the leftmost border wins.
        guard let (border, hits) = counts.max(by: { ($0.value, -$0.key) < ($1.value, -$1.key) }),
              hits * 3 >= rowsWithText else { return lines }
        return cut(lines, at: border)
    }

    /// Every row cut at a display column, trailing blanks dropped.
    static func cut(_ lines: [String], at border: Int) -> [String] {
        lines.map { line in
            var column = 0
            var kept = ""
            for ch in line {
                if column >= border { break }
                kept.append(ch)
                column += cellWidth(ch)
            }
            var trimmed = Substring(kept)
            while let last = trimmed.last, last.isWhitespace || last == "\u{FFFD}" { trimmed.removeLast() }
            return String(trimmed)
        }
    }

    /// Mostly braille pattern characters: spinner / animation art, not text.
    static func isBrailleArt(_ trimmed: String) -> Bool {
        let visible = trimmed.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard !visible.isEmpty else { return false }
        let braille = visible.filter { (0x2800...0x28FF).contains($0.value) }.count
        return Double(braille) / Double(visible.count) >= 0.5
    }

    /// Codex: the input row starts with `›` near the bottom, status lines below it.
    static func codexMessages(_ lines: [String]) -> [String] {
        codexMessagesAboveInput(lines) ?? lines
    }

    /// The messages above Codex's input row, or nil when no input row sits near the bottom.
    static func codexMessagesAboveInput(_ lines: [String]) -> [String]? {
        let nonEmpty = lines.indices.filter { !lines[$0].isEmpty }
        guard let input = nonEmpty.last(where: { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("›") }),
              nonEmpty.filter({ $0 > input }).count <= 6 else { return nil }
        return Array(lines[..<input])
    }

    /// Cuts a line to `limit` characters, ending in "…" when it was longer.
    public static func cut(_ text: String, limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }

    // MARK: Generic agents

    /// The messages of a generic agent whose layout is known from its OSC 7501 word; nil for the rest.
    static func genericMessages(_ lines: [String], app: String?) -> [String]? {
        if isAntigravity(app: app) { return antigravityMessages(lines) }
        if app.flatMap(AgentCLI.matching(app:))?.command == "opencode" { return openCodeMessages(lines) }
        return nil
    }

    // MARK: Antigravity CLI

    /// Antigravity CLI reports `antigravity`; herdr may name it after its command, `agy`. Both are the
    /// catalog entry's words.
    static func isAntigravity(app: String?) -> Bool {
        app.flatMap(AgentCLI.matching(app:))?.command == "agy"
    }

    /// Antigravity CLI: like Claude Code, the input box is a pair of full-width `─` rules around `>` with a status
    /// row below; each sent message also gets a shorter rule above it, which stays. A dialog (permission, file
    /// access) takes the input box's place: then only the status row goes, so the dialog stays readable.
    static func antigravityMessages(_ input: [String]) -> [String] {
        let lines = stripAntigravityBanner(input)
        if let kept = antigravityMessagesAboveInput(lines) { return kept }
        var kept = trimTrailingBlankLines(lines)
        if let last = kept.last, isAntigravityStatusRow(last) { kept.removeLast() }
        return kept
    }

    /// The messages above the input box, or nil when no input box sits at the bottom.
    static func antigravityMessagesAboveInput(_ lines: [String]) -> [String]? {
        let rules = lines.indices.filter { isRule(lines[$0]) }
        guard rules.count >= 2 else { return nil }
        let upper = rules[rules.count - 2], lower = rules[rules.count - 1]
        // A message's own rule is shorter, and its `>` row is followed by a blank row before the reply; the
        // input box's rows (one per typed line) have no blank between its rules. A choice list's highlighted row
        // ("> 1. Yes, run command") is a dialog's, not the input box's.
        let inside = lines[(upper + 1)..<lower]
        guard trimmed(lines[upper]).count == trimmed(lines[lower]).count,
              let first = inside.first, first.hasPrefix(">"), inside.count <= 10,
              first.range(of: #"^>\s+\d+\.\s"#, options: .regularExpression) == nil,
              !inside.contains(where: { trimmed($0).isEmpty }),
              lines[(lower + 1)...].filter({ !trimmed($0).isEmpty }).count <= 3 else { return nil }
        var kept = Array(lines[..<upper])
        peelAntigravityFooter(&kept)
        // A tip: a block of `┃` rows ending in "┃ esc to dismiss" ("┃ Auto is now the default agent mode").
        if let last = kept.last, trimmed(last).hasPrefix("┃"), last.contains("esc to dismiss") {
            while let last = kept.last, trimmed(last).hasPrefix("┃") { kept.removeLast() }
            peelAntigravityFooter(&kept)
        }
        return kept
    }

    /// Rows between the last message and the input box: blank rows and the working spinner ("⡿  Working...").
    /// "⎿  Interrupted · …" is the turn's, and stays.
    static func peelAntigravityFooter(_ rows: inout [String]) {
        while let last = rows.last,
              trimmed(last).isEmpty || isDecorationRow(last) || isAntigravitySpinnerRow(last) { rows.removeLast() }
    }

    /// "⡿  Working..." or "⡿  <what it's thinking about>": a braille spinner leads the row.
    static func isAntigravitySpinnerRow(_ line: String) -> Bool {
        guard let first = trimmed(line).unicodeScalars.first else { return false }
        return (0x2800...0x28FF).contains(first.value)
    }

    /// The row under the input box: "? for shortcuts" / "esc to cancel" on the left, "auto · <model> · <effort>"
    /// right-aligned (alone when the left hint is blank).
    static func isAntigravityStatusRow(_ line: String) -> Bool {
        let t = trimmed(line)
        if t.hasPrefix("? for shortcuts") || t.hasPrefix("esc to ") { return true }
        return line.prefix { $0 == " " }.count >= 20 && t.components(separatedBy: " · ").count >= 2
    }

    /// The start banner and the blank rows after it. Wide, the version, account, model and folder sit beside the
    /// logo ("▄▀▀▄   Antigravity CLI 1.5.13"); narrow (under ~100 columns), they're stacked below it. What sits
    /// above it (the shell's `❯ agy`) isn't the agent's. When the read starts partway into the logo (its first
    /// row scrolled out), the logo rows at the top still go, if a rule (the first message's) follows them.
    static func stripAntigravityBanner(_ lines: [String]) -> [String] {
        let logo: Set<Character> = ["▀", "▄"]
        let isLogo = { (index: Int) in trimmed(lines[index]).first.map(logo.contains) ?? false }
        let isTitle = { (index: Int) -> Bool in
            if isLogo(index) { return lines[index].contains("Antigravity CLI ") }
            guard trimmed(lines[index]).hasPrefix("Antigravity CLI "),
                  let above = lines[..<index].lastIndex(where: { !trimmed($0).isEmpty }) else { return false }
            return isLogo(above)
        }
        var end: Int
        if let title = lines.indices.last(where: isTitle) {
            end = title
            if isLogo(title) {
                while end < lines.count, isLogo(end) { end += 1 }
            } else {
                // Version, account, model, folder: stop at a blank row, or at the first message if none came.
                while end < lines.count, !trimmed(lines[end]).isEmpty, !isRule(lines[end]),
                      !lines[end].hasPrefix(">") { end += 1 }
            }
        } else if let first = lines.firstIndex(where: { !trimmed($0).isEmpty }), isLogo(first) {
            end = first
            while end < lines.count, isLogo(end) { end += 1 }
            let next = lines[end...].firstIndex { !trimmed($0).isEmpty }
            guard let next, isRule(lines[next]) else { return lines }
        } else {
            return lines
        }
        while end < lines.count, trimmed(lines[end]).isEmpty { end += 1 }
        return Array(lines[end...])
    }

    // MARK: OpenCode

    /// OpenCode: an input box of `┃` rows closed by `╹▀▀…` with the status line below it, a sidebar starting at
    /// the column where the status line repeats its first item (`~/repo:branch`), a session tab row on top
    /// ("Title … +") and a "Build · model · 2.4s · 66.7 tok/s" row under each reply.
    static func openCodeMessages(_ lines: [String]) -> [String] {
        guard let boxEnd = lines.lastIndex(where: { trimmed($0).hasPrefix("╹") }) else { return lines }
        let status = lines[(boxEnd + 1)...].first { !trimmed($0).isEmpty }
        var rows = Array(lines[..<boxEnd])
        while let last = rows.last, trimmed(last).hasPrefix("┃") { rows.removeLast() }
        if let status, let column = openCodeSidebarColumn(status) { rows = cut(rows, at: column) }
        if let first = rows.first, first.hasSuffix(" +") { rows.removeFirst() }
        rows = rows.filter { trimmed($0) != "┃" && !isOpenCodeReplyFooter($0) }
        while let first = rows.first, trimmed(first).isEmpty { rows.removeFirst() }
        return rows
    }

    /// The display column of the status line's last item when it repeats the first one; nil when the sidebar is
    /// hidden (narrow window) and the status line doesn't repeat.
    static func openCodeSidebarColumn(_ status: String) -> Int? {
        var items: [(column: Int, text: String)] = []
        var column = 0
        var current = ""
        var start = 0
        var spaces = 0
        for ch in status {
            if ch == " " {
                spaces += 1
            } else {
                if !current.isEmpty, spaces >= 2 {
                    items.append((start, current))
                    current = ""
                }
                if current.isEmpty {
                    start = column
                } else {
                    current += String(repeating: " ", count: spaces)
                }
                current.append(ch)
                spaces = 0
            }
            column += cellWidth(ch)
        }
        if !current.isEmpty { items.append((start, current)) }
        guard items.count >= 2, let first = items.first, let last = items.last, first.text == last.text else { return nil }
        return last.column
    }

    /// "Build · Laguna S 2.1 · 722ms · 4.4 tok/s": the agent, model and timing under a reply.
    static func isOpenCodeReplyFooter(_ line: String) -> Bool {
        let parts = trimmed(line).components(separatedBy: " · ")
        guard parts.count >= 3, let last = parts.last else { return false }
        if last.hasSuffix(" tok/s") { return true }
        return last.range(of: #"^\d+(\.\d+)?(ms|s)$"#, options: .regularExpression) != nil
    }

    private static func trimmed(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespaces)
    }

    /// Kitty graphics' Unicode placeholder: an image cell, with its row / column as combining diacritics.
    static let imagePlaceholder: Unicode.Scalar = "\u{10EEEE}"

    static func lines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            // A placeholder and its diacritics form one Character; images aren't text, so drop them.
            var s = line.contains(where: { $0.unicodeScalars.first == imagePlaceholder })
                ? Substring(line.filter { $0.unicodeScalars.first != imagePlaceholder })
                : Substring(line)
            while let last = s.last, last.isWhitespace { s.removeLast() }
            return String(s)
        }
    }

    static func trimTrailingBlankLines(_ lines: [String]) -> [String] {
        Array(lines.reversed().drop { $0.isEmpty }.reversed())
    }

    /// A full-width horizontal rule (box drawing light/heavy horizontal).
    static func isRule(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.count >= 20 && t.allSatisfy { $0 == "─" || $0 == "━" }
    }

    /// Rows drawn by mods / status bars: they use powerline separators or caps (U+E0B0–U+E0D7).
    static func isDecorationRow(_ line: String) -> Bool {
        line.unicodeScalars.contains { (0xE0B0...0xE0D7).contains($0.value) }
    }
}
