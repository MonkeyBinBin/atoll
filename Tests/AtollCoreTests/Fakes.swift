import Foundation
@testable import AtollCore

/// Records commands and replays scripted results; updates are pushed by the test.
final class FakeHerdrClient: HerdrClient, @unchecked Sendable {
    enum Command: Equatable {
        case read(String, Int)
        case send(String, String, force: Bool)
        case keys(String, [String])
        case interrupt(String)
        case launch(LaunchRequest)
        case focus(String)
        case reconnect
    }

    private let lock = NSLock()
    private var _commands: [Command] = []
    nonisolated(unsafe) private var handler: (@MainActor (ClientUpdate) -> Void)?

    var readResult: Result<ReadOutput, HerdrError> = .success(ReadOutput(text: "hello", how: "history"))
    var sendResult: Result<SendOutput, HerdrError> = .success(SendOutput(started: true))
    var keysResult: Result<Void, HerdrError> = .success(())
    var interruptResult: Result<InterruptOutcome, HerdrError> = .success(.stopped)
    var launchResult: Result<LaunchOutput, HerdrError> = .success(LaunchOutput(terminal: "t9"))
    var focusResult: Result<Void, HerdrError> = .success(())
    var appRunning = true
    /// When set, send() suspends until `releaseSend()` is called.
    var holdSend = false
    private var sendContinuation: CheckedContinuation<Void, Never>?

    var commands: [Command] {
        lock.lock()
        defer { lock.unlock() }
        return _commands
    }

    private func record(_ command: Command) {
        lock.lock()
        _commands.append(command)
        lock.unlock()
    }

    @MainActor func start(onUpdate: @escaping @MainActor (ClientUpdate) -> Void) {
        handler = onUpdate
    }

    @MainActor func reconnect() { record(.reconnect) }
    @MainActor func stop() {}

    @MainActor func emit(_ update: ClientUpdate) {
        handler?(update)
    }

    func read(terminal: String, lines: Int) async throws -> ReadOutput {
        record(.read(terminal, lines))
        return try readResult.get()
    }

    func send(terminal: String, text: String, force: Bool) async throws -> SendOutput {
        record(.send(terminal, text, force: force))
        if holdSend {
            await withCheckedContinuation { continuation in
                lock.lock()
                sendContinuation = continuation
                lock.unlock()
            }
        }
        return try sendResult.get()
    }

    func releaseSend() {
        lock.lock()
        let continuation = sendContinuation
        sendContinuation = nil
        lock.unlock()
        continuation?.resume()
    }

    func keys(terminal: String, keys: [String]) async throws {
        record(.keys(terminal, keys))
        try keysResult.get()
    }

    func interrupt(terminal: String) async throws -> InterruptOutcome {
        record(.interrupt(terminal))
        return try interruptResult.get()
    }

    func templates() async throws -> [TemplateInfo] { [] }
    func isHerdrAppRunning() async -> Bool { appRunning }
    func spaces() async throws -> [HerdrSpace] { [] }

    func launch(_ request: LaunchRequest) async throws -> LaunchOutput {
        record(.launch(request))
        return try launchResult.get()
    }

    func focus(terminal: String) async throws {
        record(.focus(terminal))
        try focusResult.get()
    }
}

@MainActor
final class FakeScheduler: IslandScheduler {
    private struct Item {
        let due: Date
        let action: @MainActor () -> Void
        let handle: ScheduledAction
    }

    var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var items: [Item] = []

    @discardableResult
    func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledAction {
        let handle = ScheduledAction()
        items.append(Item(due: now.addingTimeInterval(seconds), action: action, handle: handle))
        return handle
    }

    func advance(by seconds: TimeInterval) {
        let target = now.addingTimeInterval(seconds)
        while let index = items.indices.filter({ items[$0].due <= target }).min(by: { items[$0].due < items[$1].due }) {
            let item = items.remove(at: index)
            now = item.due
            if !item.handle.isCancelled { item.action() }
        }
        now = target
    }
}

/// Terminal fixtures.
func term(
    _ address: String,
    _ state: String? = nil,
    app: String? = "claude-code",
    kind: String? = nil,
    cwd: String = "/Users/me/Projects/project-x",
    live: Bool = true,
    turn: UInt64 = 0,
    statusMs: UInt64? = nil,
    name: String? = nil
) -> TerminalInfo {
    TerminalInfo(
        address: address,
        name: name,
        argv: ["/bin/zsh", "-l"],
        cwd: cwd,
        state: live ? "live" : "finished",
        status: state.map { CoreStatus(state: $0, app: app, kind: kind) },
        statusMs: statusMs,
        reported: state != nil,
        turn: turn
    )
}

@MainActor
struct Harness {
    let client = FakeHerdrClient()
    let scheduler = FakeScheduler()
    let store: AgentStore

    init(timing: AgentStore.Timing = .init()) {
        store = AgentStore(client: client, scheduler: scheduler, timing: timing)
        store.start()
    }

    func connect(_ terminals: [TerminalInfo] = [], seq: UInt64 = 10) {
        client.emit(.connected(CoreHello(generation: 1, version: "0.1.19", methods: AgentStore.requiredMethods)))
        client.emit(.snapshot(seq: seq, terminals: terminals))
    }

    func status(_ address: String, _ state: String?, app: String? = "claude-code", kind: String? = nil, seq: UInt64) {
        client.emit(.event(seq: seq, .status(terminal: address, status: state.map { CoreStatus(state: $0, app: app, kind: kind) }, reported: true)))
    }

    func state(_ address: String) -> AgentState? {
        store.agent(address)?.state
    }

    var order: [String] { store.agents.map(\.address) }
}

/// Lets queued main-actor tasks (fake async commands) run.
@MainActor
func settle() async {
    for _ in 0..<20 { await Task.yield() }
}
