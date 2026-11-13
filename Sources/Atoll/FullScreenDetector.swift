import AppKit
import AtollCore

/// Tells whether a screen is showing a full-screen app, without Screen Recording or Accessibility:
/// only window bounds, layer and owner pid from CGWindowList are read (never titles).
///
/// The rule itself lives in `FullScreenWindows` (AtollCore); see there and tickets 25 / 53.
@MainActor
final class FullScreenDetector {
    /// Re-checks after a space or app switch: the full-screen animation takes about a second
    /// before the window reaches its final bounds.
    private static let recheckDelays: [TimeInterval] = [0, 0.7, 1.6]

    private let onChange: () -> Void
    private var observers: [NSObjectProtocol] = []
    private var pending: [DispatchWorkItem] = []

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleChecks() }
            })
        }
    }

    /// Ask the owner to re-evaluate now and again once animations settle.
    func scheduleChecks() {
        pending.forEach { $0.cancel() }
        pending = Self.recheckDelays.map { delay in
            let item = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.onChange() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            return item
        }
    }

    static func isFullScreen(_ screen: NSScreen) -> Bool {
        guard let primary = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let windows = list.compactMap { window -> WindowSnapshot? in
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  let pid = window[kCGWindowOwnerPID as String] as? Int,
                  let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict)
            else { return nil }
            return WindowSnapshot(layer: layer, pid: pid, bounds: bounds)
        }
        return FullScreenWindows.isFullScreen(
            windows, screen: screen.frame, primaryHeight: primary.frame.height,
            ownPID: Int(ProcessInfo.processInfo.processIdentifier)
        )
    }
}
