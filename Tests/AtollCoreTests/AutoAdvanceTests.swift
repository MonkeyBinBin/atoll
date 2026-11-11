import Foundation
import Testing
@testable import AtollCore

@MainActor
@Suite("Auto-advance to the next waiting agent")
struct AutoAdvanceTests {
    final class Sink {
        var advanced: [String] = []
        var allClear = 0
    }

    /// t1 and t2 waiting (t1 first), t3 working; t1's panel is open.
    func harness() -> (Harness, Sink) {
        let h = Harness()
        let sink = Sink()
        h.store.onAutoAdvance = { sink.advanced.append($0) }
        h.store.onAllClear = { sink.allClear += 1 }
        h.connect([term("t1", "working"), term("t2", "working"), term("t3", "working")])
        h.status("t1", "blocked", kind: "question", seq: 11)
        h.scheduler.advance(by: 1)
        h.status("t2", "blocked", kind: "permission", seq: 12)
        h.store.openPanel("t1")
        return (h, sink)
    }

    @Test("answered from the panel and out of Needs you → after the grace period, the next waiting agent")
    func advances() async {
        let (h, sink) = harness()
        h.store.send("yes", to: "t1")
        await settle()
        h.status("t1", "working", seq: 13)
        h.scheduler.advance(by: 1.4)
        #expect(sink.advanced.isEmpty)
        h.scheduler.advance(by: 0.1)
        #expect(sink.advanced == ["t2"])
        #expect(sink.allClear == 0)
    }

    @Test("the next one is the earliest waiting, not list order")
    func earliestFirst() async {
        let (h, sink) = harness()
        h.scheduler.advance(by: 1)
        h.status("t3", "blocked", kind: "question", seq: 13)
        // t2 started waiting before t3.
        h.store.send("yes", to: "t1")
        await settle()
        h.status("t1", "working", seq: 14)
        h.scheduler.advance(by: 1.5)
        #expect(sink.advanced == ["t2"])
        #expect(h.store.nextWaitingAgent(excluding: "t2")?.address == "t3")
    }

    @Test("a permission key also counts as answering")
    func keysArm() async {
        let (h, sink) = harness()
        h.store.openPanel("t2")
        h.store.pressKey("1", on: "t2")
        await settle()
        h.status("t2", "working", seq: 13)
        h.scheduler.advance(by: 1.5)
        #expect(sink.advanced == ["t1"])
    }

    @Test("nobody else waiting → All clear, no advance")
    func allClear() async {
        let (h, sink) = harness()
        h.status("t2", "working", seq: 13)
        h.store.send("yes", to: "t1")
        await settle()
        h.status("t1", "working", seq: 14)
        h.scheduler.advance(by: 1.5)
        #expect(sink.advanced.isEmpty)
        #expect(sink.allClear == 1)
    }

    @Test("back in Needs you within the grace period (chained prompt) → stays")
    func chainedPromptStays() async {
        let (h, sink) = harness()
        h.store.send("yes", to: "t1")
        await settle()
        h.status("t1", "working", seq: 13)
        h.scheduler.advance(by: 0.5)
        h.status("t1", "blocked", kind: "permission", seq: 14)
        h.scheduler.advance(by: 5)
        #expect(sink.advanced.isEmpty)
        #expect(sink.allClear == 0)
    }

    @Test("leaving Needs you without a panel action (answered in the terminal) → stays")
    func noPanelActionStays() {
        let (h, sink) = harness()
        h.status("t1", "working", seq: 13)
        h.scheduler.advance(by: 5)
        #expect(sink.advanced.isEmpty)
        #expect(sink.allClear == 0)
    }

    @Test("a failed send disarms")
    func failedSendDisarms() async {
        let (h, sink) = harness()
        h.client.sendResult = .failure(HerdrError(kind: "x", message: "nope"))
        h.store.send("yes", to: "t1")
        await settle()
        h.status("t1", "working", seq: 13)
        h.scheduler.advance(by: 5)
        #expect(sink.advanced.isEmpty)
    }

    @Test("closing or switching the panel during the grace period → stays")
    func panelChangeCancels() async {
        let (h, sink) = harness()
        h.store.send("yes", to: "t1")
        await settle()
        h.status("t1", "working", seq: 13)
        h.store.closePanel()
        h.scheduler.advance(by: 5)
        #expect(sink.advanced.isEmpty)
    }

    @Test("going Unknown (offline) doesn't advance")
    func offlineStays() async {
        let (h, sink) = harness()
        h.store.send("yes", to: "t1")
        await settle()
        h.client.emit(.disconnected(reason: "gone"))
        h.scheduler.advance(by: 5)
        #expect(sink.advanced.isEmpty)
        #expect(sink.allClear == 0)
    }

    @Test("Off → never advances")
    func off() async {
        let (h, sink) = harness()
        h.store.autoAdvance = false
        h.store.send("yes", to: "t1")
        await settle()
        h.status("t1", "working", seq: 13)
        h.scheduler.advance(by: 5)
        #expect(sink.advanced.isEmpty)
        #expect(sink.allClear == 0)
    }
}
