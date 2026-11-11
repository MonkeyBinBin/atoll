import Foundation
import Testing
@testable import AtollCore

@MainActor
@Suite("Speech bubbles")
struct BubbleTests {
    final class Sink {
        var rules = BubbleRules()
        var sent: [AgentBubble] = []
        var labels: [String] { sent.map(\.state.label) }
    }

    func harness() -> (Harness, Sink) {
        let h = Harness()
        let sink = Sink()
        h.store.onTransition = { agent, from in
            if let bubble = sink.rules.bubble(for: agent, from: from) { sink.sent.append(bubble) }
        }
        return (h, sink)
    }

    @Test("stopping or needing the user bubbles; Working never does")
    func triggers() {
        let (h, sink) = harness()
        h.connect([term("t1", "idle")])
        h.status("t1", "working", seq: 11)
        #expect(sink.sent.isEmpty)
        h.status("t1", "blocked", kind: "permission", seq: 12)
        h.status("t1", "working", seq: 13)
        h.status("t1", "error", seq: 14)
        h.status("t1", "working", seq: 15)
        h.status("t1", "done", seq: 16)
        #expect(sink.labels == ["Needs you", "Error", "Done"])
        #expect(sink.sent.first?.isUrgent == true)
        #expect(sink.sent.last?.isUrgent == false)
    }

    @Test("Done always bubbles, without the notification opt-in")
    func doneWithoutOptIn() {
        let (h, sink) = harness()
        h.connect([term("t1", "working")])
        h.status("t1", "done", seq: 11)
        #expect(sink.labels == ["Done"])
    }

    @Test("Working → Idle (stopped turn) bubbles; Done → Idle doesn't")
    func idle() {
        let (h, sink) = harness()
        h.connect([term("t1", "working"), term("t2", "working")])
        h.status("t1", "idle", seq: 11)
        h.status("t2", "done", seq: 12)
        h.status("t2", "idle", seq: 13)
        #expect(sink.sent.map { "\($0.address):\($0.state.label)" } == ["t1:Idle", "t2:Done"])
    }

    @Test("flapping Working ↔ Idle within one turn bubbles once")
    func idleFlap() {
        let (h, sink) = harness()
        h.connect([term("t1", "working")])
        h.status("t1", "idle", seq: 11)
        h.status("t1", "working", seq: 12)
        h.status("t1", "idle", seq: 13)
        #expect(sink.labels == ["Idle"])
    }

    @Test("kind changes and reconnects don't repeat a bubble")
    func noDuplicates() {
        let (h, sink) = harness()
        h.connect([term("t1", "working")])
        h.status("t1", "blocked", kind: "question", seq: 11)
        h.status("t1", "blocked", kind: "permission", seq: 12)
        h.client.emit(.disconnected(reason: "x"))
        h.connect([term("t1", "blocked", kind: "permission")], seq: 30)
        h.status("t1", "blocked", kind: "permission", seq: 31)
        #expect(sink.sent.count == 1)
    }

    @Test("going offline doesn't bubble")
    func offlineSilent() {
        let (h, sink) = harness()
        h.connect([term("t1", "working")])
        h.client.emit(.disconnected(reason: "x"))
        #expect(sink.sent.isEmpty)
    }

    @Test("a first sighting doesn't bubble")
    func firstSighting() {
        var rules = BubbleRules()
        let agent = Agent(address: "t1", state: .done)
        #expect(rules.bubble(for: agent, from: nil) == nil)
        #expect(rules.bubble(for: agent, from: .working) != nil)
    }
}
