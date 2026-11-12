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
        /// After entering Needs you (or finishing a turn), wait this long for the screen to settle before
        /// its one read: the waiting preview, or the turn's final message.
        public var previewDelay: TimeInterval = 0.6
        public var previewLines: Int = 80
        /// "No output" checks: each Working agent's screen is fingerprinted this often, reading this many lines,
        /// and never more than this many reads a minute over all agents (intervals stretch instead).
        public var outputCheckInterval: TimeInterval = 120
        public var outputCheckLines: Int = 40
        public var outputChecksPerMinute: Int = 10
        /// Codex reports Idle → Working → Idle as it starts (ticket 41): a first Working beginning this soon
        /// after the status appears, and back to Idle within `startupSettleWithin` of it, is the agent coming
        /// up, not a turn.
        public var startupWorkingWithin: TimeInterval = 3
        public var startupSettleWithin: TimeInterval = 10
        /// Herdr spaces are re-read (`herdr-app ls`) this often while the Herdr app runs: renames and moved
        /// panes have no event.
        public var spaceRefreshInterval: TimeInterval = 15
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
    /// Whether the Herdr GUI is running (launch / focus need it; spaces come from it).
    public var herdrAppRunning = false {
        didSet {
            guard herdrAppRunning != oldValue else { return }
            if herdrAppRunning {
                refreshSpaces()
            } else {
                spaceGeneration += 1
                spaceRefreshing = false
                spaceRefreshAgain = false
                spaceTimer?.cancel()
                spaceTimer = nil
                if !spaces.isEmpty {
                    spaces = []
                    rebuild()
                }
            }
        }
    }

    /// Herdr GUI spaces (ticket 42), in Herdr's order; empty while the Herdr app isn't running.
    public private(set) var spaces: [HerdrSpace] = []
    private var spaceTimer: ScheduledAction?
    private var spaceRefreshing = false
    private var spaceRefreshAgain = false
    private var spaceGeneration = 0
    /// herdr-core agents a refresh already ran for while they had no space (each triggers one).
    private var spaceMisses: Set<String> = []

    /// Visible agents, sorted by priority.
    public private(set) var agents: [Agent] = []

    public private(set) var panel: PanelState?
    public private(set) var sendStates: [String: SendState] = [:]
    public private(set) var keyStates: [String: KeyPressState] = [:]
    /// Allow / Deny pressed from the list, for the current Needs-you episode.
    public private(set) var permissionResponses: [String: PermissionResponseState] = [:]
    public private(set) var interruptStates: [String: InterruptButtonState] = [:]
    public private(set) var launchState: LaunchState = .idle {
        didSet {
            switch (oldValue, launchState) {
            case (.starting, .launched), (.starting, .unconfirmed): onLaunchFinished?(true)
            case (_, .failed): onLaunchFinished?(false)
            default: break
            }
        }
    }
    /// A launch ended: true when it went out (the agent started, or Herdr took it without confirmation),
    /// false when it failed (worktree, Herdr, or the app not running).
    public var onLaunchFinished: ((_ succeeded: Bool) -> Void)?

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

    /// A Working agent whose screen hasn't changed this long is marked "No output for …"; nil turns the
    /// checks off entirely.
    public var noOutputThreshold: TimeInterval? = 600 {
        didSet {
            guard noOutputThreshold != oldValue else { return }
            if noOutputThreshold == nil {
                noOutputWatch.removeAll()
                noOutputTimer?.cancel()
                noOutputTimer = nil
            }
            rebuild()
        }
    }

    /// Today's finished turns (ticket 38). In memory only; never written to disk or put in notifications.
    public private(set) var timeline = TodayTimeline()
    /// Off: nothing is collected, and what was collected goes.
    public var timelineEnabled = true {
        didSet {
            guard timelineEnabled != oldValue, !timelineEnabled else { return }
            clearTimeline()
        }
    }
    /// Local days for the timeline (injectable for tests).
    public var calendar = Calendar.autoupdatingCurrent
    /// Empties the timeline at the next local midnight.
    private var midnightTimer: ScheduledAction?

    /// Messages waiting for their agent's turn to end (ticket 34). In memory only.
    public private(set) var queuedMessages: [String: QueuedMessage] = [:]
    /// Notes about a queued message for the open panel's agent; cleared with the panel.
    public private(set) var queueNotices: [String: QueueNotice] = [:]
    /// A queued message went out (Delivered / Agent started / Sent · unconfirmed).
    public var onQueuedSent: ((_ agent: Agent) -> Void)?
    /// A queued message couldn't be sent; never retried, the text goes back to the user.
    public var onQueuedFailed: ((_ address: String, _ text: String) -> Void)?

    /// Computes per-turn change summaries; nil turns the feature off (no git runs at all).
    /// Lists a turn's files and diffs for the panel's changes view; nil = the view is unavailable.
    public var changeInspector: (any ChangeInspecting)?

    public var changeProbe: (any ChangeProbing)? {
        didSet {
            guard changeProbe == nil, oldValue != nil else { return }
            openTurns.removeAll()
            changeSummaries.removeAll()
            summaryGeneration.removeAll()
            rebuild()
        }
    }

    /// Groups agents by git working tree to warn when several are active in one; nil = off (no git).
    public var treeProbe: (any WorkingTreeProbing)? {
        didSet {
            guard treeProbe == nil, oldValue != nil else { return }
            treeGeneration += 1
            treeCache.removeAll()
            pendingTrees.removeAll()
            sharedAnnounced.removeAll()
            rebuild()
        }
    }
    /// An agent became active in a working tree another active agent already works in. Once per newcomer
    /// while the tree keeps two or more agents; announced again only after it drops below two.
    public var onSharedTree: ((_ agent: Agent) -> Void)?
    /// The one screen read of a Needs-you episode finished (whatever it found) while the agent still waits.
    public var onWaitingDetails: ((_ agent: Agent) -> Void)?

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
        /// When the status last appeared (from none, or for another app): startup settle counts from here.
        var statusAppearedAt: Date?
        /// A Working has been seen since the status appeared.
        var workedSinceAppeared = false
        /// The current Working began within the startup window: going Idle soon is just starting up.
        var startupWorking = false
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
    /// Turns in progress per agent, with the baseline being captured as they started.
    private var openTurns: [String: Task<TurnBaseline?, Never>] = [:]
    private var changeSummaries: [String: ChangeSummary] = [:]
    /// Working-tree top level last seen per agent (from baselines and summaries).
    private var toplevels: [String: String] = [:]
    /// Bumped per turn start / finish so a late git result never lands on a newer turn.
    private var summaryGeneration: [String: Int] = [:]
    /// Needs-you episode (its `waitingSince`) whose screen was read, or is being read, per agent.
    private var previewEpisodes: [String: Date] = [:]
    /// Waiting previews for the current episode only; dropped the moment the agent leaves Needs you.
    private var previews: [String: WaitingPreview] = [:]
    private var choices: [String: PermissionChoices] = [:]
    /// Episodes whose screen read is over, found or not.
    private var previewResolved: [String: Date] = [:]
    /// Episode each list response belongs to; a "No longer waiting" note outlives it on its own timer.
    private var responseEpisodes: [String: Date] = [:]
    private var responseTimers: [String: ScheduledAction] = [:]
    private var previewTimers: [String: ScheduledAction] = [:]
    /// Final message of each agent's last finished turn, and the token of its pending read: a new turn,
    /// or the agent going away, removes the token so a late result is thrown away.
    private var finalMessages: [String: TurnFinalMessage] = [:]
    private var finalReads: [String: Int] = [:]
    private var nextFinalRead = 0
    private var finalTimers: [String: ScheduledAction] = [:]
    private var noOutputWatch = NoOutputWatch()
    private var noOutputTimer: ScheduledAction?
    /// Working-tree top level per project path ("" = not in a repo). Resolved once per path, never polled.
    private var treeCache: [String: String] = [:]
    private var pendingTrees: Set<String> = []
    private var treeGeneration = 0
    /// Per top level: agents already covered by a shared-tree announcement.
    private var sharedAnnounced: [String: Set<String>] = [:]

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
        var startupSettle = false

        switch event {
        case .created:
            break
        case .status(_, let status, let reported):
            startupSettle = observeStartup(&record, status: status, now: now)
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
            // Settling after start-up: reported as a first sighting, so nothing treats it as a finished turn.
            let from = startupSettle ? nil : before
            if startupSettle { discardOpenTurn(address) }
            onTransition?(after, from)
            advanceAfterTransition(after, from: from)
            notifyIfFinished(after, from: from)
            sendQueuedIfFinished(after, from: from)
            trackTurn(after, from: from)
            trackFinalMessage(after, from: from)
            trackTimeline(after, from: from)
        }
        if refreshOutput, panel?.address == address {
            refreshPanelOutput()
        }
    }

    /// Follows a status change for start-up settle (ticket 41, Codex only); returns true when it is the
    /// Working → Idle of an agent just coming up.
    private func observeStartup(_ record: inout Record, status: CoreStatus?, now: Date) -> Bool {
        let old = record.info.status
        guard let status, AgentTool.from(app: status.app) == .codex else {
            record.statusAppearedAt = nil
            record.startupWorking = false
            return false
        }
        if old == nil || old?.app != status.app {
            record.statusAppearedAt = now
            record.workedSinceAppeared = false
            record.startupWorking = false
        }
        let wasWorking = old?.state == "working"
        if status.state == "working", !wasWorking {
            let appeared = record.statusAppearedAt
            record.startupWorking = !record.workedSinceAppeared
                && appeared.map { now.timeIntervalSince($0) <= timing.startupWorkingWithin } == true
            record.workedSinceAppeared = true
            return false
        }
        guard status.state != "working" else { return false }
        defer { record.startupWorking = false }
        guard wasWorking, record.startupWorking, status.state == "idle", let appeared = record.statusAppearedAt else { return false }
        return now.timeIntervalSince(appeared) <= timing.startupSettleWithin
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
        var spaceByTerminal: [String: HerdrSpace] = [:]
        for space in spaces {
            for terminal in space.terminals where spaceByTerminal[terminal] == nil { spaceByTerminal[terminal] = space }
        }
        var unmapped = false
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
            if record.source == .core {
                if let space = spaceByTerminal[info.address] {
                    agent.spaceID = space.id
                    agent.spaceName = space.name
                } else if herdrAppRunning, spaceMisses.insert(info.address).inserted {
                    unmapped = true
                }
            }
            agent.changeSummary = changeSummaries[info.address]
            agent.finalMessage = finalMessages[info.address]
            if state.isNeedsYou, let since = agent.waitingSince, previewEpisodes[info.address] == since {
                agent.waitingPreview = previews[info.address]
                agent.permissionChoices = choices[info.address]
            }
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
        var built = list.map(\.0)
        let newcomers = treeProbe == nil ? [] : markSharedTrees(&built)
        markNoOutput(&built)
        agents = built
        notifyWhenDone = notifyWhenDone.filter { records[$0] != nil }
        spaceMisses = spaceMisses.filter { records[$0] != nil }
        if unmapped { refreshSpaces() }
        reconcileQueued()
        for address in Set(finalMessages.keys).union(finalReads.keys) where records[address] == nil {
            dropFinalMessage(address, rebuilding: false)
        }
        for address in Set(openTurns.keys).union(changeSummaries.keys).union(toplevels.keys) where records[address] == nil {
            openTurns.removeValue(forKey: address)?.cancel()
            changeSummaries[address] = nil
            toplevels[address] = nil
            summaryGeneration[address] = nil
        }
        // Assigned only on a change: most rebuilds don't touch it, and every write re-renders its viewers.
        if !timeline.entries.isEmpty {
            var updated = timeline
            updated.fill(built)
            updated.markGone(built, ended: Set(records.values.filter(hasEnded).map(\.info.address)))
            if updated != timeline { timeline = updated }
        }
        reconcileReminders()
        reconcilePreviews()
        dropStaleChanges()
        for address in newcomers {
            if let agent = agent(address) { onSharedTree?(agent) }
        }
    }

    // MARK: Herdr spaces

    /// Re-reads the Herdr app's spaces now (then every `spaceRefreshInterval`). A failed read keeps the last ones.
    public func refreshSpaces() {
        guard herdrAppRunning else { return }
        guard !spaceRefreshing else {
            spaceRefreshAgain = true
            return
        }
        spaceRefreshing = true
        spaceTimer?.cancel()
        spaceTimer = nil
        let generation = spaceGeneration
        Task { [client] in
            let result = try? await client.spaces()
            guard generation == self.spaceGeneration else { return }
            self.spaceRefreshing = false
            if let result, result != self.spaces {
                self.spaces = result
                self.rebuild()
            }
            if self.spaceRefreshAgain {
                self.spaceRefreshAgain = false
                self.refreshSpaces()
            } else {
                self.spaceTimer = self.scheduler.schedule(after: self.timing.spaceRefreshInterval) { [weak self] in
                    self?.spaceTimer = nil
                    self?.refreshSpaces()
                }
            }
        }
    }

    // MARK: Waiting preview

    /// One screen read per Needs-you episode: for the preview when the source didn't say why (`statusMessage`),
    /// and for a permission dialog's answer keys even when it did.
    /// Leaving Needs you (or a new episode) drops both: the only screen text kept with the panel closed.
    private func reconcilePreviews() {
        var waiting: [String: Agent] = [:]
        for agent in agents where agent.state.isNeedsYou && agent.waitingSince != nil {
            waiting[agent.address] = agent
        }
        for (address, episode) in previewEpisodes where waiting[address]?.waitingSince != episode {
            previewEpisodes[address] = nil
            previews[address] = nil
            choices[address] = nil
            previewResolved[address] = nil
            previewTimers.removeValue(forKey: address)?.cancel()
        }
        for (address, episode) in responseEpisodes where waiting[address]?.waitingSince != episode {
            responseEpisodes[address] = nil
            if permissionResponses[address] != .noLongerWaiting { permissionResponses[address] = nil }
        }
        for agent in waiting.values where previewEpisodes[agent.address] == nil && needsScreenRead(agent) {
            guard let episode = agent.waitingSince else { continue }
            let address = agent.address
            previewEpisodes[address] = episode
            previewTimers[address] = scheduler.schedule(after: timing.previewDelay) { [weak self] in
                self?.previewTimers[address] = nil
                self?.readPreview(address, episode: episode)
            }
        }
    }

    private func needsScreenRead(_ agent: Agent) -> Bool {
        if agent.statusMessage == nil { return true }
        guard agent.tool != .generic, let kind = agent.state.blockedKind else { return false }
        return kind == .permission || kind == .unspecified
    }

    private func readPreview(_ address: String, episode: Date) {
        guard let agent = agent(address), agent.waitingSince == episode, let kind = agent.state.blockedKind else {
            resolvePreview(address, episode: episode)
            return
        }
        let lines = timing.previewLines
        let tool = agent.tool
        let keepPreview = agent.statusMessage == nil
        Task { [client = client(for: address)] in
            // A failed read just means no preview; never retried within the episode.
            let output = try? await client.read(terminal: address, lines: lines)
            guard self.previewEpisodes[address] == episode else { return }
            if let output, let preview = WaitingPreview.extract(from: output.text, tool: tool, kind: kind) {
                if keepPreview { self.previews[address] = preview }
                self.choices[address] = PermissionChoices.extract(from: output.text, tool: tool, kind: kind)
            }
            // Rebuild first so whoever hears "resolved" sees the preview and keys on the agent.
            self.rebuild()
            self.resolvePreview(address, episode: episode)
        }
    }

    private func resolvePreview(_ address: String, episode: Date) {
        guard previewEpisodes[address] == episode else { return }
        previewResolved[address] = episode
        if let agent = agent(address), agent.waitingSince == episode { onWaitingDetails?(agent) }
    }

    /// The current Needs-you episode's screen read hasn't finished yet (so its preview and keys may still come).
    public func isReadingWaitingScreen(_ address: String) -> Bool {
        guard let episode = previewEpisodes[address] else { return false }
        return previewResolved[address] != episode
    }

    // MARK: Permission from the list

    /// Allow / Deny a permission dialog without opening the panel. `episode` is the `waitingSince` the user
    /// saw; if the agent has left that dialog since, nothing is sent so the key can't land in the next one.
    public func respond(
        _ choice: PermissionChoice, to address: String, episode: Date?,
        completion: (@MainActor (PermissionResponseState) -> Void)? = nil
    ) {
        if case .sending = permissionResponses[address] { return }
        guard let agent = agent(address), agent.state.isNeedsYou, let episode, agent.waitingSince == episode,
              let key = agent.permissionChoices?.key(for: choice) else {
            showNoLongerWaiting(address)
            completion?(.noLongerWaiting)
            return
        }
        responseTimers.removeValue(forKey: address)?.cancel()
        responseEpisodes[address] = episode
        permissionResponses[address] = .sending(choice)
        armAdvance(address)
        Task { [client = client(for: address)] in
            let result: PermissionResponseState
            do {
                try await client.keys(terminal: address, keys: [key])
                result = .sent(choice)
            } catch let error as HerdrError {
                result = .failed(choice, error)
            } catch {
                result = .failed(choice, .unavailable(error.localizedDescription))
            }
            if case .failed = result { self.disarmAdvance(address) }
            completion?(result)
            // Never retried. Only shown while the agent is still in the episode it was sent for.
            guard self.responseEpisodes[address] == episode else { return }
            self.permissionResponses[address] = result
        }
    }

    private func showNoLongerWaiting(_ address: String) {
        responseEpisodes[address] = nil
        permissionResponses[address] = .noLongerWaiting
        responseTimers[address]?.cancel()
        responseTimers[address] = scheduler.schedule(after: timing.interruptFeedbackDuration) { [weak self] in
            guard let self else { return }
            self.responseTimers[address] = nil
            if self.permissionResponses[address] == .noLongerWaiting { self.permissionResponses[address] = nil }
        }
    }

    // MARK: Shared working tree

    /// Resolves unknown project paths in the background, flags active agents that share a tree,
    /// and returns the agents whose arrival should be announced.
    private func markSharedTrees(_ list: inout [Agent]) -> [String] {
        let paths = Set(list.map(\.projectPath))
        treeCache = treeCache.filter { paths.contains($0.key) }
        if let probe = treeProbe {
            for path in paths where treeCache[path] == nil && !pendingTrees.contains(path) {
                pendingTrees.insert(path)
                let generation = treeGeneration
                Task {
                    let toplevel = await probe.toplevel(in: path)
                    guard generation == self.treeGeneration else { return }
                    self.pendingTrees.remove(path)
                    self.treeCache[path] = toplevel ?? ""
                    self.rebuild()
                }
            }
        }
        var groups: [String: [Int]] = [:]
        for (index, agent) in list.enumerated() where agent.state != .exited {
            guard let toplevel = treeCache[agent.projectPath], !toplevel.isEmpty else { continue }
            groups[toplevel, default: []].append(index)
        }
        var newcomers: [String] = []
        for (toplevel, members) in groups {
            let memberAddresses = Set(members.map { list[$0].address })
            guard members.count >= 2 else {
                sharedAnnounced[toplevel] = nil
                continue
            }
            let active = members.filter { list[$0].state.isActiveInTree }
            guard active.count >= 2 else { continue }
            for index in active {
                list[index].sharedTreeWith = active.filter { $0 != index }.map { list[$0].address }
            }
            let announced = (sharedAnnounced[toplevel] ?? []).intersection(memberAddresses)
            let fresh = active.filter { !announced.contains(list[$0].address) }
            // Point at the one that just started; the others were already working there.
            if let newest = fresh.max(by: { (list[$0].stateSince ?? .distantPast) < (list[$1].stateSince ?? .distantPast) }) {
                newcomers.append(list[newest].address)
            }
            sharedAnnounced[toplevel] = announced.union(active.map { list[$0].address })
        }
        sharedAnnounced = sharedAnnounced.filter { groups[$0.key] != nil }
        return newcomers
    }

    // MARK: Change summary

    /// A turn starts on Working / Starting (Needs you and Unknown stay inside it); it finishes on Done,
    /// Exited, or Idle that ends it. Error closes it without a summary (Error is its own announcement).
    private func trackTurn(_ agent: Agent, from previous: AgentState?) {
        guard let probe = changeProbe else { return }
        let address = agent.address
        let directory = agent.projectPath
        let isOpen = openTurns[address] != nil
        switch agent.state {
        case .working, .starting:
            guard !isOpen else { return }
            let generation = bumpGeneration(address)
            let hadSummary = changeSummaries.removeValue(forKey: address) != nil
            let baseline = Task { await probe.baseline(in: directory) }
            openTurns[address] = baseline
            Task {
                guard let toplevel = await baseline.value?.toplevel, self.summaryGeneration[address] == generation else { return }
                self.toplevels[address] = toplevel
            }
            if hadSummary { rebuild() }
        case .done, .exited, .idle:
            let wasRunning = previous == .working || previous == .starting
            // Done → Idle / Exited is the same turn settling: keep its summary.
            guard isOpen || (agent.state == .done && previous != nil) || wasRunning else { return }
            let baseline = openTurns.removeValue(forKey: address)
            let generation = bumpGeneration(address)
            Task {
                let base = await baseline?.value
                let summary = await probe.summary(in: directory, since: base)
                self.finishSummary(address, generation: generation, summary: summary)
            }
        case .error:
            discardOpenTurn(address)
        case .needsYou, .unknown:
            break
        }
    }

    /// Drops a turn's git baseline without a summary, and any summary still on its way.
    private func discardOpenTurn(_ address: String) {
        openTurns.removeValue(forKey: address)?.cancel()
        bumpGeneration(address)
    }

    @discardableResult
    private func bumpGeneration(_ address: String) -> Int {
        let next = (summaryGeneration[address] ?? 0) + 1
        summaryGeneration[address] = next
        return next
    }

    private func finishSummary(_ address: String, generation: Int, summary: ChangeSummary?) {
        guard changeProbe != nil, summaryGeneration[address] == generation, records[address] != nil else { return }
        guard var summary else {
            changeSummaries[address] = nil
            rebuild()
            return
        }
        toplevels[address] = summary.toplevel
        // Another agent still around in the same tree: the diff can't be pinned on this one.
        summary.sharedTree = agents.contains {
            let tree = treeCache[$0.projectPath].flatMap { $0.isEmpty ? nil : $0 } ?? toplevels[$0.address]
            return $0.address != address && $0.state != .exited && tree == summary.toplevel
        }
        changeSummaries[address] = summary
        rebuild()
    }

    // MARK: Notify when done

    public func toggleNotifyWhenDone(_ address: String) {
        guard records[address] != nil else { return }
        if notifyWhenDone.contains(address) { notifyWhenDone.remove(address) } else { notifyWhenDone.insert(address) }
    }

    /// A turn ended: Done or Exited, or Idle straight from Working / Starting (stopped without reporting Done).
    /// Error ends it too but is handled on its own; Needs you is mid-turn.
    private static func turnEnded(_ state: AgentState, from previous: AgentState?) -> Bool {
        switch state {
        case .done, .exited: true
        case .idle: previous == .working || previous == .starting
        default: false
        }
    }

    /// Error already notifies, so it just disarms the bell; Needs you keeps it armed.
    private func notifyIfFinished(_ agent: Agent, from previous: AgentState?) {
        guard notifyWhenDone.contains(agent.address) else { return }
        if agent.state == .error {
            notifyWhenDone.remove(agent.address)
            return
        }
        guard Self.turnEnded(agent.state, from: previous) else { return }
        notifyWhenDone.remove(agent.address)
        onNotifyWhenDone?(agent)
    }

    // MARK: Queued message

    /// Only a working agent takes a queued message; otherwise the panel sends directly.
    public func canQueue(_ address: String) -> Bool {
        guard let state = agent(address)?.state else { return false }
        return state == .working || state == .starting
    }

    /// Queues `text` for an agent that is working; replaces an earlier one. False when it isn't working
    /// or the text is empty.
    @discardableResult
    public func queue(_ text: String, for address: String) -> Bool {
        guard canQueue(address), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        // A trailing newline would submit an extra empty line.
        var text = text
        while text.last?.isWhitespace == true { text.removeLast() }
        queuedMessages[address] = QueuedMessage(text: text)
        queueNotices[address] = nil
        return true
    }

    public func cancelQueued(_ address: String) {
        guard queuedMessages[address]?.status != .sending else { return }
        queuedMessages[address] = nil
    }

    /// Takes the queued text out to edit it in the reply box (it is no longer queued).
    public func editQueued(_ address: String) -> String? {
        guard let queued = queuedMessages[address], queued.status != .sending else { return nil }
        queuedMessages[address] = nil
        return queued.text
    }

    /// Exited drops the message instead of sending it.
    private func sendQueuedIfFinished(_ agent: Agent, from previous: AgentState?) {
        guard let queued = queuedMessages[agent.address], queued.status == .waiting,
              agent.state != .exited, Self.turnEnded(agent.state, from: previous) else { return }
        deliverQueued(agent.address, text: queued.text)
    }

    /// A held message may go out on the user's say-so, but never into a dialog it would answer.
    public func canSendQueuedNow(_ address: String) -> Bool {
        guard queuedMessages[address]?.status == .held, let agent = agent(address) else { return false }
        return agent.replyMode == .text(force: false)
    }

    public func sendQueuedNow(_ address: String) {
        guard canSendQueuedNow(address), let queued = queuedMessages[address] else { return }
        deliverQueued(address, text: queued.text)
    }

    /// One attempt through the panel's send path; a failure hands the text back instead of retrying.
    private func deliverQueued(_ address: String, text: String) {
        queuedMessages[address]?.status = .sending
        let started = send(text, to: address) { [weak self] state in
            guard let self else { return }
            self.queuedMessages[address] = nil
            if case .failed = state {
                self.onQueuedFailed?(address, text)
            } else if let agent = self.agent(address) {
                self.onQueuedSent?(agent)
            }
        }
        if !started {
            queuedMessages[address] = nil
            queueNotices[address] = .notSent
            onQueuedFailed?(address, text)
        }
    }

    /// State-based upkeep on every rebuild: Error holds a waiting message, Exited or removed drops it
    /// (one already being sent finishes first). Sending only ever happens on a live transition, so a turn end
    /// missed while offline isn't caught up.
    private func reconcileQueued() {
        for (address, queued) in queuedMessages where queued.status != .sending {
            guard records[address] != nil else {
                queuedMessages[address] = nil
                continue
            }
            let state = agent(address)?.state
            if records[address]?.info.state == "finished" || state == .exited {
                queuedMessages[address] = nil
                if panel?.address == address { queueNotices[address] = .dropped }
            } else if queued.status == .waiting, state == .error {
                queuedMessages[address]?.status = .held
            }
        }
    }

    // MARK: No output

    /// Keeps the watch in step with who is Working, and stamps the ones whose screen sat still too long.
    private func markNoOutput(_ agents: inout [Agent]) {
        guard let threshold = noOutputThreshold else { return }
        noOutputWatch.sync(working: Set(agents.filter { $0.state == .working }.map(\.address)), now: scheduler.now)
        for index in agents.indices {
            agents[index].noOutputSince = noOutputWatch.quietSince(agents[index].address, threshold: threshold)
        }
        scheduleNoOutputTick()
    }

    /// One tick per `60 / outputChecksPerMinute` seconds while anyone is Working; each tick reads at most one
    /// screen, so the per-minute cap holds however many agents work.
    private func scheduleNoOutputTick() {
        guard noOutputTimer == nil, noOutputThreshold != nil, !noOutputWatch.entries.isEmpty else { return }
        let spacing = 60 / Double(max(1, timing.outputChecksPerMinute))
        noOutputTimer = scheduler.schedule(after: spacing) { [weak self] in
            guard let self else { return }
            self.noOutputTimer = nil
            self.checkNextOutput()
            self.scheduleNoOutputTick()
        }
    }

    private func checkNextOutput() {
        guard let ticket = noOutputWatch.takeDue(now: scheduler.now, interval: timing.outputCheckInterval),
              let tool = agent(ticket.address)?.tool else { return }
        let lines = timing.outputCheckLines
        Task { [client = client(for: ticket.address)] in
            // The screen text lives only for this hash.
            let hash = (try? await client.read(terminal: ticket.address, lines: lines))
                .map { OutputFilter.activityFingerprint($0.text, tool: tool) }
            let before = self.noOutputThreshold.flatMap { self.noOutputWatch.quietSince(ticket.address, threshold: $0) }
            self.noOutputWatch.record(ticket, hash: hash, now: self.scheduler.now)
            let after = self.noOutputThreshold.flatMap { self.noOutputWatch.quietSince(ticket.address, threshold: $0) }
            // Most checks change nothing visible: skip the full rebuild then.
            if before != after { self.rebuild() }
        }
    }

    // MARK: Turn final message

    /// A finished turn without a `statusMessage` gets one screen read (after the screen settles);
    /// the next turn, or the agent leaving, drops the result. Done / Idle → Exited is the same turn settling.
    private func trackFinalMessage(_ agent: Agent, from previous: AgentState?) {
        let settling = agent.state == .exited && (previous == .done || previous == .idle)
        if Self.turnEnded(agent.state, from: previous), !settling {
            dropFinalMessage(agent.address)
            guard agent.statusMessage == nil, agent.tool != .generic else { return }
            scheduleFinalRead(agent.address, tool: agent.tool)
        } else if agent.state == .working || agent.state == .starting || agent.state.isNeedsYou {
            dropFinalMessage(agent.address)
        }
    }

    private func scheduleFinalRead(_ address: String, tool: AgentTool) {
        nextFinalRead += 1
        let token = nextFinalRead
        finalReads[address] = token
        let lines = timing.previewLines
        finalTimers[address] = scheduler.schedule(after: timing.previewDelay) { [weak self] in
            guard let self, self.finalReads[address] == token else { return }
            self.finalTimers[address] = nil
            // Moved on (Error, offline…) while the screen settled: nothing to read for this turn.
            guard let state = self.agent(address)?.state, [.done, .idle, .exited].contains(state) else {
                self.finalReads[address] = nil
                return
            }
            Task { [client = self.client(for: address)] in
                // A failed read just means no final message; never retried for this turn.
                let output = try? await client.read(terminal: address, lines: lines)
                guard self.finalReads[address] == token else { return }
                self.finalReads[address] = nil
                guard let output, let message = TurnFinalMessage.extract(from: output.text, tool: tool) else { return }
                self.finalMessages[address] = message
                self.rebuild()
            }
        }
    }

    /// `rebuilding: false` from inside `rebuild` itself (the agent is already gone from the list).
    private func dropFinalMessage(_ address: String, rebuilding: Bool = true) {
        finalReads[address] = nil
        finalTimers.removeValue(forKey: address)?.cancel()
        if finalMessages.removeValue(forKey: address) != nil, rebuilding { rebuild() }
    }

    // MARK: Today timeline

    /// The user's Clear.
    public func clearTimeline() {
        timeline.clear()
        midnightTimer?.cancel()
        midnightTimer = nil
    }

    private func trackTimeline(_ agent: Agent, from previous: AgentState?) {
        guard timelineEnabled else { return }
        switch agent.state {
        case .done, .idle, .exited:
            guard Self.turnEnded(agent.state, from: previous) else { return }
            recordTimeline(agent)
        case .error:
            recordTimeline(agent)
        case .working, .starting, .needsYou:
            if timeline.isOpen(agent.address) { timeline.close(agent.address) }
        case .unknown:
            break
        }
    }

    /// The day may have changed without the midnight timer (it doesn't count while the Mac sleeps), or the
    /// time zone did: drop what is no longer today. Called on wake and day / time zone changes.
    public func rollOverTimeline() {
        let start = calendar.startOfDay(for: scheduler.now)
        guard timeline.entries.contains(where: { $0.at < start }) else { return }
        timeline.drop(before: start)
    }

    private func recordTimeline(_ agent: Agent) {
        let now = scheduler.now
        timeline.drop(before: calendar.startOfDay(for: now))
        timeline.record(agent, at: now, seen: panel?.address == agent.address)
        scheduleMidnight()
    }

    private func scheduleMidnight() {
        let now = scheduler.now
        guard midnightTimer == nil,
              let next = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime)
        else { return }
        midnightTimer = scheduler.schedule(after: next.timeIntervalSince(now)) { [weak self] in
            guard let self else { return }
            self.midnightTimer = nil
            self.timeline.drop(before: self.calendar.startOfDay(for: self.scheduler.now))
        }
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
            queueNotices.removeAll()
            disarmAdvance()
        }
        if stateOfStored(address) == .done {
            // Local only: never written back to Herdr.
            acknowledged.insert(address)
        }
        if timeline.hasUnseen(address) { timeline.markSeen(address) }
        rebuild()
        refreshPanelOutput()
    }

    // MARK: Changes view

    /// Shows the open panel's agent's last turn changes in place of its output, listing the files on demand.
    public func showChanges() {
        guard let inspector = changeInspector, var current = panel, current.changes == nil,
              let summary = agent(current.address)?.changeSummary, !summary.isEmpty else { return }
        current.changes = PanelChanges(summary: summary)
        panel = current
        let address = current.address
        Task {
            let files = await inspector.files(for: summary)
            guard self.panel?.address == address, self.panel?.changes?.summary == summary else { return }
            self.panel?.changes?.files = files.map { .loaded($0) } ?? .failed
        }
    }

    public func hideChanges() {
        panel?.changes = nil
    }

    /// Expands a file (loading its diff the first time) or collapses it.
    public func toggleDiff(_ file: ChangedFile) {
        guard let inspector = changeInspector, let changes = panel?.changes, file.hasDiff else { return }
        if changes.expanded.contains(file.path) {
            panel?.changes?.expanded.remove(file.path)
            return
        }
        panel?.changes?.expanded.insert(file.path)
        if let existing = changes.diffs[file.path], existing != .failed { return }
        panel?.changes?.diffs[file.path] = .loading
        let address = panel?.address
        let summary = changes.summary
        Task {
            let diff = await inspector.diff(of: file, for: summary)
            guard self.panel?.address == address, self.panel?.changes?.summary == summary else { return }
            self.panel?.changes?.diffs[file.path] = diff.map { .loaded($0) } ?? .failed
        }
    }

    /// A new turn (or a recomputed summary) makes the shown changes stale.
    private func dropStaleChanges() {
        guard let current = panel, let changes = current.changes,
              agent(current.address)?.changeSummary != changes.summary else { return }
        panel?.changes = nil
    }

    public func closePanel() {
        outputRequest += 1
        let wasOpen = panel != nil
        panel = nil
        queueNotices.removeAll()
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

    /// Returns false when nothing was sent (wrong mode, already in flight, empty text).
    @discardableResult
    public func send(_ text: String, to address: String, completion: (@MainActor (SendState) -> Void)? = nil) -> Bool {
        guard let agent = agent(address) else { return false }
        let force: Bool
        switch agent.replyMode {
        case .text(let f): force = f
        case .textAndKeys: force = true
        default: return false
        }
        if sendStates[address]?.isInFlight == true { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        sendStates[address] = .waiting
        armAdvance(address)
        Task { [client = client(for: address)] in
            let state: SendState
            do {
                let output = try await client.send(terminal: address, text: text, force: force)
                state = switch output.started {
                case .some(true): .started
                case .some(false): .delivered
                case .none: .unconfirmed
                }
            } catch let error as HerdrError {
                state = .failed(error)
                self.disarmAdvance(address)
            } catch {
                state = .failed(.unavailable(error.localizedDescription))
                self.disarmAdvance(address)
            }
            self.sendStates[address] = state
            completion?(state)
        }
        return true
    }

    /// Reply to a Needs-you agent only if it still waits in the episode the user saw (e.g. from a notification).
    /// `completion` gets nil when nothing was sent because it moved on.
    public func reply(_ text: String, to address: String, episode: Date?, completion: @escaping @MainActor (SendState?) -> Void) {
        guard let agent = agent(address), agent.state.isNeedsYou, let episode, agent.waitingSince == episode else {
            completion(nil)
            return
        }
        if !send(text, to: address, completion: { completion($0) }) {
            completion(.failed(HerdrError(kind: "not_sent", message: "Another message is still being sent, or the reply was empty.")))
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

    /// Creates worktrees for "New worktree" launches; nil = unavailable.
    public var worktreeCreator: (any WorktreeCreating)?
    /// The worktree the last launch created, kept on disk even if the launch then failed.
    public private(set) var launchWorktree: String?
    /// A launch created a worktree (its path), e.g. for the recent-folders list.
    public var onWorktreeCreated: ((_ path: String) -> Void)?

    public var isLaunchBusy: Bool {
        switch launchState {
        case .starting, .creatingWorktree: true
        default: false
        }
    }

    /// With a plan, first creates the worktree, then launches in it (`request.folder` is replaced).
    public func launch(_ request: LaunchRequest, worktree: WorktreePlan? = nil) {
        if isLaunchBusy { return }
        guard herdrAppRunning else {
            launchState = .failed(HerdrError(kind: "app_not_running", message: "Herdr app isn't running", hint: "Open Herdr, then try again."))
            return
        }
        launchWorktree = nil
        guard let worktree else { return startLaunch(request) }
        guard let creator = worktreeCreator else {
            launchState = .failed(HerdrError(kind: "worktree_failed", message: "Worktrees aren't available"))
            return
        }
        launchState = .creatingWorktree
        Task {
            switch await creator.create(worktree) {
            case .failure(let error):
                self.launchState = .failed(HerdrError(kind: "worktree_failed", message: error.message))
            case .success:
                self.launchWorktree = worktree.path
                self.onWorktreeCreated?(worktree.launchFolder)
                var request = request
                request.folder = worktree.launchFolder
                self.startLaunch(request)
            }
        }
    }

    private func startLaunch(_ request: LaunchRequest) {
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
        if isLaunchBusy { return }
        launchState = .idle
        launchWorktree = nil
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
    /// The turn's changes view, while it's shown in this panel. Code lives only here: gone with the panel.
    public var changes: PanelChanges?

    public init(address: String) {
        self.address = address
    }
}

/// The open panel's view of a finished turn's changes.
public struct PanelChanges: Equatable, Sendable {
    public enum Load<Value: Equatable & Sendable>: Equatable, Sendable {
        case loading
        case loaded(Value)
        case failed
    }

    /// The summary being inspected; a new turn replaces it and closes the view.
    public var summary: ChangeSummary
    public var files: Load<[ChangedFile]> = .loading
    /// Diffs of the files expanded so far, by path.
    public var diffs: [String: Load<FileDiff>] = [:]
    public var expanded: Set<String> = []

    public init(summary: ChangeSummary) {
        self.summary = summary
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
    /// "New worktree": `git worktree add` is running; the launch follows.
    case creatingWorktree
    /// Command sent (terminal nil) or terminal created and waiting for it to start working.
    case starting(terminal: String?)
    case launched(terminal: String)
    case unconfirmed(terminal: String?)
    case failed(HerdrError)

    public var label: String {
        switch self {
        case .idle: ""
        case .creatingWorktree: "Creating worktree…"
        case .starting: "Starting…"
        case .launched: "Launched"
        case .unconfirmed: "Created · task start unconfirmed"
        case .failed: "Launch failed"
        }
    }
}
