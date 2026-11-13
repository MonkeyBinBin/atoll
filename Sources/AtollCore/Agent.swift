import Foundation

public enum AgentTool: String, Equatable, Sendable, CaseIterable {
    case claudeCode
    case codex
    case generic

    /// Maps the OSC 7501 `app` word to an appearance.
    public static func from(app: String?) -> AgentTool {
        guard let app = app?.lowercased() else { return .generic }
        if app.hasPrefix("claude") { return .claudeCode }
        if app.hasPrefix("codex") { return .codex }
        return .generic
    }
}

public enum BlockedKind: String, Equatable, Sendable {
    case question, permission, auth, unspecified

    public static func from(kind: String?) -> BlockedKind {
        switch kind?.lowercased() {
        case "question": .question
        case "permission": .permission
        case "auth": .auth
        default: .unspecified
        }
    }

    public var label: String {
        switch self {
        case .question: "Question"
        case .permission: "Permission"
        case .auth: "Sign-in required"
        case .unspecified: "Needs input"
        }
    }
}

/// The user-visible state, derived by AgentStore from Herdr's facts.
public enum AgentState: Equatable, Sendable, Hashable {
    case starting
    case working
    case needsYou(BlockedKind)
    case done
    case idle
    case error
    case exited
    case unknown

    public var label: String {
        switch self {
        case .starting: "Starting"
        case .working: "Working"
        case .needsYou: "Needs you"
        case .done: "Done"
        case .idle: "Idle"
        case .error: "Error"
        case .exited: "Exited"
        case .unknown: "Unknown"
        }
    }

    /// Lower sorts first: Needs you > Error > Unknown > Working > Done > Idle > Exited.
    public var priority: Int {
        switch self {
        case .needsYou: 0
        case .error: 1
        case .unknown: 2
        case .working, .starting: 3
        case .done: 4
        case .idle: 5
        case .exited: 6
        }
    }

    /// Pinned to the left wing and announced in the hint line.
    public var needsAttention: Bool {
        switch self {
        case .needsYou, .error: true
        default: false
        }
    }

    public var isNeedsYou: Bool {
        if case .needsYou = self { return true }
        return false
    }

    /// Counts toward a shared-working-tree warning: running, or stopped mid-turn on the user / an error.
    public var isActiveInTree: Bool {
        switch self {
        case .starting, .working, .needsYou, .error: true
        default: false
        }
    }

    public var blockedKind: BlockedKind? {
        if case .needsYou(let kind) = self { return kind }
        return nil
    }
}

/// How the panel may reply to an agent, decided by its state.
public enum ReplyMode: Equatable, Sendable {
    /// Free text; `force` lets it reach a blocked program (answering a question).
    case text(force: Bool)
    /// Only the generic key row (permission prompts).
    case keys
    /// Blocked without a known kind (herdr CLI, cmux): answer by text (forced) or by key.
    case textAndKeys
    /// Sign-in flows stay in the full terminal.
    case openInHerdrOnly
    /// Nothing to send to (exited).
    case none

    public static func forState(_ state: AgentState) -> ReplyMode {
        switch state {
        case .needsYou(.question): .text(force: true)
        case .needsYou(.permission): .keys
        case .needsYou(.unspecified): .textAndKeys
        case .needsYou(.auth): .openInHerdrOnly
        case .exited: .none
        default: .text(force: false)
        }
    }
}

