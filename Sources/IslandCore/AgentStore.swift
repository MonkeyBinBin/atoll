import Foundation
import Observation

public enum ConnectionState: Equatable, Sendable {
    case connecting
    case connected
    case offline
}

/// A backend the island reads agents from (herdr-core, herdr CLI, cmux…).
public struct AgentSource: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public static let core = AgentSource(id: "core", name: "herdr-core")
    public static let herdrCLI = AgentSource(id: "herdr", name: "herdr CLI")
    public static let cmux = AgentSource(id: "cmux", name: "cmux")
}

/// Connection facts kept per source.
public struct SourceStatus: Equatable, Sendable {
    public var connection: ConnectionState = .connecting
    public var version: String?
    public var compatibilityWarning: String?
    public var lastUpdate: Date?
    public var isStale = false

    public var isLive: Bool { connection == .connected && !isStale }

    public init() {}
}

/// The domain core: turns HerdrClient facts and command results into the agent
/// list and every piece of state the UI shows. The only module with business rules.
@MainActor
@Observable
public final class AgentStore {
    // MARK: Tunables

    public struct Timing: Sendable {
        /// No data at all (heartbeat is every 15 s) for this long → everything Unknown.
        public var staleAfter: TimeInterval = 40
        public var interruptConfirmWindow: TimeInterval = 1.5
        public var interruptFeedbackDuration: TimeInterval = 4
        public var launchConfirmWindow: TimeInterval = 30
        public var outputLines: Int = 200
        public init() {}
    }

    /// Methods this client calls on herdr-core.
    public nonisolated static let requiredMethods = [
        "events.subscribe", "terminal.read", "terminal.send", "terminal.keys", "terminal.interrupt", "templates.list",
    ]
    public nonisolated static let supportedGeneration = 1
    /// Label set by the shell wrapper on agents started from a terminal outside Herdr.
    public nonisolated static let originLabel = "island.origin"
    public nonisolated static let individualColorCount = 8

    // MARK: Published state

    /// Per-source connection facts, in `sources` order.
    public private(set) var sourceStatus: [AgentSource: SourceStatus] = [:]

    /// Best connection over all sources.
    public var connection: ConnectionState {
        let all = sources.compactMap { sourceStatus[$0]?.connection }
        if all.contains(.connected) { return .connected }
        if all.contains(.connecting) { return .connecting }
        return .offline
    }

    /// The primary source's (herdr-core) version.
    public var coreVersion: String? { sourceStatus[primary]?.version }
    /// Set when the primary core speaks a protocol this client may not understand.
    public var compatibilityWarning: String? { sourceStatus[primary]?.compatibilityWarning }
    /// Last time anything arrived from any source.
    public var lastUpdate: Date? { sourceStatus.values.compactMap(\.lastUpdate).max() }
    /// Every connected source has gone quiet past its deadline.
    public var isStale: Bool {
        let connected = sourceStatus.values.filter { $0.connection == .connected }
        return !connected.isEmpty && connected.allSatisfy(\.isStale)
    }
    public var showUnreportedTerminals = false
    /// Whether the Herdr GUI is running (launch / focus need it).
    public var herdrAppRunning = false

    /// Visible agents, sorted by priority.
    public private(set) var agents: [Agent] = []

    public private(set) var panel: PanelState?
    public private(set) var sendStates: [String: SendState] = [:]
    public private(set) var keyStates: [String: KeyPressState] = [:]
    public private(set) var interruptStates: [String: InterruptButtonState] = [:]
    public private(set) var launchState: LaunchState = .idle

    /// Called for every state change of a visible agent caused by a live core event.
    public var onTransition: ((_ agent: Agent, _ from: AgentState?) -> Void)?

    // MARK: Internals

    private struct Record {
        var source: AgentSource
        var info: TerminalInfo
        var lastKnownApp: String?
        var order: Int
        var lost = false
        var stateSince: Date?
        var waitingSince: Date?
        var lastStatusChange: Date?
    }

    public let sources: [AgentSource]
    private let clients: [AgentSource: HerdrClient]
    /// Launch and the app-level compatibility check belong to the first source (herdr-core).
    private var primary: AgentSource { sources[0] }
    private var client: HerdrClient { clients[primary]! }
    private let scheduler: IslandScheduler
    public let timing: Timing

