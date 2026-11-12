import Foundation

/// A message typed while the agent works, sent once its turn ends. One per agent, in memory only.
public struct QueuedMessage: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// Waiting for the turn to end.
        case waiting
        /// The agent errored: kept unsent until the user sends or cancels it.
        case held
        /// Handed to `send`, waiting for its result.
        case sending
    }

    public var text: String
    public var status: Status

    public init(text: String, status: Status = .waiting) {
        self.text = text
        self.status = status
    }
}

/// A one-off note about a queued message the panel shows until it closes or the agent changes.
public enum QueueNotice: Equatable, Sendable {
    /// The agent exited before its turn ended; the message was discarded.
    case dropped
    /// Another message was still being sent; the queued text went back to the reply box.
    case notSent
}
