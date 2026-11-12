import AppKit
import AtollCore
import Observation

/// Where the island sits on its screen.
struct ScreenGeometry: Equatable {
    var screenFrame: CGRect
    var hasNotch: Bool
    /// Notch rect in screen coordinates (zero width without a notch).
    var notchMinX: CGFloat
    var notchWidth: CGFloat
    /// Height of the top band (notch or menu bar).
    var barHeight: CGFloat
    /// Room on each side of the notch.
    var leftRoom: CGFloat
    var rightRoom: CGFloat

    static func of(_ screen: NSScreen) -> ScreenGeometry {
        let frame = screen.frame
        let menuBar = max(frame.maxY - screen.visibleFrame.maxY, 24)
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            // Derived from widths only, independent of which coordinate space the rects use.
            let notchMinX = frame.minX + left.width
            let notchWidth = frame.width - left.width - right.width
            return ScreenGeometry(
                screenFrame: frame, hasNotch: true, notchMinX: notchMinX, notchWidth: notchWidth,
                barHeight: screen.safeAreaInsets.top, leftRoom: left.width, rightRoom: right.width
            )
        }
        return ScreenGeometry(
            screenFrame: frame, hasNotch: false, notchMinX: frame.midX, notchWidth: 0,
            barHeight: min(menuBar, 30), leftRoom: frame.width / 2, rightRoom: frame.width / 2
        )
    }
}

/// Collapsed-row layout: widths computed explicitly so the window can hug the island.
struct IslandLayout: Equatable {
    var pinned: [Agent]
    var others: [Agent]
    var hint: String?
    var leftWidth: CGFloat
    var rightWidth: CGFloat
    var centerWidth: CGFloat
    var height: CGFloat
    var rightScrolls: Bool
    /// Extra inset at the outer ends of a floating capsule so content clears its rounding.
    var endInset: CGFloat = 0

    static let slot: CGFloat = 22
    /// Always-visible buttons (launch, list) at the outer end of the right wing.
    static let buttonWidth: CGFloat = 20
    static let buttonsWidth: CGFloat = buttonWidth * 2
    static let padding: CGFloat = 10
    nonisolated(unsafe) static let hintFont = NSFont.systemFont(ofSize: 11, weight: .semibold)

    var collapsedWidth: CGFloat { leftWidth + centerWidth + rightWidth }

    static func compute(agents: [Agent], geometry: ScreenGeometry, offlineText: String?) -> IslandLayout {
        let pinned = agents.filter { $0.state.needsAttention }
        let others = agents.filter { !$0.state.needsAttention }
        var hint: String?
        if let offlineText {
            hint = offlineText
        } else if let first = pinned.first {
            let verb = first.state.isNeedsYou ? "needs you" : "has an error"
            hint = "\(first.displayName) \(verb)" + (pinned.count > 1 ? " +\(pinned.count - 1)" : "")
        }
        let hintWidth = hint.map { ceil(($0 as NSString).size(withAttributes: [.font: hintFont]).width) + 8 } ?? 0
        let maxSide = geometry.hasNotch ? min(geometry.leftRoom, geometry.rightRoom) - 40 : 360
        var left = pinned.isEmpty && hint == nil ? 0 : padding * 2 + CGFloat(pinned.count) * slot + hintWidth
        left = min(left, maxSide)
        let othersWidth = CGFloat(others.count) * slot + padding * 2
        let rightMax = min(maxSide, 8 * slot + padding * 2)
        var right = others.isEmpty ? 0 : min(othersWidth, rightMax)
        if agents.isEmpty, offlineText == nil {
            // Minimal capsule with the empty-island icon.
            right = slot + padding * 2
            left = geometry.hasNotch ? padding : 0
        }
        if geometry.hasNotch {
            left = max(left, padding)
            right = max(right, padding)
        }
        right += buttonsWidth
        let center: CGFloat = geometry.hasNotch ? geometry.notchWidth : (left > 0 && right > 0 ? 6 : 0)
        let height = geometry.hasNotch ? geometry.barHeight : max(geometry.barHeight - 4, 22)
        let endInset = geometry.hasNotch ? 0 : max(height / 2 - padding, 0)
        if left > 0 { left += endInset }
        if right > 0 { right += endInset }
        return IslandLayout(
            pinned: pinned, others: others, hint: hint,
            leftWidth: left, rightWidth: right, centerWidth: center,
            height: height,
            rightScrolls: othersWidth > rightMax,
            endInset: endInset
        )
    }
}

