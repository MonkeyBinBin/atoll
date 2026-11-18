import Foundation
import Synchronization

/// Agents managed by the herdr CLI/TUI (`herdr`, socket `~/.config/herdr/herdr.sock`).
///
/// State comes from `agent.list`, polled every couple of seconds and refreshed at once on
/// pane events. Successive lists are diffed into created / status / removed events so
/// transitions (and notifications) work like herdr-core's. Addresses are
/// `herdr:<terminal_id>` (stable); commands resolve them to the current pane id.
/// Every request uses its own short connection; the event subscription keeps one open.
public final class HerdrCLIAdapter: HerdrClient, Sendable {
    public static let addressPrefix = "herdr:"
    public let socketPath: String
    private let pollInterval: TimeInterval

    private let wake = DispatchSemaphore(value: 0)

    private struct State {
        var running = false
        var generation = 0
        var handler: (@MainActor (ClientUpdate) -> Void)?
        var paneByAddress: [String: String] = [:]
        var lastAgents: [String: TerminalInfo] = [:]
        var seq: UInt64 = 0
        var subscription: LineSocket?
        var subscribedPanes: Set<String> = []
        /// This herdr refused an ANSI read once (while a plain one worked): skip straight to plain reads.
        var ansiUnsupported = false
        /// Set by reconnect(): report offline again if herdr still isn't running.
        var announceOffline = false
    }
    private let shared = Mutex(State())

    public init(socketPath: String = HerdrCLIAdapter.defaultSocketPath(), pollInterval: TimeInterval = 2) {
        self.socketPath = socketPath
        self.pollInterval = pollInterval
    }

    public static func defaultSocketPath() -> String {
        if let explicit = ProcessInfo.processInfo.environment["HERDR_SOCKET_PATH"], !explicit.isEmpty { return explicit }
        return (NSHomeDirectory() as NSString).appendingPathComponent(".config/herdr/herdr.sock")
    }

    // MARK: Lifecycle

    @MainActor
    public func start(onUpdate: @escaping @MainActor (ClientUpdate) -> Void) {
        let (already, gen) = shared.withLock { state in
            state.handler = onUpdate
            let already = state.running
            state.running = true
            state.generation += 1
            return (already, state.generation)
        }
        guard !already else { return }
        let thread = Thread { [weak self] in self?.pollLoop(generation: gen) }
        thread.name = "herdr CLI poll"
        thread.start()
    }

    @MainActor
    public func reconnect() {
        shared.withLock { $0.announceOffline = true }
        wake.signal()
    }

    @MainActor
    public func stop() {
        let sub = shared.withLock { state in
            state.running = false
            state.generation += 1
            defer { state.subscription = nil }
            return state.subscription
        }
        sub?.shutdown()
        wake.signal()
    }

    private func isCurrent(_ gen: Int) -> Bool {
        shared.withLock { $0.running && $0.generation == gen }
    }

