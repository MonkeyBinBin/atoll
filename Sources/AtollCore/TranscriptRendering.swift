import Foundation

/// Lays a transcript out as panel text with colors, in the shape of Claude Code's own screen: `❯` prompts, `⏺` replies
/// and tool calls, `⎿` tool output; reply markdown is styled and its markers dropped (headings, bold, backticks).
public enum TranscriptRendering {
    public static func render(_ snapshot: TranscriptSnapshot) -> (text: String, runs: [StyledRun]) {
        var out = Builder()
        if snapshot.startsMidway {
            out.line("… earlier messages not shown", OutputStyling.muted)
        }
        // Several calls can run before their results arrive: each result goes under its own call.
        let entries = snapshot.entries
        let callIDs = Set(entries.compactMap { entry -> String? in
            if case .toolCall = entry.kind { return entry.id }
            return nil
        })
        var resultByCall: [String: TranscriptEntry] = [:]
        for entry in entries where entry.kind == .toolResult {
            if let id = entry.id, callIDs.contains(id) { resultByCall[id] = entry }
        }
        var previous: TranscriptEntry.Kind?
        for entry in entries {
            if entry.kind == .toolResult, let id = entry.id, resultByCall[id] != nil { continue }
            let attached = entry.kind == .toolResult || entry.kind == .note
            if previous != nil, !attached { out.line("") }
            switch entry.kind {
            case .user:
                for (index, row) in rows(entry.text).enumerated() {
                    out.line((index == 0 ? "❯ " : "  ") + row, OutputStyling.accent)
                }
            case .assistant:
                markdown(entry.text, into: &out)
            case .toolCall(let name):
                out.text("⏺ ", OutputStyling.green)
                out.text(name, OutputStyling.bold)
                if !entry.text.isEmpty { out.text("(\(entry.text))") }
                out.line("")
                if let id = entry.id, let result = resultByCall[id] { resultRows(result.text, into: &out) }
            case .toolResult, .note:
                resultRows(entry.text, into: &out)
            }
            previous = entry.kind
        }
        return (out.result, out.runs)
    }

    private static func resultRows(_ text: String, into out: inout Builder) {
        for (index, row) in rows(text).enumerated() {
            out.line((index == 0 ? "  ⎿  " : "     ") + row, OutputStyling.muted)
        }
    }

    private static func rows(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    // MARK: Markdown

    /// A reply: `⏺` on its first row, the rest indented under it.
    static func markdown(_ text: String, into out: inout Builder) {
        var inFence = false
        for (index, row) in rows(text).enumerated() {
            out.text(index == 0 ? "⏺ " : "  ", index == 0 ? OutputStyling.bold : nil)
            let trimmed = row.drop { $0 == " " }
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                out.line(row, OutputStyling.muted)
                continue
            }
            if inFence {
                out.line(row, OutputStyling.code)
                continue
            }
            let indent = String(row.prefix { $0 == " " })
            if trimmed.hasPrefix("#"), trimmed.drop(while: { $0 == "#" }).first == " ",
               trimmed.prefix(while: { $0 == "#" }).count <= 6 {
                inline(String(trimmed.drop(while: { $0 == "#" }).dropFirst()), base: OutputStyling.bold, into: &out)
                out.line("")
                continue
            }
            out.text(indent)
            var rest = Substring(trimmed)
            if let marker = OutputStyling.listMarkerLength(trimmed) {
                out.text(String(trimmed.prefix(marker)), OutputStyling.listMarker)
                rest = trimmed.dropFirst(marker)
            } else if trimmed.hasPrefix("> ") {
                out.text("│", OutputStyling.muted)
                rest = trimmed.dropFirst(1)
            } else if trimmed.hasPrefix("|") {
                // A table row: the pipes muted, cells as text.
                for (i, cell) in trimmed.split(separator: "|", omittingEmptySubsequences: false).enumerated() {
                    if i > 0 { out.text("|", OutputStyling.muted) }
                    let isRule = !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
                    if isRule { out.text(String(cell), OutputStyling.muted) } else { inline(String(cell), base: nil, into: &out) }
                }
                out.line("")
                continue
            }
            inline(String(rest), base: nil, into: &out)
            out.line("")
        }
    }

    /// Backtick code (shown without its backticks) and `**bold**` (without its stars); links and file paths
    /// outside code. `base` styles the rest.
    static func inline(_ text: String, base: TermStyle?, into out: inout Builder) {
        var plain = ""
        var spans: [(range: NSRange, style: TermStyle)] = []
        var codeRanges: [NSRange] = []
        var rest = Substring(text)
        func length(_ s: String) -> Int { (s as NSString).length }
        while !rest.isEmpty {
            if rest.hasPrefix("`"), let close = rest.dropFirst().firstIndex(of: "`"), close > rest.index(after: rest.startIndex) {
                let code = String(rest[rest.index(after: rest.startIndex)..<close])
                let range = NSRange(location: length(plain), length: length(code))
                spans.append((range, OutputStyling.code))
                codeRanges.append(range)
                plain += code
                rest = rest[rest.index(after: close)...]
            } else if rest.hasPrefix("**"), let close = rest.dropFirst(2).range(of: "**"),
                      close.lowerBound > rest.index(rest.startIndex, offsetBy: 2) {
                let bold = String(rest[rest.index(rest.startIndex, offsetBy: 2)..<close.lowerBound])
                spans.append((NSRange(location: length(plain), length: length(bold)), OutputStyling.bold))
                plain += bold
                rest = rest[close.upperBound...]
            } else {
                plain.append(rest.removeFirst())
            }
        }
        let whole = NSRange(location: 0, length: length(plain))
        for (regex, style) in [(OutputStyling.url, OutputStyling.link), (OutputStyling.filePath, OutputStyling.path)] {
            for match in regex.matches(in: plain, range: whole)
            where !codeRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                spans.append((match.range, style))
            }
        }
        let start = out.length
        out.text(plain, base)
        for span in spans {
            var style = span.style
            if let base, base.bold { style.bold = true }
            out.style(NSRange(location: start + span.range.location, length: span.range.length), style)
        }
    }

    // MARK: Builder

    struct Builder {
        private var rows: [String] = []
        private var current = ""
        private(set) var runs: [StyledRun] = []
        /// UTF-16 length written so far.
        private(set) var length = 0

        mutating func text(_ s: String, _ style: TermStyle? = nil) {
            let count = (s as NSString).length
            if let style, count > 0 { runs.append(StyledRun(range: NSRange(location: length, length: count), style: style)) }
            current += s
            length += count
        }

        /// Ends the row (after `s`).
        mutating func line(_ s: String, _ style: TermStyle? = nil) {
            text(s, style)
            rows.append(current)
            current = ""
            length += 1
        }

        mutating func style(_ range: NSRange, _ style: TermStyle) {
            guard range.length > 0 else { return }
            runs.append(StyledRun(range: range, style: style))
        }

        var result: String {
            (rows + (current.isEmpty ? [] : [current])).joined(separator: "\n")
        }
    }
}