/// UI navigation state for the island: collapsed row, list, panel or launch form.
@MainActor
@Observable
final class IslandModel {
    enum Mode: Equatable {
        case collapsed
        case list
        case panel(String)
        case launch
    }

    let store: AgentStore
    let settings: AppSettings
    var mode: Mode = .collapsed {
        didSet {
            guard mode != oldValue else { return }
            hover = nil
            allClear = false
            // Leaving a panel (by any route) drops its output: it lives only while the panel is open.
            if case .panel = oldValue {
                if case .panel = mode {} else { store.closePanel() }
            }
            onModeChange?(mode)
        }
    }
    var selection = 0

    /// A character under the mouse in the collapsed island; anchor is in window coordinates (top-left origin).
    struct Hover: Equatable {
        var address: String
        var anchor: CGRect
    }

    var hover: Hover?
    /// Where each character currently sits in the island window (top-left origin); anchors speech bubbles.
    var characterAnchors: [String: CGRect] = [:]
    var geometry: ScreenGeometry?
    /// Measured height of the expanded content (below the top row).
    var expandedContentHeight: CGFloat = 0
    @ObservationIgnored var onModeChange: ((Mode) -> Void)?
    /// The island's screen is showing a full-screen app.
    var fullScreen = false

    /// What the collapsed island shows given full screen; nil = hidden.
    var collapsedAgents: [Agent]? {
        FullScreenPresence.collapsedAgents(store.agents, fullScreen: fullScreen, mode: settings.fullScreenMode)
    }

    /// Collapsed and nothing to show in full screen: the island steps aside (hotkeys still expand it).
    var hiddenByFullScreen: Bool { mode == .collapsed && collapsedAgents == nil }

    func showsInCollapsedIsland(_ address: String) -> Bool {
        collapsedAgents?.contains { $0.address == address } ?? false
    }

    /// ⌘⇧1–5 in a panel: which quick reply to send. The panel performs it so it shares the reply
    /// box's send path (and its Resend memory); the token makes repeats of the same index distinct.
    struct QuickReplyRequest: Equatable {
        var index: Int
        var token: Int
    }

    private(set) var quickReplyRequest: QuickReplyRequest?

    func requestQuickReply(_ index: Int) {
        guard case .panel = mode, settings.quickReplies.indices.contains(index) else { return }
        quickReplyRequest = QuickReplyRequest(index: index, token: (quickReplyRequest?.token ?? 0) + 1)
    }

    /// Keys the focused text box's command suggestions take while shown. The key monitor sees them
    /// before the field editor (which would eat ↑↓ and Return); the box performs them.
    enum CompletionKey: Equatable {
        case previous, next, complete, accept, dismiss
    }

    struct CompletionKeyRequest: Equatable {
        var key: CompletionKey
        var token: Int
    }

    /// Set by the focused reply/task box while it shows suggestions.
    var completionActive = false
    private(set) var completionKeyRequest: CompletionKeyRequest?

    func requestCompletionKey(_ key: CompletionKey) {
        completionKeyRequest = CompletionKeyRequest(key: key, token: (completionKeyRequest?.token ?? 0) + 1)
    }

    /// The open panel's reply box holds unsent text: auto-advance must not yank it away.
    var panelHasDraft = false
    /// Briefly true after the last waiting agent was answered.
    private(set) var allClear = false
    @ObservationIgnored private var allClearTask: Task<Void, Never>?

    static let expandedWidth: CGFloat = 480
    static let largePanelWidth: CGFloat = 960

