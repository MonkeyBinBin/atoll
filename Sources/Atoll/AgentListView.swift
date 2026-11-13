import AtollCore
import SwiftUI

struct AgentListView: View {
    @Bindable var model: IslandModel
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            let choices = model.spaceChoices
            // One space and nobody elsewhere: nothing to filter, unless a filter is still on.
            if choices.count > 2 || model.spaceFilter != .all {
                SpaceFilterBar(model: model, choices: choices)
                Divider().overlay(Color.white.opacity(0.08))
            }
            if model.store.agents.isEmpty {
                Text(model.store.isLive ? "No agents" : (model.offlineText ?? "Unknown"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                let ordered = model.listAgents
                let sections = SpaceGrouping.sections(model.store.agents)
                ScrollViewReader { proxy in
                    ScrollView {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            VStack(spacing: 4) {
                                if let sections {
                                    ForEach(sections) { section in
                                        SpaceHeader(section: section, filtered: model.spaceFilter == section.filter)
                                        ForEach(section.agents) { agent in
                                            card(agent, index: ordered.firstIndex { $0.address == agent.address } ?? 0, now: context.date)
                                        }
                                    }
                                } else {
                                    ForEach(Array(ordered.enumerated()), id: \.element.id) { index, agent in
                                        card(agent, index: index, now: context.date)
                                    }
                                }
                            }
                            .padding(8)
                        }
                    }
                    .frame(maxHeight: 420)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: model.selection) { _, index in
                        let agents = model.listAgents
                        guard agents.indices.contains(index) else { return }
                        withAnimation { proxy.scrollTo(agents[index].id) }
                    }
                }
            }
            Divider().overlay(Color.white.opacity(0.08))
            HStack {
                Button {
                    model.openLaunch()
                } label: {
                    Label("Launch agent", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Button {
                    model.openToday()
                } label: {
                    let unseen = model.store.timeline.unseenCount
                    Label(unseen > 0 ? "Today · \(unseen)" : "Today", systemImage: "clock")
                }
                .buttonStyle(.borderless)
                .help("Today's finished turns")
                Spacer()
                Text(model.store.agents.contains { $0.permissionChoices != nil }
                     ? "↑↓ select · ↩ open · ⌘Y allow · ⌘N deny · esc close"
                     : "↑↓ select · ↩ open · ⌘1–9 jump · esc close")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                PinButton(model: model)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear { model.validate() }
    }

    private func card(_ agent: Agent, index: Int, now: Date) -> some View {
        AgentCard(
            agent: agent,
            store: model.store,
            index: index,
            selected: index == model.selection,
            now: now,
            animate: model.animating,
            onLaunchWorktree: { model.openLaunchInWorktree(for: agent) }
        )
        .id(agent.id)
        .onTapGesture { model.openPanel(agent.address) }
    }
}

/// All / each Herdr space / Other: what the collapsed island shows (ticket 42). Tab / ⇧Tab cycles.
struct SpaceFilterBar: View {
    let model: IslandModel
    let choices: [(SpaceFilter, String)]

    var body: some View {
        let selected = model.spaceFilter
        HStack(spacing: 6) {
            Text("Island")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(choices, id: \.0) { filter, name in
                        Button {
                            model.setSpaceFilter(filter)
                        } label: {
                            Text(name)
                                .font(.system(size: 11, weight: filter == selected ? .semibold : .regular))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(filter == selected ? 0.18 : 0.05)))
                                .foregroundStyle(filter == selected ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(filter == .all
                              ? "Show every agent in the collapsed island"
                              : "Show only \(name) in the collapsed island; agents elsewhere that need you still show")
                    }
                }
            }
            Text("tab")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

/// A list section's title: the Herdr space (or Other) and how many agents it has.
struct SpaceHeader: View {
    let section: SpaceSection
    /// The collapsed island is filtered to this space.
    let filtered: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: section.filter == .other ? "square.dashed" : "square.stack")
            Text(section.name)
                .fontWeight(.semibold)
                .lineLimit(1)
            Text("\(section.agents.count)")
                .foregroundStyle(.tertiary)
            if filtered {
                Text("· island")
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct AgentCard: View {
    let agent: Agent
    let store: AgentStore
    let index: Int
    let selected: Bool
    let now: Date
    let animate: Bool
    var onLaunchWorktree: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AgentSprite(agent: agent, store: store, scale: 2)
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(agent.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if agent.state.isNeedsYou {
                        Text("Needs you")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(PixelPalette.waiting.color))
                            .foregroundStyle(.black)
                    }
                    Spacer(minLength: 4)
                    if let queued = store.queuedMessages[agent.address] {
                        QueuedBadge(queued: queued)
                    }
                    if store.notifyWhenDone.contains(agent.address) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(PixelPalette.done.color)
                            .help("Notifies when this turn finishes")
                    }
                    if index < 9 {
                        Text("⌘\(index + 1)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: agent.state.symbol)
                        .foregroundStyle(agent.state.color)
                    Text("\(agent.state.fullLabel) · \(Format.duration(since: agent.stateSince, now: now))")
                        .foregroundStyle(agent.state.color)
                    NoOutputLabel(since: agent.noOutputSince, now: now)
                    Text("· \(agent.toolName)" + (agent.whereLabel.map { " · \($0)" } ?? ""))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
                if let message = agent.lastWords {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .help(message)
                }
                if let preview = agent.waitingPreview {
                    WaitingPreviewLabel(preview: preview, lineLimit: agent.permissionChoices == nil ? 1 : 2)
                }
                if agent.permissionChoices != nil {
                    PermissionButtons(agent: agent, store: store, selected: selected)
                } else if let choices = agent.questionChoices {
                    QuestionButtons(agent: agent, choices: choices, store: store)
                } else if let response = store.permissionResponses[agent.address] {
                    PermissionResponseLabel(state: response)
                }
                if let summary = agent.changeSummary {
                    ChangeSummaryLabel(summary: summary)
                }
                SharedTreeLabel(agent: agent, store: store, onLaunchWorktree: onLaunchWorktree)
                HStack(spacing: 4) {
                    Text(Format.abbreviatePath(agent.projectPath))
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer(minLength: 4)
                    Text("Last status change \(Format.ago(agent.lastStatusChange, now: now))")
                        .lineLimit(1)
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.white.opacity(0.25) : .clear)
        )
        .opacity(agent.state == .exited ? 0.6 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// "+120 −30 · 6 files · uncommitted" with the full explanation on hover.
struct ChangeSummaryLabel: View {
    let summary: ChangeSummary
    var lineLimit = 1

    var body: some View {
        Label(summary.label, systemImage: "plus.forwardslash.minus")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(lineLimit)
            .help(summary.help)
    }
}

/// "Shares working tree with Codex · project-x"; nothing unless the agent shares one.
struct SharedTreeLabel: View {
    let agent: Agent
    let store: AgentStore
    var lineLimit = 1
    /// Offers "Launch in new worktree" (opens the launch form for the same project); nil = no button.
    var onLaunchWorktree: (() -> Void)?

    var body: some View {
        if !agent.sharedTreeWith.isEmpty {
            let names = agent.sharedTreeWith.compactMap { store.agent($0)?.displayName }
            VStack(alignment: .leading, spacing: 2) {
                Label("Shares working tree with \(names.joined(separator: ", "))", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 11))
                    .foregroundStyle(PixelPalette.waiting.color)
                    .lineLimit(lineLimit)
                    .help("Several active agents in \(Format.abbreviatePath(agent.projectPath))'s git working tree can overwrite or commit each other's changes. Separate worktrees avoid that.")
                if let onLaunchWorktree, store.worktreeCreator != nil {
                    Button("Launch in new worktree", action: onLaunchWorktree)
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                        .help("Open the launch form for this project with \"New worktree\" on; this agent keeps running")
                }
            }
        }
    }
}

/// What a Needs-you agent asks, from its screen: "Bash: rm -rf dist" over its description / options.
struct WaitingPreviewLabel: View {
    let preview: WaitingPreview
    var lineLimit = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(preview.title)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(lineLimit)
            if let detail = preview.detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(lineLimit)
            }
        }
        .help(preview.help)
    }
}

/// Allow / Deny for a recognized permission dialog, right in the list row (⌘Y / ⌘N on the selected row).
struct PermissionButtons: View {
    let agent: Agent
    let store: AgentStore
    let selected: Bool

    var body: some View {
        let response = store.permissionResponses[agent.address]
        let sending: Bool = if case .sending = response { true } else { false }
        HStack(spacing: 6) {
            button(.allow, shortcut: "⌘Y", disabled: sending)
            button(.deny, shortcut: "⌘N", disabled: sending)
            if let response {
                PermissionResponseLabel(state: response)
            }
        }
        .padding(.top, 1)
    }

    private func button(_ choice: PermissionChoice, shortcut: String, disabled: Bool) -> some View {
        Button {
            store.respond(choice, to: agent.address, episode: agent.waitingSince)
        } label: {
            HStack(spacing: 4) {
                Text(choice.label)
                if selected {
                    Text(shortcut).foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(choice == .allow ? PixelPalette.done.color : PixelPalette.error.color)
        .disabled(disabled)
        .help(choice == .allow ? "Approve this once (the dialog's plain \"Yes\")" : "Reject (the dialog's \"No\")")
    }
}

/// A recognized single-select question's options as buttons (list row and panel); the number goes to the
/// agent like a keypress, guarded by the episode the way Allow / Deny is.
struct QuestionButtons: View {
    let agent: Agent
    let choices: QuestionChoices
    let store: AgentStore

    private var tint: Color { agent.state.color }

    var body: some View {
        let response = store.permissionResponses[agent.address]
        let sending: Bool = if case .sending = response { true } else { false }
        // Wraps instead of widening the row when the labels are long.
        FlowLayout(spacing: 6, lineSpacing: 4) {
            ForEach(Array(choices.options.enumerated()), id: \.offset) { _, option in
                Button {
                    store.respond(.option(option), to: agent.address, episode: agent.waitingSince)
                } label: {
                    HStack(spacing: 5) {
                        Text(option.key)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(tint)
                        Text(AgentPanelView.chipTitle(option.label))
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(tint.opacity(0.16)))
                    .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(sending)
                .opacity(sending ? 0.5 : 1)
                .help([option.label, option.detail].compactMap { $0 }.joined(separator: "\n"))
            }
            if let response {
                PermissionResponseLabel(state: response)
            }
        }
        .padding(.top, 1)
    }
}

/// "Allow sent" / "Deny failed" / "No longer waiting".
struct PermissionResponseLabel: View {
    let state: PermissionResponseState

    var body: some View {
        let failed: Bool = switch state {
        case .failed, .noLongerWaiting: true
        default: false
        }
        Text(state.label)
            .font(.system(size: 11))
            .foregroundStyle(failed ? PixelPalette.waiting.color : .secondary)
            .help(helpText)
    }

    private var helpText: String {
        switch state {
        case .failed(_, let error): error.message
        case .noLongerWaiting: "The agent had already left that dialog, so nothing was sent."
        default: ""
        }
    }
}

/// "Queued" (or "Queued · held" once the agent errored), with the text as help.
struct QueuedBadge: View {
    let queued: QueuedMessage

    var body: some View {
        Label(queued.status == .held ? "Queued · held" : "Queued", systemImage: queued.status.symbol)
            .font(.system(size: 10))
            .foregroundStyle(queued.status.color)
            .lineLimit(1)
            .help("Queued message: \(queued.text)")
    }
}

extension QueuedMessage.Status {
    var symbol: String { self == .held ? "pause.circle.fill" : "clock.arrow.circlepath" }
    var color: Color { self == .held ? PixelPalette.error.color : PixelPalette.waiting.color }
    var title: String {
        switch self {
        case .waiting: "Queued · sends when this turn ends"
        case .held: "Queued message held · agent errored"
        case .sending: "Sending queued message…"
        }
    }
}

/// "· No output for 12m" after a Working agent's state: a fact about its screen, in the secondary colour.
struct NoOutputLabel: View {
    let since: Date?
    let now: Date

    var body: some View {
        if let since {
            Text("· No output for \(Format.duration(since: since, now: now))")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help("The screen hasn't changed since \(Format.clockSeconds.string(from: since)).")
        }
    }
}

/// Keeps the expanded island open when clicking elsewhere (until it's closed on purpose).
struct PinButton: View {
    @Bindable var model: IslandModel

    var body: some View {
        Button {
            model.pinned.toggle()
        } label: {
            Image(systemName: model.pinned ? "pin.fill" : "pin")
                .foregroundStyle(model.pinned ? AnyShapeStyle(PixelPalette.waiting.color) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.borderless)
        .help(model.pinned
            ? "Pinned: stays open when you click elsewhere · click to unpin"
            : "Pin: stay open when clicking outside the island")
    }
}
