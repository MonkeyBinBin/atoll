import AppKit
import IslandCore
import UserNotifications

/// Maps AgentStore transitions to macOS notifications; clicking one opens that agent's panel.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var rules = NotificationRules()
    private let settings: AppSettings
    private let onOpen: (String) -> Void
    private let center: UNUserNotificationCenter?

    init(settings: AppSettings, onOpen: @escaping (String) -> Void) {
        self.settings = settings
        self.onOpen = onOpen
        // UNUserNotificationCenter needs a bundle; `swift run` has none.
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        super.init()
        center?.delegate = self
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func handle(_ agent: Agent, from previous: AgentState?) {
        guard let note = rules.notification(for: agent, from: previous, settings: settings.notificationSettings) else { return }
        guard let center else {
            NSLog("HerdrIsland notification (no bundle): \(note.title) — \(note.body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = note.title
        content.body = note.body
        content.userInfo = ["address": note.address]
        content.threadIdentifier = note.address
        let request = UNNotificationRequest(identifier: "\(note.address)-\(note.key)", content: content, trigger: nil)
        center.add(request)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let address = response.notification.request.content.userInfo["address"] as? String
        await MainActor.run {
            if let address { onOpen(address) }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
