import AppKit
import AtollCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated static let herdrBundleID = "dev.herdr.app"
    nonisolated static let cmuxBundleID = "com.cmuxterm.app"

    private var settings: AppSettings!
    private var client: HerdrClient!
    private var store: AgentStore!
    private var model: IslandModel!
    private var island: IslandController!
    private var menuBar: MenuBarController!
    private var notifier: Notifier!
    private var settingsWindow: NSWindow?
    private var sigterm: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let demo = DemoMode.isOn
        settings = demo ? AppSettings(defaults: UserDefaults(suiteName: DemoMode.defaultsSuite)!) : AppSettings()
        let core = CoreRPCAdapter(
            appRunning: {
                !NSRunningApplication.runningApplications(withBundleIdentifier: AppDelegate.herdrBundleID).isEmpty
            },
            activateApp: {
                DispatchQueue.main.async {
                    NSRunningApplication.runningApplications(withBundleIdentifier: AppDelegate.herdrBundleID).first?.activate()
                }
            }
        )
        client = demo ? DemoClient() : core
        store = demo ? AgentStore(clients: [(.core, client)], scheduler: LiveScheduler()) : AgentStore(clients: [
            (.core, client),
            (.herdrCLI, HerdrCLIAdapter()),
            (.cmux, CmuxAdapter(
                appRunning: { !NSRunningApplication.runningApplications(withBundleIdentifier: AppDelegate.cmuxBundleID).isEmpty },
                activateApp: {
                    DispatchQueue.main.async {
                        NSRunningApplication.runningApplications(withBundleIdentifier: AppDelegate.cmuxBundleID).first?.activate()
                    }
                }
            )),
        ], scheduler: LiveScheduler())
        store.showUnreportedTerminals = settings.showUnreportedTerminals
        model = IslandModel(store: store, settings: settings)
        island = IslandController(model: model, settings: settings, client: client)
        menuBar = MenuBarController(store: store, settings: settings,
                                    openSettings: { [weak self] in self?.showSettings() },
                                    openToday: { [weak self] in self?.showToday() })
        notifier = Notifier(settings: settings, store: store) { [weak self] address, draft in
            self?.settings.islandVisible = true
            if let draft { self?.model.draftPrefill[address] = draft }
            self?.model.openPanel(address)
        }
        store.onTransition = { [weak self] agent, from in
            self?.notifier.handle(agent, from: from)
            self?.island.handleTransition(agent, from: from)
        }
        store.onSharedTree = { [weak self] agent in self?.island.handleSharedTree(agent) }
        store.onWaitingDetails = { [weak self] agent in self?.notifier.waitingDetails(agent) }
        store.worktreeCreator = GitWorktreeCreator()
        store.onWorktreeCreated = { [weak self] path in self?.settings.rememberFolder(path) }
        store.onLaunchFinished = { [weak self] succeeded in
            guard let self, let recipe = self.model.pendingLaunchRecipe else { return }
            // Either way it no longer belongs to a launch in progress; only one that went out is remembered.
            self.model.pendingLaunchRecipe = nil
            if succeeded { self.settings.recordLaunch(recipe) }
        }
        island.debugHook?.onOther = { [weak self] parts, dir in self?.notifier.debugCommand(parts, dir: dir) }
        store.onNotifyWhenDone = { [weak self] agent in self?.notifier.notifyWhenDone(agent) }
        store.onQueuedSent = { [weak self] agent in self?.island.handleQueuedSent(agent) }
        store.onQueuedFailed = { [weak self] address, text in self?.model.draftPrefill[address] = text }
        store.onAutoAdvance = { [weak self] next in self?.model.autoAdvance(to: next) }
        store.onAllClear = { [weak self] in self?.model.showAllClear() }
        store.onReminder = { [weak self] agent, waited in
            self?.notifier.remind(agent, waited: waited)
            self?.island.handleReminder(agent)
        }

        watchHerdrApp()
        // `kill` (SIGTERM) skips applicationWillTerminate: stop sources first, then quit.
        signal(SIGTERM, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.store?.stop() }
            exit(0)
        }
        term.resume()
        sigterm = term
        NotificationCenter.default.addObserver(forName: .atollShowSettings, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showSettings() }
        }
        // The timeline's midnight timer doesn't count while asleep, and the day depends on the time zone.
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.store.rollOverTimeline() }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.rollOverTimeline() }
        }
        trackChanges { [weak self] in self?.applySettings() }
        trackChanges { [weak self] in self?.validateModel() }
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Ends the `cmux events` child and closes sockets.
        store?.stop()
    }

    private func applySettings() {
        if store.showUnreportedTerminals != settings.showUnreportedTerminals {
            store.setShowUnreportedTerminals(settings.showUnreportedTerminals)
        }
        store.autoAdvance = settings.autoAdvance
        store.timelineEnabled = settings.todayTimeline
        if (store.changeProbe != nil) != settings.changeSummary {
            store.changeProbe = settings.changeSummary ? (DemoMode.isOn ? DemoGit() as any ChangeProbing : GitProbe()) : nil
            store.changeInspector = settings.changeSummary ? (DemoMode.isOn ? DemoGit() as any ChangeInspecting : GitProbe()) : nil
        }
        if (store.treeProbe != nil) != settings.sharedTreeWarning {
            store.treeProbe = settings.sharedTreeWarning ? (DemoMode.isOn ? DemoGit() as any WorkingTreeProbing : GitProbe()) : nil
        }
        store.noOutputThreshold = settings.noOutputMinutes > 0 ? TimeInterval(settings.noOutputMinutes * 60) : nil
        store.reminderDelay = settings.reminderMinutes > 0 ? TimeInterval(settings.reminderMinutes * 60) : nil
        HotKeyCenter.shared.register(id: 1, settings.listHotKey) { [weak self] in
            guard let self else { return }
            self.settings.islandVisible = true
            self.model.toggleList()
        }
        HotKeyCenter.shared.register(id: 2, settings.waitingHotKey) { [weak self] in
            guard let self else { return }
            self.settings.islandVisible = true
            self.model.openEarliestWaiting()
        }
        _ = settings.displayID
        // Outside this tracking scope: refreshScreen reads island state (mode, agents) that must not
        // re-run applySettings, or the island would re-target its screen on every expand.
        DispatchQueue.main.async { [weak self] in self?.island?.refreshScreen() }
    }

    private func validateModel() {
        _ = store.agents
        model.validate()
    }

    private func watchHerdrApp() {
        refreshHerdrApp()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshHerdrApp() }
            }
        }
    }

    private func refreshHerdrApp() {
        store.herdrAppRunning = DemoMode.isOn || !NSRunningApplication.runningApplications(withBundleIdentifier: Self.herdrBundleID).isEmpty
    }

    private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false
            )
            window.title = "Atoll Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(store: store, settings: settings))
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Today's finished turns: an island pane, like the list and the launch form.
    private func showToday() {
        settings.islandVisible = true
        model.openToday()
    }
}
