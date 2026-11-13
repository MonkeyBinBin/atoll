import AppKit
import AtollCore

/// Development aid, active only when ATOLL_DEBUG_DIR is set: renders the island
/// view to `<dir>/island.png` (no Screen Recording permission needed) and executes
/// one-line commands written to `<dir>/cmd`: list | panel <t> | launch | collapse | esc | snap.
@MainActor
final class DebugHook {
    private let dir: URL
    private weak var panel: NSWindow?
    private let model: IslandModel
    private var timer: Timer?
    /// bubble <address>: force a speech bubble for that agent's current state.
    var onBubble: ((String) -> Void)?
    /// Commands this hook doesn't know (e.g. the Notifier's `notes` / `notify`), with the debug dir.
    var onOther: ((_ parts: [String], _ dir: URL) -> Void)?

    init?(panel: NSWindow, model: IslandModel) {
        guard let path = ProcessInfo.processInfo.environment["ATOLL_DEBUG_DIR"], !path.isEmpty else { return nil }
        dir = URL(fileURLWithPath: path)
        self.panel = panel
        self.model = model
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        let cmdURL = dir.appendingPathComponent("cmd")
        guard let text = try? String(contentsOf: cmdURL, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: cmdURL)
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ").map(String.init)
            switch parts.first {
            case "list": model.showList()
            case "panel": if parts.count > 1 { model.openPanel(parts[1]) }
            case "launch": model.openLaunch()
            case "collapse": model.collapse()
            case "pin": model.pinned.toggle()
            case "esc": model.escape()
            case "down": model.moveSelection(1)
            case "allow": model.respondToSelected(.allow)
            case "changes": model.store.showChanges()
            case "launchwt":
                // launchwt <folder>: launch form for that folder with "New worktree" on (Claude Code)
                if parts.count > 1 {
                    model.openLaunch(prefill: .init(folder: parts[1], optionID: "builtin:claude", worktree: true))
                }
            case "difffile":
                // difffile <path>: expand / collapse that file in the open changes view
                if parts.count > 1, case .loaded(let files) = model.store.panel?.changes?.files,
                   let file = files.first(where: { $0.path == parts[1] }) {
                    model.store.toggleDiff(file)
                }
            case "deny": model.respondToSelected(.deny)
            case "queue":
                // queue <address> <text...>: queue a message for when that agent's turn ends
                if parts.count > 2 { model.store.queue(parts[2...].joined(separator: " "), for: parts[1]) }
            case "snap": snapshot(name: parts.count > 1 ? parts[1] : "island")
            case "send": if parts.count > 2 { model.store.send(parts[2...].joined(separator: " "), to: parts[1]) }
            case "key": if parts.count > 2 { model.store.pressKey(parts[2], on: parts[1]) }
            case "interrupt": if parts.count > 1 { model.store.pressInterrupt(parts[1]) }
            case "earliest": model.openEarliestWaiting()
            case "bubble": if parts.count > 1 { onBubble?(parts[1]) }
            case "hour":
                // hour <0-24> | hour off: pin the backdrop's time of day
                SkyClock.shared.overrideHour = parts.count > 1 ? Double(parts[1]) : nil
            case "snapbubble":
                if let bubble = NSApp.windows.first(where: { $0.isVisible && $0.contentView is FirstMouseHostingView<SpeechBubbleView> }) {
                    snapshot(window: bubble, name: "bubble")
                    try? "bubble=\(bubble.frame) island=\(panel?.frame ?? .zero) anchors=\(model.characterAnchors)".write(to: dir.appendingPathComponent("bubble.txt"), atomically: true, encoding: .utf8)
                }
            case "burst":
                // burst <name> <count>: one snapshot every 100 ms
                let count = parts.count > 2 ? Int(parts[2]) ?? 10 : 10
                for i in 0..<count {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 * Double(i)) {
                        MainActor.assumeIsolated { self.snapshot(name: "\(parts.count > 1 ? parts[1] : "burst")-\(i)") }
                    }
                }
            case "post":
                // post <keyCode> [cmd] [shift] [opt]: synthetic keyDown through NSApp's event queue
                if parts.count > 1, let code = UInt16(parts[1]) {
                    postKey(code, command: parts.contains("cmd"), shift: parts.contains("shift"), option: parts.contains("opt"))
                }
            case "type":
                // type <text>: synthetic key events for each character, then Return
                let text = parts.dropFirst().joined(separator: " ")
                for ch in text { postChar(String(ch)) }
                postKey(36, command: false)
            case "cmdf": postKey(3, command: true)
            case "chars":
                // chars <text>: synthetic key events for each character, no Return
                for ch in parts.dropFirst().joined(separator: " ") { postChar(String(ch)) }
            case "ret": postKey(36, command: false)
            case "sret": postKey(36, command: false, shift: true)
            case "esckey": postKey(53, command: false)
            case "draft":
                // draft <text>: type into the focused field without pressing Return
                for ch in parts.dropFirst().joined(separator: " ") { postChar(String(ch)) }
            case "hover":
                // hover <address> <x>: simulate the mouse resting on a character at window x
                if parts.count > 2, let x = Double(parts[2]) {
                    model.hover = IslandModel.Hover(address: parts[1], anchor: CGRect(x: x, y: 5, width: 16, height: 16))
                }
            case "snaphover":
                if let card = NSApp.windows.first(where: { $0.ignoresMouseEvents && $0.isVisible && $0 !== panel }) {
                    snapshot(window: card, name: "hovercard")
                    try? "card=\(card.frame) island=\(panel?.frame ?? .zero)".write(to: dir.appendingPathComponent("hovercard.txt"), atomically: true, encoding: .utf8)
                }
            case "clickother":
                // A click delivered to another window of this app (the Settings window).
                if let other = NSApp.windows.first(where: { $0.title.contains("Settings") && $0.isVisible }),
                   let event = NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 50, y: 50), modifierFlags: [],
                                                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: other.windowNumber,
                                                  context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                    NSApp.postEvent(event, atStart: false)
                }
            case "move":
                if parts.count > 2, let x = Double(parts[1]), let y = Double(parts[2]), let panel {
                    panel.acceptsMouseMovedEvents = true
                    if let event = NSEvent.mouseEvent(with: .mouseMoved, location: CGPoint(x: x, y: y), modifierFlags: [],
                                                      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                                                      context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
                        NSApp.postEvent(event, atStart: false)
                    }
                }
            case "click":
                // click <x> <y>: synthetic click at window-local point (origin bottom-left)
                if parts.count > 2, let x = Double(parts[1]), let y = Double(parts[2]) { postClick(CGPoint(x: x, y: y)) }
            case "focus":
                if parts.count > 1 {
                    let store = model.store
                    let address = parts[1]
                    Task { @MainActor in
                        let error = await store.openInHerdr(address)
                        try? "focus=\(error.map { "\($0.kind): \($0.message)" } ?? "ok")".write(to: self.dir.appendingPathComponent("focus.txt"), atomically: true, encoding: .utf8)
                    }
                }
            case "large": model.settings.largePanel.toggle()
            case "today": model.openToday()
            case "space": model.setSpaceFilter(SpaceFilter(stored: parts.count > 1 && parts[1] != "all" ? parts[1] : ""))
            case "tab": model.cycleSpaceFilter(1)
            case "settings":
                NotificationCenter.default.post(name: .atollShowSettings, object: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    MainActor.assumeIsolated {
                        if let window = NSApp.windows.first(where: { $0.title.contains("Settings") }) {
                            // settings [y]: scroll the form down to y points first (sections below the fold).
                            if parts.count > 1, let y = Double(parts[1]), let scroll = Self.scrollView(in: window.contentView) {
                                scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                                scroll.reflectScrolledClipView(scroll.contentView)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                MainActor.assumeIsolated { self.snapshot(window: window, name: parts.count > 1 ? "settings-\(parts[1])" : "settings") }
                            }
                        }
                    }
                }
            case "launchbuiltin":
                // launchbuiltin <folder> <0|1> <task...>  (0 = Claude Code, 1 = Codex)
                if parts.count > 3, let i = Int(parts[2]), LaunchOption.builtIns.indices.contains(i) {
                    model.store.launch(LaunchRequest(argv: LaunchOption.builtIns[i].argv, folder: parts[1],
                                                     task: parts[3...].joined(separator: " "), name: "island-launch-test"))
                }
            case "launchargv":
                // launchargv <folder> <argv...>
                if parts.count > 2 {
                    model.store.launch(LaunchRequest(argv: Array(parts[2...]), folder: parts[1], task: "debug launch"))
                }
            default: onOther?(parts, dir)
            }
        }
    }

    private func postKey(_ code: UInt16, command: Bool, shift: Bool = false, option: Bool = false) {
        guard let panel else { return }
        let chars: String = switch code {
        case 18: "1"
        case 19: "2"
        case 36: "\r"
        case 30: "]"
        case 16: "y"
        case 45: "n"
        case 15: "r"
        case 3: "f"
        case 53: "\u{1b}"
        default: ""
        }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(
                with: type, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(command ? [.command] : []).union(shift ? [.shift] : []).union(option ? [.option] : []),
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                isARepeat: false, keyCode: code
            ) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    private func postChar(_ ch: String) {
        guard let panel else { return }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, characters: ch, charactersIgnoringModifiers: ch,
                isARepeat: false, keyCode: 0
            ) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    private func postClick(_ point: CGPoint) {
        guard let panel else { return }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    private static func scrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews { if let found = scrollView(in: sub) { return found } }
        return nil
    }

    private func snapshot(window: NSWindow, name: String) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }

    private func snapshot(name: String) {
        guard let panel, let view = panel.contentView else { return }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        let data = rep.representation(using: .png, properties: [:])
        try? data?.write(to: dir.appendingPathComponent("\(name).png"))
        let info = "frame=\(panel.frame) agents=\(model.store.agents.map { "\($0.address):\($0.state.label)" }) mode=\(model.mode) key=\(panel.isKeyWindow) selection=\(model.selection) live=\(model.store.isLive) send=\(model.store.sendStates) keys=\(model.store.keyStates) responses=\(model.store.listAnswers) queued=\(model.store.queuedMessages) notices=\(model.store.queueNotices) choices=\(model.store.agents.compactMap { a in a.permissionChoices.map { "\(a.address):\($0.allowKey)/\($0.denyKey)" } }) interrupt=\(model.store.interruptStates) feedback=\(model.store.agents.compactMap { a in a.interruptFeedback.map { o in "\(a.address):\(o)" } }) launch=\(model.store.launchState) visible=\(panel.isVisible) fullscreen=\(model.fullScreen) hidden=\(model.hiddenByFullScreen) collapsed=\(model.collapsedAgents?.map(\.address) ?? []) pinned=\(model.pinned) search=\(model.outputSearch.map { "\($0.query)|\($0.counter ?? "-")" } ?? "closed") searchFocused=\(model.searchFieldFocused)\n"
        try? info.write(to: dir.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
    }
}

extension Notification.Name {
    static let atollShowSettings = Notification.Name("AtollShowSettings")
}
