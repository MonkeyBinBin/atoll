import Foundation
import Testing
@testable import AtollCore

/// Screens of Antigravity CLI 1.5.13 read through hc (plain text), account and folder replaced.
enum AntigravityScreens {
    static let fullRule = String(repeating: "─", count: 100)
    static let messageRule = String(repeating: "─", count: 60)

    static func status(_ left: String, _ right: String = "auto · Gemini 3.8 Flash · high") -> String {
        left + String(repeating: " ", count: 100 - left.count - right.count) + right
    }

    static let banner = [
        "❯ agy",
        "",
        "      ▄▀▀▄        Antigravity CLI 1.5.13",
        "     ▀▀▀▀▀▀       user@example.com (Antigravity Starter Quota)",
        "    ▀▀▀▀▀▀▀▀      Gemini 3.8 Flash (High)",
        "   ▄▀▀    ▀▀▄     /path/to/project",
        "  ▄▀▀      ▀▀▄",
        "",
        "",
    ]

    static let firstTurn = [
        messageRule,
        #"> <hc from="t7y">Read README.md and main.go, change main.go to print "hello atoll"</hc>"#,
        "",
        "○ Thought for 19.4s (The initial `curl` command unexpectedly produced no output despite an exit code...)",
        "● Explored 2 files (README.md, main.go)",
        "● Edited 1 file (main.go)",
        "● Ran 2 commands (curl -sI https://example.com | head -1 ×2)",
        "● Explored 1 file (main.go) (ctrl+o to expand)",
        "",
        "▸ Thought for 4s, 377 tokens",
        "",
        "  I have completed the requested steps:",
        "",
        "  1. Read README.md and main.go.",
        #"  2. Updated main.go:5-7 to print "hello atoll"."#,
        "",
    ]

    static func inputBox(_ left: String = "? for shortcuts", _ right: String = "auto · Gemini 3.8 Flash · high") -> [String] {
        [fullRule, ">", fullRule, status(left, right)]
    }

    static let idle = (banner + firstTurn + inputBox()).joined(separator: "\n")

    static let working = (banner + firstTurn + [
        messageRule,
        #"> <hc from="t7y">Without running any commands, write a 6-paragraph essay about coral atolls.</hc>"#,
        "",
        "  The formation of an atoll is an extraordinary narrative of oceanic subsidence.",
        "⡿  Working...",
    ] + inputBox("esc to cancel")).joined(separator: "\n")

    static let permission = (banner + firstTurn + [
        messageRule,
        #"> <hc from="t7y">Run exactly this shell command: go run .</hc>"#,
        "",
        "● Ran 2 commands (go run . ×2) (ctrl+o to expand)",
        "",
        "Command",
        fullRule,
        "",
        "Requesting permission for:",
        "   go run .",
        "",
        "Run this command?",
        "> 1. Yes, run command",
        "  2. Yes, and always allow in this conversation for commands that start with 'go run .'",
        "  3. Yes, and always allow for commands that start with 'go run .' (Persist to settings.json)",
        "  4. No, cancel",
        "",
        "  ↑/↓ Navigate · tab Amend · ctrl+g edit/expand command",
        status("esc to cancel", "Gemini 3.8 Flash · high"),
    ]).joined(separator: "\n")

    static let interrupted = (banner + firstTurn + [
        messageRule,
        #"> <hc from="t7y">Run exactly this shell command: go run .</hc>"#,
        "",
        "● Ran 2 commands (go run . ×2) (ctrl+o to expand)",
        "",
        "  ⎿  Interrupted · What should Antigravity CLI do instead?",
    ] + inputBox("? for shortcuts", "Gemini 3.8 Flash · high")).joined(separator: "\n")

    /// The first-run trust prompt: a full-screen view without the input box.
    static let trust = [
        "Accessing workspace:",
        "",
        "/path/to/project",
        "",
        "Do you trust the contents of this project?",
        "",
        "Antigravity CLI requires permission to read, edit, and execute files here.",
        "",
        "> Yes, I trust this folder",
        "  No, exit",
        "",
        "  ↑/↓ Navigate · enter Confirm",
    ].joined(separator: "\n")
}

@Suite("Output filter: Antigravity CLI")
struct AntigravityOutputTests {
    typealias S = AntigravityScreens

    func messages(_ screen: String, app: String = "antigravity") -> String {
        OutputFilter.messages(screen, tool: .generic, app: app)
    }

    @Test("idle: the shell's `agy` row, banner, input box and status row go; message rules and rows stay")
    func idle() {
        #expect(messages(S.idle) == OutputFilter.trimTrailingBlankLines(S.firstTurn).joined(separator: "\n"))
    }

    @Test("working: the spinner row above the input box goes too")
    func working() {
        let shown = messages(S.working)
        #expect(shown.hasPrefix(S.messageRule))
        #expect(shown.hasSuffix("  The formation of an atoll is an extraordinary narrative of oceanic subsidence."))
        #expect(!shown.contains("Working..."))
        #expect(!shown.contains("esc to cancel"))
    }

