import Foundation

/// What each agent's last turn changed in git. A turn starts on Working / Starting (Needs you and Unknown stay
/// inside it), capturing a baseline; it finishes on Done, Exited, or Idle that ends it, computing the summary.
/// Error closes it without a summary (Error is its own announcement). Every start and finish takes a new
/// generation, so a late git result never lands on a newer turn.
@MainActor
final class TurnChangeTracker {
    private struct Entry {
        /// The turn in progress, its baseline still being captured.
        var openTurn: Task<TurnBaseline?, Never>?
        var summary: ChangeSummary?
        /// Working-tree top level last seen (from baselines and summaries).
        var toplevel: String?
        var generation: Int?
    }

    /// nil turns tracking off: turns in progress and summaries are dropped (top levels are kept).
    var probe: (any ChangeProbing)? {
        didSet {
            guard probe == nil, oldValue != nil else { return }
            for address in entries.keys {
                entries[address]?.openTurn = nil
                entries[address]?.summary = nil
                entries[address]?.generation = nil
            }
        }
    }
    /// Another agent still around is in this top level (so the diff can't be pinned on this one).
    var sharesTree: @MainActor (_ address: String, _ toplevel: String) -> Bool = { _, _ in false }
    /// A summary appeared or went away.
    var onChange: @MainActor () -> Void = {}

    private var entries: [String: Entry] = [:]
    private var nextGeneration = 0

    init() {}

    var addresses: some Collection<String> { entries.keys }

    func summary(for address: String) -> ChangeSummary? { entries[address]?.summary }

    func toplevel(for address: String) -> String? { entries[address]?.toplevel }

    /// Follows a live transition.
    func track(_ agent: Agent, from previous: AgentState?) {
        guard let probe else { return }
        let address = agent.address
        let directory = agent.projectPath
        let isOpen = entries[address]?.openTurn != nil
        switch agent.state {
        case .working, .starting:
            guard !isOpen else { return }
            let generation = bumpGeneration(address)
            let hadSummary = entries[address]?.summary != nil
            entries[address]?.summary = nil
            let baseline = Task { await probe.baseline(in: directory) }
            entries[address]?.openTurn = baseline
            Task {
                guard let toplevel = await baseline.value?.toplevel,
                      self.entries[address]?.generation == generation else { return }
                self.entries[address]?.toplevel = toplevel
            }
            if hadSummary { onChange() }
        case .done, .exited, .idle:
            let wasRunning = previous == .working || previous == .starting
            // Done → Idle / Exited is the same turn settling: keep its summary.
            guard isOpen || (agent.state == .done && previous != nil) || wasRunning else { return }
            let baseline = entries[address]?.openTurn
            entries[address]?.openTurn = nil
            let generation = bumpGeneration(address)
            Task {
                let base = await baseline?.value
                let summary = await probe.summary(in: directory, since: base)
                self.finish(address, generation: generation, summary: summary)
            }
        case .error:
            discardOpenTurn(address)
        case .needsYou, .unknown:
            break
        }
    }

    /// Drops a turn's git baseline without a summary, and any summary still on its way.
    func discardOpenTurn(_ address: String) {
        guard entries[address] != nil else { return }
        entries[address]?.openTurn?.cancel()
        entries[address]?.openTurn = nil
        bumpGeneration(address)
    }

    func remove(_ address: String) {
        entries.removeValue(forKey: address)?.openTurn?.cancel()
    }

    @discardableResult
    private func bumpGeneration(_ address: String) -> Int {
        // Tracker-wide, so a late result from an earlier agent at the same address can't match.
        nextGeneration += 1
        entries[address, default: Entry()].generation = nextGeneration
        return nextGeneration
    }

    private func finish(_ address: String, generation: Int, summary: ChangeSummary?) {
        guard probe != nil, entries[address]?.generation == generation else { return }
        guard var summary else {
            entries[address]?.summary = nil
            onChange()
            return
        }
        entries[address]?.toplevel = summary.toplevel
        summary.sharedTree = sharesTree(address, summary.toplevel)
        entries[address]?.summary = summary
        onChange()
    }
}
