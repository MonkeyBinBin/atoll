import Foundation

/// One screen read per Needs-you episode, kept as a `WaitingDialog`: the preview when the source didn't say
/// why (`statusMessage`), and a permission dialog's answer keys or a question's options even when it did.
/// Leaving Needs you (or a new episode) drops it: the only screen text kept with the panel closed. The store
/// feeds it the agents on every rebuild and hands the result to the waiting ones.
@MainActor
final class WaitingPreviewTracker {
    private struct Episode {
        var since: Date
        /// The agent as last seen in this episode: its tool, kind and message decide what the read keeps.
        var agent: Agent
        var result = WaitingDialog()
        var resolved = false
        var timer: ScheduledAction?
    }

    /// Reads an agent's screen; nil when the read failed (never retried within the episode).
    var read: @MainActor (_ address: String, _ lines: Int) async -> String? = { _, _ in nil }
    /// A read landed, before `onResolved`, so the agent carries the result by the time anyone hears of it.
    var onChange: @MainActor () -> Void = {}
    /// The episode's read is over, found or not.
    var onResolved: @MainActor (_ address: String, _ episode: Date) -> Void = { _, _ in }

    private let scheduler: IslandScheduler
    private let delay: TimeInterval
    private let lines: Int
    private var episodes: [String: Episode] = [:]

    /// `delay` lets the screen settle after entering Needs you; `lines` is how much of it one read takes.
    init(scheduler: IslandScheduler, delay: TimeInterval, lines: Int) {
        self.scheduler = scheduler
        self.delay = delay
        self.lines = lines
    }

    var addresses: some Collection<String> { episodes.keys }

    /// Drops episodes that ended and schedules the read of new ones that need it.
    func sync(_ agents: [Agent]) {
        var waiting: [String: Agent] = [:]
        for agent in agents where agent.state.isNeedsYou && agent.waitingSince != nil {
            waiting[agent.address] = agent
        }
        for (address, episode) in episodes {
            if let agent = waiting[address], agent.waitingSince == episode.since {
                episodes[address]?.agent = agent
            } else {
                remove(address)
            }
        }
        for agent in waiting.values where episodes[agent.address] == nil && Self.needsScreenRead(agent) {
            guard let since = agent.waitingSince else { continue }
            let address = agent.address
            let timer = scheduler.schedule(after: delay) { [weak self] in
                self?.readScreen(address, episode: since)
            }
            episodes[address] = Episode(since: since, agent: agent, timer: timer)
        }
    }

    /// What the read found for this episode (empty while reading or when nothing was recognized).
    func result(for address: String, episode: Date) -> WaitingDialog? {
        guard let current = episodes[address], current.since == episode else { return nil }
        return current.result
    }

    /// The current episode's read hasn't finished yet (so its preview and keys may still come).
    func isReading(_ address: String) -> Bool {
        episodes[address].map { !$0.resolved } ?? false
    }

    func remove(_ address: String) {
        episodes.removeValue(forKey: address)?.timer?.cancel()
    }

    /// Without a source message the screen gives the preview; with one, it's still read for what can be
    /// answered from the list: a permission dialog's keys or a question's options.
    private static func needsScreenRead(_ agent: Agent) -> Bool {
        if agent.statusMessage == nil { return true }
        guard agent.tool != .generic, let kind = agent.state.blockedKind else { return false }
        return kind == .permission || kind == .question || kind == .unspecified
    }

    private func readScreen(_ address: String, episode since: Date) {
        guard let episode = episodes[address], episode.since == since else { return }
        episodes[address]?.timer = nil
        guard let kind = episode.agent.state.blockedKind else {
            resolve(address, episode: since)
            return
        }
        let tool = episode.agent.tool
        let keepPreview = episode.agent.statusMessage == nil
        Task {
            let text = await self.read(address, self.lines)
            guard self.episodes[address]?.since == since else { return }
            if let text, let preview = WaitingPreview.extract(from: text, tool: tool, kind: kind) {
                if keepPreview { self.episodes[address]?.result.preview = preview }
                self.episodes[address]?.result.permissionChoices = PermissionChoices.extract(from: text, tool: tool, kind: kind)
                self.episodes[address]?.result.questionChoices = QuestionChoices.extract(from: text, tool: tool, kind: kind)
            }
            self.onChange()
            self.resolve(address, episode: since)
        }
    }

    private func resolve(_ address: String, episode since: Date) {
        guard episodes[address]?.since == since else { return }
        episodes[address]?.resolved = true
        onResolved(address, since)
    }
}
