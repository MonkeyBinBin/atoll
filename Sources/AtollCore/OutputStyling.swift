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

    /// The filters only drop rows and shorten them (trailing blanks, a side panel cut off), keeping their order,
    /// so each shown row is matched to the next source row it equals, or failing that, starts with. A row that
    /// matches nothing (its text was rewritten) stays plain.
    static func mapped(shown: String, source: String, runs: [StyledRun]) -> [StyledRun] {
        let sourceLines = lineRanges(source)
        let sourceTexts = sourceLines.map { trimmedEnd(String($0.text)) }
        var cursor = 0
        var result: [StyledRun] = []
        var runIndex = 0
        for line in lineRanges(shown) {
            let text = String(line.text)
            let match = sourceTexts[cursor...].firstIndex(of: text)
                ?? (text.isEmpty ? nil : sourceTexts[cursor...].firstIndex { $0.hasPrefix(text) })
            guard let match else { continue }
            cursor = match + 1
            let from = sourceLines[match].location
            let length = (text as NSString).length
            // Runs are sorted: skip the ones that end before this source row.
            while runIndex < runs.count, NSMaxRange(runs[runIndex].range) <= from { runIndex += 1 }
            var k = runIndex
            while k < runs.count, runs[k].range.location < from + length {
                let start = max(runs[k].range.location, from)
                let end = min(NSMaxRange(runs[k].range), from + length)
                if end > start {
                    result.append(StyledRun(range: NSRange(location: line.location + start - from, length: end - start),
                                            style: runs[k].style))
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

    private static func trimmedEnd(_ line: String) -> String {
        var s = Substring(line)
        while let last = s.last, last.isWhitespace { s.removeLast() }
        return String(s)
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

    /// Colors for Claude Code / Codex / plain markdown rows: the user's prompts, reply bullets and tool names,
    /// tool output (muted), numbered diff rows (green / red), errors, headings and backtick code.
    static func heuristic(_ text: String) -> [StyledRun] {
        var runs: [StyledRun] = []
        /// Indent of the `⎿` / `└` tool output in progress: deeper rows below it are part of it.
        var outputIndent: Int?
        for line in lineRanges(text) {
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

            if let match = diffRow.firstMatch(in: row, range: whole) {
                add(whole, ns.substring(with: match.range(at: 1)) == "+" ? green : red)
                continue
            }
            if indent == 0, let first = trimmed.first, first == "❯" || first == ">" || first == "›",
               trimmed.dropFirst().first == " " {
                add(whole, accent)
                outputIndent = nil
                continue
            }
            if trimmed.hasPrefix("⎿") || trimmed.hasPrefix("└") {
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
                          codexToolVerbs.contains(String(verb)) {
                    add(bullet, green)
                    add(NSRange(location: bullet.length + 1, length: (String(verb) as NSString).length), bold)
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
