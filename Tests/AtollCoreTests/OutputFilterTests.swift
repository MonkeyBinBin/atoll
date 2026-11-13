import Testing
@testable import AtollCore

@Suite("Output filter")
struct OutputFilterTests {
    let rule = String(repeating: "─", count: 120)
    let pad = String(repeating: "\u{00A0}", count: 80)

    var claudeScreen: String {
        [
            "❯ /review",
            "",
            "● Looking at the MR now.",
            "  - head is unchanged",
            "",
            "\u{F13D}  \u{E0B6} \u{F017} 16s \u{E0B4} \u{E0B6} $1.36 \u{E0B4}",
            pad,
            "\u{E0B6} ^G \u{F044} editor \u{E0B4} \u{E0B6} ^S stash \u{E0B4}",
            pad,
            rule,
            "❯\u{00A0}",
            rule,
            "  Opus 5.5 medium │ \u{F07B} project │ context ●●○○○",
            "  ⏵⏵ auto mode on (shift+tab to cycle)",
        ].joined(separator: "\n")
    }

    @Test("Claude Code: keeps the conversation, drops the input box, status lines and mod rows")
    func claude() {
        #expect(OutputFilter.messages(claudeScreen, tool: .claudeCode) == """
        ❯ /review

        ● Looking at the MR now.
          - head is unchanged
        """)
    }

    @Test("Claude Code: idle hint rows above the prompt box are dropped")
    func claudeIdleHints() {
        let screen = [
            "● Done, waiting on the author.",
            "",
            "[-]",
            "",
            "new task? /clear to save 191.9k tokens · ✔ Update installed · Restart to update",
            pad,
            rule, "❯\u{00A0}", rule,
            "  status",
        ].joined(separator: "\n")
        #expect(OutputFilter.messages(screen, tool: .claudeCode) == "● Done, waiting on the author.")
    }

    @Test("Claude Code: working spinner, braille animation and key-hint rows are dropped")
    func claudeWorkingFooter() {
        let screen = [
            "● Reading the schema.",
            "",
            "✻ Pondering… (12s · ↑ 1.2k tokens · esc to interrupt)",
            "",
            "⢀⠐⠀⠀⢀⣀⣏⣁⠀⠀⠀⠀     ⢠⠞⠛⠉⠉⠳⡄",
            "⣠⢀⣤⣶⠾⣿⡿⢿⣶⠶⣤⡀ ⠤⠤⠤⣤⠏  \u{E0B6} \u{F017}  20s \u{E0B4}",
            "⠙⠈⠛⠿⠶⠿⠷⠾⠿⠶⠛⠁                               ⠈⠳",
            pad,
            "\u{E0B6} esc \u{F04D} stop \u{E0B4} \u{E0B6} ^B bg \u{E0B4}",
            rule, "❯ ", rule,
        ].joined(separator: "\n")
        #expect(OutputFilter.messages(screen, tool: .claudeCode) == "● Reading the schema.")
    }

    /// Kitty graphics placeholders (U+10EEEE plus row/column diacritics) that a statusline mod draws its sprite
    /// with; cmux's read-screen returns them as text (ticket 54).
    static let sprite = "\u{10EEEE}\u{0305}\u{0305}\u{10EEEE}\u{0305}\u{030D}\u{10EEEE}\u{0305}\u{030E}"

    @Test("image placeholders are removed, so a spinner row drawn after a sprite is still dropped")
    func imagePlaceholders() {
        let screen = [
            "● 你選了飯，那午餐就吃飯。\(Self.sprite)",
            "",
            "\(Self.sprite) ✳ 🏹 Loosing arrows… (running Stop hooks… 8/9 · 8s · ↓ 249 tokens · thinking)",
            rule, "❯ ", rule,
        ].joined(separator: "\n")
        #expect(OutputFilter.messages(screen, tool: .claudeCode) == "● 你選了飯，那午餐就吃飯。")
        #expect(!OutputFilter.clean(screen).unicodeScalars.contains { $0.value == 0x10EEEE })
    }

    @Test("Claude Code: hint-like text inside the conversation is kept")
    func claudeKeepsMidConversationText() {
        let screen = [
            "❯ what does /clear to save do?",
            "● It clears the context.",
            rule, "❯ ", rule,
        ].joined(separator: "\n")
        #expect(OutputFilter.messages(screen, tool: .claudeCode) == "❯ what does /clear to save do?\n● It clears the context.")
    }

    @Test("Claude Code in cmux: side panel, statusline art, context and hint rows, banner and turn summary are dropped")
    func claudeCmuxScreen() {
        func padded(_ text: String, to column: Int = 166) -> String {
            let w = text.reduce(0) { $0 + OutputFilter.cellWidth($1) }
            return text + String(repeating: " ", count: max(column - w, 0)) + "│ panel stuff \u{FFFD}"
        }
        let screen = [
            padded(""),
            " ▐▛███▛█   Claude Code v2.1.322",
            "▝▜██████▀  Opus 5.5 · Claude Max",
            " ▝▝   ▝▝   ~/Projects/herdr-agent-island · /rc",
            padded(""),
            padded("❯ Run this exact shell command: touch x.txt"),
            padded(""),
            padded("🌀   Ran 1 shell command"),
            padded(""),
            padded("⏺ touch x.txt 跑完了，沒有錯誤。"),
            String(repeating: " ", count: 159) + "· +1 XP│",
            padded("✻ 💎 Looted for 7s · done 下午4:50"),
            padded(""), padded(""),
            String(repeating: " ", count: 95) + "✎ changed   ↻ turn   ◷ last turn",
            "                 ▄▄▄▄                         ▀▀▀▄▀▀▀▄     ▄▀▄",
            String(repeating: "▀", count: 56),
            padded("📜 System prompt 4.4k  🔧 System tools 16.8k  🔮 MCP 4.1k  ✨ Skills 10.0k"),
            padded("💬 Messages 34.4k"),
            " ^G  editor   ^S  stash   ^R  history   esc esc  rewind",
            padded(""),
            rule, "❯ ", rule,
            "  Opus 5.5 medium │ herdr-agent-island main",
            "  ⏸ manual mode on",
        ].joined(separator: "\n")
        #expect(OutputFilter.messages(screen, tool: .claudeCode) == """
        ❯ Run this exact shell command: touch x.txt

        🌀   Ran 1 shell command

        ⏺ touch x.txt 跑完了，沒有錯誤。
        """)
    }

    @Test("CJK and emoji take two cells")
    func widths() {
        #expect(OutputFilter.cellWidth("a") == 1)
        #expect(OutputFilter.cellWidth("跑") == 2)
        #expect(OutputFilter.cellWidth("💬") == 2)
    }

    @Test("Claude Code: rules inside the conversation (tables, separators) are kept")
    func claudeKeepsContentRules() {
        let screen = (["● Result", rule, "a table row", rule] + Array(repeating: "line", count: 20) + [rule, "❯ ", rule, "status"])
            .joined(separator: "\n")
        let out = OutputFilter.messages(screen, tool: .claudeCode)
        #expect(out.hasPrefix("● Result\n\(rule)\na table row\n\(rule)"))
        #expect(!out.contains("status"))
    }

    @Test("Codex: drops the › input row and the status lines under it")
    func codex() {
        let screen = [
            "• Ran the tests, all green.",
            "",
            "› Ask Codex to do anything",
            "  GPT-5.6 medium · /tmp/x · Context 0% used",
            "  ← for agents · ? for shortcuts",
        ].joined(separator: "\n")
        #expect(OutputFilter.messages(screen, tool: .codex) == "• Ran the tests, all green.")
    }

    @Test("unknown tools are only cleaned of padding")
    func generic() {
        let screen = "$ make\nok   \n\(pad)\n\n"
        #expect(OutputFilter.messages(screen, tool: .generic) == "$ make\nok")
    }

    @Test("falls back to the full screen when filtering leaves nothing")
    func fallback() {
        let screen = [rule, "❯ ", rule, "status"].joined(separator: "\n")
        #expect(OutputFilter.messages(screen, tool: .claudeCode) == OutputFilter.clean(screen))
    }
}
