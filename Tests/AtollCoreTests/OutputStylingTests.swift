import Foundation
import Testing
@testable import AtollCore

@Suite("ANSI parser")
struct ANSIParserTests {
    func styled(_ input: String) -> [(String, TermStyle)] {
        let (text, runs) = ANSIParser.parse(input)
        return runs.map { ((text as NSString).substring(with: $0.range), $0.style) }
    }

    @Test("basic SGR colors and attributes become runs; plain text gets none")
    func basic() {
        let input = "plain \u{1B}[1;31mbold red\u{1B}[0m \u{1B}[2mdim\u{1B}[22m end"
        #expect(ANSIParser.parse(input).text == "plain bold red dim end")
        let runs = styled(input)
        #expect(runs.count == 2)
        #expect(runs[0].0 == "bold red")
        #expect(runs[0].1 == TermStyle(foreground: .palette(1), bold: true))
        #expect(runs[1].0 == "dim")
        #expect(runs[1].1 == TermStyle(dim: true))
    }

    @Test("256-color, truecolor (semicolon and colon forms), bright and background codes")
    func extended() {
        #expect(ANSIParser.applySGR("38;5;208", to: TermStyle()).foreground == .palette(208))
        #expect(ANSIParser.applySGR("38;2;10;20;30", to: TermStyle()).foreground == .rgb(10, 20, 30))
        #expect(ANSIParser.applySGR("38:2::10:20:30", to: TermStyle()).foreground == .rgb(10, 20, 30))
        #expect(ANSIParser.applySGR("48:5:17", to: TermStyle()).background == .palette(17))
        #expect(ANSIParser.applySGR("94", to: TermStyle()).foreground == .palette(12))
        #expect(ANSIParser.applySGR("38;5;208;1", to: TermStyle()) == TermStyle(foreground: .palette(208), bold: true))
        #expect(ANSIParser.applySGR("", to: TermStyle(bold: true)) == TermStyle())
        #expect(ANSIParser.applySGR("39;49", to: TermStyle(foreground: .palette(1), background: .palette(2))) == TermStyle())
    }

    @Test("OSC hyperlinks / titles, cursor moves and carriage returns are dropped; cursor-forward becomes spaces")
    func otherEscapes() {
        let input = "\u{1B}]0;title\u{07}a\u{1B}]8;;https://x.dev\u{1B}\\link\u{1B}]8;;\u{1B}\\\u{1B}[2Cb\u{1B}[?25l\r\u{1B}(Bc"
        #expect(ANSIParser.parse(input).text == "alink  bc")
        #expect(ANSIParser.parse(input).runs.isEmpty)
    }

    @Test("ranges are UTF-16 offsets, a style carries across newlines, and equal neighbours merge")
    func offsets() {
        let input = "你好\u{1B}[32m🙂 ok\nnext\u{1B}[0m\u{1B}[32m\u{1B}[0m tail"
        let (text, runs) = ANSIParser.parse(input)
        #expect(text == "你好🙂 ok\nnext tail")
        #expect(runs == [StyledRun(range: NSRange(location: 2, length: 10), style: TermStyle(foreground: .palette(2)))])
    }
}

@Suite("Output styling")
struct OutputStylingTests {
    func pieces(_ text: String, _ runs: [StyledRun]) -> [(String, TermStyle)] {
        runs.map { ((text as NSString).substring(with: $0.range), $0.style) }
    }

    @Test("source colors follow each shown row through the Messages filter")
    func mappedThroughFilter() {
        let rule = String(repeating: "─", count: 40)
        let raw = [
            "\u{1B}[48;5;237m> fix it   \u{1B}[0m",
            "",
            "\u{1B}[32m⏺\u{1B}[0m \u{1B}[1mBash\u{1B}[0m(ls)",
            "  ⎿  \u{1B}[2mREADME.md\u{1B}[0m",
            rule, "❯ ", rule,
            "\u{1B}[33m  status line\u{1B}[0m",
        ].joined(separator: "\n")
        let (text, runs) = ANSIParser.parse(raw)
        let source = ReadOutput(text: text, how: "history", runs: runs)
        let shown = OutputFilter.messages(text, tool: .claudeCode)
        #expect(shown == "> fix it\n\n⏺ Bash(ls)\n  ⎿  README.md")
        let mapped = pieces(shown, OutputStyling.runs(shown: shown, source: source))
        #expect(mapped.map(\.0) == ["> fix it", "⏺", "Bash", "README.md"])
        #expect(mapped[0].1 == TermStyle(background: .palette(237)))
        #expect(mapped[1].1 == TermStyle(foreground: .palette(2)))
        #expect(mapped[3].1 == TermStyle(dim: true))
    }

