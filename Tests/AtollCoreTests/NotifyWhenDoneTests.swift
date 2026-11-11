import Foundation
import Testing
@testable import AtollCore

@MainActor
@Suite("Notify when done (one-shot)")
struct NotifyWhenDoneTests {
    /// Wires the store like the app: transitions through the rules first, then the one-shot.
    final class Sink {
        var rules = NotificationRules()
        var settings = NotificationSettings()
        var sent: [AgentNotification] = []
    }

    func harness() -> (Harness, Sink) {
        let h = Harness()
        let sink = Sink()
        h.store.onTransition = { agent, from in
            if let note = sink.rules.notification(for: agent, from: from, settings: sink.settings) { sink.sent.append(note) }
        }
        h.store.onNotifyWhenDone = { agent in
            if let note = sink.rules.finished(for: agent, settings: sink.settings) { sink.sent.append(note) }
        }
        h.connect([term("t1", "working"), term("t2", "working")])
        return (h, sink)
    }

    @Test("armed: the next Done notifies once, then the bell is off")
    func doneFiresOnce() {
        let (h, sink) = harness()
        h.store.toggleNotifyWhenDone("t1")
        #expect(h.store.notifyWhenDone == ["t1"])
        h.status("t1", "done", seq: 11)
        #expect(sink.sent.map(\.body) == ["Done"])
        #expect(sink.sent.first?.address == "t1")
        #expect(h.store.notifyWhenDone.isEmpty)
        h.status("t1", "working", seq: 12)
        h.status("t1", "done", seq: 13)
        #expect(sink.sent.count == 1)
    }

    @Test("Idle straight from Working counts as finished; Done → Idle doesn't")
    func idleFromWorking() {
        let (h, sink) = harness()
        h.store.toggleNotifyWhenDone("t1")
        h.status("t1", "idle", seq: 11)
        #expect(sink.sent.map(\.body) == ["Idle"])
        #expect(h.store.notifyWhenDone.isEmpty)
    }

    @Test("Exited counts as finished")
    func exited() {
        let (h, sink) = harness()
        h.store.toggleNotifyWhenDone("t1")
        h.client.emit(.event(seq: 11, .finished(terminal: "t1", exitCode: 0, reason: nil, finishedMs: nil)))
        #expect(h.state("t1") == .exited)
        #expect(sink.sent.map(\.body) == ["Exited"])
    }

    @Test("Needs you keeps it armed (and notifies as usual); the later Done fires")
    func needsYouKeepsArmed() {
        let (h, sink) = harness()
        h.store.toggleNotifyWhenDone("t1")
        h.status("t1", "blocked", kind: "question", seq: 11)
        #expect(sink.sent.map(\.body) == ["Needs you"])
        #expect(h.store.notifyWhenDone == ["t1"])
        h.status("t1", "working", seq: 12)
        h.status("t1", "done", seq: 13)
        #expect(sink.sent.map(\.body) == ["Needs you", "Done"])
    }

    @Test("Error disarms without a second notification")
    func errorDisarms() {
        let (h, sink) = harness()
        h.store.toggleNotifyWhenDone("t1")
        h.status("t1", "error", seq: 11)
        #expect(sink.sent.map(\.body) == ["Error"])
        #expect(h.store.notifyWhenDone.isEmpty)
    }

    @Test("armed while already Done: waits for the next finished turn")
    func armedWhileDone() {
        let (h, sink) = harness()
        h.status("t1", "done", seq: 11)
        h.store.toggleNotifyWhenDone("t1")
        h.client.emit(.event(seq: 12, .title(terminal: "t1", title: "x")))
        #expect(sink.sent.isEmpty)
        h.status("t1", "working", seq: 13)
        h.status("t1", "done", seq: 14)
        #expect(sink.sent.map(\.body) == ["Done"])
    }

    @Test("with the always-on Done list too, one transition notifies once")
    func noDoubleWithPermanent() {
        let (h, sink) = harness()
        sink.settings.doneAgents = ["t1"]
        h.store.toggleNotifyWhenDone("t1")
        h.status("t1", "done", seq: 11)
        #expect(sink.sent.count == 1)
        #expect(h.store.notifyWhenDone.isEmpty)
    }

    @Test("toggling twice disarms; other agents are unaffected")
    func toggleOff() {
        let (h, sink) = harness()
        h.store.toggleNotifyWhenDone("t1")
        h.store.toggleNotifyWhenDone("t1")
        h.status("t1", "done", seq: 11)
        h.status("t2", "done", seq: 12)
        #expect(sink.sent.isEmpty)
    }

    @Test("the master switch silences it but still disarms")
    func masterSwitch() {
        let (h, sink) = harness()
        sink.settings.enabled = false
        h.store.toggleNotifyWhenDone("t1")
        h.status("t1", "done", seq: 11)
        #expect(sink.sent.isEmpty)
        #expect(h.store.notifyWhenDone.isEmpty)
    }

    @Test("a removed agent drops its bell")
    func removedClears() {
        let (h, _) = harness()
        h.store.toggleNotifyWhenDone("t1")
        h.client.emit(.event(seq: 11, .removed(terminal: "t1")))
        #expect(h.store.notifyWhenDone.isEmpty)
    }
}
