import AtollCore
import SwiftUI

/// Today's finished turns, newest first: "14:32 · Claude Code · atoll · Done · +120 −30 · last words".
/// A dot marks turns whose agent's panel hasn't been opened since; clicking a row opens that panel.
struct TodayView: View {
    let model: IslandModel
    let settings: AppSettings
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
            HStack(spacing: 10) {
                Picker("Agent", selection: $filter) {
                    Text("All agents").tag(String?.none)
                    ForEach(agentChoices, id: \.address) { choice in
                        Text(choice.name).tag(Optional(choice.address))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
                Spacer()
                let unseen = store.timeline.unseenCount
                if unseen > 0 {
                    Text("\(unseen) unseen")
                        .foregroundStyle(.secondary)
                }
                Button("Clear") {
                    filter = nil
                    store.clearTimeline()
                }
                .disabled(store.timeline.entries.isEmpty)
                .help("Forget today's entries (they are only in memory)")
            }
            .padding(12)
            Divider()
            if entries.isEmpty {
                Spacer()
                Text(emptyText)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(entries) { entry in
                    TimelineRow(entry: entry, present: !entry.gone) {
                        settings.islandVisible = true
                        model.openPanel(entry.address)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 460, minHeight: 280)
        .onChange(of: agentChoices.map(\.address)) { _, addresses in
            if let filter, !addresses.contains(filter) { self.filter = nil }
        }
    }

    private var emptyText: String {
        if !settings.todayTimeline { return "The Today timeline is off in Settings." }
        return filter == nil ? "No finished turns yet today." : "No finished turns for this agent."
    }
}

private struct TimelineRow: View {
    let entry: TimelineEntry
    /// The agent hasn't exited or left the list; a gone one's row opens nothing.
    let present: Bool
    let open: () -> Void

    /// "Claude Code · atoll"; a terminal with its own name also gets the project.
    private var name: String {
        entry.displayName.hasSuffix(" · \(entry.projectName)") ? entry.displayName : "\(entry.displayName) · \(entry.projectName)"
    }

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(entry.unseen ? Color.accentColor : .clear)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(Format.clock.string(from: entry.at))
                            .monospacedDigit()
                        Text("· \(name) ·")
                        // State colors are tuned for the dark island: only the icon carries them here.
                        Image(systemName: entry.state.symbol)
                            .foregroundStyle(entry.state.color)
                        Text(entry.state.label)
                        if let changes = entry.changes {
                            Text("· \(changes)")
                                .foregroundStyle(.secondary)
                        }
                        if !present {
                            Text("· Gone")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .lineLimit(1)
                    if let words = entry.lastWords {
                        Text(words)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .help(words)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!present)
        .help(present ? "Open \(entry.displayName)" : "This agent is no longer around")
        .accessibilityLabel([
            Format.clock.string(from: entry.at), name, entry.state.label, entry.changes, entry.lastWords,
            entry.unseen ? "unseen" : nil, present ? nil : "gone",
        ].compactMap { $0 }.joined(separator: ", "))
    }
}
