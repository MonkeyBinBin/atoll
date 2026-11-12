import Foundation
import Testing
@testable import AtollCore

@MainActor
@Suite("Today timeline")
struct TimelineTests {
    func harness(_ terminals: [TerminalInfo] = [term("t1", "working")]) -> Harness {
        let h = Harness()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        h.store.calendar = calendar
        h.connect(terminals)
        return h
    }

    func line(_ entry: TimelineEntry) -> String {
        "\(entry.address) \(entry.state.label) \(entry.lastWords ?? "-") \(entry.changes ?? "-")"
    }

    func lines(_ h: Harness) -> [String] { h.store.timeline.entries.map(line) }

    @Test("a finished turn records one entry with when, who, where and how it ended")
    func recordsTurnEnd() throws {
        let h = harness()
        h.status("t1", "done", seq: 11)
        let entry = try #require(h.store.timeline.entries.first)
        #expect(h.store.timeline.entries.count == 1)
        #expect(entry.at == h.scheduler.now)
        #expect(entry.displayName == "Claude Code · project-x")
        #expect(entry.projectName == "project-x")
        #expect(entry.state == .done)
        #expect(entry.unseen)
    }

    @Test("Needs you isn't a finished turn; settling Done → Idle → Exited stays one entry; Error and a stopped turn count")
    func whatCounts() {
        let h = harness([term("t1", "working"), term("t2", "working"), term("t3", "working")])
        h.status("t1", "blocked", kind: "permission", seq: 11)
        #expect(h.store.timeline.entries.isEmpty)
        h.status("t1", "working", seq: 12)
        h.status("t1", "done", seq: 13)
        h.status("t1", "idle", seq: 14)
        h.client.emit(.event(seq: 15, .finished(terminal: "t1", exitCode: 0, reason: "exited", finishedMs: nil)))
        h.status("t2", "error", seq: 16)
        h.status("t3", "idle", seq: 17)
        #expect(lines(h) == ["t1 Done - -", "t2 Error - -", "t3 Idle - -"])
    }

    @Test("a reconnect in the same finished turn doesn't record it again; the next turn does")
    func reconnect() {
        let h = harness()
        h.status("t1", "done", seq: 11)
        h.client.emit(.disconnected(reason: "x"))
        h.connect([term("t1", "done")], seq: 30)
        h.status("t1", "done", seq: 31)
        #expect(h.store.timeline.entries.count == 1)
        h.status("t1", "working", seq: 32)
        h.status("t1", "done", seq: 33)
        #expect(h.store.timeline.entries.count == 2)
    }

    @Test("last words read off the screen later land in the same entry, and stay after the next turn drops them")
    func lateLastWords() async {
        let h = harness([term("t1", "working", app: "codex")])
        h.client.readResult = .success(ReadOutput(text: FinalScreens.codexShort, how: "screen"))
        h.status("t1", "done", app: "codex", seq: 11)
        #expect(lines(h) == ["t1 Done - -"])
        h.scheduler.advance(by: h.store.timing.previewDelay)
        await settle()
        #expect(h.store.timeline.entries.count == 1)
        let words = h.store.agent("t1")?.lastWords
        #expect(words != nil)
        #expect(h.store.timeline.entries.first?.lastWords == words)
        h.status("t1", "working", app: "codex", seq: 12)
        #expect(h.store.agent("t1")?.lastWords == nil)
        #expect(h.store.timeline.entries.first?.lastWords == words)
    }

    @Test("a source's status message is kept cut like the final message: 2 lines, 200 characters each")
    func statusMessageCut() {
        let h = harness()
        let long = String(repeating: "x", count: 300)
        h.client.emit(.event(seq: 11, .status(terminal: "t1", status: CoreStatus(state: "done", app: "claude-code", msg: "one\ntwo\n" + long), reported: true)))
        let words = h.store.timeline.entries.first?.lastWords
        #expect(words?.hasPrefix("two\n") == true)
        #expect(words?.split(separator: "\n").last?.count == 200)
    }

