import AppKit
import AtollCore
import SwiftUI

/// What can be launched: built-in tools plus herdr-core templates.
struct LaunchOption: Identifiable, Hashable {
    var id: String
    var title: String
    var argv: [String]
    var tool: AgentTool

    /// Plain argv: `herdr-app do tab.new` already runs it as `$SHELL -lic '"$@"; exec "$0" -li' <argv…> <task>`,
    /// so shell init (nvm, PATH) is loaded and the task arrives as the program's last argument.
    static let builtIns = [
        LaunchOption(id: "builtin:claude", title: "Claude Code", argv: ["claude"], tool: .claudeCode),
        LaunchOption(id: "builtin:codex", title: "Codex", argv: ["codex", "--no-daemon"], tool: .codex),
    ]

    static func template(_ t: TemplateInfo) -> LaunchOption {
        // argv[0] naming a template makes core start its command and send its body.
        LaunchOption(id: "template:\(t.name)", title: "\(t.name) (template)", argv: [t.name], tool: .from(app: t.command))
    }
}

struct LaunchFormView: View {
    @Bindable var model: IslandModel
    @Environment(AppSettings.self) private var settings
    @Environment(\.herdrClient) private var client

    @State private var options = LaunchOption.builtIns
    @State private var optionID = LaunchOption.builtIns[0].id
    @State private var folder = ""
    @State private var task = ""
    @State private var name = ""
    @State private var spaces: [HerdrSpace] = []
    @State private var space = ""
    /// The folder's repo, when it is one (offers "New worktree").
    @State private var source: WorktreeSource?
    @State private var useWorktree = false
    @State private var branchText = ""
    @State private var branchEdited = false
    @FocusState private var taskFocused: Bool

    private var store: AgentStore { model.store }
    private var option: LaunchOption { options.first { $0.id == optionID } ?? options[0] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Launch agent").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { model.escape() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    label("Tool")
                    Picker("", selection: $optionID) {
                        ForEach(options) { Text($0.title).tag($0.id) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    label("Folder")
                    HStack(spacing: 6) {
                        Menu {
                            ForEach(settings.recentFolders, id: \.self) { path in
                                Button(Format.abbreviatePath(path)) { folder = path }
                            }
                            if settings.recentFolders.isEmpty { Text("No recent folders") }
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
                    TextField("Initial task", text: $task, axis: .vertical)
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
                    TextField("Optional display name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                if source != nil {
                    GridRow {
                        label("Worktree")
                        Toggle("New worktree", isOn: $useWorktree)
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
                    Picker("", selection: $space) {
                        Text("Selected space").tag("")
                        ForEach(spaces) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                }
            }
            .font(.system(size: 12))

            // Always-visible confirmation summary.
            VStack(alignment: .leading, spacing: 3) {
                Text(summary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
                    Text("Herdr app isn't running")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Button("Launch", action: launch)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canLaunch)
            }
        }
        .padding(14)
        .task { await load() }
        .task(id: folder) {
            guard !folder.isEmpty, let creator = store.worktreeCreator else {
                source = nil
                return
            }
            let found = await creator.source(for: folder)
            guard !Task.isCancelled else { return }
            source = found
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
        store.herdrAppRunning && !folder.isEmpty && !store.isLaunchBusy
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

    private func load() async {
        if let prefill = model.launchPrefill {
            model.launchPrefill = nil
            folder = prefill.folder
            if let id = prefill.optionID { optionID = id }
            useWorktree = prefill.worktree
        }
        if folder.isEmpty { folder = settings.recentFolders.first ?? "" }
        space = settings.defaultSpace
        taskFocused = true
        if let templates = try? await client?.templates() {
            options = LaunchOption.builtIns + templates.filter { $0.error == nil }.map(LaunchOption.template)
        }
        if let list = try? await client?.spaces() {
            spaces = list
            if !space.isEmpty, !list.contains(where: { $0.id == space }) { space = "" }
        }
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
            folder = url.path
        }
    }

    private func launch() {
        guard canLaunch else { return }
        settings.rememberFolder(folder)
        store.launch(LaunchRequest(
            argv: option.argv,
            folder: folder,
            task: task.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : Self.sanitizeName(name),
            space: space.isEmpty ? nil : space
        ), worktree: plan)
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
