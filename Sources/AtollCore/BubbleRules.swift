import Foundation

/// A speech bubble to pop above (below, on screen) an agent's character in the collapsed island.
/// Carries only the state word (plus, once a turn finishes, its git change counts; for a shared working tree,
/// the other agents' "tool · project" names as in notifications — never paths or output):
/// it appears unprompted, possibly while screen sharing.
public struct AgentBubble: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Announces `state`.
        case state
        /// Another agent became active in the same git working tree.
        case sharedTree
        /// A message queued from the panel went out at the end of the turn.
        case queuedSent
    }

    public var address: String
    /// The state the bubble announces; it is dismissed once the agent leaves it.
    public var state: AgentState
    /// Dedupe key: one bubble per transition.
    public var key: String
    public var kind: Kind

    public init(address: String, state: AgentState, key: String, kind: Kind = .state) {
        self.address = address
        self.state = state
        self.key = key
        self.kind = kind
    }

    /// Needs you / Error pre-empt the rest.
    public var isUrgent: Bool { kind == .state && state.needsAttention }

    /// Still worth showing for this agent as it is now.
    public func stillApplies(to agent: Agent?) -> Bool {
        guard let agent else { return false }
        switch kind {
        case .state: return agent.state.label == state.label
        case .sharedTree: return !agent.sharedTreeWith.isEmpty
        case .queuedSent: return true
        }
    }
}

/// Decides which state transitions pop a bubble: whenever an agent stops or needs the user.
/// Unlike notifications, Done always bubbles: the bubble is quiet and only on the island.
public struct BubbleRules: Sendable {
    private var lastSent: [String: String] = [:]
    /// Turn of the last Idle bubble per agent: a source flapping Working ↔ Idle mid-turn bubbles once.
    private var idleTurn: [String: UInt64] = [:]

    public init() {}

    public mutating func bubble(for agent: Agent, from previous: AgentState?) -> AgentBubble? {
        let category: String
        switch agent.state {
        case .needsYou: category = "needs-you"
        case .error: category = "error"
        case .done: category = "done"
        case .exited: category = "exited"
        case .idle:
            // A turn that stopped without reporting Done (e.g. interrupted). Done → Idle is just settling.
            guard previous == .working || previous == .starting, idleTurn[agent.address] != agent.turn else { return nil }
            idleTurn[agent.address] = agent.turn
            category = "idle"
        case .working, .starting:
            // A new turn re-arms the next announcement.
            lastSent[agent.address] = nil
            return nil
        case .unknown:
            // Lost / offline: keep what was sent so the same state isn't re-announced after a reconnect.
            return nil
        }
        // First sighting: nothing changed from the user's point of view.
        guard let previous else { return nil }
        if previous.label == agent.state.label { return nil }
        let key = "\(category)#\(agent.turn)"
        if lastSent[agent.address] == key { return nil }
        lastSent[agent.address] = key
        return AgentBubble(address: agent.address, state: agent.state, key: key)
    }
}
