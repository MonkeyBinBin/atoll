import AppKit
import AtollCore

/// Menu bar icon: waiting-count badge, Show/Hide Island, Today…, Settings…, Quit. Nothing else.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store: AgentStore
    private let settings: AppSettings
    private let openSettings: () -> Void
    private let openToday: () -> Void
    private let toggleItem = NSMenuItem(title: "Hide Island", action: #selector(toggleIsland), keyEquivalent: "")

    init(store: AgentStore, settings: AppSettings, openSettings: @escaping () -> Void, openToday: @escaping () -> Void) {
        self.store = store
        self.settings = settings
        self.openSettings = openSettings
        self.openToday = openToday
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        toggleItem.target = self
        menu.addItem(toggleItem)
        let todayItem = NSMenuItem(title: "Today…", action: #selector(showToday), keyEquivalent: "")
        todayItem.target = self
        menu.addItem(todayItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Atoll", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        trackChanges { [weak self] in self?.render() }
    }

    private func render() {
        guard let button = item.button else { return }
        let waiting = store.waitingCount
        let offline = !store.isLive
        let icon: MenuBarIcon = offline ? .offline : (waiting > 0 ? .waiting : .idle)
        let image = icon.image
        image.accessibilityDescription = "Atoll"
        button.image = image
        button.imagePosition = .imageLeading
        button.title = waiting > 0 ? " \(waiting)" : ""
        button.toolTip = offline ? "Herdr offline" : (waiting > 0 ? "\(waiting) agent(s) need you" : "Atoll")
        toggleItem.title = settings.islandVisible ? "Hide Island" : "Show Island"
    }

    func menuWillOpen(_ menu: NSMenu) {
        toggleItem.title = settings.islandVisible ? "Hide Island" : "Show Island"
    }

    @objc private func toggleIsland() {
        settings.islandVisible.toggle()
    }

    @objc private func showToday() {
        openToday()
    }

    @objc private func showSettings() {
        openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
