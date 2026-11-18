import Foundation

/// Display-only colors for the output panel. When the read carried the terminal's own colors (herdr), each shown
/// row takes the styles of the source row it came from; otherwise the rows are colored by the tool's known layout.
public enum OutputStyling {
    /// Style runs for `shown`, the text the panel displays (filtered and/or cut from `source.text`).
    public static func runs(shown: String, source: ReadOutput) -> [StyledRun] {
        if let runs = source.runs, !runs.isEmpty {
            return mapped(shown: shown, source: source.text, runs: runs)
        }
        return heuristic(shown)
    }

    // MARK: Source colors

    /// A source row as the filters see it (`OutputFilter.lines`), and where its kept characters sit in the raw row.
    struct SourceRow {
        var text: String
        /// UTF-16 offset of the raw row in the source.
        var location: Int
        var rawLength: Int
        /// Kept stretches: raw-row offset, cleaned-row offset, length (UTF-16). Image placeholders fall between them.
        var segments: [(raw: Int, clean: Int, length: Int)]
    }

    static func sourceRow(_ raw: Substring, location: Int) -> SourceRow {
        let text = OutputFilter.lines(String(raw))[0]
        let rawLength = raw.utf16.count
        let isPlaceholder = { (ch: Character) in ch.unicodeScalars.first == OutputFilter.imagePlaceholder }
        guard raw.contains(where: isPlaceholder) else {
            return SourceRow(text: text, location: location, rawLength: rawLength, segments: [(0, 0, rawLength)])
        }
        var segments: [(raw: Int, clean: Int, length: Int)] = []
        var rawOffset = 0
        var cleanOffset = 0
        for ch in raw {
            let length = ch.utf16.count
            defer { rawOffset += length }
            if isPlaceholder(ch) { continue }
            if let last = segments.last, last.raw + last.length == rawOffset {
                segments[segments.count - 1].length += length
            } else {
                segments.append((rawOffset, cleanOffset, length))
            }
            cleanOffset += length
        }
        return SourceRow(text: text, location: location, rawLength: rawLength, segments: segments)
    }

    /// The filters only drop rows and shorten them (trailing blanks, a side panel cut off), keeping their order,
    /// so each shown row is matched to the next source row it equals, or failing that, starts with. A row that
    /// matches nothing (its text was rewritten) stays plain.
    static func mapped(shown: String, source: String, runs: [StyledRun]) -> [StyledRun] {
        let rows = lineRanges(source).map { sourceRow($0.text, location: $0.location) }
        var cursor = 0
        var result: [StyledRun] = []
        var runIndex = 0
        for line in lineRanges(shown) {
            let text = String(line.text)
            let rest = rows[cursor...]
            let match = rest.firstIndex { $0.text == text }
                ?? (text.isEmpty ? nil : rest.firstIndex { $0.text.hasPrefix(text) })
            guard let match else { continue }
            cursor = match + 1
            let row = rows[match]
            let shownLength = (text as NSString).length
            // Runs are sorted: skip the ones that end before this source row.
            while runIndex < runs.count, NSMaxRange(runs[runIndex].range) <= row.location { runIndex += 1 }
            var k = runIndex
            while k < runs.count, runs[k].range.location < row.location + row.rawLength {
                let runStart = runs[k].range.location - row.location
                let runEnd = NSMaxRange(runs[k].range) - row.location
                for segment in row.segments {
                    let start = max(runStart, segment.raw)
                    let end = min(runEnd, segment.raw + segment.length)
                    guard end > start else { continue }
                    let cleanStart = segment.clean + start - segment.raw
                    let cleanEnd = min(segment.clean + end - segment.raw, shownLength)
                    if cleanEnd > cleanStart {
                        result.append(StyledRun(range: NSRange(location: line.location + cleanStart, length: cleanEnd - cleanStart),
                                                style: runs[k].style))
                    }
                }
                k += 1
            }
        }
        return result
    }