    /// Width of the expanded island: wider for a panel in large mode.
    func expandedWidth(_ layout: IslandLayout) -> CGFloat {
        var base = Self.expandedWidth
        if case .panel = mode, settings.largePanel { base = Self.largePanelWidth }
        if let geometry { base = min(base, geometry.screenFrame.width - 16) }
        return max(base, layout.centerWidth + 2 * max(layout.leftWidth, layout.rightWidth))
    }

    init(store: AgentStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    var isExpanded: Bool { mode != .collapsed }

    var offlineText: String? {
        guard !store.isLive else { return nil }
        if store.compatibilityWarning != nil, store.connection == .offline { return "herdr-core incompatible · see Settings" }
        if store.connection == .connecting && store.lastUpdate == nil { return "Connecting to Herdr…" }
        let last = store.lastUpdate.map { Format.clock.string(from: $0) } ?? "never"
        return "Herdr offline · Last updated \(last)"
    }

    var layout: IslandLayout {
        let geometry = geometry ?? ScreenGeometry(
            screenFrame: .zero, hasNotch: false, notchMinX: 0, notchWidth: 0, barHeight: 28, leftRoom: 400, rightRoom: 400
        )
        let agents = mode == .collapsed ? collapsedAgents ?? [] : store.agents
        return IslandLayout.compute(agents: agents, geometry: geometry, offlineText: offlineText)
    }

    // MARK: Intents

    func toggleList() {
        mode = mode == .collapsed ? .list : .collapsed
        clampSelection()
    }

    func showList() {
        mode = .list
        clampSelection()
    }

    func openPanel(_ address: String) {
        if let index = store.agents.firstIndex(where: { $0.address == address }) { selection = index }
        mode = .panel(address)
        store.openPanel(address)
    }

    func openLaunch() {
        store.closePanel()
        store.resetLaunch()
        mode = .launch
    }

    func collapse() {
        store.closePanel()
        mode = .collapsed
    }

    /// Esc: panel → list → collapsed (launch form → collapsed).
    func escape() {
        switch mode {
        case .panel:
            store.closePanel()
            mode = .list
        case .list, .launch:
            collapse()
        case .collapsed:
            break
        }
    }

    func moveSelection(_ delta: Int) {
        guard !store.agents.isEmpty else { return }
        selection = min(max(selection + delta, 0), store.agents.count - 1)
    }

    func openSelected() {
        guard store.agents.indices.contains(selection) else { return }
        openPanel(store.agents[selection].address)
    }

    /// ⌘Y / ⌘N on the selected row: answer its permission dialog without opening the panel.
    func respondToSelected(_ choice: PermissionChoice) {
        guard mode == .list, store.agents.indices.contains(selection) else { return }
        let agent = store.agents[selection]
        guard agent.permissionChoices != nil else { return }
        store.respond(choice, to: agent.address, episode: agent.waitingSince)
    }

    /// ⌘1–⌘9
    func jump(to number: Int) {
        let index = number - 1
        guard store.agents.indices.contains(index) else { return }
        selection = index
        openPanel(store.agents[index].address)
    }

    /// Store: the answered agent settled; open the next waiting one unless the user is mid-typing.
    func autoAdvance(to next: String) {
        guard case .panel = mode, !panelHasDraft else { return }
        openPanel(next)
    }

    /// ⌘]: the earliest waiting agent other than the open one.
    func openNextWaiting() {
        guard case .panel(let current) = mode, let next = store.nextWaitingAgent(excluding: current) else { return }
        openPanel(next.address)
    }

    func showAllClear() {
        guard case .panel = mode else { return }
        allClear = true
        allClearTask?.cancel()
        allClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.allClear = false
        }
    }

    /// Second global shortcut: the agent that started waiting first. No-op when nobody waits.
    func openEarliestWaiting() {
        guard let agent = store.earliestWaitingAgent else { return }
        openPanel(agent.address)
    }

    private func clampSelection() {
        selection = min(max(selection, 0), max(store.agents.count - 1, 0))
    }

    /// Keep the panel valid if its agent disappears.
    func validate() {
        if case .panel(let address) = mode, store.agent(address) == nil {
            store.closePanel()
            mode = .list
        }
        clampSelection()
    }
}
