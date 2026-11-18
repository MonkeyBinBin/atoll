import Foundation
import Testing
@testable import AtollCore

/// Screen reads for the trackers: counts calls, and can hold them to land late.
@MainActor
final class ScreenReads {
    var text: String?
    var hold = false
    private(set) var calls: [String] = []
    private var held: [CheckedContinuation<Void, Never>] = []

    init(_ text: String?) { self.text = text }

    func read(_ address: String, _ lines: Int) async -> String? {
        calls.append(address)
        if hold { await withCheckedContinuation { held.append($0) } }
        return text
    }

    func release() {
        let waiting = held
        held = []
        waiting.forEach { $0.resume() }
    }
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func waiting(_ address: String = "a", _ kind: BlockedKind = .permission, since: Date = t0,
                     message: String? = nil, tool: AgentTool = .claudeCode) -> Agent {
    Agent(address: address, tool: tool, state: .needsYou(kind), statusMessage: message, waitingSince: since)
}

// MARK: - Waiting preview

@MainActor
@Suite("WaitingPreviewTracker")
struct WaitingPreviewTrackerTests {
    let scheduler = FakeScheduler()
    let reads = ScreenReads(WaitingScreens.claudePermission)
    let tracker: WaitingPreviewTracker

    init() {
        tracker = WaitingPreviewTracker(scheduler: scheduler, delay: 0.6, lines: 80)
        tracker.read = { [reads] in await reads.read($0, $1) }
    }

    @Test("one read per episode once the screen settles; the result belongs to that episode")
    func readsOnce() async {
        var resolved: [Date] = []
        var changed = 0
        tracker.onResolved = { _, episode in resolved.append(episode) }
        tracker.onChange = { changed += 1 }
        tracker.sync([waiting()])
        #expect(tracker.isReading("a"))
        #expect(reads.calls.isEmpty)
        scheduler.advance(by: 0.6)
        await settle()
        tracker.sync([waiting()])
        scheduler.advance(by: 10)
        await settle()
        #expect(reads.calls == ["a"])
        let found = tracker.result(for: "a", episode: t0)
        #expect(found?.preview != nil)
        #expect(found?.permissionChoices != nil)
        #expect(!tracker.isReading("a"))
        #expect(resolved == [t0])
        #expect(changed == 1)
    }

    @Test("a new episode drops the old result, and a read landing after it is thrown away")
    func newEpisode() async {
        var resolved: [Date] = []
        tracker.onResolved = { _, episode in resolved.append(episode) }
        reads.hold = true
        tracker.sync([waiting()])
        scheduler.advance(by: 0.6)
        await settle()
        let later = t0.addingTimeInterval(30)
        tracker.sync([waiting(since: later)])
        reads.release()
        await settle()
        #expect(tracker.result(for: "a", episode: t0) == nil)
        #expect(tracker.result(for: "a", episode: later) == .init())
        #expect(resolved.isEmpty)
        #expect(tracker.isReading("a"))
    }

    @Test("leaving Needs you drops the episode and its result")
    func leaving() async {
        tracker.sync([waiting()])
        scheduler.advance(by: 0.6)
        await settle()
        #expect(tracker.result(for: "a", episode: t0)?.preview != nil)
        tracker.sync([Agent(address: "a", tool: .claudeCode, state: .working)])
        #expect(tracker.result(for: "a", episode: t0) == nil)
        #expect(!tracker.isReading("a"))
    }

    @Test("with a status message only a known tool's dialog is read (permission keys, question options); the preview stays the message")
    func withMessage() async {
        tracker.sync([waiting("q", .question, message: "Pick a color"), waiting("g", message: "x", tool: .generic)])
        #expect(tracker.isReading("q"))
        #expect(!tracker.isReading("g"))
        tracker.sync([waiting(message: "Bash: touch hello.txt")])
        scheduler.advance(by: 0.6)
        await settle()
        #expect(reads.calls == ["a"])
        let found = tracker.result(for: "a", episode: t0)
        #expect(found?.preview == nil)
        #expect(found?.permissionChoices != nil)
    }

