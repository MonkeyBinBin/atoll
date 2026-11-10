import IslandCore
import SwiftUI

struct AgentListView: View {
    @Bindable var model: IslandModel
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            if model.store.agents.isEmpty {
                Text(model.store.isLive ? "No agents" : (model.offlineText ?? "Unknown"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            VStack(spacing: 4) {
                                ForEach(Array(model.store.agents.enumerated()), id: \.element.id) { index, agent in
                                    AgentCard(
                                        agent: agent,
                                        store: model.store,
                                        index: index,
                                        selected: index == model.selection,
                                        now: context.date,
                                        animate: settings.animationsEnabled
                                    )
                                    .id(agent.id)
                                    .onTapGesture { model.openPanel(agent.address) }
                                }
                            }
                            .padding(8)
                        }
                    }
                    .frame(maxHeight: 420)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: model.selection) { _, index in
                        guard model.store.agents.indices.contains(index) else { return }
                        withAnimation { proxy.scrollTo(model.store.agents[index].id) }
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
                Spacer()
                Text("↑↓ select · ↩ open · ⌘1–9 jump · esc close")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear { model.validate() }
    }
}

struct AgentCard: View {
    let agent: Agent
    let store: AgentStore
    let index: Int
    let selected: Bool
    let now: Date
    let animate: Bool

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
                    Text("· \(agent.toolName)" + (agent.whereLabel.map { " · \($0)" } ?? ""))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
                if let message = agent.statusMessage {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