    private var records: [String: Record] = [:]
    private var colors: [String: Int] = [:]
    private var nextColor = 0
    private var nextOrder = 0
    private var acknowledged: Set<String> = []
    private var interruptFeedback: [String: InterruptOutcome] = [:]
    private var launching: Set<String> = []
    private var snapshotSeq: [AgentSource: UInt64] = [:]
    private var staleTimers: [AgentSource: ScheduledAction] = [:]
    private var interruptTimers: [String: ScheduledAction] = [:]
    private var feedbackTimers: [String: ScheduledAction] = [:]
    private var launchTimer: ScheduledAction?
    /// Without a task an agent never goes working; its first status counts as started.
    private var launchHasTask = true
    private var outputRequest = 0

    public convenience init(client: HerdrClient, scheduler: IslandScheduler, timing: Timing = Timing()) {
        self.init(clients: [(.core, client)], scheduler: scheduler, timing: timing)
    }

    /// The first client is the primary (herdr-core): it launches agents.
    public init(clients: [(AgentSource, HerdrClient)], scheduler: IslandScheduler, timing: Timing = Timing()) {
        precondition(!clients.isEmpty)
        sources = clients.map(\.0)
        self.clients = Dictionary(uniqueKeysWithValues: clients)
        self.scheduler = scheduler
        self.timing = timing
        for source in sources { sourceStatus[source] = SourceStatus() }
    }

    public func start() {
        for source in sources {
            clients[source]?.start { [weak self] update in self?.handle(update, from: source) }
        }
    }

    /// Stops every source (child processes, sockets). Call on quit.
    public func stop() {
        for source in sources { clients[source]?.stop() }
    }

    public func reconnect() {
        for source in sources {
            sourceStatus[source]?.connection = .connecting
            clients[source]?.reconnect()
        }
    }

    public func isLive(_ source: AgentSource) -> Bool { sourceStatus[source]?.isLive ?? false }

    /// The source an agent comes from.
    public func source(of address: String) -> AgentSource? { records[address]?.source }

    private func client(for address: String) -> HerdrClient {
        records[address].flatMap { clients[$0.source] } ?? client
    }

    public func setShowUnreportedTerminals(_ value: Bool) {
        showUnreportedTerminals = value
        rebuild()
    }

    /// Data is live from at least one source.
    public var isLive: Bool { sourceStatus.values.contains(where: \.isLive) }

    public func agent(_ address: String) -> Agent? {
        agents.first { $0.address == address }
    }

    /// Needs-you agents, earliest waiting first.
    public var earliestWaitingAgent: Agent? {
        agents.filter { $0.state.isNeedsYou }.min { ($0.waitingSince ?? .distantFuture) < ($1.waitingSince ?? .distantFuture) }
    }

    public var waitingCount: Int { agents.filter { $0.state.isNeedsYou }.count }

    // MARK: Client updates

    public func handle(_ update: ClientUpdate) {
        handle(update, from: primary)
    }

    public func handle(_ update: ClientUpdate, from source: AgentSource) {
        guard sourceStatus[source] != nil else { return }
        switch update {
        case .connecting:
            sourceStatus[source]?.connection = .connecting
        case .connected(let hello):
            sourceStatus[source]?.connection = .connected
            sourceStatus[source]?.version = hello.version
            sourceStatus[source]?.compatibilityWarning = source == primary ? Self.compatibilityProblem(hello) : nil
            touch(source)
        case .snapshot(let seq, let terminals):
            if sourceStatus[source]?.connection != .connected { sourceStatus[source]?.connection = .connected }
            applySnapshot(seq: seq, terminals: terminals, from: source)
            touch(source)
        case .event(let seq, let event):
            touch(source)
            if seq <= snapshotSeq[source, default: 0] { return }
            apply(event, from: source)
        case .heartbeat:
            touch(source)
        case .missed:
            // A fresh snapshot follows; events up to its seq will be ignored.
            touch(source)
        case .incompatible(let reason):
            sourceStatus[source]?.compatibilityWarning = reason
            sourceStatus[source]?.connection = .offline
            staleTimers[source]?.cancel()
            staleTimers[source] = nil
            rebuild()
        case .disconnected:
            sourceStatus[source]?.connection = .offline
            staleTimers[source]?.cancel()
            staleTimers[source] = nil
            rebuild()
        }
    }

