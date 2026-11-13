import AppKit
import AtollCore
import SwiftUI

/// What can be launched: built-in tools, other agent CLIs found on this Mac, and herdr-core templates.
struct LaunchOption: Identifiable, Hashable {
    var id: String
    var title: String
    var argv: [String]
    var tool: AgentTool
    var taskPassing: TaskPassing = .lastArgument

    /// Plain argv: `herdr-app do tab.new` already runs it as `$SHELL -lic '"$@"; exec "$0" -li' <argv…> <task>`,
    /// so shell init (nvm, PATH) is loaded and the task arrives as the program's last argument.
    static let builtIns = [
        LaunchOption(id: "builtin:claude", title: "Claude Code", argv: ["claude"], tool: .claudeCode),
        LaunchOption(id: "builtin:codex", title: "Codex", argv: ["codex", "--no-daemon"], tool: .codex),
    ]

    static func detected(_ cli: AgentCLI) -> LaunchOption {
        LaunchOption(id: detectedID(cli), title: cli.title, argv: [cli.command], tool: .from(app: cli.command),
                     taskPassing: cli.taskPassing)
    }

    static func detectedID(_ cli: AgentCLI) -> String { "builtin:\(cli.command)" }

    /// The catalog CLI an option id names, if it's one.
    static func catalogCLI(id: String) -> AgentCLI? {
        AgentCLI.catalog.first { detectedID($0) == id }
    }

    static func template(_ t: TemplateInfo) -> LaunchOption {
        // argv[0] naming a template makes core start its command and send its body.
        LaunchOption(id: "template:\(t.name)", title: "\(t.name) (template)", argv: [t.name], tool: .from(app: t.command))
    }
}

struct LaunchFormView: View {
    @Bindable var model: IslandModel
    @Environment(AppSettings.self) private var settings
    @Environment(\.herdrClient) private var client

    /// Agent CLIs from `AgentCLI.catalog` found on this Mac.
    @State private var installed: [AgentCLI] = []
    /// The latest detection failed, so `installed` may be missing CLIs: a restored recipe's CLI is trusted.
    @State private var detectionFailed = false
    /// The background re-detection after showing the cached list is still running.
    @State private var refreshing = true
    @State private var templateOptions: [LaunchOption] = []
    @State private var optionID = LaunchOption.builtIns[0].id
    @State private var folder = ""
    @State private var task = ""
    @State private var name = ""
    @State private var spaces: [HerdrSpace] = []
    /// False until `spaces` loads and the starting space is checked against it.
    @State private var spacesLoaded = false
    @State private var space: LaunchSpaceChoice = .selected
    /// The name for a new space (`space == .new`); empty = Herdr names it after the folder.
    @State private var newSpaceName = ""
    /// Where the starting space came from, while the user hasn't changed it (ticket 43).
    @State private var spaceOrigin: SpaceGrouping.LaunchSpaceSource?
    @State private var startingSpace: LaunchSpaceChoice = .selected
    /// The folder's repo, when it is one (offers "New worktree").
    @State private var source: WorktreeSource?
    @State private var useWorktree = false
    @State private var branchText = ""
    @State private var branchEdited = false
    /// A restored recipe's "New worktree", applied once the folder's repo check answers.
    @State private var pendingWorktree: Bool?
    /// The folder `source` was checked for (nil while a check runs).
    @State private var sourceFolder: String?
    /// False until installed CLIs and herdr-core templates are in the tool list.
    @State private var toolsLoaded = false
    /// False when the herdr-core templates couldn't be loaded.
    @State private var templatesLoaded = false
    /// A recipe picked before the tool list was complete, applied once it is.
    @State private var deferredRecipe: LaunchRecipe?
    /// What a restored recipe couldn't bring back.
    @State private var restoreNotes: [String] = []
    @State private var savingPreset = false
    @State private var presetName = ""
    @FocusState private var taskFocused: Bool
    @FocusState private var launchFocused: Bool