    @Test("a removed agent: its read never happens, and one in flight reports nothing")
    func removed() async {
        var heard = 0
        tracker.onResolved = { _, _ in heard += 1 }
        tracker.onChange = { heard += 1 }
        tracker.sync([waiting("a"), waiting("b")])
        tracker.remove("a")
        reads.hold = true
        scheduler.advance(by: 0.6)
        await settle()
        #expect(reads.calls == ["b"])
        tracker.remove("b")
        reads.release()
        await settle()
        #expect(heard == 0)
        #expect(tracker.addresses.isEmpty)
        #expect(!tracker.isReading("a"))
    }
}

// MARK: - Turn final message

@MainActor
@Suite("FinalMessageTracker")
struct FinalMessageTrackerTests {
    let scheduler = FakeScheduler()
    let reads = ScreenReads(FinalScreens.claudeShort)
    let tracker: FinalMessageTracker
    let states = StateBox()

    @MainActor
    final class StateBox { var value: AgentState? = .done }

    init() {
        tracker = FinalMessageTracker(scheduler: scheduler, delay: 0.6, lines: 80)
        tracker.read = { [reads] in await reads.read($0, $1) }
        tracker.currentState = { [states] _ in states.value }
    }

    private func agent(_ state: AgentState, message: String? = nil, tool: AgentTool = .claudeCode) -> Agent {
        Agent(address: "a", tool: tool, state: state, statusMessage: message)
    }

    @Test("a finished turn gets one read once the screen settles; the next turn drops the message")
    func finishedTurn() async {
        var changed = 0
        tracker.onChange = { changed += 1 }
        tracker.track(agent(.done), from: .working)
        #expect(reads.calls.isEmpty)
        scheduler.advance(by: 0.6)
        await settle()
        #expect(reads.calls == ["a"])
        #expect(tracker.message(for: "a") != nil)
        #expect(changed == 1)
        states.value = .exited
        tracker.track(agent(.exited), from: .done)
        scheduler.advance(by: 1)
        await settle()
        #expect(reads.calls == ["a"])
        #expect(tracker.message(for: "a") != nil)
        tracker.track(agent(.working), from: .exited)
        #expect(tracker.message(for: "a") == nil)
        #expect(changed == 2)
    }

    @Test("a read landing after the next turn started is thrown away")
    func lateRead() async {
        var changed = 0
        tracker.onChange = { changed += 1 }
        reads.hold = true
        tracker.track(agent(.done), from: .working)
        scheduler.advance(by: 0.6)
        await settle()
        tracker.track(agent(.working), from: .done)
        reads.release()
        await settle()
        #expect(tracker.message(for: "a") == nil)
        #expect(changed == 0)
        #expect(tracker.addresses.isEmpty)
    }

    @Test("nothing to read: a status message, a generic tool, or a turn that moved on while settling")
    func nothingToRead() async {
        tracker.track(agent(.done, message: "All set"), from: .working)
        tracker.track(Agent(address: "g", tool: .generic, state: .done), from: .working)
        states.value = .error
        tracker.track(Agent(address: "e", tool: .claudeCode, state: .done), from: .working)
        scheduler.advance(by: 1)
        await settle()
        #expect(reads.calls.isEmpty)
        #expect(tracker.addresses.isEmpty)
    }

    @Test("a removed agent: no read, and one in flight lands nothing")
    func removed() async {
        var changed = 0
        tracker.onChange = { changed += 1 }
        tracker.track(agent(.done), from: .working)
        tracker.remove("a")
        scheduler.advance(by: 1)
        await settle()
        #expect(reads.calls.isEmpty)
        reads.hold = true
        tracker.track(agent(.done), from: .working)
        scheduler.advance(by: 0.6)
        await settle()
        tracker.remove("a")
        reads.release()
        await settle()
        #expect(tracker.message(for: "a") == nil)
        #expect(changed == 0)
        #expect(tracker.addresses.isEmpty)
    }
}

// MARK: - Waiting reminders

@MainActor
@Suite("WaitingReminderTracker")
struct WaitingReminderTrackerTests {
    let scheduler = FakeScheduler()
    let tracker: WaitingReminderTracker
    let log = Log()

    @MainActor
    final class Log {
        var due: [String] = []
        var stillWaiting = true
    }

