import Foundation
import Testing
@testable import AtollCore

/// An agent that goes away leaves nothing behind in what the store shows, and nothing of it fires later
/// (tickets 51, 52). The trackers' own leftovers are covered by their suites.
@MainActor
@Suite("Agent teardown")
struct AgentTeardownTests {
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

    /// What was asked of agents (the stale timer's reconnect isn't about any one of them).
    private func agentCommands(_ h: Harness) -> [FakeHerdrClient.Command] {
        h.client.commands.filter { $0 != .reconnect }
    }

    private func holdsNothing(_ store: AgentStore, for address: String) -> Bool {
        store.sendStates[address] == nil && store.keyStates[address] == nil
            && store.listAnswers[address] == nil && store.interruptStates[address] == nil
            && store.lastInterruptError[address] == nil && !store.notifyWhenDone.contains(address)
            && store.queuedMessages[address] == nil && !store.isReadingWaitingScreen(address)
    }

    @Test("removed by an event: nothing of it is shown, and nothing of it fires later")
    func removedEvent() async {
        let h = Harness()
        var reminded: [String] = []
        h.store.onReminder = { agent, _ in reminded.append(agent.address) }
        await busy(h)
        #expect(!holdsNothing(h.store, for: "t1"))
        h.client.emit(.event(seq: 12, .removed(terminal: "t1")))
        await settle()
        #expect(holdsNothing(h.store, for: "t1"))
        let commands = agentCommands(h)
        h.scheduler.advance(by: 600)
        await settle()
        #expect(holdsNothing(h.store, for: "t1"))
        #expect(reminded.isEmpty)
        #expect(agentCommands(h) == commands)
        #expect(h.store.agent("t2") != nil)
    }

    @Test("dropped from a snapshot after a failed interrupt and a finished turn: nothing of it remains")
    func droppedFromSnapshot() async {
        let h = Harness()
        h.connect([term("t1", "working"), term("t2", "working")])
        h.client.interruptResult = .failure(.unavailable("gone"))
        h.store.pressInterrupt("t1")
        h.store.pressInterrupt("t1")
        await settle()
        #expect(h.store.lastInterruptError["t1"] != nil)
        h.status("t1", "done", seq: 11)
        await settle()
        h.client.emit(.snapshot(seq: 20, terminals: [term("t2", "working")]))
        await settle()
        #expect(holdsNothing(h.store, for: "t1"))
        let commands = agentCommands(h)
        h.scheduler.advance(by: 600)
        await settle()
        #expect(holdsNothing(h.store, for: "t1"))
        #expect(agentCommands(h) == commands)
    }

    @Test("an agent back at the same address starts clean: no last words or change summary from before")
    func sameAddressAgain() async {
        let h = Harness()
        h.store.changeProbe = FakeProbe()
        h.client.readResult = .success(ReadOutput(text: FinalScreens.claudeShort, how: "screen"))
        h.connect([term("t1", "working"), term("t2", "working")])
        h.status("t1", "done", seq: 11)
        await settle()
        h.scheduler.advance(by: 1)
        await settle()
        #expect(h.store.agent("t1")?.finalMessage != nil)
        #expect(h.store.agent("t1")?.changeSummary != nil)
        h.client.emit(.event(seq: 12, .removed(terminal: "t1")))
        await settle()
        h.client.emit(.event(seq: 13, .created(term("t1", "idle"))))
        await settle()
        #expect(h.store.agent("t1") != nil)
        #expect(h.store.agent("t1")?.finalMessage == nil)
        #expect(h.store.agent("t1")?.changeSummary == nil)
    }

    @Test("a send still in flight when its agent goes away doesn't bring its state back")
    func lateSend() async {
        let h = Harness()
        h.connect([term("t1", "idle")])
        h.client.holdSend = true
        var heard: SendState?
        #expect(h.store.send("hi", to: "t1") { heard = $0 })
        h.client.emit(.event(seq: 11, .removed(terminal: "t1")))
        await settle()
        h.client.releaseSend()
        await settle()
        #expect(heard != nil)
        #expect(holdsNothing(h.store, for: "t1"))
    }
}
