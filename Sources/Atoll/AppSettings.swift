import Carbon.HIToolbox
import Foundation
import AtollCore
import Observation

struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon modifier flags (cmdKey, optionKey, controlKey, shiftKey).
    var modifiers: UInt32

    static let defaultList = HotKey(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey | cmdKey))
    /// ⌃⌥⌘A — ⌥⌘W would steal "Close All Windows" from every app.
    static let defaultWaiting = HotKey(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(controlKey | optionKey | cmdKey))

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    static func keyName(_ code: UInt32) -> String {
        let names: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
            kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
            kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "Space", kVK_Return: "↩", kVK_ANSI_Period: ".", kVK_ANSI_Comma: ",", kVK_ANSI_Slash: "/",
            kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_Grave: "`", kVK_ANSI_Backslash: "\\",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        return names[Int(code)] ?? "#\(code)"
    }
}

/// User preferences, persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var islandVisible: Bool { didSet { defaults.set(islandVisible, forKey: "islandVisible") } }
    var showUnreportedTerminals: Bool { didSet { defaults.set(showUnreportedTerminals, forKey: "showUnreportedTerminals") } }
    var animationsEnabled: Bool { didSet { defaults.set(animationsEnabled, forKey: "animationsEnabled") } }
    /// Pixel decorations on the island (gradient, rim, stage dots, stars); off = plain black.
    var decorations: Bool { didSet { defaults.set(decorations, forKey: "decorations") } }
    /// Speech bubble over a character when its agent stops or needs the user.
    var speechBubbles: Bool { didSet { defaults.set(speechBubbles, forKey: "speechBubbles") } }
    var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: "notificationsEnabled") } }
    /// Needs-you notifications show the waiting reason (and only then offer Allow). Off by default.
    var notifyShowsWaitingReason: Bool { didSet { defaults.set(notifyShowsWaitingReason, forKey: "notifyShowsWaitingReason") } }
    /// Only agents in the island's space notify (ticket 44); the bell is exempt.
    var notifyIslandSpaceOnly: Bool { didSet { defaults.set(notifyIslandSpaceOnly, forKey: "notifyIslandSpaceOnly") } }
    /// Canned replies under the panel's reply box (normalized; empty = none shown).
    var quickReplies: [String] { didSet { defaults.set(quickReplies, forKey: "quickReplies") } }
    /// After a turn finishes, show what it changed in git (+/− lines, files).
    var changeSummary: Bool { didSet { defaults.set(changeSummary, forKey: "changeSummary") } }
    /// Warn when two or more active agents work in the same git working tree.
    var sharedTreeWarning: Bool { didSet { defaults.set(sharedTreeWarning, forKey: "sharedTreeWarning") } }
    /// Collect today's finished turns for the Today window (in memory only); off = nothing collected.
    var todayTimeline: Bool { didSet { defaults.set(todayTimeline, forKey: "todayTimeline") } }
    /// After answering a waiting agent in its panel, open the next waiting one.
    var autoAdvance: Bool { didSet { defaults.set(autoAdvance, forKey: "autoAdvance") } }
    /// Minutes a Working agent's screen may sit unchanged before "No output for …" shows; 0 = off.
    var noOutputMinutes: Int { didSet { defaults.set(noOutputMinutes, forKey: "noOutputMinutes") } }
    /// Minutes in Needs you before one reminder (notification + bubble); 0 = off.
    var reminderMinutes: Int { didSet { defaults.set(reminderMinutes, forKey: "reminderMinutes") } }
    var doneNotifyAgents: Set<String> { didSet { defaults.set(Array(doneNotifyAgents), forKey: "doneNotifyAgents") } }
    var doneNotifyProjects: Set<String> { didSet { defaults.set(Array(doneNotifyProjects), forKey: "doneNotifyProjects") } }
    /// The collapsed island while its screen shows a full-screen app.
    var fullScreenMode: FullScreenMode { didSet { defaults.set(fullScreenMode.rawValue, forKey: "fullScreenMode") } }
    /// `displayID` value meaning "the screen under the mouse".
    static let followMouseDisplay = UInt32.max
    /// CGDirectDisplayID of the chosen screen; 0 = automatic (built-in / main); `followMouseDisplay` = follow the mouse.
    var displayID: UInt32 { didSet { defaults.set(Int(displayID), forKey: "displayID") } }
    var listHotKey: HotKey { didSet { save(listHotKey, "listHotKey") } }
    var waitingHotKey: HotKey { didSet { save(waitingHotKey, "waitingHotKey") } }
    /// Herdr space id for new agents; empty = Herdr's selected space.
    var defaultSpace: String { didSet { defaults.set(defaultSpace, forKey: "defaultSpace") } }
    /// The collapsed island's space filter (`SpaceFilter.stored`); empty = all agents.
    var islandSpace: String { didSet { defaults.set(islandSpace, forKey: "islandSpace") } }
    var recentFolders: [String] { didSet { defaults.set(recentFolders, forKey: "recentFolders") } }
    /// Folders pinned at the top of the launch form's Folder menu, in the user's order.
    var pinnedFolders: [String] { didSet { defaults.set(pinnedFolders, forKey: "pinnedFolders") } }
    /// The last spaces read from the Herdr app, for launches while it isn't running.
    var herdrSpaceCache: [HerdrSpace] { didSet { save(herdrSpaceCache, "herdrSpaceCache") } }
    /// Names waiting for spaces that launches without the Herdr app made (space id → name).
    var pendingSpaceNames: [String: String] { didSet { defaults.set(pendingSpaceNames, forKey: "pendingSpaceNames") } }
    /// The launch form's last launches and saved presets (tasks included), on this Mac only.
    var recentLaunches: [LaunchRecipe] { didSet { save(recentLaunches, "recentLaunches") } }
    var launchPresets: [LaunchPreset] { didSet { save(launchPresets, "launchPresets") } }
    /// Output font family; empty = automatic (an installed Nerd Font Mono, else SF Mono).
    var outputFontFamily: String { didSet { defaults.set(outputFontFamily, forKey: "outputFontFamily") } }
    var outputFontSize: Double { didSet { defaults.set(outputFontSize, forKey: "outputFontSize") } }
    /// Large panel: wider island and taller output.
    var largePanel: Bool { didSet { defaults.set(largePanel, forKey: "largePanel") } }
    /// Show only the conversation (drop input box, status lines, mod rows) for known tools.
    var messagesOnly: Bool {
        didSet {
            defaults.set(messagesOnly, forKey: "messagesOnly")
            wrapOverride = nil // back to automatic wrapping for the new mode
        }
    }
    /// Wrap output lines. nil = automatic: wrap in Messages only, scroll sideways for full screens.
    var wrapOverride: Bool? { didSet { defaults.set(wrapOverride, forKey: "wrapOverride") } }

    var wrapOutput: Bool { wrapOverride ?? messagesOnly }

    static let fontSizeRange: ClosedRange<Double> = 9...16

    func adjustFontSize(_ delta: Double) {
        outputFontSize = min(max(outputFontSize + delta, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
    }

    /// Every key this app stores; used to carry settings over from the old bundle id.
    static let keys = [
        "islandVisible", "showUnreportedTerminals", "animationsEnabled", "decorations", "notificationsEnabled",
        "doneNotifyAgents", "doneNotifyProjects", "displayID", "listHotKey", "waitingHotKey", "defaultSpace",
        "recentFolders", "outputFontFamily", "outputFontSize", "largePanel", "messagesOnly", "wrapOverride", "speechBubbles",
    ]

    /// The app was "Herdr Island" (bundle id local.herdr-island) before the rename to Atoll.
    static func migrateLegacySettings(into defaults: UserDefaults) {
        let flag = "migratedFromHerdrIsland"
        guard !defaults.bool(forKey: flag), let legacy = UserDefaults(suiteName: "local.herdr-island") else { return }
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = legacy.persistentDomain(forName: "local.herdr-island")?[key] {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: flag)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults === UserDefaults.standard { Self.migrateLegacySettings(into: defaults) }
        islandVisible = defaults.object(forKey: "islandVisible") as? Bool ?? true
        showUnreportedTerminals = defaults.bool(forKey: "showUnreportedTerminals")
        animationsEnabled = defaults.object(forKey: "animationsEnabled") as? Bool ?? true
        decorations = defaults.object(forKey: "decorations") as? Bool ?? true
        notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
        notifyShowsWaitingReason = defaults.bool(forKey: "notifyShowsWaitingReason")
        notifyIslandSpaceOnly = defaults.bool(forKey: "notifyIslandSpaceOnly")
        speechBubbles = defaults.object(forKey: "speechBubbles") as? Bool ?? true
        reminderMinutes = defaults.object(forKey: "reminderMinutes") as? Int ?? 5
        noOutputMinutes = defaults.object(forKey: "noOutputMinutes") as? Int ?? 10
        autoAdvance = defaults.object(forKey: "autoAdvance") as? Bool ?? true
        changeSummary = defaults.object(forKey: "changeSummary") as? Bool ?? true
        sharedTreeWarning = defaults.object(forKey: "sharedTreeWarning") as? Bool ?? true
        todayTimeline = defaults.object(forKey: "todayTimeline") as? Bool ?? true
        quickReplies = QuickReplies.resolve(stored: defaults.stringArray(forKey: "quickReplies"))
        doneNotifyAgents = Set(defaults.stringArray(forKey: "doneNotifyAgents") ?? [])
        doneNotifyProjects = Set(defaults.stringArray(forKey: "doneNotifyProjects") ?? [])
        displayID = UInt32(truncatingIfNeeded: defaults.integer(forKey: "displayID"))
        fullScreenMode = defaults.string(forKey: "fullScreenMode").flatMap(FullScreenMode.init(rawValue:)) ?? .attentionOnly
        listHotKey = Self.load("listHotKey", defaults) ?? .defaultList
        waitingHotKey = Self.load("waitingHotKey", defaults) ?? .defaultWaiting
        defaultSpace = defaults.string(forKey: "defaultSpace") ?? ""
        islandSpace = defaults.string(forKey: "islandSpace") ?? ""
        recentFolders = defaults.stringArray(forKey: "recentFolders") ?? []
        pinnedFolders = defaults.stringArray(forKey: "pinnedFolders") ?? []
        herdrSpaceCache = Self.load("herdrSpaceCache", defaults) ?? []
        pendingSpaceNames = defaults.dictionary(forKey: "pendingSpaceNames") as? [String: String] ?? [:]
        recentLaunches = Self.load("recentLaunches", defaults) ?? []
        launchPresets = Self.load("launchPresets", defaults) ?? []
        outputFontFamily = defaults.string(forKey: "outputFontFamily") ?? ""
        outputFontSize = defaults.object(forKey: "outputFontSize") as? Double ?? 11
        largePanel = defaults.bool(forKey: "largePanel")
        messagesOnly = defaults.object(forKey: "messagesOnly") as? Bool ?? true
        wrapOverride = defaults.object(forKey: "wrapOverride") as? Bool
    }

    var notificationSettings: NotificationSettings {
        NotificationSettings(enabled: notificationsEnabled, doneAgents: doneNotifyAgents, doneProjects: doneNotifyProjects,
                             showWaitingReason: notifyShowsWaitingReason)
    }

    var folders: FolderList {
        get { FolderList(pinned: pinnedFolders, recent: recentFolders) }
        set {
            if pinnedFolders != newValue.pinned { pinnedFolders = newValue.pinned }
            if recentFolders != newValue.recent { recentFolders = newValue.recent }
        }
    }

    func rememberFolder(_ path: String) {
        folders = folders.remembering(path)
    }

    func recordLaunch(_ recipe: LaunchRecipe) {
        recentLaunches = LaunchHistory.recording(recipe, in: recentLaunches)
    }

    func clearRecentLaunches() {
        recentLaunches = []
    }

    /// JSON-encoded values (hotkeys, recent launches, presets).
    private func save<T: Encodable>(_ value: T, _ name: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: name)
    }

    private static func load<T: Decodable>(_ name: String, _ defaults: UserDefaults) -> T? {
        defaults.data(forKey: name).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
