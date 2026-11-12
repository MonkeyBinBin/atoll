import Foundation
import Testing
@testable import AtollCore

@MainActor
@Suite("Queued message (send when the turn ends)")
struct QueuedMessageTests {
    func harness() -> Harness {
        let h = Harness()
        h.connect([term("t1", "working"), term("t2", "working")])
        return h
    }

    var sends: (Harness) -> [FakeHerdrClient.Command] {
        { h in h.client.commands.filter { if case .send = $0 { true } else { false } } }
    }

    @Test("Working → Done sends the queued text once and clears the queue")
    func doneSendsOnce() async {
        let h = harness()
        #expect(h.store.queue("run the tests", for: "t1"))
        #expect(h.store.queuedMessages["t1"]?.text == "run the tests")
        h.status("t1", "done", seq: 11)
        await settle()
        #expect(sends(h) == [.send("t1", "run the tests", force: false)])
        #expect(h.store.queuedMessages["t1"] == nil)
        #expect(h.store.sendStates["t1"] == .started)
        h.status("t1", "working", seq: 12)
        h.status("t1", "done", seq: 13)
        await settle()
        #expect(sends(h).count == 1)
    }

    @Test("Idle straight from Working sends")
    func idleFromWorking() async {
        let h = harness()
        h.store.queue("next", for: "t1")
        h.status("t1", "idle", seq: 11)
        await settle()
        #expect(sends(h) == [.send("t1", "next", force: false)])
    }

    @Test("Needs you doesn't consume it: a question isn't answered with it; the later Done sends")
    func needsYouKeepsWaiting() async {
        let h = harness()
        h.store.queue("next", for: "t1")
        h.status("t1", "blocked", kind: "question", seq: 11)
        h.status("t1", "blocked", kind: "permission", seq: 12)
        h.status("t1", "idle", seq: 13)
        await settle()
        #expect(sends(h).isEmpty)
        #expect(h.store.queuedMessages["t1"]?.status == .waiting)
        h.status("t1", "working", seq: 14)
        h.status("t1", "done", seq: 15)
        await settle()
        #expect(sends(h) == [.send("t1", "next", force: false)])
    }

    @Test("only a working agent takes a queued message; empty text is refused, trailing newlines trimmed")
    func onlyWhileWorking() {
        let h = harness()
        h.status("t2", "done", seq: 11)
        #expect(!h.store.queue("x", for: "t2"))
        #expect(!h.store.queue("   ", for: "t1"))
        #expect(h.store.queuedMessages.isEmpty)
        h.store.queue("run it\n ", for: "t1")
        #expect(h.store.queuedMessages["t1"]?.text == "run it")
    }

    @Test("queuing again replaces; cancel and edit take it out")
    func replaceCancelEdit() async {
        let h = harness()
        h.store.queue("first", for: "t1")
        h.store.queue("second", for: "t1")
        #expect(h.store.queuedMessages["t1"]?.text == "second")
        #expect(h.store.editQueued("t1") == "second")
        #expect(h.store.queuedMessages["t1"] == nil)
        h.store.queue("third", for: "t1")
        h.store.cancelQueued("t1")
        h.status("t1", "done", seq: 11)
        await settle()
        #expect(sends(h).isEmpty)
    }

    @Test("Error holds it unsent; the user can send it now or cancel")
    func errorHolds() async {
        let h = harness()
        h.store.queue("next", for: "t1")
        h.status("t1", "error", seq: 11)
        await settle()
        #expect(sends(h).isEmpty)
        #expect(h.store.queuedMessages["t1"] == QueuedMessage(text: "next", status: .held))
        // Held stays held even if the agent later finishes a turn.
        h.status("t1", "working", seq: 12)
        h.status("t1", "done", seq: 13)
        await settle()
        #expect(sends(h).isEmpty)
        h.store.sendQueuedNow("t1")
        await settle()
        #expect(sends(h) == [.send("t1", "next", force: false)])
        #expect(h.store.queuedMessages["t1"] == nil)
    }

    @Test("Exited drops it, with a one-time note while its panel is open")
    func exitedDrops() async {
        let h = harness()
        h.store.openPanel("t1")
        h.store.queue("next", for: "t1")
        h.client.emit(.event(seq: 11, .finished(terminal: "t1", exitCode: 0, reason: nil, finishedMs: nil)))
        await settle()
        #expect(sends(h).isEmpty)
        #expect(h.store.queuedMessages["t1"] == nil)
        #expect(h.store.queueNotices == ["t1": .dropped])
        h.store.closePanel()
        #expect(h.store.queueNotices.isEmpty)
    }

    @Test("Exited with the panel elsewhere drops it silently; a removed agent drops it too")
    func droppedQuietly() {
        let h = harness()
        h.store.queue("a", for: "t1")
        h.store.queue("b", for: "t2")
        h.client.emit(.event(seq: 11, .finished(terminal: "t1", exitCode: 0, reason: nil, finishedMs: nil)))
        h.client.emit(.event(seq: 12, .removed(terminal: "t2")))
        #expect(h.store.queuedMessages.isEmpty)
        #expect(h.store.queueNotices.isEmpty)
    }