    init() {
        tracker = WaitingReminderTracker(scheduler: scheduler)
        tracker.delay = 300
        tracker.isStillWaiting = { [log] _, _ in log.stillWaiting }
        tracker.onDue = { [log] address, _ in log.due.append(address) }
    }

    private func sync(_ waiting: [String: Date], known: [String: Date]? = nil) {
        let known = known ?? waiting
        tracker.sync(waiting: waiting) { known[$0] }
    }

    @Test("once per episode, `delay` after it was first seen here")
    func oncePerEpisode() {
        sync(["a": t0])
        scheduler.advance(by: 299)
        #expect(log.due.isEmpty)
        scheduler.advance(by: 1)
        #expect(log.due == ["a"])
        sync(["a": t0])
        scheduler.advance(by: 600)
        #expect(log.due == ["a"])
    }

    @Test("leaving the episode cancels; offline keeps the mark; a new episode reminds again")
    func episodes() {
        sync(["a": t0])
        sync([:])
        scheduler.advance(by: 600)
        #expect(log.due.isEmpty)
        sync(["a": t0])
        scheduler.advance(by: 300)
        #expect(log.due == ["a"])
        // Offline: not in the visible list, still waiting in the same episode.
        sync([:], known: ["a": t0])
        sync(["a": t0])
        scheduler.advance(by: 600)
        #expect(log.due == ["a"])
        sync(["a": t0.addingTimeInterval(60)])
        scheduler.advance(by: 300)
        #expect(log.due == ["a", "a"])
    }

    @Test("an agent no longer waiting when the timer fires isn't reminded or marked")
    func notWaitingAnyMore() {
        log.stillWaiting = false
        sync(["a": t0])
        scheduler.advance(by: 300)
        #expect(log.due.isEmpty)
        log.stillWaiting = true
        sync(["a": t0])
        scheduler.advance(by: 300)
        #expect(log.due == ["a"])
    }

    @Test("changing the delay drops the pending timers; off stops them")
    func delayChange() {
        sync(["a": t0])
        scheduler.advance(by: 200)
        tracker.delay = 600
        sync(["a": t0])
        scheduler.advance(by: 599)
        #expect(log.due.isEmpty)
        tracker.delay = nil
        sync(["a": t0])
        scheduler.advance(by: 1000)
        #expect(log.due.isEmpty)
        #expect(tracker.addresses.isEmpty)
    }

    @Test("a removed agent is never reminded")
    func removed() {
        sync(["a": t0, "b": t0])
        tracker.remove("a")
        scheduler.advance(by: 300)
        #expect(log.due == ["b"])
        tracker.remove("b")
        #expect(tracker.addresses.isEmpty)
    }
}

// MARK: - Turn changes

/// Answers summaries only when released, in order, so a result can land after a newer turn.
final class HeldProbe: ChangeProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var held: [CheckedContinuation<Void, Never>] = []
    let toplevel = "/repo"

    func baseline(in directory: String) async -> TurnBaseline? {
        TurnBaseline(toplevel: toplevel, head: "h", dirty: false, untracked: [])
    }

    func summary(in directory: String, since baseline: TurnBaseline?) async -> ChangeSummary? {
        await withCheckedContinuation { continuation in
            lock.withLock { held.append(continuation) }
        }
        return ChangeSummary(insertions: 1, deletions: 0, files: 1, untracked: 0, baseline: .turnStart, toplevel: toplevel)
    }

    var pending: Int { lock.withLock { held.count } }

    func releaseFirst() {
        let next = lock.withLock { held.isEmpty ? nil : held.removeFirst() }
        next?.resume()
    }
}

@MainActor
@Suite("TurnChangeTracker")
struct TurnChangeTrackerTests {
    let tracker = TurnChangeTracker()

    private func agent(_ state: AgentState) -> Agent {
        Agent(address: "a", state: state, projectPath: "/repo/app")
    }

    @Test("Working → Done: the summary lands with whether another agent shares the tree")
    func fullTurn() async throws {
        let probe = FakeProbe()
        var changed = 0
        tracker.probe = probe
        tracker.onChange = { changed += 1 }
        tracker.sharesTree = { address, toplevel in address == "a" && toplevel == probe.toplevel }
        tracker.track(agent(.working), from: .idle)
        await settle()
        tracker.track(agent(.done), from: .working)
        await settle()
        let summary = try #require(tracker.summary(for: "a"))
        #expect(summary.sharedTree)
        #expect(summary.baseline == .turnStart)
        #expect(tracker.toplevel(for: "a") == probe.toplevel)
        #expect(changed == 1)
    }

