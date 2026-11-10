import Foundation
import Testing
@testable import AtollCore

@MainActor
@Suite("State model")
struct StateModelTests {
    @Test("snapshot terminals appear with their mapped state, and status events update them")
    func walkingSkeleton() {
        let h = Harness()
        h.connect([term("t1", "working")])
        #expect(h.store.agents.map(\.address) == ["t1"])
        #expect(h.state("t1") == .working)
        #expect(h.store.agent("t1")?.state.label == "Working")

        h.status("t1", "idle", seq: 11)
        #expect(h.state("t1") == .idle)
    }

    @Test("every row of the mapping table", arguments: [
        ("working", nil, AgentState.working),
        ("blocked", "question", .needsYou(.question)),
        ("blocked", "permission", .needsYou(.permission)),
        ("blocked", "auth", .needsYou(.auth)),
        ("blocked", nil, .needsYou(.unspecified)),
        ("done", nil, .done),
        ("idle", nil, .idle),
        ("error", nil, .error),
        ("something-new", nil, .unknown),
    ] as [(String, String?, AgentState)])
    func mapping(state: String, kind: String?, expected: AgentState) {
        let h = Harness()
        h.connect([term("t1", state, kind: kind)])
        #expect(h.state("t1") == expected)
    }

    @Test("blocked kinds have English labels")
    func blockedLabels() {
        #expect(BlockedKind.question.label == "Question")
        #expect(BlockedKind.permission.label == "Permission")
        #expect(BlockedKind.auth.label == "Sign-in required")
    }

    @Test("a finished terminal is Exited")
    func finished() {
        let h = Harness()
        h.connect([term("t1", "working")])
        h.client.emit(.event(seq: 11, .finished(terminal: "t1", exitCode: 0, reason: "exited", finishedMs: nil)))
        #expect(h.state("t1") == .exited)
    }

    @Test("a reporting agent whose status goes null is Unknown, not guessed")
    func statusCleared() {
        let h = Harness()
        h.connect([term("t1", "working")])
        h.status("t1", nil, seq: 11)
        #expect(h.state("t1") == .unknown)
        #expect(h.store.agent("t1")?.tool == .claudeCode)
    }

    @Test("removed terminals disappear")
    func removed() {
        let h = Harness()
        h.connect([term("t1", "working")])
        h.client.emit(.event(seq: 11, .removed(terminal: "t1")))
        #expect(h.store.agents.isEmpty)
    }

    @Test("created events add agents once they report")
    func created() {
        let h = Harness()
        h.connect([])
        h.client.emit(.event(seq: 11, .created(term("t2"))))
        #expect(h.store.agents.isEmpty, "unreported terminals are hidden by default")
        h.status("t2", "working", app: "codex", seq: 12)
        #expect(h.state("t2") == .working)
        #expect(h.store.agent("t2")?.tool == .codex)
        #expect(h.store.agent("t2")?.displayName == "Codex · project-x")
    }

    @Test("terminals that never reported are hidden unless the setting is on, then Unknown")
    func unreportedFilter() {
        let h = Harness()
        h.connect([term("t1", "working"), term("t2", nil, app: nil)])
        #expect(h.order == ["t1"])
        h.store.setShowUnreportedTerminals(true)
        #expect(Set(h.order) == ["t1", "t2"])
        #expect(h.state("t2") == .unknown)
        h.store.setShowUnreportedTerminals(false)
        #expect(h.order == ["t1"])
    }

    @Test("priority order: Needs you > Error > Unknown > Working > Done > Idle > Exited")
    func priority() {
        let h = Harness()
        h.connect([
            term("idle", "idle"),
            term("exited", nil, live: false),
            term("done", "done"),
            term("working", "working"),
            term("unknown", "weird"),
            term("error", "error"),
            term("blocked", "blocked", kind: "question"),
        ])
        // "exited" never reported an app: show it via the setting to check its place.
        h.store.setShowUnreportedTerminals(true)
        #expect(h.order == ["blocked", "error", "unknown", "working", "done", "idle", "exited"])
    }

    @Test("Needs you agents sort by when they started waiting, earliest first")
    func waitingOrder() {
        let h = Harness()
        h.connect([term("a", "working"), term("b", "working")])
        h.scheduler.advance(by: 1)
        h.status("b", "blocked", kind: "question", seq: 11)
        h.scheduler.advance(by: 1)
        h.status("a", "blocked", kind: "permission", seq: 12)
        #expect(h.order == ["b", "a"])
        #expect(h.store.earliestWaitingAgent?.address == "b")
        // Kind changes keep the original waiting time.
        h.scheduler.advance(by: 1)
        h.status("b", "blocked", kind: "permission", seq: 13)
        #expect(h.order == ["b", "a"])
    }

