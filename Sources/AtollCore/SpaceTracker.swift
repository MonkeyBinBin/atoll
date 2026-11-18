import Foundation

/// Herdr GUI spaces (tickets 42, 45): re-reads them while the Herdr app runs, keeps the last ones across its
/// quits, names the spaces launches without the app made, and answers the launch form. Holds no per-agent state
/// except the herdr-core terminals a refresh already ran for while they had no space.
@MainActor
final class SpaceTracker {
    /// The app's spaces changed (emptied when it quits). The store publishes them and rebuilds.
    var onChange: @MainActor ([HerdrSpace]) -> Void = { _ in }
    /// A read brought new non-empty spaces; they replaced `cached`.
    var onCached: @MainActor ([HerdrSpace]) -> Void = { _ in }
    /// `pendingNames` changed.
    var onPendingNamesChange: @MainActor ([String: String]) -> Void = { _ in }
    /// The primary source's terminals, in the store's order (for `offlineSpaces`).
    var terminals: @MainActor () -> [TerminalInfo] = { [] }
    /// The space ids the primary source's live terminals are labelled for (read on every refresh, so unsorted).
    var liveSpaceIDs: @MainActor () -> Set<String> = { [] }
    /// Whether the primary source's snapshot arrived: until then every pending name would look orphaned.
    var snapshotArrived: @MainActor () -> Bool = { false }

    /// The last spaces read from the Herdr app, kept across its quits (and app restarts, via `onCached`).
    var cached: [HerdrSpace] = []
    /// Names for spaces made by launches without the app (space id → name), applied once the app shows them.
    var pendingNames: [String: String] = [:] {
        didSet { if pendingNames != oldValue { onPendingNamesChange(pendingNames) } }
    }

    /// Whether the Herdr app runs: on, spaces are read now and then every `refreshInterval`; off, a read in
    /// flight is dropped and the spaces empty.
    var appRunning = false {
        didSet {
            guard appRunning != oldValue else { return }
            if appRunning {
                refresh()
            } else {
                generation += 1
                refreshing = false
                refreshAgain = false
                timer?.cancel()
                timer = nil
                if !spaces.isEmpty {
                    spaces = []
                    onChange([])
                }
            }
        }
    }

    private let client: HerdrClient
    private let scheduler: IslandScheduler
    private let refreshInterval: TimeInterval
    private let launchTimeout: TimeInterval

    private var spaces: [HerdrSpace] = []
    private var renaming: Set<String> = []
    private var timer: ScheduledAction?
    private var refreshing = false
    private var refreshAgain = false
    private var generation = 0
    /// herdr-core terminals a refresh already ran for while they had no space (each triggers one).
    private var misses: Set<String> = []

    init(client: HerdrClient, scheduler: IslandScheduler, refreshInterval: TimeInterval, launchTimeout: TimeInterval) {
        self.client = client
        self.scheduler = scheduler
        self.refreshInterval = refreshInterval
        self.launchTimeout = launchTimeout
    }

    var addresses: some Collection<String> { misses }

    /// Re-reads the app's spaces now (then every `refreshInterval`). A failed read keeps the last ones; a call
    /// while a read is in flight runs one more read after it.
    func refresh() {
        guard appRunning else { return }
        guard !refreshing else {
            refreshAgain = true
            return
        }
        refreshing = true
        timer?.cancel()
        timer = nil
        let generation = generation
        // Weak like the timer it schedules: neither the read nor the next refresh keeps the tracker alive.
        Task { [weak self, client] in
            let result = try? await client.spaces()
            guard let self, generation == self.generation else { return }
            self.refreshing = false
            if let result, result != self.spaces {
                self.spaces = result
                self.onChange(result)
            }
            if let result, !result.isEmpty, result != self.cached {
                self.cached = result
                self.onCached(result)
            }
            if let result { self.applyPendingNames(result) }
            if self.refreshAgain {
                self.refreshAgain = false
                self.refresh()
            } else if !self.refreshing {
                // A refresh started by the callbacks above (the store's rebuild, a rename) schedules the next
                // timer itself; scheduling one here too would run two polling chains.
                self.timer = self.scheduler.schedule(after: self.refreshInterval) { [weak self] in
                    self?.timer = nil
                    self?.refresh()
                }
            }
        }
    }

    /// A herdr-core terminal the spaces don't list: true the first time while the app runs (the caller then
    /// refreshes), false after that until it is removed.
    func claimMiss(_ address: String) -> Bool {
        appRunning && misses.insert(address).inserted
    }

    func remove(_ address: String) {
        misses.remove(address)
    }

    /// Names the spaces launches without the app made, once the app shows them. A failed rename is tried again
    /// on the next read. A name whose space the app doesn't show and no live terminal is labelled for (its agent
    /// ended before the app opened) is dropped: that space will never appear.
    private func applyPendingNames(_ shown: [HerdrSpace]) {
        let labelled = liveSpaceIDs()
        let shownIDs = Set(shown.map(\.id))
        if snapshotArrived() {
            for id in pendingNames.keys where !shownIDs.contains(id) && !labelled.contains(id) {
                pendingNames[id] = nil
            }
        }
        for space in shown {
            guard let name = pendingNames[space.id], !renaming.contains(space.id) else { continue }
            renaming.insert(space.id)
            Task { [weak self, client] in
                let renamed = (try? await client.renameSpace(id: space.id, name: name)) != nil
                guard let self else { return }
                self.renaming.remove(space.id)
                guard renamed else { return }
                if self.pendingNames[space.id] == name { self.pendingNames[space.id] = nil }
                self.refresh()
            }
        }
    }

    /// The spaces a launch can pick: the app's, read now; without the app, `offlineSpaces`. A read that fails or
    /// takes longer than `launchTimeout` gets `offlineSpaces` too: the launch form waits on this.
    func launchSpaces() async -> [HerdrSpace] {
        guard appRunning else { return offlineSpaces }
        let client = client
        return await withCheckedContinuation { continuation in
            let once = Once(continuation)
            let read = Task { @MainActor [weak self] in
                let shown = try? await client.spaces()
                once.resume(shown ?? self?.offlineSpaces ?? [])
            }
            let timer = scheduler.schedule(after: launchTimeout) { [weak self] in
                read.cancel()
                once.resume(self?.offlineSpaces ?? [])
            }
            once.onResume = { timer.cancel() }
        }
    }

    /// The cached spaces as herdr-core's labels have them now (`HerdrLabels.spaces`).
    var offlineSpaces: [HerdrSpace] {
        HerdrLabels.spaces(cached: cached, terminals: terminals(), pendingNames: pendingNames)
    }

    /// Resumes a continuation the first time only (a read racing its timeout).
    @MainActor
    private final class Once {
        private var continuation: CheckedContinuation<[HerdrSpace], Never>?
        var onResume: () -> Void = {}

        init(_ continuation: CheckedContinuation<[HerdrSpace], Never>) {
            self.continuation = continuation
        }

        func resume(_ value: [HerdrSpace]) {
            guard let continuation else { return }
            self.continuation = nil
            onResume()
            continuation.resume(returning: value)
        }
    }
}
