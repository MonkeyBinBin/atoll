import Foundation
import Testing
@testable import AtollCore

/// Screens captured from real sessions (Claude Code 2.1.322, Codex 0.167.0); only the long temp path is shortened.
enum WaitingScreens {
    static let rule = String(repeating: "─", count: 200)
    static let dashed = String(repeating: "╌", count: 200)

    static let claudePermission = [
        " ▐▛███▛█   Claude Code v2.1.322",
        "▝▜██████▀  Haiku 5.5 · Claude Max",
        " ▝▝   ▝▝   /tmp/cap27 · /rc",
        "",
        "",
        "❯ Run the shell command: touch hello.txt",
        "",
        "  Creating empty hello.txt in current directory",
        "  ⎿  $ touch hello.txt",
        "",
        rule,
        " Bash command",
        " Tip: auto mode handles these prompts for you — choose \"switch to auto mode\" below",
        " Create empty hello.txt in current directory",
        dashed,
        " touch hello.txt",
        dashed,
        " Do you want to proceed?",
        " ❯ 1. Yes",
        "   2. Yes, and always allow access to /tmp/cap27 from this project",
        "   3. Yes, and switch to auto mode · auto mode handles these prompts for you",
        "   4. No",
        "",
        " Esc to cancel · Tab to amend",
    ].joined(separator: "\n")

    static let claudeQuestion = [
        "❯ Use the AskUserQuestion tool to ask me which color I prefer for the button, red or blue. Do nothing else.",
        rule,
        " ☐ Button color",
        "",
        "Which color do you prefer for the button, red or blue?",
        "",
        "❯ 1. Red",
        "     Use red for the button.",
        "  2. Blue",
        "     Use blue for the button.",
        "  3. Type something.",
        rule,
        "  4. Chat about this",
        "",
        "Enter to select · ↑/↓ to navigate · Esc to cancel",
    ].joined(separator: "\n")

    static let codexPermission = [
        "",
        "",
        "  Would you like to run the following command?",
        "",
        "  Environment: local",
        "",
        "  Reason: 允許我在目前工作目錄建立空白檔案 hello2.txt 嗎？",
        "",
        "  $ touch hello2.txt",
        "",
        "",
        "› 1. Yes, proceed (y)",
        "  2. Yes, and don't ask again for commands that start with `touch hello2.txt` (p)",
        "  3. No, and tell Codex what to do differently (esc)",
        "",
        "  Press enter to confirm or esc to cancel",
    ].joined(separator: "\n")
}

@Suite("Waiting preview: extraction")
struct WaitingPreviewExtractionTests {
    @Test("Claude Code permission: tool and command, description as detail (the Tip is skipped)")
    func claudePermission() {
        let preview = WaitingPreview.extract(from: WaitingScreens.claudePermission, tool: .claudeCode, kind: .permission)
        #expect(preview == WaitingPreview(title: "Bash: touch hello.txt", detail: "Create empty hello.txt in current directory"))
    }

    @Test("Claude Code question: the question, options as detail (free-text rows dropped)")
    func claudeQuestion() {
        let preview = WaitingPreview.extract(from: WaitingScreens.claudeQuestion, tool: .claudeCode, kind: .question)
        #expect(preview == WaitingPreview(title: "Which color do you prefer for the button, red or blue?", detail: "Red · Blue"))
    }

    @Test("Codex permission: the command, Codex's reason as detail")
    func codexPermission() {
        let preview = WaitingPreview.extract(from: WaitingScreens.codexPermission, tool: .codex, kind: .permission)
        #expect(preview == WaitingPreview(title: "Run: touch hello2.txt", detail: "允許我在目前工作目錄建立空白檔案 hello2.txt 嗎？"))
    }

    @Test("blocked without a kind (herdr CLI, cmux): either Claude Code layout is recognized")
    func unspecified() {
        #expect(WaitingPreview.extract(from: WaitingScreens.claudePermission, tool: .claudeCode, kind: .unspecified)?.title == "Bash: touch hello.txt")
        #expect(WaitingPreview.extract(from: WaitingScreens.claudeQuestion, tool: .claudeCode, kind: .unspecified)?.detail == "Red · Blue")
        #expect(WaitingPreview.extract(from: WaitingScreens.codexPermission, tool: .codex, kind: .unspecified)?.title == "Run: touch hello2.txt")
    }

    @Test("an older dialog in the scrollback doesn't win over the one on screen")
    func lastDialogWins() {
        let screen = WaitingScreens.claudePermission + "\n  ⎿  Done\n" + WaitingScreens.claudePermission.replacingOccurrences(of: "touch hello.txt", with: "ls")
        #expect(WaitingPreview.extract(from: screen, tool: .claudeCode, kind: .permission)?.title == "Bash: ls")
    }

