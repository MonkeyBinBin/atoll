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
        /// After an answered agent leaves Needs you, wait this long before auto-advancing (chained prompts).
        public var autoAdvanceGrace: TimeInterval = 1.5
        public var interruptFeedbackDuration: TimeInterval = 4
        public var launchConfirmWindow: TimeInterval = 30
        public var outputLines: Int = 200
        /// An agent that exited (or whose terminal no longer runs one) leaves the island after this long.
        public var hideEndedAfter: TimeInterval = 15
        public init() {}
    }

    /// Methods this client calls on herdr-core.
    public nonisolated static let requiredMethods = [
        "events.subscribe", "terminal.read", "terminal.send", "terminal.keys", "terminal.interrupt", "templates.list",
    ]
    public nonisolated static let supportedGeneration = 1
    /// Label set by the shell wrapper on agents started from a terminal outside Herdr.
    public nonisolated static let originLabel = "atoll.origin"
    /// Written by the shell wrapper before the rename to Atoll; still read.
    public nonisolated static let legacyOriginLabel = "island.origin"
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

    /// How long an agent may sit in Needs you before one reminder; nil = never remind.
    public var reminderDelay: TimeInterval? {
        didSet {
            guard reminderDelay != oldValue else { return }
            reminderTimers.values.forEach { $0.cancel() }
            reminderTimers.removeAll()
            reminderEpisodes.removeAll()
            reconcileReminders()
        }
    }
    /// Called once per waiting episode that outlasts `reminderDelay` while its panel is closed.
    public var onReminder: ((_ agent: Agent, _ waited: TimeInterval) -> Void)?

    /// After answering a Needs-you agent from its panel, move on to the next waiting one.
    public var autoAdvance = true {
        didSet { if !autoAdvance { disarmAdvance() } }
    }
    /// The panel's agent was answered and has settled out of Needs you: open this one next.
    public var onAutoAdvance: ((_ next: String) -> Void)?
    /// Same moment, but nobody else is waiting.
    public var onAllClear: (() -> Void)?

    /// Agents whose next finished turn notifies once (armed from the panel). In memory only.
    public private(set) var notifyWhenDone: Set<String> = []
    /// An armed agent finished its turn (Done, Exited, or stopped to Idle); it is now disarmed.
    public var onNotifyWhenDone: ((_ agent: Agent) -> Void)?

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
        /// When the agent was first seen ended (Exited, or its status cleared); nil while running.
        var endedSince: Date?
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
    private var endedTimers: [String: ScheduledAction] = [:]
    /// Pending reminder per agent, and the episode (its `waitingSince`) it was scheduled for.
    private var reminderTimers: [String: ScheduledAction] = [:]
    private var reminderEpisodes: [String: Date] = [:]
    /// Episodes already reminded (or skipped): never again for the same `waitingSince`.
    private var remindedEpisodes: [String: Date] = [:]
    /// The Needs-you agent the user just acted on from its panel, and the grace timer once it left Needs you.
    private var advanceArmed: String?
    private var advanceTimer: ScheduledAction?
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

    /// The earliest-waiting Needs-you agent other than `address`.
    public func nextWaitingAgent(excluding address: String?) -> Agent? {
        agents.filter { $0.state.isNeedsYou && $0.address != address }
            .min { ($0.waitingSince ?? .distantFuture) < ($1.waitingSince ?? .distantFuture) }
    }

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
            advanceAfterTransition(after, from: before)
            notifyIfFinished(after, from: before)
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
        if showUnreportedTerminals || launching.contains(record.info.address) { return true }
        guard record.lastKnownApp != nil else { return false }
        guard let ended = record.endedSince, panel?.address != record.info.address else { return true }
        return scheduler.now.timeIntervalSince(ended) < timing.hideEndedAfter
    }

    /// The terminal no longer runs its agent: it exited, or the source cleared its status.
    /// A lost terminal may come back, so it doesn't count.
    private func hasEnded(_ record: Record) -> Bool {
        guard record.lastKnownApp != nil, !launching.contains(record.info.address) else { return false }
        return record.info.state == "finished" || (record.info.status == nil && !record.lost)
    }

    /// Stamps `endedSince` and keeps one timer per ended agent to drop it from the list on time.
    private func reconcileEnded() {
        let now = scheduler.now
        for (address, record) in records {
            if hasEnded(record) {
                guard record.endedSince == nil else { continue }
                // An exit reported with its time (e.g. in a snapshot after a restart) counts from then.
                let since = record.info.state == "finished"
                    ? record.info.finishedMs.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? now
                    : now
                records[address]?.endedSince = min(since, now)
                let remaining = timing.hideEndedAfter - now.timeIntervalSince(min(since, now))
                endedTimers[address]?.cancel()
                endedTimers[address] = remaining > 0
                    ? scheduler.schedule(after: remaining) { [weak self] in
                        self?.endedTimers[address] = nil
                        self?.rebuild()
                    }
                    : nil
            } else if record.endedSince != nil {
                records[address]?.endedSince = nil
                endedTimers.removeValue(forKey: address)?.cancel()
            }
        }
        for address in endedTimers.keys where records[address] == nil {
            endedTimers.removeValue(forKey: address)?.cancel()
        }
    }

    private func rebuild() {
        reconcileEnded()
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
                origin: (info.labels[Self.originLabel] ?? info.labels[Self.legacyOriginLabel]).flatMap { $0.isEmpty ? nil : $0 }
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
        notifyWhenDone = notifyWhenDone.filter { records[$0] != nil }
        reconcileReminders()
    }

    // MARK: Notify when done

    public func toggleNotifyWhenDone(_ address: String) {
        guard records[address] != nil else { return }
        if notifyWhenDone.contains(address) { notifyWhenDone.remove(address) } else { notifyWhenDone.insert(address) }
    }

    /// A turn ended: Done or Exited, or Idle straight from Working (stopped without reporting Done).
    /// Error ends it too but already notifies; Needs you is mid-turn and keeps the bell armed.
    private func notifyIfFinished(_ agent: Agent, from previous: AgentState?) {
        guard notifyWhenDone.contains(agent.address) else { return }
        let finished: Bool
        switch agent.state {
        case .done, .exited: finished = true
        case .idle: finished = previous == .working || previous == .starting
        case .error:
            notifyWhenDone.remove(agent.address)
            return
        default: finished = false
        }
        guard finished else { return }
        notifyWhenDone.remove(agent.address)
        onNotifyWhenDone?(agent)
    }

    // MARK: Waiting reminders

    /// Keeps one timer per live Needs-you episode. The delay counts from when the episode was first
    /// seen here, so a snapshot carrying an old `waitingSince` doesn't remind the moment it arrives.
    private func reconcileReminders() {
        var waiting: [String: Date] = [:]
        if reminderDelay != nil {
            for agent in agents where agent.state.isNeedsYou {
                if let since = agent.waitingSince { waiting[agent.address] = since }
            }
        }
        for (address, episode) in reminderEpisodes where waiting[address] != episode {
            reminderTimers.removeValue(forKey: address)?.cancel()
            reminderEpisodes[address] = nil
        }
        // Offline agents keep their mark: the same episode isn't re-reminded after a reconnect.
        remindedEpisodes = remindedEpisodes.filter { records[$0.key]?.waitingSince == $0.value }
        guard let delay = reminderDelay else { return }
        for (address, since) in waiting where reminderEpisodes[address] != since && remindedEpisodes[address] != since {
            reminderEpisodes[address] = since
            reminderTimers[address] = scheduler.schedule(after: delay) { [weak self] in
                self?.fireReminder(address, episode: since)
            }
        }
    }

    private func fireReminder(_ address: String, episode: Date) {
        reminderTimers[address] = nil
        reminderEpisodes[address] = nil
        guard let agent = agent(address), agent.state.isNeedsYou, agent.waitingSince == episode else { return }
        remindedEpisodes[address] = episode
        // The user is already looking at it.
        if panel?.address == address { return }
        onReminder?(agent, scheduler.now.timeIntervalSince(episode))
    }

    // MARK: Panel

    public func openPanel(_ address: String) {
        guard records[address] != nil else { return }
        if panel?.address != address {
            outputRequest += 1
            panel = PanelState(address: address)
            disarmAdvance()
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
        let wasOpen = panel != nil
        panel = nil
        disarmAdvance()
        // An ended agent kept on screen for its open panel may leave now.
        if wasOpen { rebuild() }
    }

    // MARK: Auto-advance

    /// Only an answer from the open panel to an agent that is waiting arms the advance.
    private func armAdvance(_ address: String) {
        guard autoAdvance, panel?.address == address, agent(address)?.state.isNeedsYou == true else { return }
        advanceTimer?.cancel()
        advanceTimer = nil
        advanceArmed = address
    }

    private func disarmAdvance(_ address: String? = nil) {
        guard address == nil || advanceArmed == address else { return }
        advanceArmed = nil
        advanceTimer?.cancel()
        advanceTimer = nil
    }

    /// The source reported the answered agent out of Needs you: wait out the grace period, then move on.
    private func advanceAfterTransition(_ agent: Agent, from previous: AgentState?) {
        guard advanceArmed == agent.address, previous?.isNeedsYou == true,
              !agent.state.isNeedsYou, agent.state != .unknown else { return }
        let address = agent.address
        advanceTimer?.cancel()
        advanceTimer = scheduler.schedule(after: timing.autoAdvanceGrace) { [weak self] in
            self?.finishAdvance(address)
        }
    }

    private func finishAdvance(_ address: String) {
        advanceTimer = nil
        guard advanceArmed == address else { return }
        advanceArmed = nil
        // Back in Needs you (a chained prompt), or the user moved elsewhere: stay put.
        guard autoAdvance, panel?.address == address, let agent = agent(address),
              !agent.state.isNeedsYou, agent.state != .unknown else { return }
        if let next = nextWaitingAgent(excluding: address) {
            onAutoAdvance?(next.address)
        } else {
            onAllClear?()
        }
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
        armAdvance(address)
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
                self.disarmAdvance(address)
            } catch {
                self.sendStates[address] = .failed(.unavailable(error.localizedDescription))
                self.disarmAdvance(address)
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
        armAdvance(address)
        Task { [client = client(for: address)] in
            do {
                try await client.keys(terminal: address, keys: [key])
                self.keyStates[address] = .sent(key)
            } catch let error as HerdrError {
                self.keyStates[address] = .failed(key, error)
                self.disarmAdvance(address)
            } catch {
                self.keyStates[address] = .failed(key, .unavailable(error.localizedDescription))
                self.disarmAdvance(address)
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
            armAdvance(address)
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
