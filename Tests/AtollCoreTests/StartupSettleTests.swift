import Foundation
import Testing
@testable import AtollCore

/// Codex reports Idle → Working → Idle within a second or two of starting (ticket 41): not a turn.
@MainActor
@Suite("Startup settle")
struct StartupSettleTests {
    final class Sink {
        var rules = BubbleRules()
        var bubbles: [String] = []
        var transitions: [String] = []
    }

    func harness() -> (Harness, Sink, FakeProbe) {
        let h = Harness()
        let probe = FakeProbe()
        h.store.changeProbe = probe
        let sink = Sink()
        h.store.onTransition = { agent, from in
            sink.transitions.append("\(from?.label ?? "nil")→\(agent.state.label)")
            if let bubble = sink.rules.bubble(for: agent, from: from) { sink.bubbles.append(bubble.state.label) }
        }
        // A shell: no agent yet.
        h.connect([term("t1", nil, app: nil)])
        h.client.readResult = .success(ReadOutput(text: FinalScreens.codexShort, how: "screen"))
        return (h, sink, probe)
    }

    func reads(_ h: Harness) -> Int {
        h.client.commands.filter { if case .read = $0 { true } else { false } }.count
    }

    /// Codex starts in the shell: its status appears, works for a moment, and settles.
    func start(_ h: Harness, workAfter: TimeInterval = 0.3, settleAfter: TimeInterval = 1, end: String = "idle", seq: UInt64 = 11) {
        h.status("t1", "idle", app: "codex", seq: seq)
        h.scheduler.advance(by: workAfter)
        h.status("t1", "working", app: "codex", seq: seq + 1)
        h.scheduler.advance(by: settleAfter)
        h.status("t1", end, app: "codex", seq: seq + 2)
    }

    @Test("the startup Working → Idle is reported as a first sighting: no bubble, timeline entry, read or change summary")
    func startupIsNotATurn() async {
        let (h, sink, probe) = harness()
        h.store.toggleNotifyWhenDone("t1")
        var notified = 0
        h.store.onNotifyWhenDone = { _ in notified += 1 }
        start(h)
        h.scheduler.advance(by: h.store.timing.previewDelay)
        await settle()
        #expect(sink.transitions.last == "nil→Idle")
        #expect(sink.bubbles.isEmpty)
        #expect(h.store.timeline.entries.isEmpty)
        #expect(notified == 0)
        #expect(h.store.notifyWhenDone.contains("t1"))
        #expect(reads(h) == 0)
        #expect(probe.summaryCalls.isEmpty)
        #expect(h.store.agent("t1")?.changeSummary == nil)
    }

    @Test("Working that starts later than the startup window is a real turn")
    func lateWorking() {
        let (h, sink, _) = harness()
        start(h, workAfter: 3.5)
        #expect(sink.bubbles == ["Idle"])
        #expect(h.store.timeline.entries.count == 1)
    }

    @Test("Idle arriving past the settle window is a real turn")
    func lateIdle() {
        let (h, sink, _) = harness()
        start(h, settleAfter: 10)
        #expect(sink.bubbles == ["Idle"])
    }

    @Test("a startup that ends in Done is a real turn")
    func endsDone() {
        let (h, sink, _) = harness()
        start(h, end: "done")
        #expect(sink.bubbles == ["Done"])
    }

    @Test("only the first Working after the status appears can be the startup one")
    func secondWorking() {
        let (h, sink, _) = harness()
        start(h)
        h.status("t1", "working", app: "codex", seq: 20)
        h.scheduler.advance(by: 1)
        h.status("t1", "idle", app: "codex", seq: 21)
        #expect(sink.bubbles == ["Idle"])
        #expect(h.store.timeline.entries.count == 1)
    }

    @Test("quitting back to the shell and starting again counts afresh")
    func restart() {
        let (h, sink, _) = harness()
        start(h)
        h.status("t1", nil, app: nil, seq: 20)
        h.scheduler.advance(by: 30)
        start(h, seq: 21)
        #expect(sink.bubbles.isEmpty)
        #expect(h.store.timeline.entries.isEmpty)
    }

    @Test("only Codex: another tool's quick first turn ending Idle stays a turn")
    func otherToolsUnchanged() {
        let (h, sink, _) = harness()
        h.status("t1", "idle", app: "claude-code", seq: 11)
        h.scheduler.advance(by: 0.3)
        h.status("t1", "working", app: "claude-code", seq: 12)
        h.scheduler.advance(by: 1)
        h.status("t1", "idle", app: "claude-code", seq: 13)
        #expect(sink.bubbles == ["Idle"])
        #expect(h.store.timeline.entries.count == 1)
    }
}
