import AtollCore
import SwiftUI

/// Today's finished turns as an island pane, newest first: "14:32 · Claude Code · atoll · Done · +120 −30",
/// with the last words below. A dot marks turns whose agent's panel hasn't been opened since; clicking a
/// row opens that panel.
struct TodayView: View {
    @Bindable var model: IslandModel
    @Environment(AppSettings.self) private var settings
    /// nil = all agents.
    @State private var filter: String?

    private var store: AgentStore { model.store }

    private var entries: [TimelineEntry] {
        store.timeline.entries.reversed().filter { filter == nil || $0.address == filter }
    }

    /// One choice per agent seen today, labelled as everywhere else.
    private var agentChoices: [(address: String, name: String)] {
        var seen = Set<String>()
        return store.timeline.entries.reversed().compactMap { entry in
            seen.insert(entry.address).inserted ? (entry.address, entry.displayName) : nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider().overlay(Color.white.opacity(0.08))
            if entries.isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(entries) { entry in
                            TimelineRow(entry: entry) { model.openPanel(entry.address) }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 420)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: agentChoices.map(\.address)) { _, addresses in
            if let filter, !addresses.contains(filter) { self.filter = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Today").font(.system(size: 13, weight: .semibold))
            let unseen = store.timeline.unseenCount
            if unseen > 0 {
                Text("\(unseen) unseen")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Agent", selection: $filter) {
                Text("All agents").tag(String?.none)
                ForEach(agentChoices, id: \.address) { choice in
                    Text(choice.name).tag(Optional(choice.address))
                }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(agentChoices.isEmpty)
            Button("Clear") {
                filter = nil
                store.clearTimeline()
            }
            .buttonStyle(.borderless)
            .disabled(store.timeline.entries.isEmpty)
            .help("Forget today's entries (they are only in memory)")
            PinButton(model: model)
            Button { model.escape() } label: { Image(systemName: "list.bullet") }
                .buttonStyle(.borderless)
                .help("Back to agent list (esc)")
        }
        .font(.system(size: 11))
    }

    private var emptyText: String {
        if !settings.todayTimeline { return "The Today timeline is off in Settings." }
        return filter == nil ? "No finished turns yet today." : "No finished turns for this agent."
    }
}

private struct TimelineRow: View {
    let entry: TimelineEntry
    let open: () -> Void
    @State private var hovered = false

    /// "Claude Code · atoll"; a terminal with its own name also gets the project.
    private var name: String {
        entry.displayName.hasSuffix(" · \(entry.projectName)") ? entry.displayName : "\(entry.displayName) · \(entry.projectName)"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(entry.unseen ? Color.accentColor : .clear)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(Format.clock.string(from: entry.at))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: entry.state.symbol)
                        .foregroundStyle(entry.state.color)
                    Text(entry.state.label)
                        .foregroundStyle(entry.state.color)
                    if let changes = entry.changes {
                        Text("· \(changes)")
                            .foregroundStyle(.secondary)
                    }
                    if entry.gone {
                        Text("· Gone")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 12))
                .lineLimit(1)
                if let words = entry.lastWords {
                    Text(words)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .help(words)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(hovered && !entry.gone ? 0.08 : 0.04))
        )
        .opacity(entry.gone ? 0.55 : 1)
        .contentShape(Rectangle())
        // Gone: the agent exited or left the list, so there is no panel to open.
        .onTapGesture { if !entry.gone { open() } }
        .onHover { hovered = $0 }
        .help(entry.gone ? "This agent is no longer around" : "Open \(entry.displayName)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([
            Format.clock.string(from: entry.at), name, entry.state.label, entry.changes, entry.lastWords,
            entry.unseen ? "unseen" : nil, entry.gone ? "gone" : nil,
        ].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(entry.gone ? [] : .isButton)
    }
}
