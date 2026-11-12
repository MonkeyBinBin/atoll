import Foundation

/// Find in the panel's output: case-insensitive substring matches over the text as shown (already read,
/// never fetched for this). Ranges are UTF-16 (`NSRange`) so the text view can highlight them directly.
/// Lives only in memory while the panel is open.
public struct OutputSearch: Equatable, Sendable {
    public private(set) var query = ""
    public private(set) var text: String
    public private(set) var matches: [NSRange] = []
    /// Index into `matches` of the one to scroll to; nil without matches.
    public private(set) var current: Int?

    public init(text: String = "") {
        self.text = text
    }

    /// A new query starts at the newest match: the bottom of the output is what just happened.
    public mutating func setQuery(_ query: String) {
        guard query != self.query else { return }
        self.query = query
        matches = Self.ranges(of: query, in: text)
        current = matches.isEmpty ? nil : matches.count - 1
    }

    /// The output refreshed (or Messages only flipped): match again, staying on the same line if it is still
    /// there (it may have moved as lines scroll off the top), else on the match nearest where it was.
    public mutating func update(text: String) {
        guard text != self.text else { return }
        let anchor = current.map { Self.places(matches, in: self.text)[$0] }
        self.text = text
        matches = Self.ranges(of: query, in: text)
        guard !matches.isEmpty else {
            current = nil
            return
        }
        guard let anchor else {
            current = matches.count - 1
            return
        }
        let places = Self.places(matches, in: text)
        let distance = { (i: Int) in abs(places[i].line - anchor.line) }
        let same = places.indices.filter { places[$0].lineText == anchor.lineText && places[$0].ordinal == anchor.ordinal }
        current = (same.isEmpty ? Array(places.indices) : same).min { distance($0) < distance($1) }
    }

    /// Where a match sits: its line (index and content) and which occurrence it is on that line.
    private struct Place {
        var line: Int
        var lineText: String
        var ordinal: Int
    }

    private static func places(_ matches: [NSRange], in text: String) -> [Place] {
        let text = text as NSString
        var places: [Place] = []
        // Lines as NSString sees them (\n, \r\n, \r…), walked once from the top.
        var line = 0
        var lineRange = text.lineRange(for: NSRange(location: 0, length: 0))
        for match in matches {
            while NSMaxRange(lineRange) <= match.location, NSMaxRange(lineRange) < text.length {
                lineRange = text.lineRange(for: NSRange(location: NSMaxRange(lineRange), length: 0))
                line += 1
            }
            let ordinal = places.last.map { $0.line == line ? $0.ordinal + 1 : 0 } ?? 0
            // Without its line break: the last line has none until more output arrives.
            let content = text.substring(with: lineRange).trimmingCharacters(in: .newlines)
            places.append(Place(line: line, lineText: content, ordinal: ordinal))
        }
        return places
    }

    /// ↩ / ⇧↩: the next or previous match, wrapping at either end.
    public mutating func step(forward: Bool) {
        guard let current, !matches.isEmpty else { return }
        self.current = (current + (forward ? 1 : -1) + matches.count) % matches.count
    }

    /// "3 / 12", "No matches", or nil while the query is empty.
    public var counter: String? {
        guard !query.isEmpty else { return nil }
        guard let current else { return "No matches" }
        return "\(current + 1) / \(matches.count)"
    }

    static func ranges(of query: String, in text: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let text = text as NSString
        var found: [NSRange] = []
        var start = 0
        while start < text.length {
            let range = text.range(of: query, options: .caseInsensitive, range: NSRange(location: start, length: text.length - start))
            guard range.location != NSNotFound else { break }
            found.append(range)
            start = range.location + max(range.length, 1)
        }
        return found
    }
}
