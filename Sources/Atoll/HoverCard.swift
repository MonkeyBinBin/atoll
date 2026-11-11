import AppKit
import AtollCore
import SwiftUI

/// Info card shown under a character when the mouse rests on it in the collapsed island.
/// Lives in its own click-through window so the island itself never resizes.
@MainActor
final class HoverCardController {
    private let model: IslandModel
    private weak var island: NSWindow?
    private let panel: NSPanel
    private let host: NSHostingView<AnyView>
    private var showTask: DispatchWorkItem?

    static let width: CGFloat = 280

    init(model: IslandModel, island: NSWindow, settings: AppSettings) {
        self.model = model
        self.island = island
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: island.level.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none
        host = NSHostingView(rootView: AnyView(EmptyView()))
        panel.contentView = host
        trackChanges { [weak self] in self?.update() }
    }

    private func update() {
        let hover = model.hover
        let agent = hover.flatMap { model.store.agent($0.address) }
        showTask?.cancel()
        guard let hover, let agent, !model.isExpanded, let island else {
            panel.orderOut(nil)
            return
        }
        host.rootView = AnyView(
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HoverCardView(agent: agent, now: context.date)
            }
            .environment(\.colorScheme, .dark)
        )
        let size = host.fittingSize
        let anchorX = island.frame.minX + hover.anchor.midX
        let top = island.frame.minY - 6
        let screen = island.screen?.frame ?? island.frame
        let x = min(max(anchorX - Self.width / 2, screen.minX + 8), screen.maxX - Self.width - 8)
        let frame = NSRect(x: x.rounded(), y: (top - size.height).rounded(), width: Self.width, height: size.height.rounded(.up))
        // A short delay so sweeping across the row doesn't flash cards.
        let alreadyVisible = panel.isVisible
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.panel.setFrame(frame, display: true)
            self.panel.orderFrontRegardless()
        }
        showTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + (alreadyVisible ? 0 : 0.25), execute: task)
    }
}

struct HoverCardView: View {
    let agent: Agent
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(agent.displayName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: agent.state.symbol)
                Text("\(agent.state.fullLabel) · \(Format.duration(since: agent.stateSince, now: now))")
            }
            .font(.system(size: 11))
            .foregroundStyle(agent.state.color)
            if let message = agent.statusMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let summary = agent.changeSummary {
                ChangeSummaryLabel(summary: summary, lineLimit: 2)
            }
            Text(Format.abbreviatePath(agent.projectPath) + (agent.whereLabel.map { " · \($0)" } ?? ""))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            HStack {
                Text("Last status change \(Format.ago(agent.lastStatusChange, now: now))")
                Spacer()
                Text("Click to open")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(width: HoverCardController.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.1)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.12)))
    }
}