    private var store: AgentStore { model.store }
    private var options: [LaunchOption] { LaunchOption.builtIns + installed.map(LaunchOption.detected) + templateOptions }
    private var option: LaunchOption { options.first { $0.id == optionID } ?? options[0] }
    private var taskSupported: Bool { option.taskPassing != .unsupported }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Launch agent").font(.system(size: 13, weight: .semibold))
                Spacer()
                recentMenu
                presetMenu
                Button("Launch again", action: launchAgain)
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(settings.recentLaunches.isEmpty)
                    .help("Fill in the last launch (⌘R); confirm with Launch")
                PinButton(model: model)
                Button { model.escape() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
            }
            .font(.system(size: 11))
            if savingPreset { savePresetRow }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    label("Tool")
                    Picker("", selection: Binding(get: { optionID }, set: { optionID = $0; restoreNotes = [] })) {
                        ForEach(options) { Text($0.title).tag($0.id) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    label("Folder")
                    HStack(spacing: 6) {
                        Menu {
                            let folders = settings.folders
                            ForEach(folders.pinned, id: \.self) { path in
                                Button { pickFolder(path) } label: { Label(Format.abbreviatePath(path), systemImage: "pin") }
                            }
                            if !folders.pinned.isEmpty, !folders.unpinnedRecent.isEmpty { Divider() }
                            ForEach(folders.unpinnedRecent, id: \.self) { path in
                                Button(Format.abbreviatePath(path)) { pickFolder(path) }
                            }
                            if folders.recent.isEmpty { Text("No recent folders") }
                            Divider()
                            Button("Edit…") { NotificationCenter.default.post(name: .atollShowSettings, object: nil) }
                        } label: {
                            Text(folder.isEmpty ? "Choose a folder" : Format.abbreviatePath(folder))
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                        Button("Finder…", action: chooseFolder)
                    }
                }
                GridRow(alignment: .top) {
                    label("Task")
                    TextField(taskSupported ? "Initial task" : "\(option.title) can't start with a task",
                              text: $task, axis: .vertical)
                        .disabled(!taskSupported)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)
                        .focused($taskFocused)
                        .commandCompletion(
                            model: model, draft: $task, focused: taskFocused,
                            tool: option.tool, cwd: folder.isEmpty ? nil : folder
                        )
                }
                GridRow {
                    label("Name")
                    // Herdr's space.new takes no terminal name; without the app, hc run does.
                    let nameUnused = space == .new && store.herdrAppRunning
                    TextField(nameUnused ? "Not used for a new space" : "Optional display name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .disabled(nameUnused)
                }
                if source != nil {
                    GridRow {
                        label("Worktree")
                        Toggle("New worktree", isOn: Binding(get: { useWorktree }, set: { useWorktree = $0; pendingWorktree = nil }))
                            .toggleStyle(.checkbox)
                            .help("Create a separate git worktree on a new branch and start the agent there")
                    }
                    if useWorktree, let plan {
                        GridRow {
                            label("Branch")
                            TextField("atoll/…", text: Binding(
                                get: { branch },
                                set: { branchText = $0; branchEdited = true }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        }
                        GridRow {
                            label("Location")
                            Text(Format.abbreviatePath(plan.path))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                                .help(plan.path)
                        }
                    }
                }
                GridRow {
                    label("Space")
                    HStack(spacing: 6) {
                        Picker("", selection: $space) {
                            // Without the app: the space it showed last.
                            Text(store.herdrAppRunning ? "Selected space" : "Last selected space").tag(LaunchSpaceChoice.selected)
                            ForEach(spaces) { Text($0.name).tag(LaunchSpaceChoice.existing($0.id)) }
                            Divider()
                            Text("New space…").tag(LaunchSpaceChoice.new)
                        }
                        .labelsHidden()
                        if let note = spaceNote {
                            Text(note)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .fixedSize()
                        }
                    }
                }
                if space == .new {
                    GridRow {
                        label("Space name")
                        TextField("Named after the folder", text: $newSpaceName)
                            .textFieldStyle(.roundedBorder)
                            .help(store.herdrAppRunning ? "Name for the new Herdr space"
                                  : "Name for the new Herdr space; applied when the Herdr app opens")
                    }
                }
            }
            .font(.system(size: 12))

            // Always-visible confirmation summary.
            VStack(alignment: .leading, spacing: 3) {
                Text(summary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                ForEach(restoreNotes, id: \.self) { note in
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(PixelPalette.waiting.color)
                        .lineLimit(2)
                }
                if let plan {
                    Text("From HEAD \(plan.source.shortHead)" + (plan.source.dirty ? " · uncommitted changes in the repo won't be carried over" : ""))
                        .font(.system(size: 11))
                        .foregroundStyle(plan.source.dirty ? PixelPalette.waiting.color : .secondary)
                        .lineLimit(2)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))

            HStack(spacing: 8) {
                statusView
                Spacer()
                if !store.herdrAppRunning {
                    Text("Herdr app isn't running · shows up there once it opens")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .help("The agent starts in herdr-core now and appears in its Herdr space when the app opens")
                }
                Button("Launch", action: launch)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canLaunch)
                    .focused($launchFocused)
            }
        }
        .padding(14)
        .task { await load() }
        .task(id: folder) {
            source = nil
            sourceFolder = nil
            guard !folder.isEmpty, let creator = store.worktreeCreator else {
                pendingWorktree = nil
                return
            }
            let checked = folder
            let found = await creator.source(for: checked)
            guard !Task.isCancelled else { return }
            source = found
            sourceFolder = checked
            if let wish = pendingWorktree {
                pendingWorktree = nil
                useWorktree = wish && found != nil
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }

    private var branch: String {
        branchEdited ? branchText : WorktreeNaming.defaultBranch(name: name, task: task)
    }

    /// The worktree to create, when "New worktree" is on and the folder is a repo.
    private var plan: WorktreePlan? {
        guard useWorktree, let source else { return nil }
        return WorktreePlan.make(source: source, branch: branch.trimmingCharacters(in: .whitespaces), folder: folder)
    }

    private var summary: String {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        let head = trimmed.count > 60 ? String(trimmed.prefix(60)) + "…" : trimmed
        let task = head.isEmpty ? "(no task)" : head
        if let plan {
            return "\(option.title) · \((plan.path as NSString).lastPathComponent) (\(plan.branch)) · \(task)"
        }
        let dir = folder.isEmpty ? "(no folder)" : (folder as NSString).lastPathComponent
        return "\(option.title) · \(dir) · \(task)"
    }

    private var canLaunch: Bool {
        spacesLoaded && !folder.isEmpty && !store.isLaunchBusy
            && (plan == nil || !branch.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @ViewBuilder
    private var statusView: some View {
        switch store.launchState {
        case .idle:
            EmptyView()
        case .creatingWorktree, .starting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(store.launchState.label)
            }
            .font(.system(size: 11))
        case .launched(let terminal):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(PixelPalette.done.color)
                Text(store.launchState.label)
                Button("Open panel") { model.openPanel(terminal) }.buttonStyle(.borderless)
            }
            .font(.system(size: 11))
        case .unconfirmed(let terminal):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(PixelPalette.waiting.color)
                Text(store.launchState.label)
                if let terminal {
                    Button("Open in Herdr") { Task { _ = await store.openInHerdr(terminal) } }
                        .buttonStyle(.borderless)
                }
                worktreeNote
            }
            .font(.system(size: 11))
        case .failed(let error):
            HStack(spacing: 6) {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(PixelPalette.error.color)
                Text("\(store.launchState.label) · \(error.message)\(error.hint.map { " — \($0)" } ?? "")")
                    .lineLimit(3)
                    .help(error.message)
                worktreeNote
            }
            .font(.system(size: 11))
        }
    }

    /// The worktree stays on disk when the launch after it didn't work out.
    @ViewBuilder
    private var worktreeNote: some View {
        if let path = store.launchWorktree {
            Text("Worktree kept at \(Format.abbreviatePath(path))")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .help(path)
        }
    }

    /// "from island" / "same as agent" while the starting space is still the one picked.
    private var spaceNote: String? {
        guard space != .selected, space == startingSpace else { return nil }
        return switch spaceOrigin {
        case .island: "from island"
        case .agent: "same as agent"
        case .settings, nil: nil
        }
    }

    private func load() async {
        var agentSpace: String?
        if let prefill = model.launchPrefill {
            model.launchPrefill = nil
            folder = prefill.folder
            if let id = prefill.optionID { optionID = id }
            useWorktree = prefill.worktree
            agentSpace = prefill.space
        }
        if folder.isEmpty { folder = settings.recentFolders.first ?? "" }
        let start = SpaceGrouping.launchSpace(agentSpace: agentSpace, island: model.spaceFilter, defaultSpace: settings.defaultSpace)
        space = LaunchSpaceChoice(stored: start.space)
        startingSpace = space
        spaceOrigin = start.source
        taskFocused = true
        // Spaces first: Launch waits for them (a stale starting space must fall back first), not for templates.
        let list = await store.launchSpaces()
        spaces = list
        if space.isMissing(from: list) { space = .selected }
        spacesLoaded = true
        // Installed CLIs: the last detection shows at once and is refreshed in the background; only the first
        // detection is waited for (alongside the templates).
        let detector = AgentCLIDetector.shared
        let refresh = Task { await detector.refresh() }
        let cached = await detector.lastKnown
        let templates = try? await client?.templates()
        templateOptions = (templates ?? []).filter { $0.error == nil }.map(LaunchOption.template)
        templatesLoaded = templates != nil
        if let cached {
            installed = cached
        } else {
            let firstDetection = await refresh.value
            installed = firstDetection ?? []
            detectionFailed = firstDetection == nil
            refreshing = false
        }
        toolsLoaded = true
        applyDeferredRecipe()
        guard refreshing else { return }
        let fresh = await refresh.value
        refreshing = false
        detectionFailed = fresh == nil
        if let fresh { takeRefreshed(fresh) }
        applyDeferredRecipe()
    }

    private func applyDeferredRecipe() {
        guard let recipe = deferredRecipe else { return }
        deferredRecipe = nil
        apply(recipe)
    }

    /// A newer detection; the selected CLI stays selectable (with a note) even if it's no longer found.
    private func takeRefreshed(_ fresh: [AgentCLI]) {
        var list = fresh
        if let selected = LaunchOption.catalogCLI(id: optionID), !fresh.contains(selected) {
            list.append(selected)
            restoreNotes.append("\(selected.title) (\(selected.command)) wasn't found on this Mac")
        }
        installed = list
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if !folder.isEmpty { panel.directoryURL = URL(fileURLWithPath: folder) }
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url {
            pickFolder(url.path)
        }
    }

    private func launch() {
        guard canLaunch else { return }
        model.pendingLaunchRecipe = currentRecipe
        restoreNotes = []
        settings.rememberFolder(folder)
        let start = option.taskPassing.apply(argv: option.argv, task: task.trimmingCharacters(in: .whitespacesAndNewlines))
        store.launch(LaunchRequest(
            argv: start.argv,
            folder: folder,
            task: start.task,
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : Self.sanitizeName(name),
            optionID: option.id,
            space: space,
            newSpaceName: newSpaceName
        ), worktree: plan)
    }

    // MARK: Recent launches and presets

    private var currentRecipe: LaunchRecipe {
        LaunchRecipe(optionID: optionID, folder: folder, task: taskSupported ? task.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                     name: name.trimmingCharacters(in: .whitespaces),
                     space: space.stored, worktree: plan != nil,
                     newSpaceName: space == .new ? newSpaceName.trimmingCharacters(in: .whitespaces) : nil)
    }

    private func toolTitle(_ id: String) -> String {
        options.first { $0.id == id }?.title ?? LaunchHistory.templateName(of: id).map { "\($0) (template)" } ?? id
    }

    /// The user picked a folder: drops anything a restored recipe was still going to apply.
    private func pickFolder(_ path: String) {
        folder = path
        pendingWorktree = nil
        restoreNotes = []
    }

    private var recentMenu: some View {
        Menu("Recent") {
            ForEach(Array(settings.recentLaunches.enumerated()), id: \.offset) { _, recipe in
                Button(recipe.menuTitle(toolTitle: toolTitle(recipe.optionID))) { apply(recipe) }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(settings.recentLaunches.isEmpty)
        .help("Fill in an earlier launch (doesn't launch it)")
    }

    private var presetMenu: some View {
        Menu("Presets") {
            ForEach(settings.launchPresets) { preset in
                Button(preset.name) { apply(preset.recipe) }
            }
            if settings.launchPresets.isEmpty { Text("No presets yet") }
            Divider()
            Button("Save as preset…") {
                presetName = name
                savingPreset = true
            }
            .disabled(settings.launchPresets.count >= LaunchHistory.maxPresets)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Atoll's saved launch settings (herdr-core templates are in the Tool menu)")
    }

    private var savePresetRow: some View {
        HStack(spacing: 6) {
            TextField("Preset name", text: $presetName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(savePreset)
            Button("Save", action: savePreset)
                .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel") { savingPreset = false }
        }
        .font(.system(size: 12))
    }

    private func savePreset() {
        guard let presets = LaunchHistory.adding(name: presetName, recipe: currentRecipe, to: settings.launchPresets) else { return }
        settings.launchPresets = presets
        savingPreset = false
    }

    /// Fills the form (never launches). Checks the folder and tool still exist; a worktree comes back only if the
    /// folder is still a repo, always on a freshly generated branch.
    private func apply(_ recipe: LaunchRecipe) {
        // The tool list isn't complete until templates and installed CLIs arrive, and a CLI missing from the
        // cached list may have been installed since: don't call a tool gone before the list is current.
        let cli = LaunchOption.catalogCLI(id: recipe.optionID)
        guard toolsLoaded, !(refreshing && cli.map { !installed.contains($0) } == true) else {
            deferredRecipe = recipe
            return
        }
        if detectionFailed, let cli, !installed.contains(cli) { installed.append(cli) }
        let restored = LaunchHistory.restore(
            recipe,
            folderExists: { path in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            },
            availableOptionIDs: Set(options.map(\.id)),
            defaultOptionID: LaunchOption.builtIns[0].id,
            templatesLoaded: templatesLoaded,
            spaces: spaces.isEmpty ? nil : Set(spaces.map(\.id))
        )
        let r = restored.recipe
        optionID = r.optionID
        task = r.task
        name = r.name
        space = r.spaceChoice
        newSpaceName = r.newSpaceName ?? ""
        spaceOrigin = nil
        branchText = ""
        branchEdited = false
        if r.folder == folder, sourceFolder == folder {
            // Same folder, already checked: the repo check won't run again.
            pendingWorktree = nil
            useWorktree = r.worktree && source != nil
        } else {
            folder = r.folder
            useWorktree = false
            pendingWorktree = r.worktree
        }
        restoreNotes = restored.notes
        store.resetLaunch()
    }

    private func launchAgain() {
        guard let last = settings.recentLaunches.first else { return }
        apply(last)
        taskFocused = false
        launchFocused = true
    }

    /// Herdr names: 1–32 of a-z 0-9 - _ .
    static func sanitizeName(_ raw: String) -> String {
        let lowered = raw.lowercased().replacingOccurrences(of: " ", with: "-")
        let allowed = lowered.filter { $0.isLetter && $0.isASCII || $0.isNumber || "-_.".contains($0) }
        return String(allowed.prefix(32))
    }
}

private struct HerdrClientKey: EnvironmentKey {
    static let defaultValue: HerdrClient? = nil
}

extension EnvironmentValues {
    var herdrClient: HerdrClient? {
        get { self[HerdrClientKey.self] }
        set { self[HerdrClientKey.self] = newValue }
    }
}