    @Test("earliest waiting is nil when nobody waits")
    func noWaiting() {
        let h = Harness()
        h.connect([term("a", "working")])
        #expect(h.store.earliestWaitingAgent == nil)
        #expect(h.store.waitingCount == 0)
    }

    @Test("snapshot status_ms is used as the waiting time")
    func waitingFromSnapshot() {
        let h = Harness()
        h.connect([
            term("late", "blocked", kind: "question", statusMs: 2_000_000),
            term("early", "blocked", kind: "question", statusMs: 1_000_000),
        ])
        #expect(h.order == ["early", "late"])
    }

    @Test("pinned (attention) agents are Needs you and Error only")
    func attention() {
        #expect(AgentState.needsYou(.auth).needsAttention)
        #expect(AgentState.error.needsAttention)
        #expect(!AgentState.unknown.needsAttention)
        #expect(!AgentState.working.needsAttention)
    }

    @Test("Last status change is recorded locally from status, turn and foreground events")
    func lastStatusChange() {
        let h = Harness()
        h.connect([term("t1", "working")])
        h.scheduler.advance(by: 5)
        h.client.emit(.event(seq: 11, .turn(terminal: "t1", turn: 1, state: "idle")))
        #expect(h.store.agent("t1")?.lastStatusChange == h.scheduler.now)
        h.scheduler.advance(by: 5)
        h.client.emit(.event(seq: 12, .title(terminal: "t1", title: "x")))
        #expect(h.store.agent("t1")?.lastStatusChange == h.scheduler.now.addingTimeInterval(-5), "title is not activity")
        h.client.emit(.event(seq: 13, .foreground(terminal: "t1", foreground: CoreForeground(cwd: "/tmp/other"))))
        #expect(h.store.agent("t1")?.lastStatusChange == h.scheduler.now)
        #expect(h.store.agent("t1")?.projectName == "other", "project follows the foreground cwd")
    }

    @Test("individual colors are assigned once and survive re-sorting")
    func colorsStable() {
        let h = Harness()
        h.connect([term("a", "working"), term("b", "working"), term("c", "working")])
        let before = Dictionary(uniqueKeysWithValues: h.store.agents.map { ($0.address, $0.colorIndex) })
        #expect(Set(before.values).count == 3)
        h.status("c", "blocked", kind: "question", seq: 11)
        h.status("a", "idle", seq: 12)
        #expect(h.order.first == "c")
        let after = Dictionary(uniqueKeysWithValues: h.store.agents.map { ($0.address, $0.colorIndex) })
        #expect(before == after)
        // Survives a reconnect snapshot too.
        h.client.emit(.disconnected(reason: "x"))
        h.connect([term("c", "working"), term("b", "working"), term("a", "working")], seq: 50)
        let reconnected = Dictionary(uniqueKeysWithValues: h.store.agents.map { ($0.address, $0.colorIndex) })
        #expect(before == reconnected)
    }

    @Test("events at or below the snapshot seq are ignored")
    func seqFiltering() {
        let h = Harness()
        h.connect([term("t1", "working")], seq: 20)
        h.status("t1", "idle", seq: 20)
        #expect(h.state("t1") == .working)
        h.status("t1", "idle", seq: 21)
        #expect(h.state("t1") == .idle)
    }

    @Test("missed + fresh snapshot rebuilds the list")
    func missedRebuild() {
        let h = Harness()
        h.connect([term("t1", "working"), term("t2", "working")], seq: 10)
        h.client.emit(.missed)
        h.client.emit(.snapshot(seq: 40, terminals: [term("t2", "done"), term("t3", "blocked", kind: "auth")]))
        #expect(Set(h.order) == ["t2", "t3"])
        #expect(h.state("t2") == .done)
        #expect(h.state("t3") == .needsYou(.auth))
        h.status("t2", "working", seq: 39)
        #expect(h.state("t2") == .done, "stale events from before the snapshot are dropped")
    }

    @Test("agents started outside Herdr carry their origin app from the atoll.origin label (legacy island.origin still read)")
    func origin() {
        let h = Harness()
        var outside = term("t1", "working")
        outside.labels = ["atoll.origin": "com.mitchellh.ghostty"]
        var legacy = term("t3", "working")
        legacy.labels = ["island.origin": "com.cmuxterm.app"]
        h.connect([outside, term("t2", "working"), legacy])
        #expect(h.store.agent("t1")?.origin == "com.mitchellh.ghostty")
        #expect(h.store.agent("t2")?.origin == nil)
        #expect(h.store.agent("t3")?.origin == "com.cmuxterm.app")
    }

    @Test("a lost program is Unknown until restarted")
    func lost() {
        let h = Harness()
        h.connect([term("t1", "working")])
        h.client.emit(.event(seq: 11, .lost(terminal: "t1")))
        #expect(h.state("t1") == .unknown)
        h.client.emit(.event(seq: 12, .restarted(terminal: "t1")))
        #expect(h.state("t1") == .working)
    }
}
