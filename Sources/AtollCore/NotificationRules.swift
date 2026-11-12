import Foundation

public struct NotificationSettings: Equatable, Sendable {
    public var enabled: Bool
    /// Agents (terminal addresses) whose Done also notifies.
    public var doneAgents: Set<String>
    /// Project paths whose agents' Done also notifies.
    public var doneProjects: Set<String>
    /// Put the waiting reason ("Bash: rm -rf dist") in Needs-you notifications. Off by default; without it a
    /// notification never offers Allow, since approving a command you can't see is approving blind.
    public var showWaitingReason: Bool

    public init(enabled: Bool = true, doneAgents: Set<String> = [], doneProjects: Set<String> = [], showWaitingReason: Bool = false) {
        self.enabled = enabled
        self.doneAgents = doneAgents
        self.doneProjects = doneProjects
        self.showWaitingReason = showWaitingReason
    }
}

/// A macOS notification to post. Carries only "tool · project" and a state word — never terminal output or
/// task content — plus, only when Settings allows it, a Needs-you agent's waiting reason.
public struct AgentNotification: Equatable, Sendable {
    public var address: String
    public var title: String
    public var body: String
    /// Dedupe key: one notification per transition.
    public var key: String
    /// Buttons it offers (Needs you only); empty = click to open the panel, nothing else.
    public var actions: NotificationActions = []
    /// The Needs-you episode (`waitingSince`) an action answers; acting on a later one sends nothing.
    public var episode: Date?

    /// The episode as stored in a notification's userInfo. `Date`'s own value (seconds since 2001), so it reads
    /// back bit-for-bit equal; a round trip through `timeIntervalSince1970` can be off by a rounding step.
    public static func encodeEpisode(_ date: Date) -> Double { date.timeIntervalSinceReferenceDate }
    public static func decodeEpisode(_ value: Double) -> Date { Date(timeIntervalSinceReferenceDate: value) }

    public init(address: String, title: String, body: String, key: String, actions: NotificationActions = [], episode: Date? = nil) {
        self.address = address
        self.title = title
        self.body = body
        self.key = key
        self.actions = actions
        self.episode = episode
    }
}

/// What a Needs-you notification lets you do without opening Atoll.
public struct NotificationActions: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let allow = NotificationActions(rawValue: 1)
    public static let deny = NotificationActions(rawValue: 2)
    public static let reply = NotificationActions(rawValue: 4)

    /// Every non-empty combination, for registering one notification category each.
    public static let combinations: [NotificationActions] = (1...7).map { NotificationActions(rawValue: $0) }

    /// Stable category identifier, e.g. "atoll.actions.allow-deny".
    public var categoryIdentifier: String {
        let names = [(Self.allow, "allow"), (Self.deny, "deny"), (Self.reply, "reply")].filter { contains($0.0) }.map(\.1)
        return "atoll.actions." + names.joined(separator: "-")
    }

    public init?(categoryIdentifier: String) {
        guard let match = Self.combinations.first(where: { $0.categoryIdentifier == categoryIdentifier }) else { return nil }
        self = match
    }
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

    /// The one-shot "notify when done" for a finished turn. Skipped when the always-on Done
    /// notification already went out for this same transition.
    public mutating func finished(for agent: Agent, settings: NotificationSettings) -> AgentNotification? {
        guard settings.enabled else { return nil }
        let doneKey = "done#\(agent.turn)"
        if agent.state == .done, lastSent[agent.address] == doneKey { return nil }
        let key = agent.state == .done ? doneKey : "finished#\(agent.turn)"
        lastSent[agent.address] = key
        return AgentNotification(address: agent.address, title: agent.displayName, body: agent.state.label, key: key)
    }

    /// Fills in a Needs-you notification from the agent as it is now (after its screen was read): the reason
    /// when Settings allows it, and the buttons. Allow only appears together with the reason, Deny only when
    /// the permission dialog's keys are known, Reply only where the agent takes text.
    public static func decorate(_ note: AgentNotification, with agent: Agent, settings: NotificationSettings) -> AgentNotification {
        guard agent.state.isNeedsYou else { return note }
        var note = note
        note.episode = agent.waitingSince
        let reason = settings.showWaitingReason ? (agent.waitingPreview?.title ?? agent.statusMessage) : nil
        if let reason { note.body += " · \(reason)" }
        var actions: NotificationActions = []
        if agent.permissionChoices != nil {
            actions.insert(.deny)
            if reason != nil { actions.insert(.allow) }
        }
        switch agent.replyMode {
        case .text(force: true), .textAndKeys: actions.insert(.reply)
        default: break
        }
        note.actions = actions
        return note
    }

    /// The one reminder for a Needs-you episode that outlasted the reminder delay.
    public func reminder(for agent: Agent, waited: TimeInterval, settings: NotificationSettings) -> AgentNotification? {
        guard settings.enabled, agent.state.isNeedsYou else { return nil }
        let minutes = max(1, Int(waited / 60))
        let episode = Int(agent.waitingSince?.timeIntervalSince1970 ?? 0)
        return AgentNotification(
            address: agent.address,
            title: agent.displayName,
            body: "Still needs you · \(minutes)m",
            key: "reminder#\(agent.turn)#\(episode)"
        )
    }
}
