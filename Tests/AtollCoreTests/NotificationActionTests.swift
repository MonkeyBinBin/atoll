import Foundation
import Testing
@testable import AtollCore

@Suite("Notification actions: decorate")
struct NotificationDecorateTests {
    let since = Date(timeIntervalSince1970: 1_800_000_000)
    let base = AgentNotification(address: "t1", title: "Claude Code · project-x", body: "Needs you", key: "needs-you#0")

    func agent(_ kind: BlockedKind, choices: Bool = true, preview: String? = "Bash: rm -rf dist", msg: String? = nil) -> Agent {
        var agent = Agent(address: "t1", tool: .claudeCode, state: .needsYou(kind), statusMessage: msg, waitingSince: since)
        agent.waitingPreview = preview.map { WaitingPreview(title: $0) }
        if choices { agent.permissionChoices = PermissionChoices(allowKey: "1", denyKey: "4") }
        return agent
    }

    func settings(reason: Bool) -> NotificationSettings { NotificationSettings(showWaitingReason: reason) }

    @Test("reason hidden (default): Deny only, body unchanged — never Allow on a command you can't see")
    func hiddenReason() {
        let note = NotificationRules.decorate(base, with: agent(.permission), settings: settings(reason: false))
        #expect(note.actions == [.deny])
        #expect(note.body == "Needs you")
        #expect(note.episode == since)
    }

    @Test("reason shown: the command is in the body and Allow is offered")
    func shownReason() {
        let note = NotificationRules.decorate(base, with: agent(.permission), settings: settings(reason: true))
        #expect(note.actions == [.allow, .deny])
        #expect(note.body == "Needs you · Bash: rm -rf dist")
    }

    @Test("the source's status msg counts as the reason")
    func statusMessage() {
        let note = NotificationRules.decorate(base, with: agent(.permission, preview: nil, msg: "approve Bash: ls"), settings: settings(reason: true))
        #expect(note.actions == [.allow, .deny])
        #expect(note.body == "Needs you · approve Bash: ls")
    }

    @Test("reason shown but nothing to show: still no Allow")
    func noReasonText() {
        let note = NotificationRules.decorate(base, with: agent(.permission, preview: nil), settings: settings(reason: true))
        #expect(note.actions == [.deny])
    }

    @Test("permission whose keys weren't recognized: no buttons (it only takes keys)")
    func unknownPermission() {
        let note = NotificationRules.decorate(base, with: agent(.permission, choices: false), settings: settings(reason: true))
        #expect(note.actions.isEmpty)
    }

    @Test("question: Reply")
    func question() {
        let note = NotificationRules.decorate(base, with: agent(.question, choices: false, preview: "Which color?"), settings: settings(reason: false))
        #expect(note.actions == [.reply])
        #expect(note.body == "Needs you")
    }

    @Test("blocked without a kind (herdr CLI, cmux): Reply, plus Deny / Allow when the dialog was recognized")
    func unspecified() {
        #expect(NotificationRules.decorate(base, with: agent(.unspecified), settings: settings(reason: true)).actions == [.allow, .deny, .reply])
        #expect(NotificationRules.decorate(base, with: agent(.unspecified, choices: false), settings: settings(reason: false)).actions == [.reply])
    }

    @Test("auth and non-waiting states: untouched")
    func untouched() {
        let auth = NotificationRules.decorate(base, with: agent(.auth, choices: false), settings: settings(reason: true))
        #expect(auth.actions.isEmpty)
        let done = NotificationRules.decorate(base, with: Agent(address: "t1", state: .done), settings: settings(reason: true))
        #expect(done == base)
    }

    @Test("the episode survives the userInfo round trip exactly (1970-based seconds don't)")
    func episodeRoundTrip() {
        // A live waitingSince has sub-microsecond digits; this one is off by a step through timeIntervalSince1970.
        let lossy = (0..<2000).lazy.map { Date(timeIntervalSinceReferenceDate: 815_000_000.123456 + Double($0) * 0.000_037) }
            .first { Date(timeIntervalSince1970: $0.timeIntervalSince1970) != $0 }
        #expect(lossy != nil)
        let date = lossy ?? Date()
        #expect(AgentNotification.decodeEpisode(AgentNotification.encodeEpisode(date)) == date)
    }

    @Test("category identifiers are stable and round-trip")
    func categories() {
        #expect(NotificationActions.combinations.count == 7)
        #expect(NotificationActions([.allow, .deny]).categoryIdentifier == "atoll.actions.allow-deny")
        #expect(NotificationActions.reply.categoryIdentifier == "atoll.actions.reply")
        for combo in NotificationActions.combinations {
            #expect(NotificationActions(categoryIdentifier: combo.categoryIdentifier) == combo)
        }
        #expect(Set(NotificationActions.combinations.map(\.categoryIdentifier)).count == 7)
    }
}

