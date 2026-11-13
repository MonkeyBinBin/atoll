import Foundation
import Testing
@testable import AtollCore

@Suite("Permission choices: extraction")
struct PermissionChoicesExtractionTests {
    @Test("Claude Code: Allow is the plain \"1. Yes\", Deny is \"4. No\" (always-allow / auto mode skipped)")
    func claude() {
        let choices = PermissionChoices.extract(from: WaitingScreens.claudePermission, tool: .claudeCode, kind: .permission)
        #expect(choices == PermissionChoices(allowKey: "1", denyKey: "4"))
    }

    @Test("Codex: the options' own shortcuts, (y) and (esc); (p) for don't-ask-again is never used")
    func codex() {
        let choices = PermissionChoices.extract(from: WaitingScreens.codexPermission, tool: .codex, kind: .permission)
        #expect(choices == PermissionChoices(allowKey: "y", denyKey: "esc"))
    }

    @Test("blocked without a kind (herdr CLI, cmux) still reads a permission dialog")
    func unspecified() {
        #expect(PermissionChoices.extract(from: WaitingScreens.claudePermission, tool: .claudeCode, kind: .unspecified)?.allowKey == "1")
        #expect(PermissionChoices.extract(from: WaitingScreens.codexPermission, tool: .codex, kind: .unspecified)?.denyKey == "esc")
    }

    @Test("a two-option dialog (Yes / No)")
    func twoOptions() {
        let screen = Self.claude(options: ["❯ 1. Yes", "  2. No"])
        #expect(PermissionChoices.extract(from: screen, tool: .claudeCode, kind: .permission) == PermissionChoices(allowKey: "1", denyKey: "2"))
    }

    @Test("an edit dialog: \"allow all edits during this session (shift+tab)\" is not a plain Yes")
    func editSession() {
        let screen = Self.claude(options: ["❯ 1. Yes", "  2. Yes, allow all edits during this session (shift+tab)", "  3. No"])
        #expect(PermissionChoices.extract(from: screen, tool: .claudeCode, kind: .permission) == PermissionChoices(allowKey: "1", denyKey: "3"))
    }

    @Test("an older dialog in the scrollback doesn't win over the one on screen")
    func lastDialogWins() {
        let screen = WaitingScreens.claudePermission + "\n  ⎿  Done\n" + Self.claude(options: ["❯ 1. Yes", "  2. No"])
        #expect(PermissionChoices.extract(from: screen, tool: .claudeCode, kind: .permission)?.denyKey == "2")
    }

    @Test("nothing to offer", arguments: [
        // Only don't-ask-again style approvals.
        (claude(options: ["❯ 1. Yes, and always allow access to /tmp", "  2. No"]), AgentTool.claudeCode, BlockedKind.permission),
        // No "No" option.
        (claude(options: ["❯ 1. Yes", "  2. Yes, and always allow access to /tmp"]), AgentTool.claudeCode, BlockedKind.permission),
        // Options not found.
        (claude(options: []), AgentTool.claudeCode, BlockedKind.permission),
        // Numbering that isn't 1, 2, 3…: not a layout we know.
        (claude(options: ["❯ 2. Yes", "  3. No"]), AgentTool.claudeCode, BlockedKind.permission),
        (WaitingScreens.claudeQuestion, AgentTool.claudeCode, BlockedKind.question),
        (WaitingScreens.claudeQuestion, AgentTool.claudeCode, BlockedKind.unspecified),
        (WaitingScreens.claudePermission, AgentTool.claudeCode, BlockedKind.auth),
        (WaitingScreens.claudePermission, AgentTool.generic, BlockedKind.permission),
        (WaitingScreens.codexPermission, AgentTool.codex, BlockedKind.question),
        ("● Just a message.\n❯ ", AgentTool.claudeCode, BlockedKind.permission),
    ])
    func nothing(screen: String, tool: AgentTool, kind: BlockedKind) {
        #expect(PermissionChoices.extract(from: screen, tool: tool, kind: kind) == nil)
    }

    static func claude(options: [String]) -> String {
        ([
            WaitingScreens.rule,
            " Bash command",
            " List files",
            WaitingScreens.dashed,
            " ls",
            WaitingScreens.dashed,
            " Do you want to proceed?",
        ] + options + ["", " Esc to cancel · Tab to amend"]).joined(separator: "\n")
    }
}

@MainActor
@Suite("Permission choices: answering from the list")
struct PermissionResponseTests {
    func waiting(_ screen: String = WaitingScreens.claudePermission, app: String = "claude-code") async -> Harness {
        let h = Harness()
        h.client.readResult = .success(ReadOutput(text: screen, how: "screen"))
        h.connect([term("t1", "working", app: app)])
        h.status("t1", "blocked", app: app, kind: "permission", seq: 11)
        h.scheduler.advance(by: h.store.timing.previewDelay)
        await settle()
        return h
    }