public struct Agent: Identifiable, Equatable, Sendable {
    public var id: String { address }
    public var address: String
    /// The terminal's own name (set at launch), if any.
    public var name: String?
    public var tool: AgentTool
    /// The raw OSC 7501 `app` word last reported, if any.
    public var app: String?
    public var state: AgentState
    public var statusMessage: String?
    public var projectPath: String
    /// When the current state began (Herdr's `status_ms` when known).
    public var stateSince: Date?
    /// When the agent started waiting for the user (only while Needs you).
    public var waitingSince: Date?
    /// Last status / turn / foreground event seen locally.
    public var lastStatusChange: Date?
    /// Individual color, fixed for the session.
    public var colorIndex: Int
    /// Done and already opened in the panel: celebrate no more.
    public var acknowledged: Bool
    public var turn: UInt64
    public var title: String
    /// One-shot interrupt feedback, cleared after a short while.
    public var interruptFeedback: InterruptOutcome?
    /// Bundle id (or TERM_PROGRAM) of the terminal app it was started from outside Herdr,
    /// from the `atoll.origin` label set by scripts/shell/atoll.zsh.
    public var origin: String?
    /// The backend this agent comes from.
    public var source: AgentSource = .core
    /// The Herdr space showing its terminal (ticket 42); nil = not in the Herdr window (Other).
    public var spaceID: String?
    public var spaceName: String?
    /// What its last finished turn changed in git; cleared when the next turn starts.
    public var changeSummary: ChangeSummary?
    /// Why it waits, read once from its screen when the source gave no `statusMessage`; Needs you only.
    public var waitingPreview: WaitingPreview?
    /// The last lines the agent wrote, read from its screen once when a turn ended without a `statusMessage`.
    /// Dropped when the next turn starts.
    public var finalMessage: TurnFinalMessage?

    /// Working with a screen that hasn't changed since then (past the "no output" threshold). States a fact,
    /// not that the agent is stuck.
    public var noOutputSince: Date?

    /// What the agent last said, for the list, hover card and bubble: the source's own summary
    /// (`statusMessage`), else the lines read off its screen when the turn ended.
    public var lastWords: String? { statusMessage ?? finalMessage?.text }
    /// Keys for answering its permission dialog straight from the list; only when the dialog's layout was
    /// recognized on screen in this Needs-you episode.
    public var permissionChoices: PermissionChoices?
    /// Other active agents in the same git working tree (addresses); empty unless this one is active too.
    public var sharedTreeWith: [String] = []

    public init(
        address: String, name: String? = nil, tool: AgentTool = .generic, app: String? = nil,
        state: AgentState = .unknown, statusMessage: String? = nil, projectPath: String = "/",
        stateSince: Date? = nil, waitingSince: Date? = nil, lastStatusChange: Date? = nil,
        colorIndex: Int = 0, acknowledged: Bool = false, turn: UInt64 = 0, title: String = "",
        interruptFeedback: InterruptOutcome? = nil, origin: String? = nil
    ) {
        self.address = address
        self.name = name
        self.tool = tool
        self.app = app
        self.state = state
        self.statusMessage = statusMessage
        self.projectPath = projectPath
        self.stateSince = stateSince
        self.waitingSince = waitingSince
        self.lastStatusChange = lastStatusChange
        self.colorIndex = colorIndex
        self.acknowledged = acknowledged
        self.turn = turn
        self.title = title
        self.interruptFeedback = interruptFeedback
        self.origin = origin
    }

    public var projectName: String {
        let last = (projectPath as NSString).lastPathComponent
        return last.isEmpty ? projectPath : last
    }

    public var toolName: String {
        switch tool {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .generic:
            guard let app, !app.isEmpty else { return "Terminal" }
            return app.prefix(1).uppercased() + app.dropFirst()
        }
    }

    /// "Codex · project-x" — the label used everywhere a target is named.
    public var displayName: String {
        "\(toolName) · \(name ?? projectName)"
    }

    public var replyMode: ReplyMode { .forState(state) }
}

extension AgentState {
    /// Entering this state ends a turn: Done or Exited, or Idle straight from Working / Starting (stopped
    /// without reporting Done). Error ends it too but is handled on its own; Needs you is mid-turn.
    func endsTurn(from previous: AgentState?) -> Bool {
        switch self {
        case .done, .exited: true
        case .idle: previous == .working || previous == .starting
        default: false
        }
    }
}
