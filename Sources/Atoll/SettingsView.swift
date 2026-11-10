import AppKit
import AtollCore
import SwiftUI

struct SettingsView: View {
    let store: AgentStore
    @Bindable var settings: AppSettings
    @State private var screens: [(id: UInt32, name: String)] = []
    @State private var monoFamilies: [String] = []

    var body: some View {
        Form {
            Section("Sources") {
                ForEach(store.sources) { source in
                    let status = store.sourceStatus[source] ?? SourceStatus()
                    LabeledContent(source.name) {
                        HStack(spacing: 6) {
                            if let version = status.version {
                                Text(version).foregroundStyle(.secondary)
                            }
                            Circle().fill(Self.color(status)).frame(width: 8, height: 8)
                            Text(Self.text(status))
                        }
                    }
                    if let warning = status.compatibilityWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }
                LabeledContent("Herdr app", value: store.herdrAppRunning ? "Running" : "Herdr app isn't running")
                Button("Reconnect") { store.reconnect() }
                Text("A source that isn't running (for example cmux closed) only affects its own agents.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Island") {
                Toggle("Show island", isOn: $settings.islandVisible)
                Picker("Screen", selection: $settings.displayID) {
                    Text("Automatic (built-in display)").tag(UInt32(0))
                    ForEach(screens, id: \.id) { screen in
                        Text(screen.name).tag(screen.id)
                    }
                }
                Toggle("Animations", isOn: $settings.animationsEnabled)
                Toggle("Decorations", isOn: $settings.decorations)
                Toggle("Show terminals without status", isOn: $settings.showUnreportedTerminals)
            }

            Section("Output") {
                Picker("Font", selection: $settings.outputFontFamily) {
                    Text("Automatic (\(TerminalFont.resolvedName(family: "")))").tag("")
                    ForEach(monoFamilies, id: \.self) { Text($0).tag($0) }
                }
                Stepper(value: $settings.outputFontSize, in: AppSettings.fontSizeRange, step: 1) {
                    LabeledContent("Size", value: "\(Int(settings.outputFontSize)) pt")
                }
                Toggle("Large panel", isOn: $settings.largePanel)
                Toggle("Messages only (Claude Code, Codex)", isOn: $settings.messagesOnly)
                Text("Nerd Font icons need a Nerd Font installed; Automatic picks one when available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("Notifications", isOn: $settings.notificationsEnabled)
                Text("Needs you and Error always notify. Turn on Done per agent or project:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(store.agents) { agent in
                    Toggle(agent.displayName, isOn: Binding(
                        get: { settings.doneNotifyAgents.contains(agent.address) },
                        set: { on in
                            if on { settings.doneNotifyAgents.insert(agent.address) } else { settings.doneNotifyAgents.remove(agent.address) }
                        }
                    ))
                }
                ForEach(projects, id: \.self) { project in
                    Toggle("Project \(Format.abbreviatePath(project))", isOn: Binding(
                        get: { settings.doneNotifyProjects.contains(project) },
                        set: { on in
                            if on { settings.doneNotifyProjects.insert(project) } else { settings.doneNotifyProjects.remove(project) }
                        }
                    ))
                }
            }

            Section("Shortcuts") {
                LabeledContent("Show agent list") { HotKeyRecorder(key: $settings.listHotKey) }
                LabeledContent("Open earliest waiting agent") { HotKeyRecorder(key: $settings.waitingHotKey) }
            }

            Section("Launch") {
                TextField("Default space id (empty = selected space)", text: $settings.defaultSpace)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .frame(minHeight: 520)
        .onAppear {
            loadScreens()
            monoFamilies = TerminalFont.monospacedFamilies
        }
    }

    private var projects: [String] {
        Array(Set(store.agents.map(\.projectPath)).union(settings.doneNotifyProjects)).sorted()
    }

    static func text(_ status: SourceStatus) -> String {
        switch status.connection {
        case .connected: status.isStale ? "Not responding" : "Connected"
        case .connecting: "Connecting…"
        case .offline: "Not running"
        }
    }

    static func color(_ status: SourceStatus) -> Color {
        status.isLive ? .green : (status.connection == .connecting ? .yellow : .gray)
    }

    private var connectionText: String {
        switch store.connection {
        case .connected: store.isStale ? "Not responding" : "Connected"
        case .connecting: "Connecting…"
        case .offline: "Disconnected"
        }
    }

    private var connectionColor: Color {
        store.isLive ? .green : (store.connection == .connecting ? .yellow : .red)
    }

    private func loadScreens() {
        screens = NSScreen.screens.map { ($0.displayID, $0.localizedName) }
    }
}

/// Click, then press the new shortcut (needs ⌘, ⌥ or ⌃). Esc cancels.
struct HotKeyRecorder: View {
    @Binding var key: HotKey
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press shortcut…" : key.display) {
            recording ? stop() : start()
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stop()
                return nil
            }
            if let hotKey = HotKey(event: event) {
                key = hotKey
                stop()
                return nil
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
