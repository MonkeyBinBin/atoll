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
    /// so shown rows and source rows are aligned as a whole: the order-keeping pairing that scores best, where a row
    /// equal to its source scores more than one its source merely starts with. A row that pairs with nothing (its
    /// text was rewritten) stays plain.
    static func mapped(shown: String, source: String, runs: [StyledRun]) -> [StyledRun] {
        let rows = lineRanges(source).map { sourceRow($0.text, location: $0.location) }
        let lines = lineRanges(shown)
        let pairs = align(lines.map { String($0.text) }, rows.map(\.text))
        var result: [StyledRun] = []
        var runIndex = 0
        for (index, line) in lines.enumerated() {
            guard let match = pairs[index] else { continue }
            let text = String(line.text)
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

    /// How well a shown row fits a source row: equal beats "starts with"; a blank row fits every row (all of them
    /// start with it, and a cut-off side panel leaves no source row blank), so it scores least even when equal,
    /// or a run of blank rows would pair with the empty rows at the bottom instead of their own.
    static func fit(_ shown: String, _ source: String) -> Int {
        if shown.isEmpty { return 1 }
        if shown == source { return 4 }
        return source.hasPrefix(shown) ? 2 : 0
    }

    /// For each shown row, the source row it pairs with: the order-keeping pairing with the best total fit (a
    /// weighted longest common subsequence). Ties go to later source rows, since the shown text is the tail.
    static func align(_ shown: [String], _ source: [String]) -> [Int?] {
        let n = shown.count, m = source.count
        guard n > 0, m > 0 else { return Array(repeating: nil, count: n) }
        var score = [Int](repeating: 0, count: (n + 1) * (m + 1))
        var fits = [Int](repeating: 0, count: n * m)
        func at(_ i: Int, _ j: Int) -> Int { i * (m + 1) + j }
        for i in 1...n {
            for j in 1...m {
                let f = fit(shown[i - 1], source[j - 1])
                fits[(i - 1) * m + j - 1] = f
                var best = max(score[at(i - 1, j)], score[at(i, j - 1)])
                if f > 0 { best = max(best, score[at(i - 1, j - 1)] + f) }
                score[at(i, j)] = best
            }
        }
        var pairs = [Int?](repeating: nil, count: n)
        var i = n, j = m
        while i > 0, j > 0 {
            let f = fits[(i - 1) * m + j - 1]
            if f > 0, score[at(i, j)] == score[at(i - 1, j - 1)] + f {
                pairs[i - 1] = j - 1
                i -= 1
                j -= 1
            } else if score[at(i, j - 1)] >= score[at(i - 1, j)] {
                j -= 1
            } else {
                i -= 1
            }
        }
        return pairs
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
    static let listMarker = TermStyle(foreground: .palette(6))
    static let path = TermStyle(foreground: .palette(4))
    static let link = TermStyle(foreground: .palette(4), underline: true)

    /// Codex's tool rows: "• Ran git status", "• Explored", "• Edited Sources/App.swift (+3 -1)".
    static let codexToolVerbs: Set<String> = [
        "Ran", "Explored", "Edited", "Added", "Deleted", "Read", "Searched", "Updated", "Called", "Waited", "Listed",
        "Wrote", "Viewed",
    ]

    private static let diffRow = try! NSRegularExpression(pattern: #"^\s+\d+ +([+-])"#)
    private static let toolCall = try! NSRegularExpression(pattern: #"^[⏺●•] ([A-Z][A-Za-z0-9_]*)\("#)
    /// Antigravity CLI's tool rows: "● Explored 2 files (…)", "● Ran 9 commands, killed 1 task (…)", "● Ran (go run .)".
    /// A count of files / commands / tasks right after the verb with the `(…)` summary later on the row, or `(`
    /// right after "Ran", tells them from a reply bullet ("● Found 3 issues:", "● Updated 3 files to use the new
    /// API.", "● Updated (and pushed) the branch").
    private static let summaryToolRow = try! NSRegularExpression(
        pattern: #"^● ([A-Z][a-z]+) (?:\d+ (?:files?|commands?|tasks?|patterns?)\b.* \(|(?<=● Ran )\()"#)
    private static let inlineCode = try! NSRegularExpression(pattern: #"`[^`\n]+`"#)
    private static let url = try! NSRegularExpression(pattern: #"https?://[^\s<>()\[\]"'`]+(?<![.,;:!?])"#)
    /// "Sources/App.swift", "~/x/y.md", "./a/b.ts:12:3", or a bare file with a line: "App.swift:12".
    private static let filePath = try! NSRegularExpression(
        pattern: #"(?<![\w/.~-])(?:(?:~|\.{1,2})?/?(?:[\w.-]+/)+[\w.-]+\.[A-Za-z][A-Za-z0-9]*|[\w-]+\.[A-Za-z][A-Za-z0-9]*(?=:\d))(?::\d+(?::\d+)?)?"#)
    private static let boxDrawing = try! NSRegularExpression(pattern: #"[\u2500-\u257F]+"#)

    /// "- ", "* ", "12. ", "3) ": the marker's length, without its space.
    static func listMarkerLength(_ trimmed: Substring) -> Int? {
        if let first = trimmed.first, first == "-" || first == "*", trimmed.dropFirst().first == " " { return 1 }
        let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
        guard (1...3).contains(digits.count) else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard let mark = rest.first, mark == "." || mark == ")", rest.dropFirst().first == " " else { return nil }
        return digits.count + 1
    }

    /// Backtick code, then links and file paths outside it, then table borders.
    private static func inlineRuns(_ row: String, add: (NSRange, TermStyle) -> Void) {
        let whole = NSRange(location: 0, length: (row as NSString).length)
        var taken: [NSRange] = []
        for match in inlineCode.matches(in: row, range: whole) {
            add(match.range, code)
            taken.append(match.range)
        }
        for (range, style) in linkRuns(row, excluding: taken) { add(range, style) }
        for match in boxDrawing.matches(in: row, range: whole) { add(match.range, muted) }
    }

    /// Links, then file paths, in `text` outside `excluding` (code) and not inside each other. Shared with the
    /// transcript's markdown.
    static func linkRuns(_ text: String, excluding: [NSRange]) -> [(NSRange, TermStyle)] {
        let whole = NSRange(location: 0, length: (text as NSString).length)
        var taken = excluding
        var runs: [(NSRange, TermStyle)] = []
        for (regex, style) in [(url, link), (filePath, path)] {
            for match in regex.matches(in: text, range: whole)
            where !taken.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                runs.append((match.range, style))
                taken.append(match.range)
            }
        }
        return runs
    }

    private static func isDiffRow(_ row: String) -> Bool {
        diffRow.firstMatch(in: row, range: NSRange(location: 0, length: (row as NSString).length)) != nil
    }

    /// Claude Code's `⎿` and Codex's `└ ` (a space after it: a tree listing's `└──` is part of a reply).
    private static func isOutputMark(_ trimmed: Substring) -> Bool {
        trimmed.hasPrefix("⎿") || (trimmed.hasPrefix("└") && trimmed.dropFirst().first == " ")
    }

    /// The indented block under row `index` starts with a `└` row or holds a numbered diff row.
    private static func hasToolOutput(below index: Int, in lines: [(text: Substring, location: Int)]) -> Bool {
        var first = true
        for line in lines[(index + 1)...] where !line.text.allSatisfy({ $0 == " " }) {
            guard line.text.first == " " else { return false }
            if first, isOutputMark(line.text.drop { $0 == " " }) { return true }
            if isDiffRow(String(line.text)) { return true }
            first = false
        }
        return false
    }

    /// Antigravity CLI's "○ Thought for 13.3s (…)" / "▸ Thought for 5s, 391 tokens".
    private static func isThoughtRow(_ trimmed: Substring) -> Bool {
        guard let first = trimmed.first, first == "○" || first == "▸" else { return false }
        return trimmed.dropFirst().drop { $0 == " " }.hasPrefix("Thought for ")
    }

    /// Colors for Claude Code / Codex / Antigravity CLI / plain markdown rows: the user's prompts, reply bullets and tool names,
    /// tool output (muted) with its numbered diff rows (green / red), errors, headings, list markers, backtick code,
    /// links, file paths and table borders.
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
            if indent == 0, isThoughtRow(trimmed) {
                add(whole, muted)
                continue
            }
            if indent == 0, let first = trimmed.first, first == "⏺" || first == "●" || first == "•" {
                let bullet = NSRange(location: 0, length: (String(first) as NSString).length)
                if let match = toolCall.firstMatch(in: row, range: whole) ?? summaryToolRow.firstMatch(in: row, range: whole) {
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
            } else if let marker = listMarkerLength(trimmed) {
                add(NSRange(location: indent, length: marker), listMarker)
            } else if indent > 0, trimmed.hasPrefix("• ") {
                add(NSRange(location: indent, length: 1), listMarker)
            }
            inlineRuns(row, add: add)
        }
        return runs.sorted { $0.range.location < $1.range.location }
    }
}
