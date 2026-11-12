import AppKit
import AtollCore
import SwiftUI

/// Pops a speech bubble under a character in the collapsed island when its agent stops or needs the user.
/// One bubble at a time (slots are narrower than a bubble): Needs you / Error pre-empt, the rest queue.
/// Lives in its own window so the island never resizes; clicking the bubble opens that agent's panel.
@MainActor
final class SpeechBubbleController {
    private let model: IslandModel
    private let settings: AppSettings
    private weak var island: NSWindow?
    private let panel: NSPanel
    private let host: FirstMouseHostingView<SpeechBubbleView>
    private var rules = BubbleRules()
    private var current: AgentBubble?
    private var queue: [AgentBubble] = []
    private var expiry: DispatchWorkItem?
    /// Key of the bubble currently on screen; nil while hidden.
    private var shownKey: String?

    static let duration: TimeInterval = 5
    /// Gap between the island's bottom edge and the bubble's tail tip.
    static let gap: CGFloat = 2

    init(model: IslandModel, island: NSWindow, settings: AppSettings) {
        self.model = model
        self.settings = settings
        self.island = island
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: island.level.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none
        host = FirstMouseHostingView(rootView: SpeechBubbleView(key: "", state: .unknown, kind: .state, detail: nil, message: nil, tailX: 0, animate: false, onTap: {}))
        panel.contentView = host
        trackChanges { [weak self] in self?.update() }
    }

    /// Feed every store transition; the rules decide whether it bubbles.
    func handle(_ agent: Agent, from previous: AgentState?) {
        // Always consult the rules so their dedupe memory stays current while bubbles are suppressed.
        guard let bubble = rules.bubble(for: agent, from: previous) else { return }
        // Full screen, attention only: no character to point at for the others.
        guard model.showsInCollapsedIsland(agent.address) else { return }
        enqueue(bubble)
    }

    /// Another active agent already works in this agent's git working tree (the store dedupes).
    func sharedTree(_ agent: Agent) {
        guard model.showsInCollapsedIsland(agent.address) else { return }
        enqueue(AgentBubble(address: agent.address, state: agent.state, key: "shared#\(UUID().uuidString)", kind: .sharedTree))
    }

    /// A queued message went out when the turn ended.
    func queuedSent(_ agent: Agent) {
        guard model.showsInCollapsedIsland(agent.address) else { return }
        enqueue(AgentBubble(address: agent.address, state: agent.state, key: "queued#\(UUID().uuidString)", kind: .queuedSent))
    }

    /// Re-announce an agent still waiting past the reminder delay; its own key so it shows again.
    func remind(_ agent: Agent) {
        guard model.showsInCollapsedIsland(agent.address) else { return }
        let since = Int(agent.waitingSince?.timeIntervalSince1970 ?? 0)
        enqueue(AgentBubble(address: agent.address, state: agent.state, key: "reminder#\(agent.turn)#\(since)"))
    }

    /// Debug: bubble an agent's current state regardless of the rules.
    func force(_ address: String) {
        guard let agent = model.store.agent(address) else { return }
        enqueue(AgentBubble(address: address, state: agent.state, key: "debug-\(Date().timeIntervalSince1970)"))
    }

    /// The island window moved or resized.
    func reposition() { update() }

    private var suppressed: Bool {
        !settings.speechBubbles || !settings.islandVisible || model.isExpanded || model.hiddenByFullScreen
    }

    private func enqueue(_ bubble: AgentBubble) {
        guard !suppressed else { return }
        queue.removeAll { $0.address == bubble.address }
        if current?.address == bubble.address {
            current = nil
        } else if let shown = current, bubble.isUrgent, !shown.isUrgent {
            queue.insert(shown, at: 0)
            current = nil
        }
        // Urgent ones go after other urgent ones, ahead of the rest.
        let index = bubble.isUrgent ? (queue.firstIndex { !$0.isUrgent } ?? queue.count) : queue.count
        queue.insert(bubble, at: index)
        if current == nil { advance() }
        update()
    }

    private func isStillTrue(_ bubble: AgentBubble) -> Bool {
        bubble.stillApplies(to: model.store.agent(bubble.address))
    }

