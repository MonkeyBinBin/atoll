import Foundation
import Testing
@testable import AtollCore

@Suite("Panel output search")
struct OutputSearchTests {
    func search(_ text: String, _ query: String) -> OutputSearch {
        var search = OutputSearch(text: text)
        search.setQuery(query)
        return search
    }

    func found(_ search: OutputSearch) -> [String] {
        search.matches.map { (search.text as NSString).substring(with: $0) }
    }

    @Test("matches every occurrence, ignoring case, and starts at the newest one")
    func caseInsensitive() {
        let s = search("FAIL a\nok\nfail b\nFaIl c", "fail")
        #expect(found(s) == ["FAIL", "fail", "FaIl"])
        #expect(s.current == 2)
        #expect(s.counter == "3 / 3")
    }

    @Test("no match says so; an empty query shows nothing")
    func noMatchAndEmpty() {
        let none = search("all green", "fail")
        #expect(none.matches.isEmpty)
        #expect(none.current == nil)
        #expect(none.counter == "No matches")
        var cleared = search("fail", "fail")
        cleared.setQuery("")
        #expect(cleared.matches.isEmpty)
        #expect(cleared.current == nil)
        #expect(cleared.counter == nil)
    }

    @Test("next and previous wrap around at either end")
    func wraps() {
        var s = search("x x x", "x")
        #expect(s.current == 2)
        s.step(forward: true)
        #expect(s.current == 0)
        s.step(forward: true)
        #expect(s.counter == "2 / 3")
        s.step(forward: false)
        s.step(forward: false)
        #expect(s.current == 2)
        var none = search("y", "x")
        none.step(forward: true)
        #expect(none.current == nil)
    }

    @Test("refreshed output keeps the query and stays on the same line as it moves")
    func relocatesSameLine() {
        var s = search("a\nfail one\nb\nfail two", "fail")
        s.step(forward: false)
        #expect(s.current == 0)
        // Older lines scrolled off the top and new ones arrived below.
        s.update(text: "fail one\nb\nfail two\nc\nfail three")
        #expect(s.query == "fail")
        #expect(found(s) == ["fail", "fail", "fail"])
        #expect(s.current == 0)
        #expect(s.counter == "1 / 3")
    }

    @Test("when the current line is gone, the nearest match takes over")
    func relocatesNearest() {
        var s = search("a\nfail one\nb\nc\nd\nfail two", "fail")
        s.step(forward: false)
        s.update(text: "a\nfail other\nb\nc\nd\nfail two")
        #expect(s.current == 0)
        s.update(text: "a\nb\nc\nd\nok")
        #expect(s.current == nil)
        #expect(s.counter == "No matches")
        s.update(text: "a\nfail again\nfail last")
        #expect(s.current == 1)
    }

    @Test("among identical lines the one nearest the old position wins, and the occurrence within the line is kept")
    func relocatesDuplicates() {
        var s = search("FAIL\nx\nFAIL x FAIL\ny\nFAIL", "fail")
        // The second FAIL on line 2.
        s.step(forward: false)
        #expect(s.current == 2)
        s.update(text: "new\nFAIL\nx\nFAIL x FAIL\ny\nFAIL")
        #expect(s.current == 2)
        #expect(s.matches[2].location == ("new\nFAIL\nx\nFAIL x " as NSString).length)
        // The last FAIL, a line identical to the first one: stays the last.
        s.step(forward: true)
        s.update(text: "older\nnew\nFAIL\nx\nFAIL x FAIL\ny\nFAIL")
        #expect(s.current == 3)
    }

    @Test("a match on the last line stays put when more output arrives below it")
    func relocatesFromLastLine() {
        var s = search("a\nfail x\nb\nfail y", "fail")
        s.step(forward: false)
        s.step(forward: true)
        #expect(s.current == 1)
        // Two lines scrolled off the top, two arrived below.
        s.update(text: "b\nfail y\nfail z\nfail w")
        #expect(s.current == 0)
    }

    @Test("CRLF line breaks count as one line each")
    func crlf() {
        var s = search("fail a\r\nb\r\nc\r\nfail one\r\nd", "fail")
        #expect(s.current == 1)
        // "fail one" (line 3) is gone: "fail x" on line 3 is nearer than "fail a" on line 0.
        s.update(text: "fail a\r\nb\r\nc\r\nfail x\r\nd")
        #expect(s.current == 1)
    }
}
