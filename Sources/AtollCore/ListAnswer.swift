import Foundation

/// An answer given from the list without opening the panel: a permission dialog's Allow / Deny, or one
/// option of a question (`QuestionChoices`).
public enum ListAnswer: Equatable, Sendable {
    case allow, deny
    case option(QuestionChoices.Option)

    public var label: String {
        switch self {
        case .allow: "Allow"
        case .deny: "Deny"
        case .option(let option): option.label
        }
    }
}

/// Answering a permission dialog or question from the list; per agent, for the episode it was pressed in.
public enum ListAnswerState: Equatable, Sendable {
    case sending(ListAnswer)
    case sent(ListAnswer)
    case failed(ListAnswer, HerdrError)
    /// The agent had already left that dialog (or moved on to a new one): nothing was sent.
    case noLongerWaiting

    public var label: String {
        switch self {
        case .sending(let choice): "\(choice.label)…"
        case .sent(let choice): "\(choice.label) sent"
        case .failed(let choice, _): "\(choice.label) failed"
        case .noLongerWaiting: "No longer waiting"
        }
    }
}

extension Agent {
    /// The key an answer sends, only while this Needs-you episode's screen read still offers it.
    public func key(for answer: ListAnswer) -> String? {
        switch answer {
        case .allow: permissionChoices?.allowKey
        case .deny: permissionChoices?.denyKey
        case .option(let option): questionChoices?.options.contains(option) == true ? option.key : nil
        }
    }
}
