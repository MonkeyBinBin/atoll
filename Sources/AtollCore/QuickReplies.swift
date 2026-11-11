import Foundation

/// Canned replies shown under the panel's reply box (⌘⇧1–⌘⇧5).
public enum QuickReplies {
    public static let maxCount = 5
    public static let defaults = ["continue", "yes, go ahead", "run the tests"]

    /// Trimmed, non-empty, without duplicates (first wins), at most `maxCount`.
    public static func normalize(_ replies: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for reply in replies {
            let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, seen.insert(text).inserted else { continue }
            result.append(text)
            if result.count == maxCount { break }
        }
        return result
    }

    /// The stored list, or the defaults when nothing was ever saved. An empty saved list stays empty.
    public static func resolve(stored: [String]?) -> [String] {
        stored.map(normalize) ?? defaults
    }
}