    public nonisolated static func compatibilityProblem(_ hello: CoreHello) -> String? {
        if hello.generation != supportedGeneration {
            return "herdr-core \(hello.version) speaks protocol generation \(hello.generation); this app supports generation \(supportedGeneration). Update the app or herdr-core."
        }
        let missing = requiredMethods.filter { !hello.methods.contains($0) }
        if !missing.isEmpty {
            return "herdr-core \(hello.version) lacks \(missing.joined(separator: ", ")). Update herdr-core (hc update)."
        }
        return nil
    }

    private func touch(_ source: AgentSource) {
        sourceStatus[source]?.lastUpdate = scheduler.now
        let wasStale = sourceStatus[source]?.isStale ?? false
        sourceStatus[source]?.isStale = false
        staleTimers[source]?.cancel()
        staleTimers[source] = scheduler.schedule(after: timing.staleAfter) { [weak self] in
            guard let self else { return }
            self.sourceStatus[source]?.isStale = true
            self.rebuild()
            self.clients[source]?.reconnect()
        }
        if wasStale { rebuild() }
    }

    /// A source's snapshot replaces only that source's agents.
    private func applySnapshot(seq: UInt64, terminals: [TerminalInfo], from source: AgentSource) {
        snapshotSeq[source] = seq
        let now = scheduler.now
        var fresh = records.filter { $0.value.source != source }
        for info in terminals {
            var record = records[info.address].flatMap { $0.source == source ? $0 : nil } ?? newRecord(info, source: source)
            let before = state(of: record)
            record.info = info
            record.lost = false
            if let app = info.status?.app { record.lastKnownApp = app }
            let since = info.statusMs.map { Date(timeIntervalSince1970: Double($0) / 1000) }
            if record.lastStatusChange == nil { record.lastStatusChange = since }
            if before != state(of: record) || record.stateSince == nil {
                // Without a timestamp from the source, the start is unknown (shown blank) rather
                // than "since the app started".
                record.stateSince = info.state == "finished"
                    ? info.finishedMs.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? now
                    : since ?? (source == primary ? now : nil)
            }
            if info.status?.state == "blocked" {
                if record.waitingSince == nil { record.waitingSince = since ?? now }
            } else {
                record.waitingSince = nil
            }
            fresh[info.address] = record
        }
        records = fresh
        launching = launching.filter { fresh[$0] != nil }
        rebuild()
    }

    private func newRecord(_ info: TerminalInfo, source: AgentSource) -> Record {
        defer { nextOrder += 1 }
        if colors[info.address] == nil {
            colors[info.address] = nextColor % Self.individualColorCount
            nextColor += 1
        }
        return Record(source: source, info: info, lastKnownApp: info.status?.app, order: nextOrder)
    }

