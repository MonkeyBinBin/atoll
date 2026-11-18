import Foundation
import Synchronization

/// Claude Code / Codex sessions that cmux integrates itself, read through the `cmux` CLI.
///
/// A long-lived `cmux events` child streams hook events. On start, the retained
/// history is replayed into `CmuxSessions` and published as one snapshot (no notifications
/// for history); later changes are diffed into events. Nothing runs while cmux isn't open,
/// so the CLI never launches cmux.
public final class CmuxAdapter: HerdrClient, Sendable {
    public let cmuxPath: String?
    private let appRunning: @Sendable () -> Bool
    private let activateApp: @Sendable () -> Void
    private let refreshInterval: TimeInterval

    private struct State {
        var running = false
        var generation = 0
        var handler: (@MainActor (ClientUpdate) -> Void)?
        var sessions = CmuxSessions()
        var published: [String: TerminalInfo] = [:]
        var seq: UInt64 = 0
        var child: Process?
        var ownership: [Int32: Bool] = [:]
        /// Set by reconnect(): report offline again if cmux still isn't running.
        var announceOffline = false
    }
    private let shared = Mutex(State())

    public init(
        cmuxPath: String? = CmuxAdapter.findCmux(),
        appRunning: @escaping @Sendable () -> Bool,
        activateApp: @escaping @Sendable () -> Void = {},
        refreshInterval: TimeInterval = 3
    ) {
        self.cmuxPath = cmuxPath
        self.appRunning = appRunning
        self.activateApp = activateApp
        self.refreshInterval = refreshInterval
    }

    public static func findCmux() -> String? {
        let candidates = [
            "/Applications/cmux.app/Contents/Resources/bin/cmux",
            "\(NSHomeDirectory())/Applications/cmux.app/Contents/Resources/bin/cmux",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
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
        let thread = Thread { [weak self] in self?.supervise(generation: gen) }
        thread.name = "cmux events"
        thread.start()
    }

    @MainActor
    public func reconnect() {
        let process = shared.withLock { state in
            state.announceOffline = true
            return state.child
        }
        process?.terminate()
    }

    @MainActor
    public func stop() {
        let process = shared.withLock { state in
            state.running = false
            state.generation += 1
            defer { state.child = nil }
            return state.child
        }
        process?.terminate()
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

    private var currentSeq: UInt64 { shared.withLock { $0.seq } }

    /// Keeps one `cmux events` child running while cmux is open.
    private func supervise(generation gen: Int) {
        var announcedOffline = false
        while isCurrent(gen) {
            guard let path = cmuxPath, appRunning() else {
                let again = shared.withLock { state in
                    defer { state.announceOffline = false }
                    return state.announceOffline
                }
                if again { announcedOffline = false }
                if !announcedOffline {
                    emit(.disconnected(reason: cmuxPath == nil ? "cmux isn't installed" : "cmux isn't running"))
                    announcedOffline = true
                }
                Thread.sleep(forTimeInterval: 5)
                continue
            }
            announcedOffline = false
            runStream(path: path, generation: gen)
            guard isCurrent(gen) else { return }
            emit(.disconnected(reason: "cmux event stream ended"))
            announcedOffline = true
            Thread.sleep(forTimeInterval: 3)
        }
    }

    private func runStream(path: String, generation gen: Int) {
        // Where retained history starts and ends right now.
        guard let ackData = try? Self.run(path, ["events", "--snapshot"]),
              let ack = try? JSONSerialization.jsonObject(with: ackData) as? [String: Any],
              let resume = ack["resume"] as? [String: Any] else { return }
        let oldest = (resume["oldest_seq"] as? NSNumber)?.uint64Value ?? 1
        let latest = (resume["latest_seq"] as? NSNumber)?.uint64Value ?? 0

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        // No --reconnect: if this app dies, the child exits on its next write (broken pipe,
        // within one 15 s heartbeat). supervise() restarts the stream itself.
        process.arguments = ["events", "--after", String(max(oldest, 1) - 1)]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return }
        shared.withLock { state in
            state.child = process
            state.sessions = CmuxSessions()
            state.published = [:]
        }

        let ticker = Thread { [weak self] in
            while let self, self.isCurrent(gen), process.isRunning {
                Thread.sleep(forTimeInterval: self.refreshInterval)
                // Stop the stream when cmux quits so the source goes offline at once.
                guard self.appRunning() else {
                    process.terminate()
                    break
                }
                self.publishChanges()
            }
        }

        var replaying = latest > 0
        if !replaying { publishSnapshot(); ticker.start() }
        let reader = out.fileHandleForReading
        var buffer = Data()
        while isCurrent(gen) {
            let chunk = reader.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                guard let frame = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                let type = frame["type"] as? String
                if type == "heartbeat" {
                    if replaying {
                        // Heartbeats only come once the replay is over.
                        replaying = false
                        publishSnapshot()
                        ticker.start()
                    } else {
                        emit(.heartbeat(seq: currentSeq))
                    }
                    continue
                }
                guard type == "event" else { continue }
                let frameSeq = (frame["seq"] as? NSNumber)?.uint64Value ?? 0
                shared.withLock { $0.sessions.apply(frame) }
                if replaying {
                    if frameSeq >= latest {
                        replaying = false
                        publishSnapshot()
                        ticker.start()
                    }
                } else {
                    publishChanges()
                }
            }
        }
        process.terminate()
        shared.withLock { state in
            if state.child === process { state.child = nil }
        }
    }

