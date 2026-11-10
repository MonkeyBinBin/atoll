import AppKit
import AtollCore

/// The terminal app an agent was started from outside Herdr (`atoll.origin` label).
struct OriginApp {
    let bundleID: String?
    let name: String

    /// TERM_PROGRAM values for terminals that don't expose __CFBundleIdentifier.
    private static let termPrograms: [String: (String, String)] = [
        "ghostty": ("com.mitchellh.ghostty", "Ghostty"),
        "iTerm.app": ("com.googlecode.iterm2", "iTerm"),
        "Apple_Terminal": ("com.apple.Terminal", "Terminal"),
        "WezTerm": ("com.github.wez.wezterm", "WezTerm"),
        "vscode": ("com.microsoft.VSCode", "VS Code"),
        "WarpTerminal": ("dev.warp.Warp-Stable", "Warp"),
        "cmux": ("com.cmuxterm.app", "cmux"),
    ]

    init(origin: String) {
        if let known = Self.termPrograms[origin] {
            bundleID = known.0
            name = known.1
        } else if let known = Self.termPrograms.values.first(where: { $0.0 == origin }) {
            bundleID = origin
            name = known.1
        } else if origin.contains("."), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: origin) {
            bundleID = origin
            name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        } else if origin.contains(".") {
            // Unknown bundle id: use its last component ("com.example.Foo" → "Foo").
            bundleID = origin
            let last = origin.split(separator: ".").last.map(String.init) ?? origin
            name = last.prefix(1).uppercased() + last.dropFirst()
        } else {
            bundleID = nil
            name = origin
        }
    }

    /// The app is installed, so switching to it can work.
    var canActivate: Bool {
        guard let bundleID else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    var isRunning: Bool {
        guard let bundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func activate() {
        guard let bundleID else { return }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            running.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

extension Agent {
    /// "in cmux" / "in herdr" / "in Ghostty": where it runs when that's not the Herdr app.
    var whereLabel: String? {
        switch source.id {
        case AgentSource.herdrCLI.id: return "in herdr"
        case AgentSource.cmux.id: return "in cmux"
        default: return origin.map { "in \(OriginApp(origin: $0).name)" }
        }
    }
}