    private func apply(_ event: CoreEvent, from source: AgentSource) {
        let now = scheduler.now
        guard let address = event.terminal else { return }
        if case .created(let info) = event {
            var record = records[address] ?? newRecord(info, source: source)
            record.info = info
            if let app = info.status?.app { record.lastKnownApp = app }
            record.stateSince = now
            record.lastStatusChange = now
            if info.status?.state == "blocked" { record.waitingSince = now }
            records[address] = record
            rebuild()
            return
        }
        guard var record = records[address], record.source == source else { return }
        let before = visibleState(of: record)
        var refreshOutput = false

        switch event {
        case .created:
            break
        case .status(_, let status, let reported):
            let wasBlocked = record.info.status?.state == "blocked"
            record.info.status = status
            record.info.reported = record.info.reported || reported || status != nil
            if let app = status?.app { record.lastKnownApp = app }
            record.lastStatusChange = now
            if status?.state == "blocked" {
                if !wasBlocked || record.waitingSince == nil { record.waitingSince = now }
            } else {
                record.waitingSince = nil
            }
            if status?.state != "done" { acknowledged.remove(address) }
            refreshOutput = true
        case .turn(_, let turn, _):
            record.info.turn = turn
            record.lastStatusChange = now
            refreshOutput = true
        case .title(_, let title):
            record.info.title = title
        case .labels(_, let labels):
            record.info.labels = labels
        case .foreground(_, let foreground):
            record.info.foreground = foreground
            record.lastStatusChange = now
        case .finished(_, let exitCode, let reason, let finishedMs):
            record.info.state = "finished"
            record.info.status = nil
            record.info.exitCode = exitCode
            record.info.reason = reason
            record.info.finishedMs = finishedMs
            record.waitingSince = nil
        case .removed:
            records[address] = nil
            launching.remove(address)
            if panel?.address == address { closePanel() }
            rebuild()
            return
        case .lost:
            record.lost = true
        case .restarted:
            record.lost = false
        case .other:
            return
        }

        if state(of: record) != stateOfStored(address) { record.stateSince = now }
        records[address] = record

        if launching.contains(address), record.info.status != nil {
            launching.remove(address)
        }
        if case .starting(let pending) = launchState, pending == address,
           let status = record.info.status, status.state == "working" || !launchHasTask {
            launchTimer?.cancel()
            launchState = .launched(terminal: address)
        }

        rebuild()

        if let after = agent(address), after.state != before, isLive(source) {
            onTransition?(after, before)
        }
        if refreshOutput, panel?.address == address {
            refreshPanelOutput()
        }
    }

    private func stateOfStored(_ address: String) -> AgentState? {
        records[address].map(state(of:))
    }

    /// The state a record maps to, ignoring connection liveness.
    private func state(of record: Record) -> AgentState {
        let info = record.info
        if info.state == "finished" { return .exited }
        if record.lost { return .unknown }
        guard let status = info.status else {
            return launching.contains(info.address) ? .starting : .unknown
        }
        switch status.state {
        case "working": return .working
        case "blocked": return .needsYou(.from(kind: status.kind))
        case "done": return .done
        case "idle": return .idle
        case "error": return .error
        default: return .unknown
        }
    }

    private func visibleState(of record: Record) -> AgentState? {
        agent(record.info.address)?.state
    }

    private func isVisible(_ record: Record) -> Bool {
        record.lastKnownApp != nil || launching.contains(record.info.address) || showUnreportedTerminals
    }

    private func rebuild() {
        var list: [(Agent, Int)] = []
        for record in records.values where isVisible(record) {
            let info = record.info
            var state = state(of: record)
            if !isLive(record.source) { state = .unknown }
            var agent = Agent(
                address: info.address,
                name: info.name,
                tool: .from(app: record.lastKnownApp),
                app: record.lastKnownApp,
                state: state,
                statusMessage: info.status?.msg.flatMap { $0.isEmpty ? nil : $0 },
                projectPath: info.foreground?.cwd ?? info.cwd,
                stateSince: record.stateSince,
                waitingSince: state.isNeedsYou ? record.waitingSince : nil,
                lastStatusChange: record.lastStatusChange,
                colorIndex: colors[info.address] ?? 0,
                acknowledged: state == .done && acknowledged.contains(info.address),
                turn: info.turn,
                title: info.title,
                interruptFeedback: interruptFeedback[info.address],
                origin: info.labels[Self.originLabel].flatMap { $0.isEmpty ? nil : $0 }
            )
            agent.source = record.source
            list.append((agent, record.order))
        }
        list.sort { lhs, rhs in
            let (a, ao) = lhs
            let (b, bo) = rhs
            if a.state.priority != b.state.priority { return a.state.priority < b.state.priority }
            if a.state.isNeedsYou, b.state.isNeedsYou {
                let aw = a.waitingSince ?? .distantFuture
                let bw = b.waitingSince ?? .distantFuture
                if aw != bw { return aw < bw }
            }
            return ao < bo
        }
        agents = list.map(\.0)
    }

    // MARK: Panel

    public func openPanel(_ address: String) {
        guard records[address] != nil else { return }
        if panel?.address != address {
            outputRequest += 1
            panel = PanelState(address: address)
        }
        if stateOfStored(address) == .done {
            // Local only: never written back to Herdr.
            acknowledged.insert(address)
        }
        rebuild()
        refreshPanelOutput()
    }

