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
                }
                GridRow {
                    label("Name")
                    TextField("Optional display name", text: $name)
                        .textFieldStyle(.roundedBorder)
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
            Text(summary)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
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
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }

    private var summary: String {
        let dir = folder.isEmpty ? "(no folder)" : (folder as NSString).lastPathComponent
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        let head = trimmed.count > 60 ? String(trimmed.prefix(60)) + "…" : trimmed
        return "\(option.title) · \(dir) · \(head.isEmpty ? "(no task)" : head)"
    }

    private var isStarting: Bool {
        if case .starting = store.launchState { return true }
        return false
    }

    private var canLaunch: Bool {
        store.herdrAppRunning && !folder.isEmpty && !isStarting
    }

    @ViewBuilder
    private var statusView: some View {
        switch store.launchState {
        case .idle:
            EmptyView()
        case .starting:
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
            }
            .font(.system(size: 11))
        case .failed(let error):
            HStack(spacing: 6) {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(PixelPalette.error.color)
                Text("\(store.launchState.label) · \(error.message)\(error.hint.map { " — \($0)" } ?? "")")
                    .lineLimit(2)
            }
            .font(.system(size: 11))
        }
    }

    private func load() async {
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
        ))
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