    private func emit(_ update: ClientUpdate) {
        guard let handler = shared.withLock({ $0.handler }) else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { handler(update) } }
    }

    private func nextSeq() -> UInt64 {
        shared.withLock { state in
            state.seq += 1
            return state.seq
        }
    }

    private func pollLoop(generation gen: Int) {
        var connected = false
        while isCurrent(gen) {
            do {
                let pong = try Self.request(socketPath, "ping", [:])
                if !connected {
                    let version = ((pong as? [String: Any])?["version"] as? String) ?? "?"
                    emit(.connected(CoreHello(generation: 1, version: version, methods: [])))
                    connected = true
                    shared.withLock { $0.lastAgents = [:] }
                    let agents = try listAgents()
                    shared.withLock { $0.lastAgents = Dictionary(uniqueKeysWithValues: agents.map { ($0.address, $0) }) }
                    emit(.snapshot(seq: nextSeq(), terminals: agents))
                } else {
                    let updates = Self.diff(old: currentAgents(), new: try listAgents())
                    let seq = shared.withLock { state in
                        state.lastAgents = updates.next
                        return state.seq
                    }
                    if updates.events.isEmpty {
                        emit(.heartbeat(seq: seq))
                    } else {
                        for event in updates.events { emit(.event(seq: nextSeq(), event)) }
                    }
                }
                ensureSubscription(generation: gen)
                shared.withLock { $0.announceOffline = false }
            } catch {
                // Offline is reported once per outage: on losing the connection, before anything was ever
                // published (seq 0, then bumped to 1), or when reconnect() asks again.
                let announce = shared.withLock { state in
                    let announce = connected || state.seq == 0 || state.announceOffline
                    state.announceOffline = false
                    if announce { state.seq = max(state.seq, 1) }
                    return announce
                }
                if announce {
                    emit(.disconnected(reason: (error as? HerdrError)?.message ?? "herdr isn't running"))
                }
                connected = false
                dropSubscription()
            }
            _ = wake.wait(timeout: .now() + (connected ? pollInterval : 5))
        }
    }

    private func currentAgents() -> [String: TerminalInfo] {
        shared.withLock { $0.lastAgents }
    }

    private func listAgents() throws -> [TerminalInfo] {
        let result = try Self.request(socketPath, "agent.list", [:])
        let agents = ((result as? [String: Any])?["agents"] as? [[String: Any]]) ?? []
        let infos = agents.compactMap(Self.terminalInfo)
        let panes = Dictionary(uniqueKeysWithValues: agents.compactMap { a -> (String, String)? in
            guard let term = a["terminal_id"] as? String, let pane = a["pane_id"] as? String else { return nil }
            return (Self.addressPrefix + term, pane)
        })
        shared.withLock { $0.paneByAddress = panes }
        return infos
    }

    // MARK: Event subscription (wakes the poll loop on pane activity)

    private func ensureSubscription(generation gen: Int) {
        let (panes, current, same) = shared.withLock { state in
            let panes = Set(state.paneByAddress.values)
            return (panes, state.subscription, panes == state.subscribedPanes)
        }
        if current != nil, same { return }
        current?.shutdown()
        guard let socket = try? LineSocket(path: socketPath) else { return }
        var subs: [[String: Any]] = ["pane.created", "pane.closed", "pane.exited", "pane.agent_detected"].map { ["type": $0] }
        subs += panes.sorted().map { ["type": "pane.agent_status_changed", "pane_id": $0] }
        guard (try? socket.writeLine(Self.encode(id: "sub", method: "events.subscribe", params: ["subscriptions": subs]))) != nil else {
            socket.close()
            return
        }
        shared.withLock { state in
            state.subscription = socket
            state.subscribedPanes = panes
        }
        let thread = Thread { [weak self] in
            while let line = socket.readLine() {
                guard let self, self.isCurrent(gen) else { break }
                if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], object["event"] != nil {
                    self.wake.signal()
                }
            }
            socket.close()
        }
        thread.name = "herdr CLI events"
        thread.start()
    }

    private func dropSubscription() {
        let sub = shared.withLock { state in
            state.subscribedPanes = []
            defer { state.subscription = nil }
            return state.subscription
        }
        sub?.shutdown()
    }

    // MARK: Mapping (internal, tested)

    static func appName(_ agent: String?) -> String? {
        switch agent?.lowercased() {
        case nil, "": nil
        case "claude": "claude-code"
        default: agent
        }
    }

    static func terminalInfo(_ a: [String: Any]) -> TerminalInfo? {
        guard let term = a["terminal_id"] as? String else { return nil }
        let status = (a["agent_status"] as? String).map { word -> String in
            ["idle", "working", "blocked", "done"].contains(word) ? word : "unknown"
        }
        let cwd = (a["foreground_cwd"] as? String) ?? (a["cwd"] as? String) ?? "/"
        var info = TerminalInfo(
            address: addressPrefix + term,
            name: (a["name"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            cwd: cwd,
            state: "live",
            status: status.map { CoreStatus(state: $0, app: appName(a["agent"] as? String)) },
            reported: true,
            turn: (a["completion_seq"] as? NSNumber)?.uint64Value ?? 0,
            title: (a["terminal_title_stripped"] as? String) ?? "",
            labels: ["atoll.herdr.pane": (a["pane_id"] as? String) ?? ""]
        )
        info.foreground = CoreForeground(cwd: cwd)
        return info
    }

    /// Successive agent lists → events (status changes, new and gone agents).
    static func diff(old: [String: TerminalInfo], new: [TerminalInfo]) -> (events: [CoreEvent], next: [String: TerminalInfo]) {
        var events: [CoreEvent] = []
        var next: [String: TerminalInfo] = [:]
        for info in new {
            next[info.address] = info
            guard let before = old[info.address] else {
                events.append(.created(info))
                continue
            }
            if before.status != info.status {
                events.append(.status(terminal: info.address, status: info.status, reported: true))
            }
            if before.turn != info.turn {
                events.append(.turn(terminal: info.address, turn: info.turn, state: info.status?.state))
            }
            if before.cwd != info.cwd {
                events.append(.foreground(terminal: info.address, foreground: CoreForeground(cwd: info.cwd)))
            }
            if before.title != info.title {
                events.append(.title(terminal: info.address, title: info.title))
            }
        }
        for address in old.keys where next[address] == nil {
            events.append(.removed(terminal: address))
        }
        return (events, next)
    }

    // MARK: Wire

    static func encode(id: String, method: String, params: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])
    }

    /// One request on a fresh connection; returns `result` or throws its `{code, message}`.
    static func request(_ path: String, _ method: String, _ params: [String: Any]) throws -> Any {
        let socket: LineSocket
        do {
            socket = try LineSocket(path: path)
        } catch {
            throw HerdrError(kind: "unavailable", message: "herdr isn't running")
        }
        defer { socket.close() }
        try socket.writeLine(encode(id: "island", method: method, params: params))
        guard let line = socket.readLine(),
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw HerdrError.unavailable("herdr closed the connection")
        }
        return try result(of: object)
    }

    static func result(of object: [String: Any]) throws -> Any {
        if let error = object["error"] as? [String: Any] {
            throw HerdrError(kind: (error["code"] as? String) ?? "error", message: (error["message"] as? String) ?? "herdr error")
        }
        return object["result"] ?? NSNull()
    }

    private func call(_ method: String, _ params: [String: Any]) async throws -> Any {
        let path = socketPath
        let body = UncheckedParams(params)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UncheckedResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: UncheckedResult(try Self.request(path, method, body.value)))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }.value
    }

    private func pane(_ address: String) throws -> String {
        guard let pane = shared.withLock({ $0.paneByAddress[address] }) else {
            throw HerdrError(kind: "not_found", message: "This agent is no longer in herdr")
        }
        return pane
    }

    // MARK: Commands

    public func read(terminal: String, lines: Int) async throws -> ReadOutput {
        let result = try await call("pane.read", ["pane_id": try pane(terminal), "source": "recent_unwrapped", "lines": lines])
        let read = ((result as? [String: Any])?["read"] as? [String: Any]) ?? [:]
        return ReadOutput(text: (read["text"] as? String) ?? "", how: "history", complete: !((read["truncated"] as? Bool) ?? false))
    }

    public func readStyled(terminal: String, lines: Int) async throws -> ReadOutput {
        let pane = try pane(terminal)
        if shared.withLock({ $0.ansiUnsupported }) { return try await self.read(terminal: terminal, lines: lines) }
        let result: Any
        do {
            result = try await call("pane.read", [
                "pane_id": pane, "source": "recent_unwrapped", "lines": lines, "format": "ansi", "strip_ansi": false,
            ])
        } catch let error as HerdrError where error.kind != "unavailable" {
            // herdr answered with an error. If a plain read works, it was the ANSI parameters it refused: remember
            // that. Otherwise the plain read's error (pane gone…) is the real one. Transport failures and timeouts
            // aren't caught, so they cost one wait, not two.
            let plain = try await self.read(terminal: terminal, lines: lines)
            shared.withLock { $0.ansiUnsupported = true }
            return plain
        }
        guard let read = (result as? [String: Any])?["read"] as? [String: Any], let raw = read["text"] as? String else {
            // Answered without text: plain text instead, colored by layout.
            return try await self.read(terminal: terminal, lines: lines)
        }
        let parsed = ANSIParser.parse(raw)
        return ReadOutput(text: parsed.text, how: "history", complete: !((read["truncated"] as? Bool) ?? false), runs: parsed.runs)
    }

    public func send(terminal: String, text: String, force: Bool) async throws -> SendOutput {
        let pane = try pane(terminal)
        if force {
            // Answering a blocked agent: agent.prompt refuses those, so type and submit directly.
            _ = try await call("pane.send_text", ["pane_id": pane, "text": text])
            _ = try await call("pane.send_keys", ["pane_id": pane, "keys": ["enter"]])
        } else {
            _ = try await call("agent.prompt", ["target": pane, "text": text])
        }
        // herdr reports submission, not whether a turn started.
        return SendOutput(started: nil)
    }

    public func keys(terminal: String, keys: [String]) async throws {
        _ = try await call("pane.send_keys", ["pane_id": try pane(terminal), "keys": keys])
    }

    public func interrupt(terminal: String) async throws -> InterruptOutcome {
        _ = try await call("pane.send_keys", ["pane_id": try pane(terminal), "keys": ["esc"]])
        return .unknown
    }

    public func focus(terminal: String) async throws {
        let pane = try pane(terminal)
        do {
            _ = try await call("agent.focus", ["target": pane])
        } catch {
            _ = try await call("pane.focus", ["pane_id": pane])
        }
    }

    public func templates() async throws -> [TemplateInfo] { [] }
    public func isHerdrAppRunning() async -> Bool { false }
    public func spaces() async throws -> [HerdrSpace] { [] }

    public func launch(_ request: LaunchRequest) async throws -> LaunchOutput {
        throw HerdrError(kind: "unsupported", message: "Launching goes through the Herdr app")
    }
}

private struct UncheckedParams: @unchecked Sendable {
    let value: [String: Any]
    init(_ value: [String: Any]) { self.value = value }
}

private struct UncheckedResult: @unchecked Sendable {
    let value: Any
    init(_ value: Any) { self.value = value }
}
