import Foundation
import Testing
@testable import IslandCore

@MainActor
struct MultiHarness {
    let core = FakeHerdrClient()
    let cmux = FakeHerdrClient()
    let scheduler = FakeScheduler()
    let store: AgentStore

    init() {
        store = AgentStore(clients: [(.core, core), (.cmux, cmux)], scheduler: scheduler)
        store.start()
    }

    func connect(_ client: FakeHerdrClient, _ terminals: [TerminalInfo], seq: UInt64) {
        client.emit(.connected(CoreHello(generation: 1, version: "1.0", methods: AgentStore.requiredMethods)))
        client.emit(.snapshot(seq: seq, terminals: terminals))
    }

    func state(_ address: String) -> AgentState? { store.agent(address)?.state }
}

@MainActor
@Suite("Multiple sources")
struct MultiSourceTests {
    @Test("a source's snapshot replaces only its own agents")
    func snapshotsAreScoped() {
        let h = MultiHarness()
        h.connect(h.core, [term("t1", "working")], seq: 10)
        h.connect(h.cmux, [term("cmux:a", "idle")], seq: 158_000)
        #expect(Set(h.store.agents.map(\.address)) == ["t1", "cmux:a"])
        h.cmux.emit(.snapshot(seq: 158_100, terminals: [term("cmux:b", "working")]))
        #expect(Set(h.store.agents.map(\.address)) == ["t1", "cmux:b"])
        #expect(h.store.source(of: "t1") == .core)
        #expect(h.store.source(of: "cmux:b") == .cmux)
    }

    @Test("event sequence numbers are compared per source")
    func seqPerSource() {
        let h = MultiHarness()
        h.connect(h.core, [term("t1", "working")], seq: 1800)
        h.connect(h.cmux, [term("cmux:a", "idle")], seq: 158_000)
        h.core.emit(.event(seq: 1801, .status(terminal: "t1", status: CoreStatus(state: "idle", app: "claude-code"), reported: true)))
        #expect(h.state("t1") == .idle, "a low core seq is not dropped because cmux's seq is higher")
    }

    @Test("one source going offline only affects its agents; the island stays live")
    func offlineIsScoped() {
        let h = MultiHarness()
        h.connect(h.core, [term("t1", "working")], seq: 10)
        h.connect(h.cmux, [term("cmux:a", "working")], seq: 5)
        h.cmux.emit(.disconnected(reason: "cmux isn't running"))
        #expect(h.state("cmux:a") == .unknown)
        #expect(h.state("t1") == .working)
        #expect(h.store.isLive)
        #expect(h.store.connection == .connected)
        #expect(h.store.sourceStatus[.cmux]?.connection == .offline)
    }

    @Test("the island goes offline only when no source is live")
    func allOffline() {
        let h = MultiHarness()
        h.connect(h.core, [term("t1", "working")], seq: 10)
        h.cmux.emit(.disconnected(reason: "not running"))
        #expect(h.store.isLive)
        h.core.emit(.disconnected(reason: "closed"))
        #expect(!h.store.isLive)
        #expect(h.store.connection == .offline)
    }

    @Test("staleness is tracked per source")
    func stalePerSource() {
        let h = MultiHarness()
        h.connect(h.core, [term("t1", "working")], seq: 10)
        h.connect(h.cmux, [term("cmux:a", "working")], seq: 5)
        // cmux keeps sending heartbeats, core goes quiet.
        for _ in 0..<5 {
            h.scheduler.advance(by: 10)
            h.cmux.emit(.heartbeat(seq: 5))
        }
        #expect(h.state("t1") == .unknown)
        #expect(h.state("cmux:a") == .working)
        #expect(h.core.commands.contains(.reconnect))
        #expect(!h.cmux.commands.contains(.reconnect))
    }

    @Test("commands go to the agent's own source")
    func routing() async {
        let h = MultiHarness()
        h.connect(h.core, [term("t1", "idle")], seq: 10)
        h.connect(h.cmux, [term("cmux:a", "idle")], seq: 5)
        h.store.send("hello", to: "cmux:a")
        h.store.openPanel("cmux:a")
        await settle()
        #expect(h.cmux.commands.contains(.send("cmux:a", "hello", force: false)))
        #expect(h.cmux.commands.contains(.read("cmux:a", 200)))
        #expect(h.core.commands.isEmpty)
    }

    @Test("focusing a non-core agent doesn't need the Herdr app")
    func focusOtherSource() async {
        let h = MultiHarness()
        h.connect(h.core, [], seq: 10)
        h.connect(h.cmux, [term("cmux:a", "idle")], seq: 5)
        h.store.herdrAppRunning = false
        let error = await h.store.openInHerdr("cmux:a")
        #expect(error == nil)
        #expect(h.cmux.commands == [.focus("cmux:a")])
    }

    @Test("launch always goes to the primary source")
    func launchPrimary() async {
        let h = MultiHarness()
        h.connect(h.core, [], seq: 10)
        h.connect(h.cmux, [], seq: 5)
        h.store.herdrAppRunning = true
        let request = LaunchRequest(argv: ["claude"], folder: "/p", task: "x")
        h.store.launch(request)
        await settle()
        #expect(h.core.commands == [.launch(request)])
        #expect(h.cmux.commands.isEmpty)
    }

    @Test("transitions from an offline source don't notify")
    func noTransitionWhenOffline() {
        let h = MultiHarness()
        var seen: [String] = []
        h.store.onTransition = { agent, _ in seen.append(agent.address) }
        h.connect(h.core, [term("t1", "working")], seq: 10)
        h.connect(h.cmux, [term("cmux:a", "working")], seq: 5)
        h.cmux.emit(.event(seq: 6, .status(terminal: "cmux:a", status: CoreStatus(state: "blocked", app: "claude-code"), reported: true)))
        #expect(seen == ["cmux:a"])
        h.core.emit(.disconnected(reason: "x"))
        h.cmux.emit(.event(seq: 7, .status(terminal: "cmux:a", status: CoreStatus(state: "error", app: "claude-code"), reported: true)))
        #expect(seen == ["cmux:a", "cmux:a"], "cmux is still live even though core went away")
    }

    @Test("without a source timestamp, a non-core agent's duration is unknown until a change is seen")
    func unknownStart() {
        let h = MultiHarness()
        h.connect(h.core, [term("t1", "working")], seq: 10)
        h.connect(h.cmux, [term("cmux:a", "idle")], seq: 5)
        #expect(h.store.agent("t1")?.stateSince != nil)
        #expect(h.store.agent("cmux:a")?.stateSince == nil)
        h.cmux.emit(.event(seq: 6, .status(terminal: "cmux:a", status: CoreStatus(state: "working", app: "claude-code"), reported: true)))
        #expect(h.store.agent("cmux:a")?.stateSince == h.scheduler.now)
    }

    @Test("an event can't touch another source's agent")
    func eventsScoped() {
        let h = MultiHarness()
        h.connect(h.core, [term("t1", "working")], seq: 10)
        h.connect(h.cmux, [], seq: 5)
        h.cmux.emit(.event(seq: 6, .status(terminal: "t1", status: CoreStatus(state: "error", app: "x"), reported: true)))
        #expect(h.state("t1") == .working)
    }
}