    @Test("unknown layouts and tools give nothing", arguments: [
        ("● Just a message.\n❯ ", AgentTool.claudeCode, BlockedKind.permission),
        ("● Just a message.\n❯ ", AgentTool.claudeCode, BlockedKind.question),
        (WaitingScreens.claudePermission, AgentTool.generic, BlockedKind.permission),
        (WaitingScreens.codexPermission, AgentTool.codex, BlockedKind.question),
        (WaitingScreens.claudePermission, AgentTool.claudeCode, BlockedKind.auth),
        // A question header without options (e.g. a different layout) isn't guessed at.
        ("☐ Header\n\nSomething?\n", AgentTool.claudeCode, BlockedKind.question),
    ])
    func nothing(screen: String, tool: AgentTool, kind: BlockedKind) {
        #expect(WaitingPreview.extract(from: screen, tool: tool, kind: kind) == nil)
    }

    @Test("lines are cut before being kept")
    func cut() {
        let preview = WaitingPreview(title: String(repeating: "a", count: 500), detail: "d")
        #expect(preview.title.count == WaitingPreview.maxLineLength)
        #expect(preview.title.hasSuffix("…"))
        #expect(preview.help == preview.title + "\nd")
    }
}

@MainActor
@Suite("Waiting preview: store")
struct WaitingPreviewStoreTests {
    func harness(_ screen: String = WaitingScreens.claudePermission) -> Harness {
        let h = Harness()
        h.client.readResult = .success(ReadOutput(text: screen, how: "screen"))
        h.connect([term("t1", "working")])
        return h
    }

    var reads: (Harness) -> Int = { h in h.client.commands.filter { if case .read = $0 { true } else { false } }.count }

    @Test("entering Needs you reads the screen once, after a short delay")
    func readsOnce() async throws {
        let h = harness()
        h.status("t1", "blocked", kind: "permission", seq: 11)
        await settle()
        #expect(reads(h) == 0)
        h.scheduler.advance(by: h.store.timing.previewDelay)
        await settle()
        #expect(h.client.commands.contains(.read("t1", h.store.timing.previewLines)))
        #expect(try #require(h.store.agent("t1")?.waitingPreview).title == "Bash: touch hello.txt")
        // More events in the same episode: no more reads.
        h.client.emit(.event(seq: 12, .turn(terminal: "t1", turn: 1, state: nil)))
        h.scheduler.advance(by: 5)
        await settle()
        #expect(reads(h) == 1)
    }

    @Test("leaving Needs you drops it; the next episode reads again")
    func dropsAndRereads() async {
        let h = harness()
        h.status("t1", "blocked", kind: "permission", seq: 11)
        h.scheduler.advance(by: 1)
        await settle()
        #expect(h.store.agent("t1")?.waitingPreview != nil)
        h.status("t1", "working", seq: 12)
        #expect(h.store.agent("t1")?.waitingPreview == nil)
        h.status("t1", "blocked", kind: "permission", seq: 13)
        #expect(h.store.agent("t1")?.waitingPreview == nil)
        h.scheduler.advance(by: 1)
        await settle()
        #expect(reads(h) == 2)
        #expect(h.store.agent("t1")?.waitingPreview != nil)
    }

    @Test("leaving before the delay: no read at all")
    func leftBeforeRead() async {
        let h = harness()
        h.status("t1", "blocked", kind: "permission", seq: 11)
        h.status("t1", "working", seq: 12)
        h.scheduler.advance(by: 1)
        await settle()
        #expect(reads(h) == 0)
    }

    @Test("the source already says why (status msg) for a question: no read")
    func statusMessageWins() async {
        let h = harness(WaitingScreens.claudeQuestion)
        h.client.emit(.event(seq: 11, .status(terminal: "t1", status: CoreStatus(state: "blocked", app: "claude-code", kind: "question", msg: "answer: Which color?"), reported: true)))
        h.scheduler.advance(by: 1)
        await settle()
        #expect(reads(h) == 0)
        #expect(h.store.agent("t1")?.statusMessage == "answer: Which color?")
        #expect(h.store.agent("t1")?.waitingPreview == nil)
    }

    @Test("a failed read or an unrecognized screen: no preview, no retry")
    func failure() async {
        let h = harness()
        h.client.readResult = .failure(.unavailable("gone"))
        h.status("t1", "blocked", kind: "permission", seq: 11)
        h.scheduler.advance(by: 1)
        await settle()
        h.client.readResult = .success(ReadOutput(text: "nothing useful", how: "screen"))
        h.scheduler.advance(by: 10)
        await settle()
        #expect(reads(h) == 1)
        #expect(h.store.agent("t1")?.waitingPreview == nil)
    }

    @Test("removed agents leave nothing behind")
    func removed() async {
        let h = harness()
        h.status("t1", "blocked", kind: "permission", seq: 11)
        h.scheduler.advance(by: 1)
        await settle()
        h.client.emit(.event(seq: 12, .removed(terminal: "t1")))
        h.client.emit(.event(seq: 13, .created(term("t1", "blocked", kind: "permission"))))
        #expect(h.store.agent("t1")?.waitingPreview == nil)
    }
}
