import AppKit
import AtollCore
import UserNotifications

/// Maps AgentStore transitions to macOS notifications; clicking one opens that agent's panel.
/// Needs-you notifications can also answer from the banner (Allow / Deny / Reply); see `NotificationRules.decorate`.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var rules = NotificationRules()
    private let settings: AppSettings
    private let store: AgentStore
    private let onOpen: (_ address: String, _ draft: String?) -> Void
    private let center: UNUserNotificationCenter?
    /// Needs-you notifications held until the agent's screen read finishes, per agent, with the episode.
    private var held: [String: (note: AgentNotification, episode: Date?, timeout: DispatchWorkItem)] = [:]

    /// Longest a Needs-you notification waits for the screen read (it starts 0.6 s after the transition).
    static let holdLimit: TimeInterval = 2

    private enum Action {
        static let allow = "atoll.allow"
        static let deny = "atoll.deny"
        static let reply = "atoll.reply"
    }

    private enum Key {
        static let address = "address"
        static let episode = "episode"
        static let draft = "draft"
    }

    init(settings: AppSettings, store: AgentStore, onOpen: @escaping (_ address: String, _ draft: String?) -> Void) {
        self.settings = settings
        self.store = store
        self.onOpen = onOpen
        // UNUserNotificationCenter needs a bundle; `swift run` has none.
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        super.init()
        center?.delegate = self
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        center?.setNotificationCategories(Self.categories)
    }

    /// One category per combination of buttons. None brings Atoll to the front: answering stays in the banner.
    private static var categories: Set<UNNotificationCategory> {
        let allow = UNNotificationAction(identifier: Action.allow, title: "Allow", options: [])
        let deny = UNNotificationAction(identifier: Action.deny, title: "Deny", options: [.destructive])
        let reply = UNTextInputNotificationAction(identifier: Action.reply, title: "Reply", options: [],
                                                  textInputButtonTitle: "Send", textInputPlaceholder: "Reply…")
        return Set(NotificationActions.combinations.map { combo in
            var actions: [UNNotificationAction] = []
            if combo.contains(.allow) { actions.append(allow) }
            if combo.contains(.deny) { actions.append(deny) }
            if combo.contains(.reply) { actions.append(reply) }
            return UNNotificationCategory(identifier: combo.categoryIdentifier, actions: actions, intentIdentifiers: [])
        })
    }

    /// Settings' rules, narrowed to the island's space when "Only notify for the island's space" is on.
    private var notificationSettings: NotificationSettings {
        var result = settings.notificationSettings
        if settings.notifyIslandSpaceOnly {
            result.space = SpaceGrouping.effective(SpaceFilter(stored: settings.islandSpace), spaces: store.spaces)
        }
        return result
    }

    func handle(_ agent: Agent, from previous: AgentState?) {
        guard let note = rules.notification(for: agent, from: previous, settings: notificationSettings) else { return }
        deliver(note, for: agent)
    }

    /// An agent armed with "notify when done" finished its turn.
    func notifyWhenDone(_ agent: Agent) {
        guard let note = rules.finished(for: agent, settings: notificationSettings) else { return }
        post(note)
    }

    /// A Needs-you episode outlasted the reminder delay.
    func remind(_ agent: Agent, waited: TimeInterval) {
        guard let note = rules.reminder(for: agent, waited: waited, settings: notificationSettings) else { return }
        deliver(note, for: agent)
    }

    /// Store: the screen read of a Needs-you episode finished; post what was held for it.
    func waitingDetails(_ agent: Agent) {
        flush(agent.address)
    }

    // MARK: Posting

    /// Needs-you notifications wait (briefly) for the screen read, so the buttons match the dialog on screen.
    private func deliver(_ note: AgentNotification, for agent: Agent) {
        guard agent.state.isNeedsYou else { return post(note) }
        held.removeValue(forKey: agent.address)?.timeout.cancel()
        guard store.isReadingWaitingScreen(agent.address) else { return post(decorated(note, agent)) }
        let address = agent.address
        let timeout = DispatchWorkItem { [weak self] in self?.flush(address) }
        held[address] = (note, agent.waitingSince, timeout)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdLimit, execute: timeout)
    }

    private func flush(_ address: String) {
        guard let entry = held.removeValue(forKey: address) else { return }
        entry.timeout.cancel()
        // Answered (or moved on) while held: the notification has nothing left to say.
        guard let agent = store.agent(address), agent.state.isNeedsYou, agent.waitingSince == entry.episode else { return }
        post(decorated(entry.note, agent))
    }

    private func decorated(_ note: AgentNotification, _ agent: Agent) -> AgentNotification {
        NotificationRules.decorate(note, with: agent, settings: notificationSettings)
    }

    private func post(_ note: AgentNotification, draft: String? = nil) {
        guard let center else {
            NSLog("Atoll notification (no bundle): \(note.title) — \(note.body) \(note.actions.isEmpty ? "" : note.actions.categoryIdentifier)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = note.title
        content.body = note.body
        var info: [String: Any] = [Key.address: note.address]
        if let episode = note.episode { info[Key.episode] = AgentNotification.encodeEpisode(episode) }
        if let draft { info[Key.draft] = draft }
        content.userInfo = info
        content.threadIdentifier = note.address
        if !note.actions.isEmpty { content.categoryIdentifier = note.actions.categoryIdentifier }
        let request = UNNotificationRequest(identifier: "\(note.address)-\(note.key)", content: content, trigger: nil)
        center.add(request)
    }

    /// A follow-up after acting from a banner: "Allow failed", "Reply failed", "No longer waiting".
    private func postOutcome(_ address: String, _ text: String, draft: String? = nil) {
        let title = store.agent(address)?.displayName ?? "Agent"
        let key = "outcome-\(Int(Date().timeIntervalSince1970 * 1000))"
        post(AgentNotification(address: address, title: title, body: text, key: key), draft: draft)
    }

    // MARK: Responses

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let address = info[Key.address] as? String
        let episode = (info[Key.episode] as? Double).map(AgentNotification.decodeEpisode)
        let draft = info[Key.draft] as? String
        let action = response.actionIdentifier
        let text = (response as? UNTextInputNotificationResponse)?.userText
        await MainActor.run {
            guard let address else { return }
            switch action {
            case Action.allow: respond(.allow, address, episode)
            case Action.deny: respond(.deny, address, episode)
            case Action.reply: reply(text ?? "", address, episode)
            case UNNotificationDismissActionIdentifier: break
            default: onOpen(address, draft)
            }
        }
    }

    private func respond(_ choice: ListAnswer, _ address: String, _ episode: Date?) {
        store.respond(choice, to: address, episode: episode) { [weak self] state in
            switch state {
            case .noLongerWaiting: self?.postOutcome(address, "No longer waiting · nothing was sent")
            case .failed(_, let error): self?.postOutcome(address, "\(choice.label) failed · \(error.message)")
            case .sending, .sent: break
            }
        }
    }

    private func reply(_ text: String, _ address: String, _ episode: Date?) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.reply(text, to: address, episode: episode) { [weak self] state in
            switch state {
            case nil: self?.postOutcome(address, "No longer waiting · reply not sent. Click to open it with your text.", draft: text)
            case .failed(let error): self?.postOutcome(address, "Reply failed · \(error.message). Click to retry from the panel.", draft: text)
            default: break
            }
        }
    }

    // MARK: Debug hook

    /// `notes`: write delivered notifications to `<dir>/notes.txt`.
    /// `notify <address> allow|deny|open|reply <text…>`: act on that agent's latest delivered notification
    /// through the same path as a banner button (the banner itself can't be clicked from a script).
    func debugCommand(_ parts: [String], dir: URL) {
        guard let center, let command = parts.first else { return }
        Task {
            let delivered = await center.deliveredNotifications().sorted { $0.date < $1.date }
            switch command {
            case "notes":
                let lines = delivered.map { n in
                    let c = n.request.content
                    return "\(n.request.identifier) | \(c.title) | \(c.body) | \(c.categoryIdentifier) | \(c.userInfo)"
                }
                try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
            case "notify" where parts.count > 2:
                let address = parts[1]
                guard let latest = delivered.last(where: { ($0.request.content.userInfo[Key.address] as? String) == address }) else { return }
                let info = latest.request.content.userInfo
                let episode = (info[Key.episode] as? Double).map(AgentNotification.decodeEpisode)
                switch parts[2] {
                case "allow": respond(.allow, address, episode)
                case "deny": respond(.deny, address, episode)
                case "reply": reply(parts[3...].joined(separator: " "), address, episode)
                default: onOpen(address, info[Key.draft] as? String)
                }
            default: break
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
