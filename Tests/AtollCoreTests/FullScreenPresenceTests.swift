import Foundation
import Testing
@testable import AtollCore

@MainActor
@Suite("Full-screen presence")
struct FullScreenPresenceTests {
    func agents(_ states: [String: String]) -> [Agent] {
        let h = Harness()
        h.connect(states.sorted { $0.key < $1.key }.map { term($0.key, $0.value, kind: $0.value == "blocked" ? "question" : nil) })
        return h.store.agents
    }

    @Test("not full screen: every agent, whatever the mode", arguments: FullScreenMode.allCases)
    func notFullScreen(mode: FullScreenMode) {
        let list = agents(["t1": "working", "t2": "done"])
        #expect(FullScreenPresence.collapsedAgents(list, fullScreen: false, mode: mode)?.map(\.address) == list.map(\.address))
    }

    @Test("Show all keeps everyone in full screen")
    func showAll() {
        let list = agents(["t1": "working", "t2": "blocked"])
        #expect(FullScreenPresence.collapsedAgents(list, fullScreen: true, mode: .showAll)?.count == 2)
    }

    @Test("Attention only keeps Needs you and Error")
    func attentionOnly() {
        let list = agents(["t1": "working", "t2": "blocked", "t3": "error", "t4": "done"])
        let shown = FullScreenPresence.collapsedAgents(list, fullScreen: true, mode: .attentionOnly)
        #expect(Set(shown?.map(\.address) ?? []) == ["t2", "t3"])
    }

    @Test("Attention only with nobody needing attention hides the island")
    func attentionOnlyEmpty() {
        let list = agents(["t1": "working", "t2": "done"])
        #expect(FullScreenPresence.collapsedAgents(list, fullScreen: true, mode: .attentionOnly) == nil)
    }

    @Test("Hide hides even with agents needing attention")
    func hide() {
        let list = agents(["t1": "blocked", "t2": "error"])
        #expect(FullScreenPresence.collapsedAgents(list, fullScreen: true, mode: .hide) == nil)
    }
}
