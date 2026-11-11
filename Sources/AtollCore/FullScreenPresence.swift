import Foundation

/// How the collapsed island behaves while its screen shows a full-screen app.
public enum FullScreenMode: String, CaseIterable, Sendable {
    /// Same as without full screen.
    case showAll
    /// Only agents that need attention; hidden when none do.
    case attentionOnly
    /// Hidden.
    case hide
}

public enum FullScreenPresence {
    /// The agents the collapsed island shows, or nil when the island should be hidden.
    public static func collapsedAgents(_ agents: [Agent], fullScreen: Bool, mode: FullScreenMode) -> [Agent]? {
        guard fullScreen else { return agents }
        switch mode {
        case .showAll:
            return agents
        case .attentionOnly:
            let attention = agents.filter { $0.state.needsAttention }
            return attention.isEmpty ? nil : attention
        case .hide:
            return nil
        }
    }
}