    @Test("a row the filter rewrote stays plain; later rows still match")
    func unmatchedRow() {
        let source = ReadOutput(text: "abc\ndef", how: "history", runs: [
            StyledRun(range: NSRange(location: 0, length: 3), style: TermStyle(bold: true)),
            StyledRun(range: NSRange(location: 4, length: 3), style: TermStyle(italic: true)),
        ])
        let mapped = pieces("xyz\ndef", OutputStyling.runs(shown: "xyz\ndef", source: source))
        #expect(mapped.count == 1)
        #expect(mapped[0].0 == "def")
        #expect(mapped[0].1 == TermStyle(italic: true))
    }

    @Test("no source colors: Claude Code rows are colored by layout")
    func heuristicClaude() {
        let shown = [
            "> fix the build",
            "",
            "⏺ I'll check `Package.swift` first.",
            "",
            "⏺ Update(Sources/App.swift)",
            "  ⎿  Updated Sources/App.swift with 1 addition",
            "       12    let a = 1",
            "       13 +  let b = 2",
            "       14 -  let c = 3",
            "",
            "⏺ Done.",
        ].joined(separator: "\n")
        let styled = pieces(shown, OutputStyling.runs(shown: shown, source: ReadOutput(text: shown, how: "history")))
        let byText = Dictionary(styled.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        #expect(byText["> fix the build"] == OutputStyling.accent)
        #expect(byText["`Package.swift`"] == OutputStyling.code)
        #expect(byText["Update"] == OutputStyling.bold)
        #expect(byText["  ⎿  Updated Sources/App.swift with 1 addition"] == OutputStyling.muted)
        #expect(byText["       12    let a = 1"] == OutputStyling.muted)
        #expect(byText["       13 +  let b = 2"] == OutputStyling.green)
        #expect(byText["       14 -  let c = 3"] == OutputStyling.red)
        // The tool output ends at the next top-level row.
        #expect(byText["⏺"] == OutputStyling.bold)
        #expect(byText["⏺ Done."] == nil)
    }

    @Test("no source colors: Codex prompts and tool verbs, headings and errors")
    func heuristicCodex() {
        let shown = "› add tests\n\n• Ran swift test\n  └ Build complete\n# Summary\nError: missing file\n- a list item"
        let styled = pieces(shown, OutputStyling.heuristic(shown))
        #expect(styled.map(\.0) == ["› add tests", "•", "Ran", "  └ Build complete", "# Summary", "Error: missing file"])
    }

    @Test("an image placeholder in a source row is skipped: the colors after it stay on their characters")
    func placeholderRow() {
        let sprite = "\u{10EEEE}\u{0305}\u{0305}\u{10EEEE}\u{0305}\u{030D}"
        let raw = "\u{1B}[1m⏺\u{1B}[0m hi\(sprite) \u{1B}[32mok\u{1B}[0m"
        let (text, runs) = ANSIParser.parse(raw)
        let shown = OutputFilter.messages(text, tool: .generic)
        #expect(shown == "⏺ hi ok")
        let mapped = pieces(shown, OutputStyling.runs(shown: shown, source: ReadOutput(text: text, how: "history", runs: runs)))
        #expect(mapped.map(\.0) == ["⏺", "ok"])
        #expect(mapped[1].1 == TermStyle(foreground: .palette(2)))
    }

    @Test("numbered +/- rows are a diff only inside tool output")
    func diffOnlyInOutput() {
        let shown = "⏺ The sum:\n  2 + 2 = 4\n  3 - optional step"
        #expect(pieces(shown, OutputStyling.heuristic(shown)).map(\.0) == ["⏺"])
    }

    @Test("Codex: a reply bullet starting with a tool verb is not a tool row; an edit with its diff below is")
    func codexToolRows() {
        let reply = "• Updated the README to mention `swift test`.\n  It now covers setup."
        let replyStyled = pieces(reply, OutputStyling.heuristic(reply))
        #expect(replyStyled.map(\.0) == ["•", "`swift test`"])
        #expect(replyStyled[0].1 == OutputStyling.bold)

        let edit = "• Edited Sources/App.swift (+1 -1)\n    12  let a = 1\n    13 -let b = 2\n    13 +let b = 3\n\n• Done."
        let editStyled = pieces(edit, OutputStyling.heuristic(edit))
        let byText = Dictionary(editStyled.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        #expect(byText["Edited"] == OutputStyling.bold)
        #expect(byText["    12  let a = 1"] == OutputStyling.muted)
        #expect(byText["    13 -let b = 2"] == OutputStyling.red)
        #expect(byText["    13 +let b = 3"] == OutputStyling.green)
        #expect(byText["• Done."] == nil)
    }

    @Test("source runs that are present but empty fall back to the layout colors")
    func emptyRunsFallBack() {
        let source = ReadOutput(text: "> hi", how: "history", runs: [])
        #expect(OutputStyling.runs(shown: "> hi", source: source).first?.style == OutputStyling.accent)
    }
}
