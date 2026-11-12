import Foundation
import Testing
@testable import AtollCore

@MainActor
@Suite("Panel")
struct PanelTests {
    @Test("opening a panel reads 200 lines and stamps the fetch time")
    func openReads() async {
        let h = Harness()
        h.connect([term("t1", "working")])
        h.client.readResult = .success(ReadOutput(text: "screen", how: "screen", why: "working"))
        h.store.openPanel("t1")
        await settle()
        #expect(h.client.commands == [.read("t1", 200)])
        #expect(h.store.panel?.output?.text == "screen")
        #expect(h.store.panel?.output?.isScreenOnly == true)
        #expect(h.store.panel?.fetchedAt == h.scheduler.now)
    }

    @Test("status and turn events of the open agent refresh the output; others don't")
    func autoRefresh() async {
        let h = Harness()
        h.connect([term("t1", "working"), term("t2", "working")])
        h.store.openPanel("t1")
        await settle()
        h.status("t2", "idle", seq: 11)
        h.client.emit(.event(seq: 12, .title(terminal: "t1", title: "x")))
        await settle()
        #expect(h.client.commands.count == 1)
        h.status("t1", "idle", seq: 13)
        await settle()
        h.client.emit(.event(seq: 14, .turn(terminal: "t1", turn: 1, state: "idle")))
        await settle()
        #expect(h.client.commands == [.read("t1", 200), .read("t1", 200), .read("t1", 200)])
    }

    @Test("one panel at a time; switching replaces and closing discards output")
    func onePanel() async {
        let h = Harness()
        h.connect([term("t1", "working"), term("t2", "working")])
        h.store.openPanel("t1")
        await settle()
        h.store.openPanel("t2")
        #expect(h.store.panel?.address == "t2")
        #expect(h.store.panel?.output == nil)
        await settle()
        h.store.closePanel()
        #expect(h.store.panel == nil)
    }

    @Test("opening a Done agent acknowledges it locally without writing back to Herdr")
    func acknowledge() async {
        let h = Harness()
        h.connect([term("t1", "done")])
        #expect(h.store.agent("t1")?.acknowledged == false)
        h.store.openPanel("t1")
        await settle()
        #expect(h.store.agent("t1")?.acknowledged == true)
        #expect(h.client.commands.allSatisfy { if case .read = $0 { true } else { false } })
        // Leaving done clears the acknowledgement for the next completion.
        h.status("t1", "working", seq: 11)
        h.status("t1", "done", seq: 12)
        #expect(h.store.agent("t1")?.acknowledged == false)
    }

    @Test("Open in Herdr focuses the agent, and is refused when the app isn't running")
    func focus() async {
        let h = Harness()
        h.connect([term("t1", "working")])
        h.store.herdrAppRunning = false
        let refused = await h.store.openInHerdr("t1")
        #expect(refused?.message == "Herdr app isn't running")
        #expect(h.client.commands.isEmpty)
        h.store.herdrAppRunning = true
        let ok = await h.store.openInHerdr("t1")
        #expect(ok == nil)
        #expect(h.client.commands == [.focus("t1")])
    }
}

@MainActor
@Suite("Send")
struct SendTests {
    @Test("started true → Agent started", arguments: [
        (Bool?.some(true), SendState.started),
        (Bool?.some(false), SendState.delivered),
        (Bool?.none, SendState.unconfirmed),
    ])
    func outcomes(started: Bool?, expected: SendState) async {
        let h = Harness()
        h.connect([term("t1", "idle")])
        h.client.sendResult = .success(SendOutput(started: started))
        h.store.send("do it", to: "t1")
        await settle()
        #expect(h.store.sendStates["t1"] == expected)
        #expect(h.client.commands == [.send("t1", "do it", force: false)])
    }

    @Test("while Herdr waits for typing to stop the state is waiting, and double sends are blocked")
    func waitingAndNoDoubleSend() async {
        let h = Harness()
        h.connect([term("t1", "idle")])
        h.client.holdSend = true
        h.store.send("one", to: "t1")
        await settle()
        #expect(h.store.sendStates["t1"] == .waiting)
        #expect(h.store.sendStates["t1"]?.label == "Waiting for you to stop typing…")
        h.store.send("one", to: "t1")
        await settle()
        #expect(h.client.commands.count == 1)
        h.client.releaseSend()
        await settle()
        #expect(h.store.sendStates["t1"] == .started)
    }

