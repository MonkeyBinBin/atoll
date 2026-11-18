import AppKit
import AtollCore
import Testing
@testable import Atoll

@Suite("Output rendering")
struct OutputRenderingTests {
    @Test("the bold face keeps the fallback chain, so icons and CJK cells in bold rows stay on the grid")
    func boldKeepsCascade() throws {
        let font = TerminalFont.font(family: "", size: 12)
        let cascade = try #require(font.fontDescriptor.object(forKey: .cascadeList) as? [NSFontDescriptor])
        let bold = TerminalFont.bold(font)
        #expect((bold.fontDescriptor.object(forKey: .cascadeList) as? [NSFontDescriptor])?.count == cascade.count)
        #expect(bold.pointSize == font.pointSize)
    }

    @Test("the shown output is worked out once per read and Messages setting")
    func cache() {
        let cache = RenderedOutputCache()
        let output = ReadOutput(text: "> hi\nplain", how: "history")
        let first = cache.value(output: output, isLoading: false, messagesOnly: false, tool: .generic, app: nil)
        #expect(first.text == "> hi\nplain")
        #expect(first.styles.first?.style == TermStyle(foreground: .palette(14), bold: true))
        #expect(cache.value(output: nil, isLoading: true, messagesOnly: false, tool: .generic, app: nil).text == "Loading…")
        let changed = ReadOutput(text: "next", how: "history")
        #expect(cache.value(output: changed, isLoading: false, messagesOnly: false, tool: .generic, app: nil).text == "next")
    }
}
