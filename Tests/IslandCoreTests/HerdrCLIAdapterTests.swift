import Foundation
import Testing
@testable import IslandCore

/// Shapes captured from herdr 0.9.3's `agent.list`.
@Suite("herdr CLI adapter")
struct HerdrCLIAdapterTests {
    func agent(_ status: String, agent: String = "claude", term: String = "term_65fcf042d22311", pane: String = "w6:p8", completion: Int? = nil) -> [String: Any] {
        var a: [String: Any] = [
            "agent": agent, "agent_status": status, "cwd": "/Users/me/Projects/demo", "focused": false,
            "foreground_cwd": "/Users/me/Projects/demo", "pane_id": pane, "revision": 7, "state_change_seq": 3,
            "tab_id": "w6:t1", "terminal_id": term, "terminal_title": "✳ Claude Code",
            "terminal_title_stripped": "Claude Code", "workspace_id": "w6",
        ]
        if let completion { a["completion_seq"] = completion }
        return a
    }

    @Test("agent.list entries map to terminals with a stable herdr: address")
    func mapping() throws {
        let info = try #require(HerdrCLIAdapter.terminalInfo(agent("idle")))
        #expect(info.address == "herdr:term_65fcf042d22311")
        #expect(info.status == CoreStatus(state: "idle", app: "claude-code"))
        #expect(info.cwd == "/Users/me/Projects/demo")
        #expect(info.title == "Claude Code")
        #expect(info.labels["island.herdr.pane"] == "w6:p8")
    }

    @Test("status words", arguments: [
        ("idle", "idle"), ("working", "working"), ("blocked", "blocked"), ("done", "done"), ("unknown", "unknown"), ("weird", "unknown"),
    ])
    func statuses(word: String, expected: String) throws {
        #expect(try #require(HerdrCLIAdapter.terminalInfo(agent(word))).status?.state == expected)
    }

    @Test("tool names: claude → claude-code, codex stays codex")
    func apps() {
        #expect(HerdrCLIAdapter.appName("claude") == "claude-code")
        #expect(HerdrCLIAdapter.appName("codex") == "codex")
        #expect(AgentTool.from(app: HerdrCLIAdapter.appName("codex")) == .codex)
        #expect(HerdrCLIAdapter.appName(nil) == nil)
    }

    @Test("successive lists become created / status / turn / removed events")
    func diff() throws {
        let a = try #require(HerdrCLIAdapter.terminalInfo(agent("working", term: "term_a")))
        let b = try #require(HerdrCLIAdapter.terminalInfo(agent("idle", agent: "codex", term: "term_b", pane: "w6:pC")))
        let old = [a.address: a, b.address: b]
        let aDone = try #require(HerdrCLIAdapter.terminalInfo(agent("done", term: "term_a", completion: 4)))
        let c = try #require(HerdrCLIAdapter.terminalInfo(agent("working", term: "term_c", pane: "w6:pD")))
        let result = HerdrCLIAdapter.diff(old: old, new: [aDone, c])
        #expect(result.events.contains(.status(terminal: "herdr:term_a", status: CoreStatus(state: "done", app: "claude-code"), reported: true)))
        #expect(result.events.contains(.turn(terminal: "herdr:term_a", turn: 4, state: "done")))
        #expect(result.events.contains(.created(c)))
        #expect(result.events.contains(.removed(terminal: "herdr:term_b")))
        #expect(Set(result.next.keys) == ["herdr:term_a", "herdr:term_c"])
    }

    @Test("an unchanged list produces no events")
    func noChange() throws {
        let a = try #require(HerdrCLIAdapter.terminalInfo(agent("idle")))
        #expect(HerdrCLIAdapter.diff(old: [a.address: a], new: [a]).events.isEmpty)
    }

    @Test("errors carry herdr's code and message")
    func errors() {
        let object: [String: Any] = ["id": "x", "error": ["code": "agent_not_found", "message": "agent target nope not found"]]
        #expect(throws: HerdrError(kind: "agent_not_found", message: "agent target nope not found")) {
            try HerdrCLIAdapter.result(of: object)
        }
    }

    @Test("diffed events drive the store: a herdr agent that blocks notifies")
    @MainActor
    func storeIntegration() throws {
        let core = FakeHerdrClient()
        let herdr = FakeHerdrClient()
        let store = AgentStore(clients: [(.core, core), (.herdrCLI, herdr)], scheduler: FakeScheduler())
        store.start()
        var transitions: [AgentState] = []
        store.onTransition = { agent, _ in transitions.append(agent.state) }
        let idle = try #require(HerdrCLIAdapter.terminalInfo(agent("idle")))
        herdr.emit(.connected(CoreHello(generation: 1, version: "0.9.3", methods: [])))
        herdr.emit(.snapshot(seq: 1, terminals: [idle]))
        let blocked = try #require(HerdrCLIAdapter.terminalInfo(agent("blocked")))
        for event in HerdrCLIAdapter.diff(old: [idle.address: idle], new: [blocked]).events {
            herdr.emit(.event(seq: 2, event))
        }
        #expect(store.agent("herdr:term_65fcf042d22311")?.state == .needsYou(.unspecified))
        #expect(store.agent("herdr:term_65fcf042d22311")?.replyMode == .textAndKeys)
        #expect(transitions == [.needsYou(.unspecified)])
    }
}