    var keys: (Harness) -> [[String]] = { h in
        h.client.commands.compactMap { if case .keys(_, let keys) = $0 { keys } else { nil } }
    }

    @Test("recognized dialog: Allow sends its key once and reports it")
    func allow() async throws {
        let h = await waiting()
        let agent = try #require(h.store.agent("t1"))
        #expect(agent.permissionChoices == PermissionChoices(allowKey: "1", denyKey: "4"))
        h.store.respond(.allow, to: "t1", episode: agent.waitingSince)
        #expect(h.store.listAnswers["t1"] == .sending(.allow))
        await settle()
        #expect(keys(h) == [["1"]])
        #expect(h.store.listAnswers["t1"] == .sent(.allow))
        // Leaving Needs you clears it.
        h.status("t1", "working", seq: 12)
        #expect(h.store.listAnswers["t1"] == nil)
    }

    @Test("Deny sends the dialog's No key")
    func deny() async throws {
        let h = await waiting(WaitingScreens.codexPermission, app: "codex")
        let agent = try #require(h.store.agent("t1"))
        h.store.respond(.deny, to: "t1", episode: agent.waitingSince)
        await settle()
        #expect(keys(h) == [["esc"]])
    }

    @Test("a new episode since the user looked: nothing sent, \"No longer waiting\"")
    func newEpisode() async throws {
        let h = await waiting()
        let seen = try #require(h.store.agent("t1")?.waitingSince)
        h.status("t1", "working", seq: 12)
        h.scheduler.advance(by: 1)
        h.status("t1", "blocked", kind: "permission", seq: 13)
        h.scheduler.advance(by: 1)
        await settle()
        #expect(h.store.agent("t1")?.permissionChoices != nil)
        h.store.respond(.allow, to: "t1", episode: seen)
        await settle()
        #expect(keys(h).isEmpty)
        #expect(h.store.listAnswers["t1"] == .noLongerWaiting)
        h.scheduler.advance(by: h.store.timing.interruptFeedbackDuration)
        #expect(h.store.listAnswers["t1"] == nil)
    }

    @Test("no longer Needs you: nothing sent")
    func leftNeedsYou() async throws {
        let h = await waiting()
        let seen = try #require(h.store.agent("t1")?.waitingSince)
        h.status("t1", "working", seq: 12)
        h.store.respond(.allow, to: "t1", episode: seen)
        await settle()
        #expect(keys(h).isEmpty)
        #expect(h.store.listAnswers["t1"] == .noLongerWaiting)
    }

    @Test("a failed send is reported and never retried")
    func failure() async throws {
        let h = await waiting()
        h.client.keysResult = .failure(.unavailable("gone"))
        let agent = try #require(h.store.agent("t1"))
        h.store.respond(.allow, to: "t1", episode: agent.waitingSince)
        await settle()
        h.scheduler.advance(by: 10)
        await settle()
        #expect(keys(h) == [["1"]])
        #expect(h.store.listAnswers["t1"] == .failed(.allow, .unavailable("gone")))
    }

    @Test("the source says why (status msg): the screen is still read for the keys, the preview stays the msg")
    func statusMessage() async throws {
        let h = Harness()
        h.client.readResult = .success(ReadOutput(text: WaitingScreens.claudePermission, how: "screen"))
        h.connect([term("t1", "working")])
        h.client.emit(.event(seq: 11, .status(terminal: "t1", status: CoreStatus(state: "blocked", app: "claude-code", kind: "permission", msg: "approve Bash: touch hello.txt"), reported: true)))
        h.scheduler.advance(by: 1)
        await settle()
        let agent = try #require(h.store.agent("t1"))
        #expect(agent.waitingPreview == nil)
        #expect(agent.permissionChoices?.allowKey == "1")
    }

    @Test("a question offers no choices", arguments: ["question", nil] as [String?])
    func question(kind: String?) async {
        let h = Harness()
        h.client.readResult = .success(ReadOutput(text: WaitingScreens.claudeQuestion, how: "screen"))
        h.connect([term("t1", "working")])
        h.status("t1", "blocked", kind: kind, seq: 11)
        h.scheduler.advance(by: 1)
        await settle()
        #expect(h.store.agent("t1")?.waitingPreview != nil)
        #expect(h.store.agent("t1")?.permissionChoices == nil)
        h.store.respond(.allow, to: "t1", episode: h.store.agent("t1")?.waitingSince)
        await settle()
        #expect(keys(h).isEmpty)
    }
}