    @Test("a summary landing after a newer turn started is thrown away")
    func lateSummary() async {
        let probe = HeldProbe()
        tracker.probe = probe
        tracker.track(agent(.working), from: .idle)
        tracker.track(agent(.done), from: .working)
        await settle()
        tracker.track(agent(.working), from: .done)
        await settle()
        probe.releaseFirst()
        await settle()
        #expect(tracker.summary(for: "a") == nil)
    }

    @Test("a summary for an agent removed meanwhile doesn't land on a new agent at the same address")
    func newAgentSameAddress() async {
        let probe = HeldProbe()
        tracker.probe = probe
        tracker.track(agent(.working), from: .idle)
        tracker.track(agent(.done), from: .working)
        await settle()
        tracker.remove("a")
        tracker.track(agent(.working), from: nil)
        tracker.track(agent(.done), from: .working)
        await settle()
        #expect(probe.pending == 2)
        probe.releaseFirst()
        await settle()
        #expect(tracker.summary(for: "a") == nil)
        probe.releaseFirst()
        await settle()
        #expect(tracker.summary(for: "a") != nil)
    }

    @Test("Error discards the turn; turning tracking off drops summaries")
    func errorAndOff() async {
        let probe = FakeProbe()
        tracker.probe = probe
        tracker.track(agent(.working), from: .idle)
        tracker.track(agent(.error), from: .working)
        tracker.track(agent(.idle), from: .error)
        await settle()
        #expect(probe.summaryCalls.isEmpty)
        tracker.track(agent(.working), from: .idle)
        tracker.track(agent(.done), from: .working)
        await settle()
        #expect(tracker.summary(for: "a") != nil)
        tracker.probe = nil
        #expect(tracker.summary(for: "a") == nil)
        tracker.remove("a")
        #expect(tracker.addresses.isEmpty)
    }
}

// MARK: - Spaces

@MainActor
@Suite("SpaceTracker")
struct SpaceTrackerTests {
    let client = FakeHerdrClient()
    let scheduler = FakeScheduler()
    let tracker: SpaceTracker
    let timing = AgentStore.Timing()
    let sp1 = HerdrSpace(id: "sp1", name: "atoll", terminals: ["t1"])

    init() {
        tracker = SpaceTracker(
            client: client,
            scheduler: scheduler,
            refreshInterval: timing.spaceRefreshInterval,
            launchTimeout: timing.launchSpacesTimeout
        )
    }

    private var renames: Int {
        client.commands.filter { if case .renameSpace = $0 { true } else { false } }.count
    }

    @Test("a refresh asked for while a read is in flight runs once after it")
    func coalesces() async {
        client.spacesResult = .success([sp1])
        tracker.appRunning = true
        tracker.refresh()
        tracker.refresh()
        await settle()
        #expect(client.spacesCalls == 2)
        scheduler.advance(by: timing.spaceRefreshInterval)
        await settle()
        #expect(client.spacesCalls == 3)
    }

    @Test("a refresh started while a read's result is handled owns the next timer: polling doesn't double")
    func noStackedTimers() async {
        // The store's rebuild refreshes again when a changed read leaves a terminal without a space.
        tracker.onChange = { [tracker] _ in tracker.refresh() }
        client.spacesResult = .success([sp1])
        tracker.appRunning = true
        await settle()
        #expect(client.spacesCalls == 2)
        for round in 1...3 {
            scheduler.advance(by: timing.spaceRefreshInterval)
            await settle()
            #expect(client.spacesCalls == 2 + round)
        }
    }