    @Test("sent: reported once with the agent, so the island can say so")
    func sentCallback() async {
        let h = harness()
        var sent: [String] = []
        h.store.onQueuedSent = { sent.append($0.address) }
        h.store.queue("next", for: "t1")
        h.status("t1", "done", seq: 11)
        await settle()
        #expect(sent == ["t1"])
    }

    @Test("a failed send isn't retried: the text goes back to the user")
    func failedSendReturnsText() async {
        let h = harness()
        h.client.sendResult = .failure(HerdrError(kind: "send_failed", message: "nope"))
        var returned: [String: String] = [:]
        h.store.onQueuedFailed = { address, text in returned[address] = text }
        h.store.queue("next", for: "t1")
        h.status("t1", "done", seq: 11)
        await settle()
        #expect(returned == ["t1": "next"])
        #expect(h.store.queuedMessages["t1"] == nil)
        if case .failed = h.store.sendStates["t1"] {} else { Issue.record("expected Failed") }
        h.status("t1", "working", seq: 12)
        h.status("t1", "done", seq: 13)
        await settle()
        #expect(sends(h).count == 1)
    }

    @Test("another send still in flight: nothing is sent and the text goes back")
    func busySendReturnsText() async {
        let h = harness()
        h.client.holdSend = true
        var returned: [String: String] = [:]
        h.store.onQueuedFailed = { address, text in returned[address] = text }
        h.store.queue("next", for: "t1")
        h.store.send("typed now", to: "t1")
        h.status("t1", "done", seq: 11)
        await settle()
        #expect(returned == ["t1": "next"])
        #expect(h.store.queuedMessages["t1"] == nil)
        #expect(h.store.queueNotices == ["t1": .notSent])
        h.client.releaseSend()
        await settle()
        #expect(sends(h) == [.send("t1", "typed now", force: false)])
    }

    @Test("disconnected through the turn's end: no catch-up send; the next finished turn sends")
    func noCatchUpAfterReconnect() async {
        let h = harness()
        h.store.queue("next", for: "t1")
        h.client.emit(.disconnected(reason: "gone"))
        #expect(h.state("t1") == .unknown)
        h.connect([term("t1", "done"), term("t2", "working")], seq: 20)
        await settle()
        #expect(sends(h).isEmpty)
        #expect(h.store.queuedMessages["t1"]?.status == .waiting)
        h.status("t1", "working", seq: 21)
        h.status("t1", "done", seq: 22)
        await settle()
        #expect(sends(h) == [.send("t1", "next", force: false)])
    }

    @Test("with notify-when-done armed too, the notification comes before the send")
    func notifyBeforeSend() async {
        let h = harness()
        var order: [String] = []
        h.store.onNotifyWhenDone = { _ in order.append("notify:\(h.store.queuedMessages["t1"]?.status == .waiting)") }
        h.store.onQueuedSent = { _ in order.append("sent") }
        h.store.toggleNotifyWhenDone("t1")
        h.store.queue("next", for: "t1")
        h.status("t1", "done", seq: 11)
        await settle()
        #expect(order == ["notify:true", "sent"])
    }

    @Test("Send now refuses while the agent waits on a dialog: it would answer it")
    func sendNowNotIntoNeedsYou() async {
        let h = harness()
        h.store.queue("next", for: "t1")
        h.status("t1", "error", seq: 11)
        h.status("t1", "blocked", kind: "question", seq: 12)
        #expect(!h.store.canSendQueuedNow("t1"))
        h.store.sendQueuedNow("t1")
        await settle()
        #expect(sends(h).isEmpty)
        #expect(h.store.queuedMessages["t1"]?.status == .held)
        h.status("t1", "idle", seq: 13)
        #expect(h.store.canSendQueuedNow("t1"))
    }

    @Test("exiting while the send is in flight lets the send finish: no dropped note on top of it")
    func exitWhileSending() async {
        let h = harness()
        h.client.holdSend = true
        h.store.openPanel("t1")
        var sent = 0
        h.store.onQueuedSent = { _ in sent += 1 }
        h.store.queue("next", for: "t1")
        h.status("t1", "done", seq: 11)
        await settle()
        #expect(h.store.queuedMessages["t1"]?.status == .sending)
        h.client.emit(.event(seq: 12, .finished(terminal: "t1", exitCode: 0, reason: nil, finishedMs: nil)))
        #expect(h.store.queueNotices.isEmpty)
        h.client.releaseSend()
        await settle()
        #expect(h.store.queuedMessages["t1"] == nil)
        #expect(sent == 1)
        #expect(h.store.queueNotices.isEmpty)
    }

    @Test("canQueue follows the store's rule")
    func canQueue() {
        let h = harness()
        h.status("t2", "done", seq: 11)
        #expect(h.store.canQueue("t1"))
        #expect(!h.store.canQueue("t2"))
        #expect(!h.store.canQueue("nope"))
    }
}
