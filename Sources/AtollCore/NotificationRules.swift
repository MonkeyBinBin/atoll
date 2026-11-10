import Foundation

public struct NotificationSettings: Equatable, Sendable {
    public var enabled: Bool
    /// Agents (terminal addresses) whose Done also notifies.
    public var doneAgents: Set<String>
    /// Project paths whose agents' Done also notifies.
    public var doneProjects: Set<String>

    public init(enabled: Bool = true, doneAgents: Set<String> = [], doneProjects: Set<String> = []) {
        self.enabled = enabled
        self.doneAgents = doneAgents
        self.doneProjects = doneProjects
    }
}

/// A macOS notification to post. Carries only "tool · project" and a state word —
/// never terminal output or task content.
public struct AgentNotification: Equatable, Sendable {
    public var address: String
    public var title: String
    public var body: String
    /// Dedupe key: one notification per transition.
    public var key: String
}

/// Decides which state transitions notify, and remembers what was already sent.
public struct NotificationRules: Sendable {
    private var lastSent: [String: String] = [:]

    public init() {}

    public mutating func notification(for agent: Agent, from previous: AgentState?, settings: NotificationSettings) -> AgentNotification? {
        let category: String
        switch agent.state {
        case .needsYou: category = "needs-you"
        case .error: category = "error"
        case .done:
            guard settings.doneAgents.contains(agent.address) || settings.doneProjects.contains(agent.projectPath) else {
                lastSent[agent.address] = nil
                return nil
            }
            category = "done"
        default:
            // Leaving an attention state re-arms the next one.
            lastSent[agent.address] = nil
            return nil
        }
        guard settings.enabled else { return nil }
        if let previous, previous.label == agent.state.label { return nil }
        let key = "\(category)#\(agent.turn)"
        if lastSent[agent.address] == key { return nil }
        lastSent[agent.address] = key
        return AgentNotification(address: agent.address, title: agent.displayName, body: agent.state.label, key: key)
    }
}