    @Test("a tip above the input box goes; the rows above it stay")
    func tip() {
        let screen = (S.banner + S.firstTurn + [
            " ┃ Auto is now the default agent mode",
            " ┃ Press Shift+Tab to switch agent modes, or change Agent Mode in /config.",
            " ┃ esc to dismiss",
            S.fullRule, "> Auto mode: edits & safe commands auto-approved (shift+tab to cycle)", S.fullRule,
            S.status("? for shortcuts"),
        ]).joined(separator: "\n")
        #expect(messages(screen) == messages(S.idle))
    }

    @Test("`┃` rows that aren't a tip (no \"esc to dismiss\" at the end) are the reply's and stay")
    func quoteAboveInput() {
        let quote = ["  ┃ Note: main.go now prints hello atoll.", "  ┃ Run go run . to see it."]
        let screen = (S.firstTurn + quote + S.inputBox()).joined(separator: "\n")
        #expect(messages(screen).hasSuffix(quote.joined(separator: "\n")))
    }

    @Test("narrow (herdr pane): the banner's text rows are stacked under the logo and go too")
    func stackedBanner() {
        let banner = [
            "❯ agy",
            "",
            "      ▄▀▀▄",
            "     ▀▀▀▀▀▀",
            "    ▀▀▀▀▀▀▀▀",
            "   ▄▀▀    ▀▀▄",
            "  ▄▀▀      ▀▀▄",
            "",
            "  Antigravity CLI 1.5.13",
            "  user@example.com (Antigravity Starter Quota)",
            "  Gemini 3.8 Flash (High)",
            "  /path/to/project",
            "",
        ]
        let screen = (banner + S.firstTurn + S.inputBox()).joined(separator: "\n")
        #expect(messages(screen, app: "agy") == messages(S.idle))
    }

    @Test("a reply that mentions the version isn't taken for the banner")
    func versionInReply() {
        let turn = S.firstTurn + ["  Antigravity CLI 1.5.13 is installed.", ""]
        let screen = (S.banner + turn + S.inputBox()).joined(separator: "\n")
        #expect(messages(screen).hasSuffix("  Antigravity CLI 1.5.13 is installed."))
        #expect(messages(screen).hasPrefix(S.messageRule))
    }

    @Test("a read that starts partway into the banner still drops its logo rows")
    func scrolledBanner() {
        let screen = (Array(S.banner.dropFirst(3)) + S.firstTurn + S.inputBox()).joined(separator: "\n")
        #expect(messages(screen) == messages(S.idle))
        #expect(!messages(screen).contains("user@example.com"))
    }

    @Test("with no input box, a deeply indented last row is content, not the status row")
    func indentedLastRow() {
        let row = String(repeating: " ", count: 44) + "centered text"
        let screen = (S.firstTurn + ["Command", S.fullRule, row]).joined(separator: "\n")
        #expect(messages(screen).hasSuffix(row))
        let status = String(repeating: " ", count: 60) + "Gemini 3.8 Flash · high"
        #expect(!messages(screen + "\n" + status).hasSuffix(status))
    }

    @Test("permission dialog: no input box, so the dialog stays and only the banner and status row go")
    func permission() {
        let shown = messages(S.permission)
        #expect(shown.hasPrefix(S.messageRule))
        #expect(shown.contains("Run this command?"))
        #expect(shown.hasSuffix("  ↑/↓ Navigate · tab Amend · ctrl+g edit/expand command"))
        #expect(!shown.contains("Antigravity CLI 1.5.13"))
    }

