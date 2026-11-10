import Foundation
import Testing
@testable import IslandCore

@MainActor
@Suite("Connection")
struct ConnectionTests {
    @Test("connecting → connected with core version")
    func connected() {
        let h = Harness()
        #expect(h.store.connection == .connecting)
        h.connect()
        #expect(h.store.connection == .connected)
        #expect(h.store.coreVersion == "0.1.19")
        #expect(h.store.compatibilityWarning == nil)
    }

    @Test("an unsupported protocol generation is flagged")
    func incompatibleGeneration() {
        let h = Harness()
        h.client.emit(.connected(CoreHello(generation: 2, version: "0.3.0", methods: AgentStore.requiredMethods)))
        #expect(h.store.compatibilityWarning?.contains("generation 2") == true)
    }

    @Test("a core refusing our generation shows the incompatibility, not just offline")
    func refusedGeneration() {
        let h = Harness()
        h.client.emit(.incompatible(reason: "herdr-core doesn't speak protocol generation 1"))
        #expect(h.store.compatibilityWarning?.contains("generation 1") == true)
        #expect(h.store.connection == .offline)
    }

    @Test("missing methods are flagged")
    func missingMethods() {
        let h = Harness()
        h.client.emit(.connected(CoreHello(generation: 1, version: "0.0.9", methods: ["events.subscribe"])))
        #expect(h.store.compatibilityWarning?.contains("terminal.send") == true)
    }

    @Test("disconnect keeps agents, marks them Unknown and remembers the last update")
    func offline() {
        let h = Harness()
        h.connect([term("t1", "working"), term("t2", "blocked", kind: "question")])
        let last = h.scheduler.now
        h.scheduler.advance(by: 3)
        h.client.emit(.disconnected(reason: "closed"))
        #expect(h.store.connection == .offline)
        #expect(h.store.lastUpdate == last)
        #expect(h.store.agents.count == 2)
        #expect(h.store.agents.allSatisfy { $0.state == .unknown })
    }

    @Test("reconnect resynchronizes from the new snapshot")
    func resync() {
        let h = Harness()
        h.connect([term("t1", "working"), term("t2", "working")])
        h.client.emit(.disconnected(reason: "closed"))
        h.client.emit(.connecting)
        h.connect([term("t1", "done")], seq: 99)
        #expect(h.store.connection == .connected)
        #expect(h.order == ["t1"])
        #expect(h.state("t1") == .done)
    }

    @Test("no data past the heartbeat deadline → everything Unknown and a reconnect is requested")
    func stale() {
        let h = Harness()
        h.connect([term("t1", "working")])
        h.scheduler.advance(by: 30)
        h.client.emit(.heartbeat(seq: 10))
        h.scheduler.advance(by: 30)
        #expect(h.state("t1") == .working, "heartbeat kept it fresh")
        h.scheduler.advance(by: 15)
        #expect(h.store.isStale)
        #expect(h.state("t1") == .unknown)
        #expect(h.client.commands.contains(.reconnect))
        h.client.emit(.heartbeat(seq: 10))
        #expect(!h.store.isStale)
        #expect(h.state("t1") == .working)
    }

    @Test("Reconnect from settings asks the client to reconnect")
    func manualReconnect() {
        let h = Harness()
        h.connect()
        h.store.reconnect()
        #expect(h.client.commands == [.reconnect])
        #expect(h.store.connection == .connecting)
    }
}
