import Testing
@testable import AtollCore

@Suite("Output filter: OpenCode")
struct OpenCodeOutputTests {
    /// A row with each text placed at a display column, like OpenCode's two-pane layout.
    func row(_ pieces: (Int, String)...) -> String {
        var line = ""
        var column = 0
        for (at, text) in pieces {
            line += String(repeating: " ", count: max(0, at - column)) + text
            column = at + text.reduce(0) { $0 + OutputFilter.cellWidth($1) }
        }
        return line
    }

    var screen: String {
        [
            row((3, "Project overview"), (33, "• Other session +")),
            "",
            row((2, "┃"), (60, "Project overview")),
            row((2, "┃"), (5, "Read Package.swift and say what it builds."), (60, "Context")),
            row((2, "┃")),
            row((60, "16,364 tokens")),
            row((5, "→ Explored: 2 reads"), (60, "2% used")),
            row((5, "一個 macOS 動態島，顯示本機 coding agent 的狀態"), (60, "MCP")),
            row((5, "via Herdr."), (60, "• context7"), (75, "Connected")),
            "",
            row((5, "Build · Laguna S 2.1 · 2.4s · 66.7 tok/s")),
            "", "", "",
            row((2, "┃")),
            row((2, "┃"), (5, "Build · Laguna S 2.1 · high")),
            row((2, "╹" + String(repeating: "▀", count: 50))),
            row((2, "~/Projects/atoll:main"), (28, "16.4K (2%)  ctrl+p commands"), (60, "~/Projects/atoll:main")),
        ].joined(separator: "\n")
    }

    @Test func keepsOnlyTheConversation() {
        #expect(OutputFilter.messages(screen, tool: .generic, app: "opencode") == """
          ┃  Read Package.swift and say what it builds.

             → Explored: 2 reads
             一個 macOS 動態島，顯示本機 coding agent 的狀態
             via Herdr.
        """)
    }

    @Test func otherGenericAgentsAreLeftAlone() {
        #expect(OutputFilter.messages(screen, tool: .generic, app: "droid") == OutputFilter.clean(screen))
        #expect(OutputFilter.messages(screen, tool: .generic) == OutputFilter.clean(screen))
    }

    @Test func noSidebarWhenTheStatusLineDoesntRepeat() {
        #expect(OutputFilter.openCodeSidebarColumn("  ~/Projects/atoll:main     16.4K (2%)  ctrl+p commands") == nil)
        #expect(OutputFilter.openCodeSidebarColumn(row((2, "~/a:main"), (30, "ctrl+p commands"), (50, "~/a:main"))) == 50)
    }

    @Test func replyFooter() {
        #expect(OutputFilter.isOpenCodeReplyFooter("     Build · Laguna S 2.1 · 722ms · 4.4 tok/s"))
        #expect(OutputFilter.isOpenCodeReplyFooter("Plan · gpt-5 · 12s"))
        #expect(!OutputFilter.isOpenCodeReplyFooter("Build · Laguna S 2.1 · high"))
        #expect(!OutputFilter.isOpenCodeReplyFooter("a · b · c"))
    }
}
