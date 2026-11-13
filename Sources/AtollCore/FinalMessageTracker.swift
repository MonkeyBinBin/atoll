import Foundation

/// The last thing an agent said in a finished turn. A turn that ends without a `statusMessage` gets one
/// screen read once the screen settles; the next turn, or the agent going away, drops the result, and a read
/// that lands after that is thrown away. Done / Idle → Exited is the same turn settling.
@MainActor
final class FinalMessageTracker {
    private struct Entry {
        var message: TurnFinalMessage?
        /// Token of the read in flight; cleared to throw its result away.
        var read: Int?
        var timer: ScheduledAction?
    }

    /// Reads an agent's screen; nil when the read failed (never retried for the turn).
    var read: @MainActor (_ address: String, _ lines: Int) async -> String? = { _, _ in nil }
    /// The agent's state now: a turn that moved on while its screen settled has nothing to read.
    var currentState: @MainActor (_ address: String) -> AgentState? = { _ in nil }
    /// A message appeared or went away.
    var onChange: @MainActor () -> Void = {}

    private let scheduler: IslandScheduler
    private let delay: TimeInterval
    private let lines: Int
    private var entries: [String: Entry] = [:]
    private var nextRead = 0

    init(scheduler: IslandScheduler, delay: TimeInterval, lines: Int) {
        self.scheduler = scheduler
        self.delay = delay
        self.lines = lines
    }

    var addresses: some Collection<String> { entries.keys }

    func message(for address: String) -> TurnFinalMessage? { entries[address]?.message }

    /// Follows a live transition.
    func track(_ agent: Agent, from previous: AgentState?) {
        let settling = agent.state == .exited && (previous == .done || previous == .idle)
        if agent.state.endsTurn(from: previous), !settling {
            drop(agent.address)
            guard agent.statusMessage == nil, agent.tool != .generic else { return }
            scheduleRead(agent.address, tool: agent.tool)
        } else if agent.state == .working || agent.state == .starting || agent.state.isNeedsYou {
            drop(agent.address)
        }
    }

    /// The agent is gone: forget it without announcing a change.
    func remove(_ address: String) {
        entries.removeValue(forKey: address)?.timer?.cancel()
    }

    private func drop(_ address: String) {
        guard let entry = entries.removeValue(forKey: address) else { return }
        entry.timer?.cancel()
        if entry.message != nil { onChange() }
    }

    private func scheduleRead(_ address: String, tool: AgentTool) {
        nextRead += 1
        let token = nextRead
        let timer = scheduler.schedule(after: delay) { [weak self] in
            self?.readScreen(address, tool: tool, token: token)
        }
        entries[address] = Entry(read: token, timer: timer)
    }

    private func readScreen(_ address: String, tool: AgentTool, token: Int) {
        guard entries[address]?.read == token else { return }
        entries[address]?.timer = nil
        // Moved on (Error, offline…) while the screen settled: nothing to read for this turn.
        guard let state = currentState(address), [.done, .idle, .exited].contains(state) else {
            entries[address] = nil
            return
        }
        Task {
            let text = await self.read(address, self.lines)
            guard self.entries[address]?.read == token else { return }
            guard let text, let message = TurnFinalMessage.extract(from: text, tool: tool) else {
                self.entries[address] = nil
                return
            }
            self.entries[address] = Entry(message: message)
            self.onChange()
        }
    }
}
