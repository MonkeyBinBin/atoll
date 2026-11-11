import AppKit
import AtollCore
import SwiftUI

/// Re-runs `apply` whenever observable state it reads changes.
@MainActor
func trackChanges(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking {
        apply()
    } onChange: {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { trackChanges(apply) }
        }
    }
}

/// Clicks land on the first try even though the panel isn't key yet.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Borderless, non-activating panel above the menu bar that can still take keys when expanded.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class IslandController {
    private let model: IslandModel
    private let settings: AppSettings
    private let panel: IslandPanel
    private var keyMonitor: Any?
    private var outsideClickMonitors: [Any] = []
    private var previousApp: NSRunningApplication?
    private var debugHook: DebugHook?
    private var hoverCard: HoverCardController?
    private var bubbles: SpeechBubbleController?
    private var fullScreenDetector: FullScreenDetector?
    private var currentScreen: NSScreen?
    private var followMouseTimer: Timer?

    init(model: IslandModel, settings: AppSettings, client: HerdrClient) {
        self.model = model
        self.settings = settings
        panel = IslandPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        let host = FirstMouseHostingView(rootView: IslandView(model: model).environment(settings).environment(\.herdrClient, client))
        host.sizingOptions = []
        panel.contentView = host

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshScreen() }
        }
        model.onModeChange = { [weak self] mode in self?.modeChanged(mode) }
        fullScreenDetector = FullScreenDetector { [weak self] in self?.checkFullScreen() }
        followMouseTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followMouse() }
        }
        refreshScreen()
        debugHook = DebugHook(panel: panel, model: model)
        hoverCard = HoverCardController(model: model, island: panel, settings: settings)
        bubbles = SpeechBubbleController(model: model, island: panel, settings: settings)
        debugHook?.onBubble = { [weak self] address in self?.bubbles?.force(address) }
        trackChanges { [weak self] in self?.updateFrame() }
        trackChanges { [weak self] in self?.applyVisibility() }
    }

    func refreshScreen() {
        let screen = targetScreen()
        currentScreen = screen
        model.geometry = ScreenGeometry.of(screen)
        updateFrame()
        fullScreenDetector?.scheduleChecks()
    }

    private func checkFullScreen() {
        guard let currentScreen else { return }
        let value = FullScreenDetector.isFullScreen(currentScreen)
        if model.fullScreen != value { model.fullScreen = value }
    }

    /// Follow mouse: move to the screen under the pointer, but never while expanded.
    private func followMouse() {
        guard settings.displayID == AppSettings.followMouseDisplay, !model.isExpanded,
              let screen = Self.screenUnderMouse(), screen.displayID != currentScreen?.displayID else { return }
        refreshScreen()
    }

    private static func screenUnderMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    private func targetScreen() -> NSScreen {
        let screens = NSScreen.screens
        if settings.displayID == AppSettings.followMouseDisplay, let screen = Self.screenUnderMouse() {
            return screen
        }
        if settings.displayID != 0,
           let match = screens.first(where: { $0.displayID == settings.displayID }) {
            return match
        }
        // Not NSScreen.main: that follows the key window and would make the island hop between displays.
        // screens[0] is the primary display (the one with the menu bar).
        return screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? screens[0]
    }

    private func applyVisibility() {
        if !settings.islandVisible {
            model.collapse()
            panel.orderOut(nil)
        } else if model.hiddenByFullScreen {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func updateFrame() {
        guard let geometry = model.geometry else { return }
        let layout = model.layout
        let expanded = model.isExpanded
        let contentHeight = model.expandedContentHeight
        var width = layout.collapsedWidth
        var height = layout.height
        let centerX = geometry.hasNotch ? geometry.notchMinX + geometry.notchWidth / 2 : geometry.screenFrame.midX
        var x: CGFloat
        if expanded {
            width = model.expandedWidth(layout)
            height = layout.height + contentHeight
            x = centerX - width / 2
        } else if geometry.hasNotch {
            x = geometry.notchMinX - layout.leftWidth
        } else {
            x = centerX - width / 2
        }
        let topInset: CGFloat = geometry.hasNotch ? 0 : 2
        let y = geometry.screenFrame.maxY - topInset - height
        x = min(max(x, geometry.screenFrame.minX), geometry.screenFrame.maxX - width)
        let frame = NSRect(x: x.rounded(), y: y.rounded(), width: width.rounded(.up), height: height.rounded(.up))
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        bubbles?.reposition()
    }

    /// Store transitions: speech bubbles over the characters.
    func handleTransition(_ agent: Agent, from previous: AgentState?) {
        bubbles?.handle(agent, from: previous)
    }

    /// Store reminder: bubble the still-waiting agent again.
    func handleReminder(_ agent: Agent) {
        bubbles?.remind(agent)
    }


    // MARK: Keys

    private func modeChanged(_ mode: IslandModel.Mode) {
        if mode == .collapsed {
            removeKeyMonitor()
            removeOutsideClickMonitors()
            if panel.isKeyWindow {
                panel.resignKey()
                // We never activated: hand keyboard focus back to the app that had it.
                previousApp?.activate()
            }
        } else {
            if !panel.isKeyWindow {
                previousApp = NSWorkspace.shared.frontmostApplication
                panel.makeKeyAndOrderFront(nil)
            }
            installKeyMonitor()
            installOutsideClickMonitors()
        }
        updateFrame()
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            nonisolated(unsafe) let unsafeEvent = event
            let handled = MainActor.assumeIsolated { self.handleKey(unsafeEvent) }
            return handled ? nil : event
        }
    }

    /// Expanded: a click anywhere outside the island (other apps, or our other windows) collapses it.
    private func installOutsideClickMonitors() {
        guard outsideClickMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.collapseFromOutside() }
        }) {
            outsideClickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            nonisolated(unsafe) let unsafeEvent = event
            MainActor.assumeIsolated {
                guard let self, unsafeEvent.window !== self.panel else { return }
                self.collapseFromOutside()
            }
            return event
        }) {
            outsideClickMonitors.append(local)
        }
    }

    private func removeOutsideClickMonitors() {
        outsideClickMonitors.forEach(NSEvent.removeMonitor)
        outsideClickMonitors.removeAll()
    }

    private func collapseFromOutside() {
        // Not while a modal (e.g. the Finder folder picker of the launch form) is up.
        guard NSApp.modalWindow == nil, model.isExpanded else { return }
        model.collapse()
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// kVK_ANSI_1…5: matched by key code because Shift turns the characters into !@#$%.
    private static let quickReplyKeyCodes: [UInt16] = [18, 19, 20, 21, 23]

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.window === panel else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 { // Esc
            model.escape()
            return true
        }
        if flags == .command, let chars = event.charactersIgnoringModifiers, let n = Int(chars), (1...9).contains(n) {
            if model.mode == .list || isPanel {
                model.jump(to: n)
                return true
            }
        }
        if isPanel, flags == [.command, .shift], let index = Self.quickReplyKeyCodes.firstIndex(of: event.keyCode) {
            model.requestQuickReply(index)
            return true
        }
        if isPanel, flags == .command, let chars = event.charactersIgnoringModifiers {
            switch chars {
            case "=", "+": settings.adjustFontSize(1); return true
            case "-": settings.adjustFontSize(-1); return true
            case "0": settings.outputFontSize = 11; return true
            case "]": model.openNextWaiting(); return true
            default: break
            }
        }
        guard model.mode == .list, flags.isDisjoint(with: [.command, .option, .control]) else { return false }
        switch event.keyCode {
        case 126: model.moveSelection(-1); return true // ↑
        case 125: model.moveSelection(1); return true  // ↓
        case 36, 76: model.openSelected(); return true // Return / Enter
        default: return false
        }
    }

    private var isPanel: Bool {
        if case .panel = model.mode { return true }
        return false
    }
}

extension NSScreen {
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