    @Test("only a change is reported; a failed read keeps the last spaces; quitting the app empties them")
    func changesOnly() async {
        var seen: [[HerdrSpace]] = []
        tracker.onChange = { seen.append($0) }
        client.spacesResult = .success([sp1])
        tracker.appRunning = true
        await settle()
        scheduler.advance(by: timing.spaceRefreshInterval)
        await settle()
        client.spacesResult = .failure(.unavailable("down"))
        scheduler.advance(by: timing.spaceRefreshInterval)
        await settle()
        #expect(seen == [[sp1]])
        tracker.appRunning = false
        #expect(seen == [[sp1], []])
        scheduler.advance(by: timing.spaceRefreshInterval * 3)
        await settle()
        #expect(client.spacesCalls == 3)
    }

    @Test("a read that lands after the app quit is dropped")
    func lateReadDropped() async {
        var seen: [[HerdrSpace]] = []
        var cached: [[HerdrSpace]] = []
        tracker.onChange = { seen.append($0) }
        tracker.onCached = { cached.append($0) }
        client.spacesResult = .success([sp1])
        tracker.appRunning = true
        tracker.appRunning = false
        await settle()
        #expect(client.spacesCalls == 1)
        #expect(seen.isEmpty)
        #expect(cached.isEmpty)
        #expect(tracker.cached.isEmpty)
    }

    @Test("new non-empty spaces replace the cache; an empty read doesn't")
    func cache() async {
        var cached: [[HerdrSpace]] = []
        tracker.onCached = { cached.append($0) }
        client.spacesResult = .success([sp1])
        tracker.appRunning = true
        await settle()
        client.spacesResult = .success([])
        scheduler.advance(by: timing.spaceRefreshInterval)
        await settle()
        #expect(cached == [[sp1]])
        #expect(tracker.cached == [sp1])
    }

    @Test("a failed rename is tried again on the next read; a done one drops its pending name")
    func renameRetry() async {
        var names: [[String: String]] = []
        tracker.onPendingNamesChange = { names.append($0) }
        tracker.snapshotArrived = { true }
        tracker.pendingNames = ["sp1": "named"]
        client.spacesResult = .success([sp1])
        client.renameResult = .failure(.unavailable("busy"))
        tracker.appRunning = true
        await settle()
        #expect(renames == 1)
        #expect(tracker.pendingNames == ["sp1": "named"])
        client.renameResult = .success(())
        scheduler.advance(by: timing.spaceRefreshInterval)
        await settle()
        #expect(renames == 2)
        #expect(tracker.pendingNames.isEmpty)
        #expect(names == [["sp1": "named"], [:]])
    }

    @Test("pending names wait for the snapshot; then one no live terminal is labelled for is dropped")
    func orphans() async {
        tracker.pendingNames = ["gone": "a", "kept": "b"]
        tracker.liveSpaceIDs = { ["kept"] }
        tracker.snapshotArrived = { false }
        tracker.appRunning = true
        await settle()
        #expect(tracker.pendingNames.count == 2)
        tracker.snapshotArrived = { true }
        scheduler.advance(by: timing.spaceRefreshInterval)
        await settle()
        #expect(tracker.pendingNames == ["kept": "b"])
        #expect(renames == 0)
    }

    @Test("launch spaces: offline without the app; with it, its answer, or the offline ones after the timeout")
    func launchSpaces() async {
        tracker.cached = [HerdrSpace(id: "sp1", name: "a")]
        #expect(await tracker.launchSpaces().map(\.id) == ["sp1"])
        #expect(client.spacesCalls == 0)

        client.spacesResult = .success([HerdrSpace(id: "live", name: "live")])
        tracker.appRunning = true
        await settle()
        #expect(await tracker.launchSpaces().map(\.id) == ["live"])

        tracker.cached = [HerdrSpace(id: "sp1", name: "a")]
        client.spacesHang = true
        let read = Task { await tracker.launchSpaces() }
        await settle()
        scheduler.advance(by: timing.launchSpacesTimeout)
        #expect(await read.value.map(\.id) == ["sp1"])
    }

    @Test("an unlisted terminal triggers one refresh while the app runs, again only after it is removed")
    func misses() async {
        #expect(!tracker.claimMiss("t1"))
        tracker.appRunning = true
        await settle()
        #expect(tracker.claimMiss("t1"))
        #expect(!tracker.claimMiss("t1"))
        tracker.remove("t1")
        #expect(tracker.addresses.isEmpty)
        #expect(tracker.claimMiss("t1"))
    }
}