    @Test("errors show Failed with kind and hint, and are never retried", arguments: ["blocked", "unavailable", "finished", "status_mismatch", "not_found"])
    func failures(kind: String) async {
        let h = Harness()
        h.connect([term("t1", "idle")])
        let error = HerdrError(kind: kind, message: "nope", hint: "try x")
        h.client.sendResult = .failure(error)
        h.store.send("hi", to: "t1")
        await settle()
        #expect(h.store.sendStates["t1"] == .failed(error))
        #expect(h.store.sendStates["t1"]?.label == "Failed")
        h.scheduler.advance(by: 120)
        await settle()
        let sends = { h.client.commands.filter { if case .send = $0 { true } else { false } }.count }
        #expect(sends() == 1, "no automatic resend")
        // Manual resend is allowed.
        h.store.send("hi", to: "t1")
        await settle()
        #expect(sends() == 2)
    }

    @Test("blocked: question answers with force")
    func questionForce() async {
        let h = Harness()
        h.connect([term("t1", "blocked", kind: "question")])
        h.store.send("yes, use postgres", to: "t1")
        await settle()
        #expect(h.client.commands == [.send("t1", "yes, use postgres", force: true)])
    }

    @Test("blocked kind decides the reply mode", arguments: [
        ("question", ReplyMode.text(force: true)),
        ("permission", .keys),
        ("auth", .openInHerdrOnly),
        (nil, .textAndKeys),
    ] as [(String?, ReplyMode)])
    func replyModes(kind: String?, mode: ReplyMode) {
        let h = Harness()
        h.connect([term("t1", "blocked", kind: kind)])
        #expect(h.store.agent("t1")?.replyMode == mode)
    }

    @Test("blocked without a kind accepts both a forced answer and keys")
    func unspecifiedBlocked() async {
        let h = Harness()
        h.connect([term("t1", "blocked")])
        h.store.send("yes", to: "t1")
        await settle()
        h.store.pressKey("1", on: "t1")
        await settle()
        #expect(h.client.commands == [.send("t1", "yes", force: true), .keys("t1", ["1"])])
    }

    @Test("permission and auth refuse text sends")
    func noTextWhenNotAllowed() async {
        for kind in ["permission", "auth"] {
            let h = Harness()
            h.connect([term("t1", "blocked", kind: kind)])
            h.store.send("x", to: "t1")
            await settle()
            #expect(h.client.commands.isEmpty)
        }
    }

    @Test("empty text is not sent")
    func emptyText() async {
        let h = Harness()
        h.connect([term("t1", "idle")])
        h.store.send("   ", to: "t1")
        await settle()
        #expect(h.client.commands.isEmpty)
    }
}

@MainActor
@Suite("Keys")
struct KeysTests {
    @Test("permission keys go to the target and report the result")
    func keys() async {
        let h = Harness()
        h.connect([term("t1", "blocked", kind: "permission")])
        h.store.pressKey("1", on: "t1")
        await settle()
        #expect(h.client.commands == [.keys("t1", ["1"])])
        #expect(h.store.keyStates["t1"] == .sent("1"))
    }

    @Test("key errors are reported and not retried")
    func keyError() async {
        let h = Harness()
        h.connect([term("t1", "blocked", kind: "permission")])
        let error = HerdrError(kind: "finished", message: "gone")
        h.client.keysResult = .failure(error)
        h.store.pressKey("y", on: "t1")
        await settle()
        #expect(h.store.keyStates["t1"] == .failed("y", error))
        #expect(h.client.commands.count == 1)
    }

    @Test("keys are refused outside permission prompts")
    func keysOnlyForPermission() async {
        let h = Harness()
        h.connect([term("t1", "blocked", kind: "auth"), term("t2", "working")])
        h.store.pressKey("enter", on: "t1")
        h.store.pressKey("enter", on: "t2")
        await settle()
        #expect(h.client.commands.isEmpty)
    }
}

