import Foundation

/// What the launch form had filled in: kept as a recent launch or saved as a preset. The folder is the one the
/// user picked (never the worktree's), and a worktree's branch is never kept: it is generated again.
public struct LaunchRecipe: Codable, Equatable, Sendable {
    /// `LaunchOption.id`: "builtin:<command>" (claude, codex or a detected `AgentCLI`) or "template:<name>".
    public var optionID: String
    public var folder: String
    public var task: String
    public var name: String
    public var space: String
    public var worktree: Bool
    /// Set when it started in a new space: that space's name (empty = named after the folder). `space` is empty
    /// then. Missing in recipes saved before new spaces existed.
    public var newSpaceName: String?

    public init(optionID: String, folder: String, task: String, name: String, space: String, worktree: Bool,
                newSpaceName: String? = nil) {
        self.optionID = optionID
        self.folder = folder
        self.task = task
        self.name = name
        self.space = space
        self.worktree = worktree
        self.newSpaceName = newSpaceName
    }

    /// The form's Space picker for this recipe: a new space again, or the space it names.
    public var spaceChoice: LaunchSpaceChoice {
        newSpaceName != nil ? .new : LaunchSpaceChoice(stored: space)
    }

    /// Tool, folder and task: what makes two launches "the same" in the recent list.
    func sameCombination(as other: LaunchRecipe) -> Bool {
        optionID == other.optionID && folder == other.folder && task == other.task
    }

    /// "Claude Code · atoll · first 40 characters of the task".
    public func menuTitle(toolTitle: String) -> String {
        let oneLine = task.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        let head = oneLine.isEmpty ? "(no task)" : OutputFilter.cut(oneLine, limit: 40)
        return "\(toolTitle) · \((folder as NSString).lastPathComponent) · \(head)"
    }
}

/// A named recipe the user saved ("Atoll presets", not herdr-core templates).
public struct LaunchPreset: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var recipe: LaunchRecipe

    public init(id: UUID = UUID(), name: String, recipe: LaunchRecipe) {
        self.id = id
        self.name = name
        self.recipe = recipe
    }
}

/// Rules for the recent-launch list and presets. The app stores both in UserDefaults; nothing here reads
/// agent screens or output.
public enum LaunchHistory {
    public static let maxRecent = 10
    public static let maxPresets = 20

    /// Newest first; the same tool + folder + task keeps only its newest launch.
    public static func recording(_ recipe: LaunchRecipe, in recent: [LaunchRecipe]) -> [LaunchRecipe] {
        Array(([recipe] + recent.filter { !$0.sameCombination(as: recipe) }).prefix(maxRecent))
    }

    /// nil when the name is blank or there are already `maxPresets`.
    public static func adding(name: String, recipe: LaunchRecipe, to presets: [LaunchPreset]) -> [LaunchPreset]? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, presets.count < maxPresets else { return nil }
        return presets + [LaunchPreset(name: name, recipe: recipe)]
    }

    /// A blank name leaves the preset as it was.
    public static func renaming(_ id: UUID, to name: String, in presets: [LaunchPreset]) -> [LaunchPreset] {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return presets }
        return presets.map { $0.id == id ? LaunchPreset(id: $0.id, name: name, recipe: $0.recipe) : $0 }
    }

    public static func deleting(_ id: UUID, from presets: [LaunchPreset]) -> [LaunchPreset] {
        presets.filter { $0.id != id }
    }

    /// Moves one place up (-1) or down (+1); no-op at the ends.
    public static func moving(_ id: UUID, by offset: Int, in presets: [LaunchPreset]) -> [LaunchPreset] {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return presets }
        let target = index + offset
        guard presets.indices.contains(target) else { return presets }
        var list = presets
        list.swapAt(index, target)
        return list
    }

    public struct Restored: Equatable, Sendable {
        public var recipe: LaunchRecipe
        /// What couldn't be brought back, for the form to show.
        public var notes: [String]
    }

    /// "template:reviewer" → "reviewer"; nil for built-in tools.
    public static func templateName(of optionID: String) -> String? {
        optionID.hasPrefix("template:") ? String(optionID.dropFirst("template:".count)) : nil
    }

    /// Checks a recipe before it fills the form: a folder that's gone is left empty, a tool that's gone falls back
    /// to the default one, a space that's gone falls back to the selected space (`spaces` nil = not known, left
    /// alone). The worktree wish is kept; the form turns it on only if the folder is still a repo.
    public static func restore(_ recipe: LaunchRecipe, folderExists: (String) -> Bool, availableOptionIDs: Set<String>,
                               defaultOptionID: String, templatesLoaded: Bool, spaces: Set<String>?) -> Restored {
        var result = recipe
        var notes: [String] = []
        if !recipe.folder.isEmpty, !folderExists(recipe.folder) {
            result.folder = ""
            notes.append("Folder \(recipe.folder) no longer exists")
        }
        if !availableOptionIDs.contains(recipe.optionID) {
            result.optionID = defaultOptionID
            if let template = templateName(of: recipe.optionID) {
                notes.append(templatesLoaded
                    ? "Template \(template) is no longer available; using the default tool"
                    : "Couldn't load herdr-core templates; using the default tool")
            } else {
                notes.append("That tool is no longer available; using the default tool")
            }
        }
        if !recipe.space.isEmpty, let spaces, !spaces.contains(recipe.space) {
            result.space = ""
            notes.append("That space no longer exists; using the selected space")
        }
        return Restored(recipe: result, notes: notes)
    }
}