    @Test("change counts arrive when git answers and fill the same entry")
    func lateChanges() async {
        let h = harness([term("t1", "idle")])
        h.store.changeProbe = FakeProbe()
        h.status("t1", "working", seq: 11)
        await settle()
        h.status("t1", "done", seq: 12)
        #expect(h.store.timeline.entries.first?.changes == nil)
        await settle()
        let text = h.store.agent("t1")?.changeSummary?.text
        #expect(text != nil)
        #expect(h.store.timeline.entries.first?.changes == text)
        #expect(h.store.timeline.entries.count == 1)
    }

    @Test("an agent's entries outlive it; a new agent at the same address gets its own entry")
    func outlivesAgent() {
        let h = harness()
        h.status("t1", "done", seq: 11)
        h.client.emit(.event(seq: 12, .removed(terminal: "t1")))
        #expect(h.store.agent("t1") == nil)
        #expect(lines(h) == ["t1 Done - -"])
        h.client.emit(.event(seq: 13, .created(term("t1", "working"))))
        h.status("t1", "done", seq: 14)
        #expect(lines(h) == ["t1 Done - -", "t1 Done - -"])
    }

    @Test("at most 200 entries: the oldest go first")
    func limit() {
        let h = harness()
        var seq: UInt64 = 10
        for _ in 0..<205 {
            seq += 1
            h.status("t1", "working", seq: seq)
            seq += 1
            h.status("t1", "done", seq: seq)
            h.scheduler.advance(by: 1)
        }
        let entries = h.store.timeline.entries
        #expect(entries.count == TodayTimeline.limit)
        #expect(entries.first?.at == Date(timeIntervalSince1970: 1_800_000_005))
    }

    @Test("only today: local midnight empties the timeline, even with nothing else happening")
    func midnight() {
        let h = harness()
        // The fake clock starts at 08:00 UTC.
        h.status("t1", "done", seq: 11)
        h.scheduler.advance(by: 15 * 3600)
        #expect(h.store.timeline.entries.count == 1)
        h.scheduler.advance(by: 3600)
        #expect(h.store.timeline.entries.isEmpty)
        // And the next day starts over, still bounded by its own midnight.
        h.status("t1", "working", seq: 12)
        h.status("t1", "done", seq: 13)
        h.scheduler.advance(by: 23 * 3600)
        #expect(h.store.timeline.entries.count == 1)
        h.scheduler.advance(by: 3600)
        #expect(h.store.timeline.entries.isEmpty)
    }

    @Test("entries are unseen until that agent's panel opens; one ending while its panel is open is seen")
    func unseen() {
        let h = harness([term("t1", "working"), term("t2", "working")])
        h.status("t1", "done", seq: 11)
        h.status("t1", "working", seq: 12)
        h.status("t1", "done", seq: 13)
        h.store.openPanel("t2")
        h.status("t2", "done", seq: 14)
        #expect(h.store.timeline.entries.map(\.unseen) == [true, true, false])
        #expect(h.store.timeline.unseenCount == 2)
        h.store.openPanel("t1")
        #expect(h.store.timeline.unseenCount == 0)
    }

    @Test("turned off, nothing is collected and what was there goes; Clear empties it")
    func offAndClear() {
        let h = harness()
        h.status("t1", "done", seq: 11)
        h.store.timelineEnabled = false
        #expect(h.store.timeline.entries.isEmpty)
        h.status("t1", "working", seq: 12)
        h.status("t1", "done", seq: 13)
        #expect(h.store.timeline.entries.isEmpty)
        h.store.timelineEnabled = true
        h.status("t1", "working", seq: 14)
        h.status("t1", "done", seq: 15)
        #expect(h.store.timeline.entries.count == 1)
        h.store.clearTimeline()
        #expect(h.store.timeline.entries.isEmpty)
        // Cleared mid-turn-end: late details don't resurrect it.
        h.status("t1", "idle", seq: 16)
        #expect(h.store.timeline.entries.isEmpty)
    }