@MainActor
@Suite("Notification actions: store")
struct NotificationActionStoreTests {
    @Test("the screen read reports when it's over, found or not, once per episode")
    func waitingDetails() async {
        let h = Harness()
        var reported: [String] = []
        h.store.onWaitingDetails = { reported.append($0.address) }
        h.client.readResult = .failure(.unavailable("gone"))
        h.connect([term("t1", "working")])
        h.status("t1", "blocked", kind: "permission", seq: 11)
        #expect(h.store.isReadingWaitingScreen("t1"))
        h.scheduler.advance(by: h.store.timing.previewDelay)
        await settle()
        #expect(!h.store.isReadingWaitingScreen("t1"))
        #expect(reported == ["t1"])
        h.scheduler.advance(by: 5)
        await settle()
        #expect(reported == ["t1"])
    }

    @Test("when the read is reported, the agent already carries what it found")
    func detailsVisibleOnReport() async {
        let h = Harness()
        var seen: Agent?
        h.store.onWaitingDetails = { _ in seen = h.store.agent("t1") }
        h.client.readResult = .success(ReadOutput(text: WaitingScreens.claudePermission, how: "screen"))
        h.connect([term("t1", "working")])
        h.status("t1", "blocked", kind: "permission", seq: 11)
        h.scheduler.advance(by: h.store.timing.previewDelay)
        await settle()
        #expect(seen?.permissionChoices?.allowKey == "1")
        #expect(seen?.waitingPreview?.title == "Bash: touch hello.txt")
    }

    @Test("no read needed (question with a status msg): not reading")
    func noRead() {
        let h = Harness()
        h.connect([term("t1", "working")])
        h.client.emit(.event(seq: 11, .status(terminal: "t1", status: CoreStatus(state: "blocked", app: "claude-code", kind: "question", msg: "answer: x?"), reported: true)))
        #expect(!h.store.isReadingWaitingScreen("t1"))
    }

    @Test("reply in the same episode sends (forced) and reports the result")
    func reply() async throws {
        let h = Harness()
        h.connect([term("t1", "working")])
        h.status("t1", "blocked", kind: "question", seq: 11)
        let episode = try #require(h.store.agent("t1")?.waitingSince)
        var result: SendState??
        h.store.reply("Blue", to: "t1", episode: episode) { result = .some($0) }
        await settle()
        #expect(h.client.commands.contains(.send("t1", "Blue", force: true)))
        #expect(result == .some(.started))
    }

    @Test("reply after the agent moved on: nothing sent, nil")
    func replyStale() async throws {
        let h = Harness()
        h.connect([term("t1", "working")])
        h.status("t1", "blocked", kind: "question", seq: 11)
        let episode = try #require(h.store.agent("t1")?.waitingSince)
        h.status("t1", "working", seq: 12)
        h.scheduler.advance(by: 1)
        h.status("t1", "blocked", kind: "question", seq: 13)
        var result: SendState??
        h.store.reply("Blue", to: "t1", episode: episode) { result = .some($0) }
        await settle()
        #expect(!h.client.commands.contains { if case .send = $0 { true } else { false } })
        #expect(result == .some(nil))
    }

    @Test("a failed reply reports the failure")
    func replyFails() async throws {
        let h = Harness()
        h.client.sendResult = .failure(.unavailable("gone"))
        h.connect([term("t1", "working")])
        h.status("t1", "blocked", kind: "question", seq: 11)
        var result: SendState??
        h.store.reply("Blue", to: "t1", episode: h.store.agent("t1")?.waitingSince) { result = .some($0) }
        await settle()
        #expect(result == .some(.failed(.unavailable("gone"))))
    }

    @Test("respond reports its outcome, including No longer waiting")
    func respondCompletion() async throws {
        let h = Harness()
        h.client.readResult = .success(ReadOutput(text: WaitingScreens.claudePermission, how: "screen"))
        h.connect([term("t1", "working")])
        h.status("t1", "blocked", kind: "permission", seq: 11)
        h.scheduler.advance(by: 1)
        await settle()
        var outcomes: [PermissionResponseState] = []
        h.store.respond(.deny, to: "t1", episode: h.store.agent("t1")?.waitingSince) { outcomes.append($0) }
        await settle()
        h.store.respond(.allow, to: "t1", episode: Date(timeIntervalSince1970: 1)) { outcomes.append($0) }
        #expect(outcomes == [.sent(.deny), .noLongerWaiting])
    }
}
