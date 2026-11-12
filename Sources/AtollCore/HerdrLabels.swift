import Foundation

/// Herdr's terminal labels in herdr-core. The Herdr app labels each terminal it shows with its space and tab
/// (`herdr.space`, `herdr.tab`) and where that is by name (`where` = "<space> / <tab>"). The labels outlive the
/// app, and a terminal started with them shows up in that space and tab when the app opens; an id Herdr doesn't
/// know becomes a new space or tab (verified on Herdr 0.1.15).
public enum HerdrLabels {
    public static let space = "herdr.space"
    public static let tab = "herdr.tab"
    public static let location = "where"

    /// The spaces offered while the Herdr app isn't running: the last ones read from it, renamed and extended
    /// by what live terminals' labels say now. Cached order first, then spaces only the labels know.
    public static func spaces(cached: [HerdrSpace], terminals: [TerminalInfo]) -> [HerdrSpace] {
        var result = cached
        var index = Dictionary(result.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        for terminal in terminals where terminal.state == "live" {
            guard let id = terminal.labels[space], !id.isEmpty else { continue }
            let name = terminal.labels[location].flatMap(spaceName(where:))
            if let at = index[id] {
                if let name { result[at].name = name }
                if !result[at].terminals.contains(terminal.address) { result[at].terminals.append(terminal.address) }
            } else {
                index[id] = result.count
                result.append(HerdrSpace(id: id, name: name ?? id, terminals: [terminal.address]))
            }
        }
        return result
    }

    /// The space part of a `where` label ("atoll / 2" → "atoll"); a space name may itself contain " / ".
    static func spaceName(where label: String) -> String? {
        guard let range = label.range(of: " / ", options: .backwards) else { return nil }
        let name = String(label[..<range.lowerBound])
        return name.isEmpty ? nil : name
    }

    /// The space a launch without the app goes to: the one picked, else the one the window showed last, else
    /// the first known; nil when none is known (start a new one).
    public static func target(picked: String?, spaces: [HerdrSpace]) -> String? {
        if let picked, !picked.isEmpty { return picked }
        return (spaces.first(where: \.active) ?? spaces.first)?.id
    }

    /// A fresh space or tab id in Herdr's shape (`sp` / `tb` + 32 hex digits).
    public static func newID(_ prefix: String) -> String {
        prefix + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}
