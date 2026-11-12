import Foundation

/// Which agents the collapsed island shows (ticket 42): everyone, one Herdr space, or the agents in none.
public enum SpaceFilter: Equatable, Hashable, Sendable {
    case all
    case space(String)
    /// Agents not shown in any Herdr space.
    case other

    /// UserDefaults form: "" = all, "@other", else the space id (Herdr's ids start with "sp").
    public init(stored: String) {
        switch stored {
        case "": self = .all
        case "@other": self = .other
        default: self = .space(stored)
        }
    }

    public var stored: String {
        switch self {
        case .all: ""
        case .other: "@other"
        case .space(let id): id
        }
    }

    public func contains(_ agent: Agent) -> Bool {
        switch self {
        case .all: true
        case .other: agent.spaceID == nil
        case .space(let id): agent.spaceID == id
        }
    }
}

/// One list section: a Herdr space's agents, or the agents in none ("Other").
public struct SpaceSection: Equatable, Identifiable, Sendable {
    public var filter: SpaceFilter
    public var name: String
    public var agents: [Agent]

    public var id: String { filter.stored }
}

public enum SpaceGrouping {
    public static let otherName = "Other"

    /// Sections for the list, or nil when no agent is in a space (the list stays flat).
    /// `agents` comes priority-sorted, so ordering sections by their first agent puts the space with whoever
    /// needs you first on top; inside a section the order is unchanged.
    public static func sections(_ agents: [Agent]) -> [SpaceSection]? {
        guard agents.contains(where: { $0.spaceID != nil }) else { return nil }
        var sections: [SpaceSection] = []
        var index: [SpaceFilter: Int] = [:]
        for agent in agents {
            let filter: SpaceFilter = agent.spaceID.map { .space($0) } ?? .other
            if let at = index[filter] {
                sections[at].agents.append(agent)
            } else {
                index[filter] = sections.count
                sections.append(SpaceSection(filter: filter, name: agent.spaceName ?? otherName, agents: [agent]))
            }
        }
        return sections
    }

    /// The list's order: sections flattened, or `agents` as is without spaces. ↑↓ and ⌘1–9 follow it.
    public static func listOrder(_ agents: [Agent]) -> [Agent] {
        sections(agents)?.flatMap(\.agents) ?? agents
    }

    /// What the filter still means now: a space Herdr no longer has (with spaces known), or Other with
    /// spaces unknown, falls back to all.
    public static func effective(_ filter: SpaceFilter, spaces: [HerdrSpace]) -> SpaceFilter {
        switch filter {
        case .all: return .all
        case .other: return spaces.isEmpty ? .all : .other
        case .space(let id): return spaces.contains { $0.id == id } ? filter : .all
        }
    }

    /// The choices offered for the island, in Herdr's order: All, each space with agents (plus the
    /// selected one), then Other when some agent is in none.
    public static func choices(agents: [Agent], spaces: [HerdrSpace], selected: SpaceFilter) -> [(SpaceFilter, String)] {
        guard !spaces.isEmpty else { return [] }
        let used = Set(agents.compactMap(\.spaceID))
        var result: [(SpaceFilter, String)] = [(.all, "All")]
        for space in spaces where used.contains(space.id) || selected == .space(space.id) {
            result.append((.space(space.id), space.name))
        }
        if agents.contains(where: { $0.spaceID == nil }) || selected == .other {
            result.append((.other, otherName))
        }
        return result
    }

    /// The collapsed island under a filter: its agents, plus anyone elsewhere who needs attention
    /// (a waiting or failed agent is never hidden by the filter). Order is kept.
    public static func islandAgents(_ agents: [Agent], filter: SpaceFilter) -> [Agent] {
        agents.filter { filter.contains($0) || $0.state.needsAttention }
    }
}