@MainActor
@Suite("Interrupt")
struct InterruptTests {
    @Test("only a second press within 1.5 s interrupts")
    func confirm() async {
        let h = Harness()
        h.connect([term("t1", "working")])
        h.store.pressInterrupt("t1")
        #expect(h.store.interruptState("t1") == .confirming)
        #expect(h.store.interruptState("t1").label == "Press again to confirm")
        h.scheduler.advance(by: 1.6)
        #expect(h.store.interruptState("t1") == .ready)
        await settle()
        #expect(h.client.commands.isEmpty)

        h.store.pressInterrupt("t1")
        h.scheduler.advance(by: 1.0)
        h.store.pressInterrupt("t1")
        await settle()
        #expect(h.client.commands == [.interrupt("t1")])
    }

    @Test("each outcome is shown once, then the real state takes over", arguments: [InterruptOutcome.stopped, .exited, .stillWorking, .unknown])
    func feedback(outcome: InterruptOutcome) async {
        let h = Harness()
        h.connect([term("t1", "working")])
        h.client.interruptResult = .success(outcome)
        h.store.pressInterrupt("t1")
        h.store.pressInterrupt("t1")
        await settle()
        #expect(h.store.agent("t1")?.interruptFeedback == outcome)
        #expect(h.state("t1") == .working, "feedback is not a state")
        h.status("t1", "idle", seq: 11)
        #expect(h.state("t1") == .idle)
        h.scheduler.advance(by: 5)
        #expect(h.store.agent("t1")?.interruptFeedback == nil)
        #expect(h.store.interruptState("t1") == .ready)
    }
}

@MainActor
@Suite("Launch")
struct LaunchTests {
    let request = LaunchRequest(argv: ["claude"], folder: "/Users/me/Projects/project-x", task: "fix the build")

    @Test("terminal returned and working within 30 s → Launched")
    func launched() async {
        let h = Harness()
        h.connect()
        h.store.herdrAppRunning = true
        h.store.launch(request)
        #expect(h.store.launchState == .starting(terminal: nil))
        await settle()
        #expect(h.store.launchState == .starting(terminal: "t9"))
        h.client.emit(.event(seq: 11, .created(term("t9"))))
        #expect(h.state("t9") == .starting, "launched terminals show as Starting before their first status")
        h.scheduler.advance(by: 10)
        h.status("t9", "working", seq: 12)
        #expect(h.store.launchState == .launched(terminal: "t9"))
        #expect(h.state("t9") == .working)
        #expect(h.client.commands == [.launch(request)])
    }

    @Test("terminal returned but no working within 30 s → unconfirmed")
    func timeout() async {
        let h = Harness()
        h.connect()
        h.store.herdrAppRunning = true
        h.store.launch(request)
        await settle()
        h.client.emit(.event(seq: 11, .created(term("t9"))))
        h.status("t9", "idle", seq: 12)
        h.scheduler.advance(by: 31)
        #expect(h.store.launchState == .unconfirmed(terminal: "t9"))
        #expect(h.store.launchState.label == "Created · task start unconfirmed")
    }

    @Test("command failure → Launch failed")
    func failed() async {
        let h = Harness()
        h.connect()
        h.store.herdrAppRunning = true
        let error = HerdrError(kind: "spawn_failed", message: "no such program")
        h.client.launchResult = .failure(error)
        h.store.launch(request)
        await settle()
        #expect(h.store.launchState == .failed(error))
        #expect(h.store.launchState.label == "Launch failed")
    }

    @Test("Herdr app not running → launched without it (through herdr-core)")
    func appNotRunning() async {
        let h = Harness()
        h.connect()
        h.store.herdrAppRunning = false
        h.store.launch(request)
        await settle()
        var expected = request
        expected.withoutApp = true
        #expect(h.client.commands == [.launch(expected)])
        #expect(h.store.launchState == .starting(terminal: "t9"))
    }

    @Test("without a task, the first status counts as launched")
    func emptyTask() async {
        let h = Harness()
        h.connect()
        h.store.herdrAppRunning = true
        h.store.launch(LaunchRequest(argv: ["claude"], folder: "/p", task: "  "))
        await settle()
        h.client.emit(.event(seq: 11, .created(term("t9"))))
        h.status("t9", "idle", seq: 12)
        #expect(h.store.launchState == .launched(terminal: "t9"))
    }

    @Test("a second launch while starting is ignored")
    func noDoubleLaunch() async {
        let h = Harness()
        h.connect()
        h.store.herdrAppRunning = true
        h.store.launch(request)
        h.store.launch(request)
        await settle()
        #expect(h.client.commands.count == 1)
    }
}