    func turnEvent(_ h: Harness, _ address: String, _ turn: UInt64, seq: UInt64) {
        h.client.emit(.event(seq: seq, .turn(terminal: address, turn: turn, state: "done")))
    }

    func msg(_ h: Harness, _ state: String, _ text: String?, kind: String? = nil, seq: UInt64) {
        h.client.emit(.event(seq: seq, .status(terminal: "t1", status: CoreStatus(state: state, app: "claude-code", kind: kind, msg: text), reported: true)))
    }

    @Test("the next turn's status message never lands in the previous entry")
    func noLeakFromNextTurn() {
        let h = harness()
        h.client.readResult = .failure(.unavailable("gone"))
        h.status("t1", "done", seq: 11)
        msg(h, "blocked", "approve Bash: rm -rf dist", kind: "permission", seq: 12)
        #expect(h.store.timeline.entries.first?.lastWords == nil)
    }

    @Test("a turn that ends without a Working in between is still its own entry")
    func newTurnWithoutWorking() {
        let h = harness()
        msg(h, "done", "first", seq: 11)
        turnEvent(h, "t1", 1, seq: 12)
        msg(h, "idle", nil, seq: 13)
        msg(h, "done", "second", seq: 14)
        #expect(lines(h) == ["t1 Done first -", "t1 Done second -"])
    }

    @Test("Error after Done is its own entry with the source's message only, not the Done's details")
    func errorAfterDone() async {
        let h = harness([term("t1", "idle")])
        h.store.changeProbe = FakeProbe()
        h.status("t1", "working", seq: 11)
        await settle()
        msg(h, "done", "all good", seq: 12)
        msg(h, "error", "rate limited", seq: 13)
        await settle()
        let entries = h.store.timeline.entries
        #expect(entries.map(\.state) == [.done, .error])
        #expect(entries.last?.lastWords == "rate limited")
        #expect(entries.last?.changes == nil)
        #expect(entries.first?.lastWords == "all good")
    }

    @Test("exited or removed, an agent's entries are marked gone for good, even if the address comes back")
    func gone() {
        let h = harness()
        h.status("t1", "done", seq: 11)
        #expect(h.store.timeline.entries.first?.gone == false)
        h.client.emit(.event(seq: 12, .finished(terminal: "t1", exitCode: 0, reason: "exited", finishedMs: nil)))
        // Still in the list for a while after exiting, but no longer reachable.
        #expect(h.store.agent("t1") != nil)
        #expect(h.store.timeline.entries.first?.gone == true)
        h.client.emit(.event(seq: 13, .removed(terminal: "t1")))
        h.client.emit(.event(seq: 14, .created(term("t1", "working"))))
        #expect(h.store.timeline.entries.first?.gone == true)
    }

    @Test("an agent quitting back to its shell (status cleared) is gone too; going offline isn't")
    func goneWhenStatusCleared() {
        let h = harness([term("t1", "working"), term("t2", "working")])
        h.status("t1", "done", seq: 11)
        h.status("t2", "done", seq: 12)
        h.status("t1", nil, seq: 13)
        h.client.emit(.disconnected(reason: "x"))
        #expect(h.store.timeline.entries.map(\.gone) == [true, false])
    }

    @Test("a day change noticed late (e.g. after sleep) drops yesterday's entries")
    func rollOver() {
        let h = harness()
        h.status("t1", "done", seq: 11)
        h.store.rollOverTimeline()
        #expect(h.store.timeline.entries.count == 1)
        // The clock jumped past midnight without the timer firing (asleep).
        h.scheduler.now = h.scheduler.now.addingTimeInterval(20 * 3600)
        h.store.rollOverTimeline()
        #expect(h.store.timeline.entries.isEmpty)
    }
}