    /// Each row with its UTF-16 start offset.
    static func lineRanges(_ text: String) -> [(text: Substring, location: Int)] {
        var result: [(Substring, Int)] = []
        var location = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            result.append((line, location))
            location += line.utf16.count + 1
        }
        return result
    }

    // MARK: Layout colors

    static let red = TermStyle(foreground: .palette(1))
    static let green = TermStyle(foreground: .palette(2))
    static let accent = TermStyle(foreground: .palette(14), bold: true)
    static let bold = TermStyle(bold: true)
    static let muted = TermStyle(dim: true)
    static let code = TermStyle(foreground: .palette(6))

    /// Codex's tool rows: "• Ran git status", "• Explored", "• Edited Sources/App.swift (+3 -1)".
    static let codexToolVerbs: Set<String> = [
        "Ran", "Explored", "Edited", "Added", "Deleted", "Read", "Searched", "Updated", "Called", "Waited", "Listed",
        "Wrote", "Viewed",
    ]

    private static let diffRow = try! NSRegularExpression(pattern: #"^\s+\d+ +([+-])"#)
    private static let toolCall = try! NSRegularExpression(pattern: #"^[⏺●•] ([A-Z][A-Za-z0-9_]*)\("#)
    private static let inlineCode = try! NSRegularExpression(pattern: #"`[^`\n]+`"#)

    private static func isDiffRow(_ row: String) -> Bool {
        diffRow.firstMatch(in: row, range: NSRange(location: 0, length: (row as NSString).length)) != nil
    }

    private static func isOutputMark(_ trimmed: Substring) -> Bool {
        trimmed.hasPrefix("⎿") || trimmed.hasPrefix("└")
    }

    /// The indented block under row `index` starts with a `└` row or holds a numbered diff row.
    private static func hasToolOutput(below index: Int, in lines: [(text: Substring, location: Int)]) -> Bool {
        let block = lines[(index + 1)...]
            .filter { !$0.text.allSatisfy { $0 == " " } }
            .prefix { $0.text.first == " " }
        guard let first = block.first else { return false }
        return isOutputMark(first.text.drop { $0 == " " }) || block.contains { isDiffRow(String($0.text)) }
    }

    /// Colors for Claude Code / Codex / plain markdown rows: the user's prompts, reply bullets and tool names,
    /// tool output (muted) with its numbered diff rows (green / red), errors, headings and backtick code.
    static func heuristic(_ text: String) -> [StyledRun] {
        var runs: [StyledRun] = []
        let lines = lineRanges(text)
        /// Indent of the tool output in progress (a `⎿` / `└` row, or a Codex tool row): deeper rows are part of it.
        var outputIndent: Int?
        for (index, line) in lines.enumerated() {
            let row = String(line.text)
            let ns = row as NSString
            let whole = NSRange(location: 0, length: ns.length)
            func add(_ range: NSRange, _ style: TermStyle) {
                guard range.length > 0 else { return }
                runs.append(StyledRun(range: NSRange(location: line.location + range.location, length: range.length), style: style))
            }
            let indent = row.prefix { $0 == " " }.count
            let trimmed = row.drop { $0 == " " }
            guard !trimmed.isEmpty else { continue }
            if let depth = outputIndent, indent <= depth { outputIndent = nil }

            if outputIndent != nil, let match = diffRow.firstMatch(in: row, range: whole) {
                add(whole, ns.substring(with: match.range(at: 1)) == "+" ? green : red)
                continue
            }
            if indent == 0, let first = trimmed.first, first == "❯" || first == ">" || first == "›",
               trimmed.dropFirst().first == " " {
                add(whole, accent)
                outputIndent = nil
                continue
            }
            if isOutputMark(trimmed) {
                let body = trimmed.dropFirst().drop { $0 == " " }
                add(whole, body.hasPrefix("Error") ? red : muted)
                outputIndent = indent
                continue
            }
            if outputIndent != nil {
                add(whole, muted)
                continue
            }
            if indent == 0, let first = trimmed.first, first == "⏺" || first == "●" || first == "•" {
                let bullet = NSRange(location: 0, length: (String(first) as NSString).length)
                if let match = toolCall.firstMatch(in: row, range: whole) {
                    add(bullet, green)
                    add(match.range(at: 1), bold)
                } else if first == "•", let verb = trimmed.dropFirst(2).split(separator: " ").first,
                          codexToolVerbs.contains(String(verb)), hasToolOutput(below: index, in: lines) {
                    // A reply bullet can start with the same word ("• Updated the README…"): a tool row has its
                    // output (`└`) or a diff right below.
                    add(bullet, green)
                    add(NSRange(location: bullet.length + 1, length: (String(verb) as NSString).length), bold)
                    outputIndent = indent
                    continue
                } else {
                    add(bullet, bold)
                }
            } else if trimmed.hasPrefix("#"), trimmed.drop(while: { $0 == "#" }).first == " ",
                      trimmed.prefix(while: { $0 == "#" }).count <= 6 {
                add(whole, bold)
                continue
            } else if trimmed.hasPrefix("Error:") || trimmed.hasPrefix("error:") || trimmed.hasPrefix("✗") {
                add(whole, red)
                continue
            }
            for match in inlineCode.matches(in: row, range: whole) { add(match.range, code) }
        }
        return runs.sorted { $0.range.location < $1.range.location }
    }
}
