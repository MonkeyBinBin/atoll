import Foundation
import Testing
@testable import AtollCore

/// Lets time pass with heartbeats every 15 s, so the source stays live (not Unknown).
@MainActor
private func elapse(_ h: Harness, _ seconds: TimeInterval) {
    var left = seconds
    while left > 0 {
        let step = min(15, left)
        h.scheduler.advance(by: step)
        left -= step
        if h.store.connection == .connected { h.client.emit(.heartbeat(seq: 10)) }
    }
}

@MainActor
@Suite("Waiting reminders")
struct ReminderTests {
    final class Sink {
        var reminded: [(address: String, waited: TimeInterval)] = []
    }

    func harness(delay: TimeInterval? = 300) -> (Harness, Sink) {
        let h = Harness()
        let sink = Sink()
        h.store.reminderDelay = delay
        h.store.onReminder = { agent, waited in sink.reminded.append((agent.address, waited)) }
        return (h, sink)
    }

    @Test("an agent still waiting past the delay is reminded once")
    func remindsOnce() {
        let (h, sink) = harness()
        h.connect([term("t1", "working")])
        h.status("t1", "blocked", kind: "question", seq: 11)
        elapse(h, 299)
        #expect(sink.reminded.isEmpty)
        elapse(h, 1)
        #expect(sink.reminded.map(\.address) == ["t1"])
        #expect(sink.reminded.first?.waited == 300)
        elapse(h, 3600)
        #expect(sink.reminded.count == 1)
    }

    @Test("a blocked kind change keeps the same episode and clock")
    func kindChangeKeepsClock() {
        let (h, sink) = harness()
        h.connect([term("t1", "working")])
        h.status("t1", "blocked", kind: "question", seq: 11)
        elapse(h, 200)
        h.status("t1", "blocked", kind: "permission", seq: 12)
        elapse(h, 100)
        #expect(sink.reminded.map(\.address) == ["t1"])
    }

    @Test("leaving Needs you cancels; coming back starts a new episode")
    func leavingCancels() {
        let (h, sink) = harness()
        h.connect([term("t1", "working")])
        h.status("t1", "blocked", kind: "question", seq: 11)
        elapse(h, 200)
        h.status("t1", "working", seq: 12)
        elapse(h, 200)
        #expect(sink.reminded.isEmpty)
        h.status("t1", "blocked", kind: "permission", seq: 13)
        elapse(h, 299)
        #expect(sink.reminded.isEmpty)
        elapse(h, 1)
        #expect(sink.reminded.count == 1)
    }

    @Test("a reminded episode followed by a new one reminds again")
    func newEpisodeRemindsAgain() {
        let (h, sink) = harness()
        h.connect([term("t1", "working")])
        h.status("t1", "blocked", kind: "question", seq: 11)
        elapse(h, 300)
        h.status("t1", "working", seq: 12)
        h.status("t1", "blocked", kind: "question", seq: 13)
        elapse(h, 300)
        #expect(sink.reminded.count == 2)
    }

    @Test("due while its panel is open: skipped for the whole episode")
    func panelOpenSkips() {
        let (h, sink) = harness()
        h.connect([term("t1", "working")])
        h.status("t1", "blocked", kind: "question", seq: 11)
        h.store.openPanel("t1")
        elapse(h, 300)
        h.store.closePanel()
        elapse(h, 3600)
        #expect(sink.reminded.isEmpty)
    }

    @Test("another agent's panel being open doesn't skip")
    func otherPanelDoesNotSkip() {
        let (h, sink) = harness()
        h.connect([term("t1", "working"), term("t2", "idle")])
        h.status("t1", "blocked", kind: "question", seq: 11)
        h.store.openPanel("t2")
        elapse(h, 300)
        #expect(sink.reminded.map(\.address) == ["t1"])
    }

    @Test("Off never reminds; turning it on counts from then")
    func off() {
        let (h, sink) = harness(delay: nil)
        h.connect([term("t1", "working")])
        h.status("t1", "blocked", kind: "question", seq: 11)
        elapse(h, 3600)
        #expect(sink.reminded.isEmpty)
        h.store.reminderDelay = 120
        elapse(h, 119)
        #expect(sink.reminded.isEmpty)
        elapse(h, 1)
        #expect(sink.reminded.count == 1)
    }

    @Test("offline (Unknown) doesn't remind")
    func offline() {
        let (h, sink) = harness()
        h.connect([term("t1", "working")])
        h.status("t1", "blocked", kind: "question", seq: 11)
        elapse(h, 100)
        h.client.emit(.disconnected(reason: "gone"))
        #expect(h.state("t1") == .unknown)
        elapse(h, 3600)
        #expect(sink.reminded.isEmpty)
    }

    @Test("an already-reminded episode isn't reminded again after a reconnect")
    func reconnectKeepsMark() {
        let (h, sink) = harness()
        h.connect([term("t1", "working")])
        h.status("t1", "blocked", kind: "question", seq: 11)
        elapse(h, 300)
        h.client.emit(.disconnected(reason: "gone"))
        h.connect([term("t1", "blocked", kind: "question")], seq: 20)
        elapse(h, 3600)
        #expect(sink.reminded.count == 1)
    }

    @Test("a snapshot with an old waitingSince counts from the snapshot, not from then")
    func snapshotCountsFromNow() {
        let (h, sink) = harness()
        let oldMs = UInt64((h.scheduler.now.timeIntervalSince1970 - 3600) * 1000)
        h.connect([term("t1", "blocked", kind: "question", statusMs: oldMs)])
        elapse(h, 1)
        #expect(sink.reminded.isEmpty)
        elapse(h, 299)
        #expect(sink.reminded.map(\.address) == ["t1"])
        // The reported wait is the real one, since the source's timestamp.
        #expect(sink.reminded.first?.waited == 3900)
    }

    @Test("reminder notification: tool · project and minutes only; respects the master switch")
    func notificationContent() {
        let (h, _) = harness()
        h.connect([term("t1", "working", app: "codex")])
        h.client.emit(.event(seq: 11, .status(terminal: "t1", status: CoreStatus(state: "blocked", app: "codex", kind: "question", msg: "secret plan"), reported: true)))
        let agent = try! #require(h.store.agent("t1"))
        let rules = NotificationRules()
        let note = try! #require(rules.reminder(for: agent, waited: 330, settings: NotificationSettings()))
        #expect(note.title == "Codex · project-x")
        #expect(note.body == "Still needs you · 5m")
        #expect(!note.body.contains("secret"))
        #expect(rules.reminder(for: agent, waited: 330, settings: NotificationSettings(enabled: false)) == nil)
    }
}
