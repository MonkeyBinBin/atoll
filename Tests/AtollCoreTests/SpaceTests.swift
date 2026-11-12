import Foundation
import Testing
@testable import AtollCore

@MainActor
@Suite("Herdr spaces")
struct SpaceTests {
    let atoll = HerdrSpace(id: "sp1", name: "atoll", terminals: ["t1", "t2"])
    let dots = HerdrSpace(id: "sp2", name: "dotfiles", terminals: ["t3"])

    // MARK: Store

    @Test("agents in a Herdr space carry its id and name; the rest have none")
    func mapping() async {
        let h = Harness()
        h.client.spacesResult = .success([atoll, dots])
        h.connect([term("t1", "working"), term("t3", "done"), term("t9", "idle")])
        h.store.herdrAppRunning = true
        await settle()
        #expect(h.store.spaces == [atoll, dots])
        #expect(h.store.agent("t1")?.spaceName == "atoll")
        #expect(h.store.agent("t3")?.spaceID == "sp2")
        #expect(h.store.agent("t9")?.spaceID == nil)
    }

    @Test("a new agent without a space re-reads the spaces once; it isn't asked again")
    func newAgentRefreshes() async {
        let h = Harness()
        h.client.spacesResult = .success([atoll])
        h.connect([term("t1", "working")])
        h.store.herdrAppRunning = true
        await settle()
        let before = h.client.spacesCalls
        h.client.spacesResult = .success([HerdrSpace(id: "sp1", name: "atoll", terminals: ["t1", "t4"])])
        h.client.emit(.event(seq: 11, .created(term("t4", "working"))))
        await settle()
        #expect(h.client.spacesCalls == before + 1)
        #expect(h.store.agent("t4")?.spaceName == "atoll")
        // Outside Herdr (`hc run` elsewhere): one read, then left alone.
        h.client.emit(.event(seq: 12, .created(term("t8", "working"))))
        await settle()
        h.status("t8", "idle", seq: 13)
        h.status("t8", "working", seq: 14)
        await settle()
        #expect(h.client.spacesCalls == before + 2)
        #expect(h.store.agent("t8")?.spaceID == nil)
    }

    @Test("re-read on a timer while the Herdr app runs; a failed read keeps the last spaces")
    func periodicAndFailure() async {
        let h = Harness()
        h.client.spacesResult = .success([atoll])
        h.connect([term("t1", "working")])
        h.store.herdrAppRunning = true
        await settle()
        let renamed = HerdrSpace(id: "sp1", name: "atoll-2", terminals: ["t1"])
        h.client.spacesResult = .success([renamed])
        h.scheduler.advance(by: h.store.timing.spaceRefreshInterval)
        await settle()
        #expect(h.store.agent("t1")?.spaceName == "atoll-2")
        h.client.spacesResult = .failure(.unavailable("herdr-app"))
        h.scheduler.advance(by: h.store.timing.spaceRefreshInterval)
        await settle()
        #expect(h.store.spaces == [renamed])
        // Keeps trying after a failure.
        h.client.spacesResult = .success([atoll])
        h.scheduler.advance(by: h.store.timing.spaceRefreshInterval)
        await settle()
        #expect(h.store.agent("t1")?.spaceName == "atoll")
    }

    @Test("Herdr app quits: spaces cleared, everyone in Other, no more reads")
    func appQuits() async {
        let h = Harness()
        h.client.spacesResult = .success([atoll])
        h.connect([term("t1", "working")])
        h.store.herdrAppRunning = true
        await settle()
        h.store.herdrAppRunning = false
        #expect(h.store.spaces.isEmpty)
        #expect(h.store.agent("t1")?.spaceID == nil)
        let calls = h.client.spacesCalls
        h.scheduler.advance(by: h.store.timing.spaceRefreshInterval * 3)
        await settle()
        #expect(h.client.spacesCalls == calls)
    }

    // MARK: Grouping

    func agents(_ list: [(String, String, HerdrSpace?)]) -> [Agent] {
        list.map { address, state, space in
            var agent = Agent(address: address, state: state == "blocked" ? .needsYou(.question) : state == "error" ? .error : .working)
            agent.spaceID = space?.id
            agent.spaceName = space?.name
            return agent
        }
    }

    @Test("no agent in a space: no sections, the list stays flat")
    func flat() {
        let list = agents([("t1", "working", nil), ("t2", "working", nil)])
        #expect(SpaceGrouping.sections(list) == nil)
        #expect(SpaceGrouping.listOrder(list).map(\.address) == ["t1", "t2"])
    }

    @Test("sections follow their first (most urgent) agent; order inside is kept")
    func sections() {
        // Priority-sorted input: the waiting t3 (dotfiles) first.
        let list = agents([("t3", "blocked", dots), ("t1", "working", atoll), ("t9", "working", nil), ("t2", "working", atoll)])
        let sections = SpaceGrouping.sections(list)
        #expect(sections?.map(\.name) == ["dotfiles", "atoll", "Other"])
        #expect(sections?[1].agents.map(\.address) == ["t1", "t2"])
        #expect(SpaceGrouping.listOrder(list).map(\.address) == ["t3", "t1", "t2", "t9"])
    }

    @Test("island filter: its space's agents plus anyone elsewhere who needs attention")
    func islandFilter() {
        let list = agents([("t3", "blocked", dots), ("t4", "error", nil), ("t1", "working", atoll), ("t5", "working", dots), ("t9", "working", nil)])
        #expect(SpaceGrouping.islandAgents(list, filter: .space("sp1")).map(\.address) == ["t3", "t4", "t1"])
        #expect(SpaceGrouping.islandAgents(list, filter: .other).map(\.address) == ["t3", "t4", "t9"])
        #expect(SpaceGrouping.islandAgents(list, filter: .all).count == 5)
    }

    @Test("a filter for a space Herdr no longer has (or Other without spaces) means all")
    func effective() {
        #expect(SpaceGrouping.effective(.space("sp1"), spaces: [atoll]) == .space("sp1"))
        #expect(SpaceGrouping.effective(.space("gone"), spaces: [atoll]) == .all)
        #expect(SpaceGrouping.effective(.space("sp1"), spaces: []) == .all)
        #expect(SpaceGrouping.effective(.other, spaces: []) == .all)
        #expect(SpaceGrouping.effective(.other, spaces: [atoll]) == .other)
    }

    @Test("choices: All, spaces with agents in Herdr's order, Other when someone is in none")
    func choices() {
        let list = agents([("t3", "working", dots), ("t1", "working", atoll)])
        let empty = HerdrSpace(id: "sp3", name: "empty")
        #expect(SpaceGrouping.choices(agents: list, spaces: [atoll, empty, dots], selected: .all).map(\.1) == ["All", "atoll", "dotfiles"])
        #expect(SpaceGrouping.choices(agents: list + agents([("t9", "working", nil)]), spaces: [atoll, dots], selected: .all).map(\.1)
                == ["All", "atoll", "dotfiles", "Other"])
        #expect(SpaceGrouping.choices(agents: list, spaces: [], selected: .all).isEmpty)
    }

    @Test("stored form round-trips")
    func stored() {
        for filter in [SpaceFilter.all, .other, .space("sp1")] {
            #expect(SpaceFilter(stored: filter.stored) == filter)
        }
    }
}
