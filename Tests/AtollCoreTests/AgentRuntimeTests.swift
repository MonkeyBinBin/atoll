import Foundation
import Testing
@testable import AtollCore

/// Ticket 51: an agent that goes away leaves no per-agent state or pending timer behind.
@MainActor
@Suite("Agent runtime teardown")
struct AgentRuntimeTests {
    /// Drives t1 through most per-agent state: a permission wait (screen read, reminder), a list response
    /// that came too late, an armed interrupt, the done bell, a queued message, a sent key.
    private func busy(_ h: Harness) async {
        h.store.reminderDelay = 300
        h.connect([term("t1", "working"), term("t2", "working")])
        h.store.toggleNotifyWhenDone("t1")
        h.store.queue("next", for: "t1")
        h.status("t1", "blocked", kind: "permission", seq: 11)
        await settle()
        h.store.respond(.allow, to: "t1", episode: Date(timeIntervalSince1970: 0))
        h.store.pressInterrupt("t1")
        h.store.pressKey("y", on: "t1")
        await settle()
    }

    @Test("removed by an event: nothing of it remains")
    func removedEvent() async {
        let h = Harness()
        await busy(h)
        #expect(!h.store.residue(of: "t1").isEmpty)
        h.client.emit(.event(seq: 12, .removed(terminal: "t1")))
        await settle()
        #expect(h.store.residue(of: "t1") == [])
        h.scheduler.advance(by: 600)
        await settle()
        #expect(h.store.residue(of: "t1") == [])
        #expect(h.store.agent("t2") != nil)
    }

    @Test("its timers are cancelled: as many stay scheduled as for the agents that remain")
    func timersCancelled() async {
        let h = Harness()
        await busy(h)
        h.client.emit(.event(seq: 12, .removed(terminal: "t1")))
        await settle()
        let control = Harness()
        control.store.reminderDelay = 300
        control.connect([term("t2", "working")])
        await settle()
        #expect(h.scheduler.liveCount == control.scheduler.liveCount)
    }

    @Test("dropped from a snapshot after an interrupt and a finished turn: nothing of it remains")
    func droppedFromSnapshot() async {
        let h = Harness()
        h.connect([term("t1", "working"), term("t2", "working")])
        h.store.pressInterrupt("t1")
        h.store.pressInterrupt("t1")
        await settle()
        h.status("t1", "done", seq: 11)
        await settle()
        h.store.openPanel("t1")
        h.store.closePanel()
        #expect(!h.store.residue(of: "t1").isEmpty)
        h.client.emit(.snapshot(seq: 20, terminals: [term("t2", "working")]))
        await settle()
        #expect(h.store.residue(of: "t1") == [])
        h.scheduler.advance(by: 600)
        await settle()
        #expect(h.store.residue(of: "t1") == [])
    }

    @Test("a send still in flight when its agent goes away doesn't bring its state back")
    func lateSend() async {
        let h = Harness()
        h.connect([term("t1", "idle")])
        h.client.holdSend = true
        #expect(h.store.send("hi", to: "t1"))
        h.client.emit(.event(seq: 11, .removed(terminal: "t1")))
        await settle()
        h.client.releaseSend()
        await settle()
        #expect(h.store.residue(of: "t1") == [])
    }
}
