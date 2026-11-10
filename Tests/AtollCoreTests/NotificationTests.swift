import Foundation
import Testing
@testable import AtollCore

@MainActor
@Suite("Notifications")
struct NotificationTests {
    /// Wires the store's transitions through the rules like the app does.
    final class Sink {
        var rules = NotificationRules()
        var settings = NotificationSettings()
        var sent: [AgentNotification] = []
    }

    func harness() -> (Harness, Sink) {
        let h = Harness()
        let sink = Sink()
        h.store.onTransition = { agent, from in
            if let note = sink.rules.notification(for: agent, from: from, settings: sink.settings) {
                sink.sent.append(note)
            }
        }
        return (h, sink)
    }

    @Test("Needs you and Error notify; Working never does; Done is off by default")
    func defaults() {
        let (h, sink) = harness()
        h.connect([term("t1", "idle")])
        h.status("t1", "working", seq: 11)
        #expect(sink.sent.isEmpty)
        h.status("t1", "blocked", kind: "question", seq: 12)
        #expect(sink.sent.map(\.body) == ["Needs you"])
        h.status("t1", "working", seq: 13)
        h.status("t1", "error", seq: 14)
        #expect(sink.sent.map(\.body) == ["Needs you", "Error"])
        h.status("t1", "done", seq: 15)
        #expect(sink.sent.count == 2)
    }

    @Test("content is only tool · project, never output or the agent's message")
    func content() {
        let (h, sink) = harness()
        h.connect([term("t1", "working", app: "codex")])
        h.client.emit(.event(seq: 11, .status(terminal: "t1", status: CoreStatus(state: "blocked", app: "codex", kind: "question", msg: "secret plan"), reported: true)))
        let note = try! #require(sink.sent.first)
        #expect(note.title == "Codex · project-x")
        #expect(!note.title.contains("secret") && !note.body.contains("secret"))
        #expect(note.address == "t1")
    }

    @Test("Done notifies when enabled for the agent or its project")
    func doneOptIn() {
        let (h, sink) = harness()
        h.connect([term("t1", "working"), term("t2", "working", cwd: "/p/other")])
        sink.settings.doneAgents = ["t1"]
        h.status("t1", "done", seq: 11)
        h.status("t2", "done", seq: 12)
        #expect(sink.sent.map(\.address) == ["t1"])
        sink.settings.doneProjects = ["/p/other"]
        h.status("t2", "working", seq: 13)
        h.status("t2", "done", seq: 14)
        #expect(sink.sent.map(\.address) == ["t1", "t2"])
    }

    @Test("the master switch silences everything")
    func masterSwitch() {
        let (h, sink) = harness()
        sink.settings.enabled = false
        h.connect([term("t1", "working")])
        h.status("t1", "blocked", kind: "question", seq: 11)
        h.status("t1", "error", seq: 12)
        #expect(sink.sent.isEmpty)
    }

    @Test("one transition notifies once (kind changes and reconnects don't repeat it)")
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

    @Test("offline flips to Unknown don't notify")
    func offlineSilent() {
        let (h, sink) = harness()
        h.connect([term("t1", "blocked", kind: "question")])
        h.client.emit(.disconnected(reason: "x"))
        #expect(sink.sent.isEmpty)
    }
}
