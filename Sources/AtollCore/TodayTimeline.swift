import Foundation

/// One finished turn on the Today timeline.
public struct TimelineEntry: Identifiable, Equatable, Sendable {
    public let id: Int
    public let address: String
    public let at: Date
    /// "Codex · project-x", as named everywhere else; kept so the entry outlives its agent.
    public let displayName: String
    public let projectName: String
    /// How the turn ended: Done, Idle, Exited or Error.
    public var state: AgentState
    /// The agent's last words for the turn (at most 2 lines), filled in once known.
    public var lastWords: String?
    /// The turn's git change counts ("+120 −30 · 3 files"), filled in once git answers.
    public var changes: String?
    /// The user hasn't opened this agent's panel since the turn ended.
    public var unseen = true
    /// The agent exited or left the list: the entry stays, but opens nothing (even if the address comes back).
    public var gone = false
    /// The source's turn counter when the turn ended (it counts up right after), to tell the next turn apart.
    let turn: UInt64
}

/// Today's finished turns, oldest first. In memory only: dropped when Atoll quits, the day changes,
/// or the user clears it.
public struct TodayTimeline: Equatable, Sendable {
    public static let limit = 200

    public private(set) var entries: [TimelineEntry] = []
    private var nextID = 0
    /// Per agent, the entry of the turn that just ended, until its next turn starts: later details land in
    /// it, and settling (Done → Idle → Exited) doesn't add another.
    private var open: [String: Int] = [:]

    public init() {}

    public var unseenCount: Int { entries.filter(\.unseen).count }

    func isOpen(_ address: String) -> Bool { open[address] != nil }

    func hasUnseen(_ address: String) -> Bool { entries.contains { $0.address == address && $0.unseen } }

    /// A turn ended (Done, Exited, Idle that stopped a turn, or Error). `seen` when its panel is open.
    mutating func record(_ agent: Agent, at date: Date, seen: Bool = false) {
        if agent.state == .error {
            // Its own entry with only the source's message: the screen read and git belong to a Done
            // before it, not to the error.
            append(agent, at: date, seen: seen)
            entries[entries.count - 1].lastWords = agent.statusMessage.map(Self.cut)
            trim()
            return
        }
        if let index = openIndex(agent.address) {
            // Still the same turn (e.g. Done → Exited): nothing new.
            guard entries[index].turn != agent.turn else { return }
        }
        append(agent, at: date, seen: seen)
        open[agent.address] = nextID
        fillEntry(entries.count - 1, from: agent)
        trim()
    }

    /// Details that arrive after the turn ended (the screen read, git) fill the open entries, only while
    /// the agent still sits in that finished turn; an agent gone from the list closes its entry.
    mutating func fill(_ agents: [Agent]) {
        for address in open.keys {
            guard let index = openIndex(address), let agent = agents.first(where: { $0.address == address }) else {
                open[address] = nil
                continue
            }
            // Already in the next turn (its counter moved past this turn's own bump): not this entry's.
            guard [.done, .idle, .exited].contains(agent.state), agent.turn <= entries[index].turn + 1 else { continue }
            fillEntry(index, from: agent)
        }
    }

    /// Entries whose agent ended (exited, or its source cleared the status) or left the list stop being
    /// reachable, for good.
    mutating func markGone(_ agents: [Agent], ended: Set<String>) {
        for index in entries.indices where !entries[index].gone {
            let address = entries[index].address
            if ended.contains(address) || !agents.contains(where: { $0.address == address }) { entries[index].gone = true }
        }
    }

    /// The agent's next turn started (or it needs the user mid-turn): its last entry is complete.
    mutating func close(_ address: String) {
        open[address] = nil
    }

    /// The agent's panel opened: everything it finished so far has been seen.
    mutating func markSeen(_ address: String) {
        for index in entries.indices where entries[index].address == address && entries[index].unseen {
            entries[index].unseen = false
        }
    }

    /// A new day: yesterday's entries go.
    mutating func drop(before start: Date) {
        entries.removeAll { $0.at < start }
        open = open.filter { _, id in entries.contains { $0.id == id } }
    }

    mutating func clear() {
        entries.removeAll()
        open.removeAll()
    }

    // MARK: Helpers

    private func openIndex(_ address: String) -> Int? {
        open[address].flatMap { id in entries.firstIndex { $0.id == id } }
    }

    private mutating func append(_ agent: Agent, at date: Date, seen: Bool) {
        nextID += 1
        entries.append(TimelineEntry(
            id: nextID, address: agent.address, at: date, displayName: agent.displayName,
            projectName: agent.projectName, state: agent.state, unseen: !seen, turn: agent.turn
        ))
    }

    private mutating func trim() {
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
        open = open.filter { _, id in entries.contains { $0.id == id } }
    }

    private mutating func fillEntry(_ index: Int, from agent: Agent) {
        if entries[index].lastWords == nil, let words = agent.lastWords {
            entries[index].lastWords = Self.cut(words)
        }
        if entries[index].changes == nil, let summary = agent.changeSummary {
            entries[index].changes = summary.text
        }
    }

    /// Like the final message (ticket 35): at most 2 lines of 200 characters.
    private static func cut(_ text: String) -> String {
        TurnFinalMessage(lines: text.split(separator: "\n").map(String.init)).text
    }
}