    private func advance() {
        expiry?.cancel()
        current = nil
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if isStillTrue(next) {
                current = next
                break
            }
        }
        guard let shown = current else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.current?.key == shown.key else { return }
            self.advance()
            self.update()
        }
        expiry = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration, execute: task)
    }

    private func dismissAll() {
        expiry?.cancel()
        current = nil
        queue.removeAll()
    }

    private func update() {
        // Read everything that should re-run this, before any early return.
        let anchors = model.characterAnchors
        let hover = model.hover
        let agents = model.store.agents
        if suppressed {
            dismissAll()
            hide()
            return
        }
        if let shown = current {
            let stale = !shown.stillApplies(to: agents.first { $0.address == shown.address })
            // A hover card takes the same spot under the island; hovering the bubble's own character means
            // the user is already looking.
            if stale || hover?.address == shown.address { advance() }
        }
        guard hover == nil, let shown = current, let island, let anchor = anchors[shown.address],
              // Scrolled out of the right wing: no character to point at.
              anchor.midX > 0, anchor.midX < island.frame.width else {
            hide()
            return
        }
        let isNew = shownKey != shown.key
        let animate = settings.animationsEnabled
        // A stopped agent's change counts (numbers only, no paths), once git has answered.
        let shownAgent = agents.first { $0.address == shown.address }
        let detail: String?
        if shown.kind == .queuedSent {
            detail = nil
        } else if shown.kind == .sharedTree {
            // Names only (tool · project or terminal name), like everywhere else a target is named.
            detail = shownAgent.map { agent in
                "with " + agent.sharedTreeWith.compactMap { other in agents.first { $0.address == other }?.displayName }.joined(separator: ", ")
            }
        } else {
            detail = switch shown.state {
            case .done, .idle, .exited: shownAgent?.changeSummary?.text
            default: nil
            }
        }
        // What the agent said last: the source's summary, else the line read off its screen.
        let message: String? = if shown.kind == .state, [.done, .idle, .exited].contains(shown.state), let shownAgent {
            // One row: the closing line.
            shownAgent.lastWords?.split(separator: "\n").last.map(String.init)
        } else {
            nil
        }
        var view = SpeechBubbleView(key: shown.key, state: shown.state, kind: shown.kind, detail: detail, message: message,
                                    tailX: 0, animate: animate) { [weak self] in
            guard let self else { return }
            self.dismissAll()
            self.hide()
            self.model.hover = nil
            self.model.openPanel(shown.address)
        }
        host.rootView = view
        let size = host.fittingSize
        let anchorX = island.frame.minX + anchor.midX
        let top = island.frame.minY - Self.gap
        let screen = island.screen?.frame ?? island.frame
        let width = size.width.rounded(.up)
        let x = min(max(anchorX - width / 2, screen.minX + 8), screen.maxX - width - 8).rounded()
        view.tailX = min(max(anchorX - x, SpeechBubbleView.radius + 4), width - SpeechBubbleView.radius - 4)
        host.rootView = view
        let frame = NSRect(x: x, y: (top - size.height).rounded(), width: width, height: size.height.rounded(.up))
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if isNew || !panel.isVisible {
            shownKey = shown.key
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    private func hide() {
        guard panel.isVisible else {
            shownKey = nil
            return
        }
        shownKey = nil
        guard settings.animationsEnabled else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.shownKey == nil else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        }
    }
}

struct SpeechBubbleView: View {
    let key: String
    let state: AgentState
    var kind: AgentBubble.Kind = .state
    var detail: String?
    /// A second row: the agent's last words for a finished turn.
    var message: String?
    /// Tail position from the bubble's leading edge, pointing up at the character.
    var tailX: CGFloat
    let animate: Bool
    let onTap: () -> Void

    static let radius: CGFloat = 8
    static let tailHeight: CGFloat = 6

    var body: some View {
        // A new identity per bubble so each one pops in.
        SpeechBubbleBody(state: state, kind: kind, detail: detail, message: message, tailX: tailX, animate: animate, onTap: onTap)
            .id(key)
    }
}

private struct SpeechBubbleBody: View {
    let state: AgentState
    let kind: AgentBubble.Kind
    let detail: String?
    let message: String?

    private var symbol: String {
        switch kind {
        case .sharedTree: "arrow.triangle.branch"
        case .queuedSent: "paperplane.fill"
        case .state: state.symbol
        }
    }
    private var title: String {
        switch kind {
        case .sharedTree: "Shared working tree"
        case .queuedSent: "Queued message sent"
        case .state: state.fullLabel
        }
    }
    private var color: Color {
        switch kind {
        case .sharedTree: PixelPalette.waiting.color
        case .queuedSent: PixelPalette.done.color
        case .state: state.color
        }
    }
    let tailX: CGFloat
    let animate: Bool
    let onTap: () -> Void
    @State private var shown = false

    var body: some View {
        let shape = BubbleShape(tailX: tailX, tailHeight: SpeechBubbleView.tailHeight, radius: SpeechBubbleView.radius)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(title)
                    .lineLimit(1)
                if let detail {
                    Text("· \(detail)")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
            if let message {
                // The bubble sizes to its content, so a long line is cut here rather than by layout.
                Text(OutputFilter.cut(message, limit: 60))
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .padding(.top, SpeechBubbleView.tailHeight)
        .fixedSize()
        .background(shape.fill(Color(white: 0.1)))
        .overlay(shape.stroke(color.opacity(0.7), lineWidth: 1))
        .contentShape(shape)
        .scaleEffect(shown || !animate ? 1 : 0.6, anchor: UnitPoint(x: 0.5, y: 0))
        .opacity(shown || !animate ? 1 : 0)
        .onAppear {
            withAnimation(.spring(duration: 0.28, bounce: 0.4)) { shown = true }
        }
        .onTapGesture(perform: onTap)
        .environment(\.colorScheme, .dark)
        .accessibilityElement()
        .accessibilityLabel([title, detail, message].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}

/// Rounded rectangle with a small tail on the top edge.
struct BubbleShape: Shape {
    var tailX: CGFloat
    var tailHeight: CGFloat
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        // Inset by half the stroke so the outline isn't clipped at the window edge.
        let rect = rect.insetBy(dx: 0.5, dy: 0.5)
        let body = CGRect(x: rect.minX, y: rect.minY + tailHeight, width: rect.width, height: rect.height - tailHeight)
        let r = min(radius, body.height / 2)
        let tip = min(max(rect.minX + tailX, body.minX + r + tailHeight), body.maxX - r - tailHeight)
        var p = Path()
        p.move(to: CGPoint(x: body.minX + r, y: body.minY))
        p.addLine(to: CGPoint(x: tip - tailHeight, y: body.minY))
        p.addLine(to: CGPoint(x: tip, y: rect.minY))
        p.addLine(to: CGPoint(x: tip + tailHeight, y: body.minY))
        p.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.minY + r), radius: r)
        p.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY), tangent2End: CGPoint(x: body.maxX - r, y: body.maxY), radius: r)
        p.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        p.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.maxY - r), radius: r)
        p.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        p.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY), tangent2End: CGPoint(x: body.minX + r, y: body.minY), radius: r)
        p.closeSubpath()
        return p
    }
}