    @Test("interrupted: the Interrupted row is the turn's and stays")
    func interrupted() {
        #expect(messages(S.interrupted).hasSuffix("""
            ● Ran 2 commands (go run . ×2) (ctrl+o to expand)

              ⎿  Interrupted · What should Antigravity CLI do instead?
            """))
    }

    @Test("a new session with no message yet: nothing would be left, so the whole screen is shown")
    func newSession() {
        let screen = (S.banner + S.inputBox()).joined(separator: "\n")
        #expect(messages(screen) == OutputFilter.clean(screen))
    }

    @Test("a full-screen view without an input box is shown whole")
    func fullScreenFallback() {
        #expect(messages(S.trust) == OutputFilter.clean(S.trust))
    }

    @Test("a typed multi-line input is still the input box")
    func typedInput() {
        let screen = (S.firstTurn + [S.fullRule, "> first line", "  second line", S.fullRule, S.status("? for shortcuts")])
            .joined(separator: "\n")
        #expect(messages(screen) == messages(S.idle))
    }

    @Test("after scrolling, the banner is gone and nothing above the first message is dropped")
    func noBanner() {
        #expect(messages((S.firstTurn + S.inputBox()).joined(separator: "\n")) == messages(S.idle))
    }

    @Test("dispatch: `antigravity` and `agy` in any case; other agents are left alone")
    func dispatch() {
        #expect(messages(S.idle, app: "agy") == messages(S.idle))
        #expect(messages(S.idle, app: "Antigravity") == messages(S.idle))
        #expect(messages(S.idle, app: "agy-1.6") == messages(S.idle))
        #expect(OutputFilter.messages(S.idle, tool: .generic, app: "agyle") == OutputFilter.clean(S.idle))
        #expect(OutputFilter.messages(S.idle, tool: .generic, app: "droid") == OutputFilter.clean(S.idle))
        #expect(OutputFilter.messages(S.idle, tool: .generic) == OutputFilter.clean(S.idle))
    }
}

@Suite("No output: Antigravity CLI")
struct AntigravityNoOutputTests {
    typealias S = AntigravityScreens

    func hash(_ screen: String) -> Int {
        OutputFilter.activityFingerprint(screen, tool: .generic, app: "antigravity")
    }

    @Test("status row, mode, model, spinner and thought timers don't count as output")
    func framing() {
        let base = hash(S.working)
        let otherStatus = S.working.replacingOccurrences(of: S.status("esc to cancel"),
                                                         with: S.status("? for shortcuts", "Gemini 3.8 Flash · low"))
        #expect(hash(otherStatus) == base)
        #expect(hash(S.working.replacingOccurrences(of: "⡿  Working...", with: "⣟  Working...")) == base)
        #expect(hash(S.working.replacingOccurrences(of: "Thought for 19.4s", with: "Thought for 21.7s")) == base)
        #expect(hash(S.working.replacingOccurrences(of: "user@example.com", with: "other@example.com")) == base)
    }

    @Test("a new reply row counts")
    func newRow() {
        let replied = S.working.replacingOccurrences(
            of: "⡿  Working...",
            with: "  The process begins with an underwater volcanic eruption.\n⡿  Working...")
        #expect(hash(replied) != hash(S.working))
    }

    @Test("without the app word the whole screen counts, as before")
    func withoutApp() {
        let otherStatus = S.working.replacingOccurrences(of: S.status("esc to cancel"), with: S.status("? for shortcuts"))
        #expect(OutputFilter.activityFingerprint(otherStatus, tool: .generic)
            != OutputFilter.activityFingerprint(S.working, tool: .generic))
    }
}

@Suite("Output styling: Antigravity CLI")
struct AntigravityStylingTests {
    func styled(_ text: String) -> [(String, TermStyle)] {
        OutputStyling.heuristic(text).map { ((text as NSString).substring(with: $0.range), $0.style) }
    }

    @Test("tool rows: green bullet and bold verb; thought rows muted; indented bullets are list markers")
    func rows() {
        let shown = [
            #"> <hc from="t7y">fix it</hc>"#,
            "",
            "○ Thought for 13.3s (The PATH environment variable appears standard)",
            "● Explored 2 files (README.md, main.go)",
            "● Ran 9 commands, killed 1 task (go run . ×2)",
            "● Ran (rm -rf /tmp/x)",
            "",
            "▸ Thought for 5s, 391 tokens",
            "",
            "  • Updated the greeting.",
        ].joined(separator: "\n")
        let pieces = styled(shown)
        let byText = Dictionary(pieces.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        #expect(byText[#"> <hc from="t7y">fix it</hc>"#] == OutputStyling.accent)
        #expect(byText["○ Thought for 13.3s (The PATH environment variable appears standard)"] == OutputStyling.muted)
        #expect(byText["▸ Thought for 5s, 391 tokens"] == OutputStyling.muted)
        #expect(pieces.filter { $0.0 == "●" }.allSatisfy { $0.1 == OutputStyling.green })
        #expect(pieces.filter { $0.0 == "●" }.count == 3)
        #expect(byText["Explored"] == OutputStyling.bold)
        #expect(byText["Ran"] == OutputStyling.bold)
        #expect(byText["•"] == OutputStyling.listMarker)
    }

    @Test("reply bullets (Claude Code via hc uses `●` too) stay plain bold bullets")
    func replyBullet() {
        for row in ["● Updated the README with the new flags.", "● Done (all tests pass)", "● Found 3 issues:",
                    "● All 12 tests pass.", "● Updated (and pushed) the branch."] {
            let pieces = styled(row)
            #expect(pieces.first?.0 == "●")
            #expect(pieces.first?.1 == OutputStyling.bold)
            #expect(!pieces.contains { $0.1 == OutputStyling.green })
        }
    }

    @Test("filtered idle screen colors end to end")
    func endToEnd() {
        let shown = OutputFilter.messages(AntigravityScreens.idle, tool: .generic, app: "antigravity")
        let pieces = OutputStyling.runs(shown: shown, source: ReadOutput(text: AntigravityScreens.idle, how: "history"))
            .map { ((shown as NSString).substring(with: $0.range), $0.style) }
        #expect(pieces.contains { $0.0 == "Edited" && $0.1 == OutputStyling.bold })
        #expect(pieces.contains { $0.0 == "1." && $0.1 == OutputStyling.listMarker })
    }
}
