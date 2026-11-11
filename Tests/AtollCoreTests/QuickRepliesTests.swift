import Testing
@testable import AtollCore

@Suite("Quick replies")
struct QuickRepliesTests {
    @Test("trims, drops blanks and duplicates, keeps order")
    func normalize() {
        #expect(QuickReplies.normalize(["  continue ", "", "   ", "yes", "continue", "\nyes\n", "run"]) == ["continue", "yes", "run"])
    }

    @Test("at most five")
    func cap() {
        #expect(QuickReplies.normalize(["a", "b", "c", "d", "e", "f", "g"]) == ["a", "b", "c", "d", "e"])
        // Blanks and duplicates don't use up slots.
        #expect(QuickReplies.normalize(["a", "", "a", "b", "c", "d", "e", "f"]) == ["a", "b", "c", "d", "e"])
    }

    @Test("never saved → defaults; saved empty → stays empty")
    func resolve() {
        #expect(QuickReplies.resolve(stored: nil) == ["繼續", "照你的建議做", "跑測試，失敗就修到通過"])
        #expect(QuickReplies.resolve(stored: []).isEmpty)
        #expect(QuickReplies.resolve(stored: [" x ", "x"]) == ["x"])
    }
}
