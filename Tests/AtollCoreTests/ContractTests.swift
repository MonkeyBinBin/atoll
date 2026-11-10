import Foundation
import Testing
@testable import AtollCore

/// CoreRPCAdapter against the real local herdr-core. Off by default; run with
///   HERDR_CONTRACT=1 swift test --filter Contract
/// Read-only, except for one probe terminal it creates (no parent, no notes) and removes.
@Suite("Contract (real herdr-core)", .enabled(if: ContractEnv.enabled), .serialized)
struct ContractTests {
    let adapter = CoreRPCAdapter()

    @Test("terminal.list / terminal.get decode")
    func listAndGet() async throws {
        let list = try await adapter.call("terminal.list", ["all": true])
        let data = try JSONSerialization.data(withJSONObject: (list as! [String: Any])["terminals"]!)
        let terminals = try JSONDecoder().decode([TerminalInfo].self, from: data)
        for t in terminals {
            let got = try await adapter.callDecoding(TerminalInfo.self, "terminal.get", ["terminal": t.address])
            #expect(got.address == t.address)
        }
    }

    @Test("errors carry kind / message / hint")
    func errorShape() async {
        do {
            _ = try await adapter.call("terminal.get", ["terminal": "island-contract-does-not-exist"])
            Issue.record("expected not_found")
        } catch let error as HerdrError {
            #expect(error.kind == "not_found")
            #expect(!error.message.isEmpty)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test("hello generation 1 with every method this app calls")
    func hello() async throws {
        let result = try await adapter.call("hello", ["generation": 1])
        let hello = CoreRPCAdapter.decodeHello(result)
        #expect(AgentStore.compatibilityProblem(hello) == nil)
    }

    @Test("probe terminal: snapshot, created/status/turn events, read, send, keys, interrupt")
    func probeLifecycle() async throws {
        let name = "island-contract-\(Int.random(in: 1000...9999))"
        let flag = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).state")
        try "working".write(to: flag, atomically: true, encoding: .utf8)
        // A tiny program that reports whatever state the flag file holds.
        let script = """
        last=""; while true; do cur=$(cat '\(flag.path)' 2>/dev/null); if [ "$cur" != "$last" ]; then last=$cur; \
        st=${cur%%:*}; k=${cur#*:}; if [ "$k" != "$cur" ]; then printf '\\033]7501;state=%s:kind=%s:app=contract\\007' "$st" "$k"; \
        else printf '\\033]7501;state=%s:app=contract\\007' "$st"; fi; echo "state $cur"; fi; sleep 0.2; done
        """

        let recorder = EventRecorder()
        let events = try LineSocket(path: adapter.socketPath)
        defer { events.close() }
        try events.writeLine(CoreRPCAdapter.request(id: 1, method: "events.subscribe", params: [:]))
        let reader = Thread {
            while let line = events.readLine() {
                if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                    recorder.add(object)
                }
            }
        }
        reader.start()

        let run = try await adapter.call("terminal.run", [
            "argv": ["sh", "-c", script], "name": name, "no_parent": true, "no_notify": true,
            "labels": ["island-contract": "1"],
        ]) as! [String: Any]
        let address = run["address"] as! String
        do {
            try await exercise(address: address, flag: flag, recorder: recorder)
        } catch {
            Issue.record("probe failed: \(error)")
        }
        _ = try? await adapter.call("terminal.kill", ["terminal": address])
        try? await Task.sleep(for: .milliseconds(300))
        _ = try? await adapter.call("terminal.rm", ["terminal": address])
        try? FileManager.default.removeItem(at: flag)
    }

    private func exercise(address: String, flag: URL, recorder: EventRecorder) async throws {
        try await waitFor { recorder.updates.contains { if case .event(_, .status(address, let s, _)) = $0 { s?.state == "working" } else { false } } }
        #expect(recorder.snapshotSeen)
        #expect(recorder.updates.contains { if case .event(_, .created(let info)) = $0 { info.address == address } else { false } })

        try "idle".write(to: flag, atomically: true, encoding: .utf8)
        try await waitFor { recorder.updates.contains { if case .event(_, .turn(address, _, _)) = $0 { true } else { false } } }

        let read = try await adapter.read(terminal: address, lines: 50)
        #expect(read.text.contains("state working"))

        let sent = try await adapter.send(terminal: address, text: "hello contract", force: false)
        #expect(sent.started != true, "the probe never goes working on input")

        try "blocked:question".write(to: flag, atomically: true, encoding: .utf8)
        try await waitFor { recorder.updates.contains { if case .event(_, .status(address, let s, _)) = $0 { s?.kind == "question" } else { false } } }
        do {
            _ = try await adapter.send(terminal: address, text: "refused", force: false)
            Issue.record("blocked programs refuse unforced sends")
        } catch let error as HerdrError {
            #expect(error.kind == "blocked")
        }
        _ = try await adapter.send(terminal: address, text: "forced answer", force: true)
        try await adapter.keys(terminal: address, keys: ["1"])

        try "working".write(to: flag, atomically: true, encoding: .utf8)
        let outcome = try await adapter.interrupt(terminal: address)
        #expect([.stopped, .stillWorking, .exited, .unknown].contains(outcome))
    }

    func waitFor(timeout: TimeInterval = 10, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { throw HerdrError(kind: "timeout", message: "condition not met") }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}

enum ContractEnv {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["HERDR_CONTRACT"] == "1"
            && FileManager.default.fileExists(atPath: CoreRPCAdapter.defaultSocketPath())
    }
}

final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _updates: [ClientUpdate] = []
    private var _snapshot = false

    func add(_ object: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        if object["id"] as? Int == 1, object["result"] != nil { _snapshot = true }
        _updates.append(contentsOf: CoreRPCAdapter.decodeNotification(object))
    }

    var updates: [ClientUpdate] {
        lock.lock()
        defer { lock.unlock() }
        return _updates
    }

    var snapshotSeen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _snapshot
    }
}