    public func closePanel() {
        outputRequest += 1
        panel = nil
    }

    public func refreshPanelOutput() {
        guard var current = panel else { return }
        outputRequest += 1
        let request = outputRequest
        let address = current.address
        current.isLoading = true
        panel = current
        let lines = timing.outputLines
        Task { [client = client(for: address)] in
            let result: Result<ReadOutput, HerdrError>
            do {
                result = .success(try await client.read(terminal: address, lines: lines))
            } catch let error as HerdrError {
                result = .failure(error)
            } catch {
                result = .failure(.unavailable(error.localizedDescription))
            }
            self.finishOutput(request: request, address: address, result: result)
        }
    }

    private func finishOutput(request: Int, address: String, result: Result<ReadOutput, HerdrError>) {
        guard request == outputRequest, var current = panel, current.address == address else { return }
        current.isLoading = false
        switch result {
        case .success(let output):
            current.output = output
            current.fetchedAt = scheduler.now
            current.error = nil
        case .failure(let error):
            current.error = error
        }
        panel = current
    }

    // MARK: Send

    public func send(_ text: String, to address: String) {
        guard let agent = agent(address) else { return }
        let force: Bool
        switch agent.replyMode {
        case .text(let f): force = f
        case .textAndKeys: force = true
        default: return
        }
        if sendStates[address]?.isInFlight == true { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sendStates[address] = .waiting
        Task { [client = client(for: address)] in
            do {
                let output = try await client.send(terminal: address, text: text, force: force)
                let state: SendState = switch output.started {
                case .some(true): .started
                case .some(false): .delivered
                case .none: .unconfirmed
                }
                self.sendStates[address] = state
            } catch let error as HerdrError {
                self.sendStates[address] = .failed(error)
            } catch {
                self.sendStates[address] = .failed(.unavailable(error.localizedDescription))
            }
        }
    }

    public func clearSendState(_ address: String) {
        if sendStates[address]?.isInFlight == true { return }
        sendStates[address] = nil
    }

    // MARK: Keys

    public nonisolated static let permissionKeys: [String] = ["1", "2", "3", "y", "n", "enter", "esc"]

    public func pressKey(_ key: String, on address: String) {
        guard let agent = agent(address), agent.replyMode == .keys || agent.replyMode == .textAndKeys else { return }
        if case .sending = keyStates[address] { return }
        keyStates[address] = .sending(key)
        Task { [client = client(for: address)] in
            do {
                try await client.keys(terminal: address, keys: [key])
                self.keyStates[address] = .sent(key)
            } catch let error as HerdrError {
                self.keyStates[address] = .failed(key, error)
            } catch {
                self.keyStates[address] = .failed(key, .unavailable(error.localizedDescription))
            }
        }
    }

    // MARK: Interrupt

    public func interruptState(_ address: String) -> InterruptButtonState {
        interruptStates[address] ?? .ready
    }

    /// First press arms; a second press within the confirm window interrupts.
    public func pressInterrupt(_ address: String) {
        guard let agent = agent(address), agent.state != .exited else { return }
        switch interruptState(address) {
        case .ready:
            interruptStates[address] = .confirming
            interruptTimers[address]?.cancel()
            interruptTimers[address] = scheduler.schedule(after: timing.interruptConfirmWindow) { [weak self] in
                guard let self, self.interruptStates[address] == .confirming else { return }
                self.interruptStates[address] = .ready
            }
        case .confirming:
            interruptTimers[address]?.cancel()
            interruptStates[address] = .interrupting
            Task { [client = client(for: address)] in
                let outcome: InterruptOutcome
                var failure: HerdrError?
                do {
                    outcome = try await client.interrupt(terminal: address)
                } catch let error as HerdrError {
                    outcome = .unknown
                    failure = error
                } catch {
                    outcome = .unknown
                    failure = .unavailable(error.localizedDescription)
                }
                self.finishInterrupt(address, outcome: outcome, failure: failure)
            }
        case .interrupting:
            break
        }
    }

    private func finishInterrupt(_ address: String, outcome: InterruptOutcome, failure: HerdrError?) {
        interruptStates[address] = .ready
        interruptFeedback[address] = outcome
        lastInterruptError[address] = failure
        feedbackTimers[address]?.cancel()
        feedbackTimers[address] = scheduler.schedule(after: timing.interruptFeedbackDuration) { [weak self] in
            self?.interruptFeedback[address] = nil
            self?.lastInterruptError[address] = nil
            self?.rebuild()
        }
        rebuild()
    }

    public private(set) var lastInterruptError: [String: HerdrError] = [:]

    // MARK: Launch

    public func launch(_ request: LaunchRequest) {
        if case .starting = launchState { return }
        guard herdrAppRunning else {
            launchState = .failed(HerdrError(kind: "app_not_running", message: "Herdr app isn't running", hint: "Open Herdr, then try again."))
            return
        }
        launchState = .starting(terminal: nil)
        launchHasTask = !request.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        Task { [client] in
            do {
                let output = try await client.launch(request)
                self.launchReturned(output)
            } catch let error as HerdrError {
                self.launchState = .failed(error)
            } catch {
                self.launchState = .failed(.unavailable(error.localizedDescription))
            }
        }
    }

    private func launchReturned(_ output: LaunchOutput) {
        guard let terminal = output.terminal else {
            launchState = .unconfirmed(terminal: nil)
            return
        }
        if let status = records[terminal]?.info.status, status.state == "working" || !launchHasTask {
            launchState = .launched(terminal: terminal)
            return
        }
        if records[terminal]?.info.status == nil { launching.insert(terminal) }
        launchState = .starting(terminal: terminal)
        rebuild()
        launchTimer?.cancel()
        launchTimer = scheduler.schedule(after: timing.launchConfirmWindow) { [weak self] in
            guard let self, case .starting(let pending) = self.launchState, pending == terminal else { return }
            self.launchState = .unconfirmed(terminal: terminal)
            self.launching.remove(terminal)
            self.rebuild()
        }
    }

    public func resetLaunch() {
        if case .starting = launchState { return }
        launchState = .idle
    }

    // MARK: Focus

    public func openInHerdr(_ address: String) async -> HerdrError? {
        // herdr-core agents open in the Herdr app; other sources focus in their own app.
        let source = records[address]?.source ?? primary
        guard source != primary || herdrAppRunning else {
            return HerdrError(kind: "app_not_running", message: "Herdr app isn't running")
        }
        do {
            try await client(for: address).focus(terminal: address)
            return nil
        } catch let error as HerdrError {
            return error
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }
}

// MARK: - State types

public struct PanelState: Equatable, Sendable {
    public var address: String
    public var output: ReadOutput?
    public var fetchedAt: Date?
    public var isLoading = false
    public var error: HerdrError?

    public init(address: String) {
        self.address = address
    }
}

public enum SendState: Equatable, Sendable {
    /// In flight: Herdr waits until nobody has typed for a few seconds.
    case waiting
    case delivered
    case started
    case unconfirmed
    case failed(HerdrError)

    public var isInFlight: Bool { self == .waiting }

    public var label: String {
        switch self {
        case .waiting: "Waiting for you to stop typing…"
        case .delivered: "Delivered"
        case .started: "Agent started"
        case .unconfirmed: "Sent · unconfirmed"
        case .failed: "Failed"
        }
    }
}

public enum KeyPressState: Equatable, Sendable {
    case sending(String)
    case sent(String)
    case failed(String, HerdrError)
}

public enum InterruptButtonState: Equatable, Sendable {
    case ready
    case confirming
    case interrupting

    public var label: String {
        switch self {
        case .ready: "Interrupt current task"
        case .confirming: "Press again to confirm"
        case .interrupting: "Interrupting…"
        }
    }
}

public enum LaunchState: Equatable, Sendable {
    case idle
    /// Command sent (terminal nil) or terminal created and waiting for it to start working.
    case starting(terminal: String?)
    case launched(terminal: String)
    case unconfirmed(terminal: String?)
    case failed(HerdrError)

    public var label: String {
        switch self {
        case .idle: ""
        case .starting: "Starting…"
        case .launched: "Launched"
        case .unconfirmed: "Created · task start unconfirmed"
        case .failed: "Launch failed"
        }
    }
}
