import Foundation

/// What one Needs-you episode's screen read found: why the agent waits (unless the source already said, in
/// `statusMessage`), and what can be answered straight from the list or panel. Built by the screen-read
/// tracker and handed to the agent whole.
public struct WaitingDialog: Equatable, Sendable {
    public var preview: WaitingPreview?
    public var permissionChoices: PermissionChoices?
    public var questionChoices: QuestionChoices?

    public init(preview: WaitingPreview? = nil, permissionChoices: PermissionChoices? = nil, questionChoices: QuestionChoices? = nil) {
        self.preview = preview
        self.permissionChoices = permissionChoices
        self.questionChoices = questionChoices
    }

    /// Nothing found (yet): the agent carries nil instead.
    var isEmpty: Bool { preview == nil && permissionChoices == nil && questionChoices == nil }
}