    // MARK: Publishing

    private func currentTerminals() -> [TerminalInfo] {
        let snapshot = shared.withLock { $0.sessions }
        return snapshot.terminals { [weak self] session in
            guard let pid = session.pid else { return true }
            guard ProcessInspector.isAlive(pid) else { return false }
            return !(self?.ownedByHerdr(pid) ?? false)
        }
    }

    /// Cached: a process doesn't move between backends.
    private func ownedByHerdr(_ pid: Int32) -> Bool {
        if let known = shared.withLock({ $0.ownership[pid] }) { return known }
        let owned = ProcessInspector.belongsToHerdr(pid)
        shared.withLock { $0.ownership[pid] = owned }
        return owned
    }

    private func publishSnapshot() {
        let terminals = currentTerminals()
        shared.withLock { $0.published = Dictionary(uniqueKeysWithValues: terminals.map { ($0.address, $0) }) }
        emit(.connected(CoreHello(generation: 1, version: "cmux", methods: [])))
        emit(.snapshot(seq: nextSeq(), terminals: terminals))
    }

    private func publishChanges() {
        let terminals = currentTerminals()
        let result = shared.withLock { state in
            let result = HerdrCLIAdapter.diff(old: state.published, new: terminals)
            state.published = result.next
            return result
        }
        for event in result.events { emit(.event(seq: nextSeq(), event)) }
    }

    private func surface(_ address: String) throws -> String {
        guard let surface = shared.withLock({ $0.published[address]?.labels["atoll.cmux.surface"] }) else {
            throw HerdrError(kind: "not_found", message: "This session is no longer in cmux")
        }
        return surface
    }

    // MARK: CLI

    /// Runs the cmux CLI; nonzero exit → HerdrError from "Error: <code>: <message>".
    static func run(_ path: String, _ arguments: [String]) throws -> Data {
        try data(from: ProcessRunner.run(path, arguments, environment: environment))
    }

    static func run(_ path: String, _ arguments: [String]) async throws -> Data {
        try data(from: await ProcessRunner.run(path, arguments, environment: environment))
    }

    private static var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["CMUX_QUIET"] = "1"
        return environment
    }

    private static func data(from output: ProcessRunner.Output) throws -> Data {
        guard output.status == 0 else { throw parseError(output.errorText) }
        return output.stdout
    }

    static func parseError(_ text: String) -> HerdrError {
        let line = text.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        if line.hasPrefix("Error: ") {
            let rest = line.dropFirst("Error: ".count)
            if let colon = rest.firstIndex(of: ":") {
                return HerdrError(kind: String(rest[..<colon]), message: rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces))
            }
            return HerdrError(kind: "cmux", message: String(rest))
        }
        return HerdrError(kind: "cmux", message: line.isEmpty ? "cmux command failed" : line)
    }

    private func cli(_ arguments: [String]) async throws -> Data {
        guard let path = cmuxPath else { throw HerdrError(kind: "not_installed", message: "cmux isn't installed") }
        guard appRunning() else { throw HerdrError(kind: "unavailable", message: "cmux isn't running") }
        return try await Self.run(path, arguments)
    }

    /// Key names cmux's send-key knows; single printable characters are typed instead.
    static func keyCommand(surface: String, key: String) -> [String] {
        switch key {
        case "enter", "esc", "escape", "tab", "up", "down", "left", "right", "backspace":
            return ["send-key", "--surface", surface, "--force", key]
        default:
            return ["send", "--surface", surface, "--force", "--", key]
        }
    }

    // MARK: Commands

    public func read(terminal: String, lines: Int) async throws -> ReadOutput {
        let data = try await cli(["read-screen", "--surface", try surface(terminal), "--scrollback", "--lines", String(lines)])
        return ReadOutput(text: String(decoding: data, as: UTF8.self), how: "history")
    }

    public func send(terminal: String, text: String, force: Bool) async throws -> SendOutput {
        let surface = try surface(terminal)
        var args = ["send", "--surface", surface]
        if force { args.append("--force") }
        _ = try await cli(args + ["--paste", "--", text])
        _ = try await cli(["send-key", "--surface", surface] + (force ? ["--force"] : []) + ["enter"])
        return SendOutput(started: nil)
    }

    public func keys(terminal: String, keys: [String]) async throws {
        let surface = try surface(terminal)
        for key in keys { _ = try await cli(Self.keyCommand(surface: surface, key: key)) }
    }

    public func interrupt(terminal: String) async throws -> InterruptOutcome {
        _ = try await cli(Self.keyCommand(surface: try surface(terminal), key: "escape"))
        return .unknown
    }

    public func focus(terminal: String) async throws {
        let surface = try surface(terminal)
        let params = String(decoding: try JSONSerialization.data(withJSONObject: ["surface_id": surface]), as: UTF8.self)
        _ = try await cli(["rpc", "surface.focus", params])
        activateApp()
    }

    public func templates() async throws -> [TemplateInfo] { [] }
    public func isHerdrAppRunning() async -> Bool { false }
    public func spaces() async throws -> [HerdrSpace] { [] }

    public func launch(_ request: LaunchRequest) async throws -> LaunchOutput {
        throw HerdrError(kind: "unsupported", message: "Launching goes through the Herdr app")
    }
}
