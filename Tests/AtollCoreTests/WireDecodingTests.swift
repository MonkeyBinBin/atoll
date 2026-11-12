import Foundation
import Testing
@testable import AtollCore

/// Decoding of real lines captured from herdr-core 0.1.19.
@Suite("Wire decoding")
struct WireDecodingTests {
    func object(_ json: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    }

    @Test func statusEvent() {
        let line = #"{"jsonrpc":"2.0","method":"event","params":{"data":{"records":{},"reported":true,"status":{"app":"probe","kind":"question","state":"blocked"}},"seq":1813,"terminal":"t46","type":"status"}}"#
        #expect(CoreRPCAdapter.decodeNotification(object(line)) == [
            .event(seq: 1813, .status(terminal: "t46", status: CoreStatus(state: "blocked", app: "probe", kind: "question"), reported: true)),
        ])
    }

    @Test func nullStatus() {
        let line = #"{"jsonrpc":"2.0","method":"event","params":{"data":{"records":{},"reported":true,"status":null},"seq":1817,"terminal":"t46","type":"status"}}"#
        #expect(CoreRPCAdapter.decodeNotification(object(line)) == [
            .event(seq: 1817, .status(terminal: "t46", status: nil, reported: true)),
        ])
    }

    @Test func turnEvent() {
        let line = #"{"jsonrpc":"2.0","method":"event","params":{"data":{"state":"idle","turn":1},"seq":1826,"terminal":"t47","type":"turn"}}"#
        #expect(CoreRPCAdapter.decodeNotification(object(line)) == [.event(seq: 1826, .turn(terminal: "t47", turn: 1, state: "idle"))])
    }

    @Test func finishedAndRemoved() {
        let finished = #"{"jsonrpc":"2.0","method":"event","params":{"data":{"exit_code":null,"finished_ms":1794293708497,"reason":"killed","signal":1},"seq":1818,"terminal":"t46","type":"finished"}}"#
        #expect(CoreRPCAdapter.decodeNotification(object(finished)) == [
            .event(seq: 1818, .finished(terminal: "t46", exitCode: nil, reason: "killed", finishedMs: 1_794_293_708_497)),
        ])
        let removed = #"{"jsonrpc":"2.0","method":"event","params":{"data":{},"seq":1819,"terminal":"t46","type":"removed"}}"#
        #expect(CoreRPCAdapter.decodeNotification(object(removed)) == [.event(seq: 1819, .removed(terminal: "t46"))])
    }

    @Test func foregroundAndLabels() {
        let fg = #"{"jsonrpc":"2.0","method":"event","params":{"data":{"argv":["sh"],"cwd":"/tmp","name":"bash","pid":67262},"seq":1812,"terminal":"t46","type":"foreground"}}"#
        #expect(CoreRPCAdapter.decodeNotification(object(fg)) == [
            .event(seq: 1812, .foreground(terminal: "t46", foreground: CoreForeground(pid: 67262, name: "bash", argv: ["sh"], cwd: "/tmp"))),
        ])
        let labels = #"{"jsonrpc":"2.0","method":"event","params":{"data":{"labels":{"where":"x / 1"}},"seq":1811,"terminal":"t46","type":"labels"}}"#
        #expect(CoreRPCAdapter.decodeNotification(object(labels)) == [.event(seq: 1811, .labels(terminal: "t46", labels: ["where": "x / 1"]))])
    }

    @Test func createdCarriesTerminal() {
        let line = #"{"jsonrpc":"2.0","method":"event","params":{"data":{"address":"t44","argv":["sh","-c","x"],"cols":200,"created_ms":1794293651657,"cwd":"/tmp","die_with_parent":true,"exit_code":null,"finished_ms":null,"identity":"ghostty","keep":false,"labels":{},"name":"island-probe","notify":true,"parent":"t3z","pid":63835,"reason":null,"reported":false,"rm":false,"rows":120,"screen":"exact","signal":null,"state":"live","status":null,"status_ms":null,"template":null,"title":"","turn":0},"seq":1798,"terminal":"t44","type":"created"}}"#
        let updates = CoreRPCAdapter.decodeNotification(object(line))
        guard case .event(1798, .created(let info)) = updates.first else {
            Issue.record("expected created")
            return
        }
        #expect(info.address == "t44")
        #expect(info.name == "island-probe")
        #expect(info.status == nil)
        #expect(!info.reported)
    }

    @Test func heartbeatAndUnknowns() {
        #expect(CoreRPCAdapter.decodeNotification(object(#"{"jsonrpc":"2.0","method":"heartbeat","params":{"seq":1797}}"#)) == [.heartbeat(seq: 1797)])
        #expect(CoreRPCAdapter.decodeNotification(object(#"{"jsonrpc":"2.0","method":"event","params":{"data":{},"seq":5,"terminal":"t1","type":"size"}}"#)) == [.event(seq: 5, .other(terminal: "t1", type: "size"))])
        #expect(CoreRPCAdapter.decodeNotification(object(#"{"jsonrpc":"2.0","method":"brand_new","params":{}}"#)).isEmpty)
    }

    @Test func missedWithSnapshot() {
        let line = #"{"jsonrpc":"2.0","method":"missed","params":{"seq":90,"terminals":[{"address":"t1","argv":[],"cwd":"/","state":"live","created_ms":1,"screen":"exact","cols":1,"rows":1,"labels":{}}]}}"#
        let updates = CoreRPCAdapter.decodeNotification(object(line))
        #expect(updates.count == 2)
        #expect(updates.first == .missed)
    }

    @Test func errorShape() {
        let response = object(#"{"error":{"code":-32000,"data":{"hint":"see `hc ls --all`","kind":"not_found"},"message":"no terminal \"nope\""},"id":8,"jsonrpc":"2.0"}"#)
        #expect(throws: HerdrError(kind: "not_found", message: "no terminal \"nope\"", hint: "see `hc ls --all`")) {
            try CoreRPCAdapter.result(of: response)
        }
    }

    @Test func terminalsShownInHerdr() {
        let ls = #"{"spaces":[{"id":"sp1","tabs":[{"id":"tb1","terminals":[{"terminal":"t3z","sub_agents":[{"terminal":"t50","sub_agents":[]}]}]}]},{"id":"sp2","tabs":[{"id":"tb2","terminals":[{"terminal":"t41","sub_agents":[]}]}]}],"recent":[]}"#
        #expect(CoreRPCAdapter.terminalsShown(inHerdrAppLs: Data(ls.utf8)) == ["t3z", "t50", "t41"])
    }

    @Test("herdr-app ls: each space's terminals, sub-agents included; a missing name falls back to the id")
    func spacesFromLs() {
        let ls = #"{"spaces":[{"id":"sp1","name":"atoll","tabs":[{"id":"tb1","terminals":[{"terminal":"t3z","sub_agents":[{"terminal":"t50","sub_agents":[]}]}]},{"id":"tb3","terminals":[{"terminal":"t7","sub_agents":["t6f"]}]}]},{"id":"sp2","name":null,"tabs":[]},{"name":"no id","tabs":[]}],"recent":[]}"#
        #expect(CoreRPCAdapter.spaces(inHerdrAppLs: Data(ls.utf8)) == [
            HerdrSpace(id: "sp1", name: "atoll", terminals: ["t3z", "t50", "t7", "t6f"]),
            HerdrSpace(id: "sp2", name: "sp2", terminals: []),
        ])
        #expect(CoreRPCAdapter.spaces(inHerdrAppLs: Data("not json".utf8)) == [])
    }

    @Test func herdrAppAddress() {
        #expect(CoreRPCAdapter.terminalAddress(inHerdrAppOutput: Data(#"{"ok":true,"tab":"tb1","terminal":"t4a"}"#.utf8)) == "t4a")
        #expect(CoreRPCAdapter.terminalAddress(inHerdrAppOutput: Data(#"{"ok":true}"#.utf8)) == nil)
    }
}
