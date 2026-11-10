import IslandCore
import SwiftUI

struct PixelColor {
    let rgb: (UInt8, UInt8, UInt8)

    init(_ hex: UInt32) {
        rgb = (UInt8(hex >> 16 & 0xFF), UInt8(hex >> 8 & 0xFF), UInt8(hex & 0xFF))
    }

    var color: Color {
        Color(red: Double(rgb.0) / 255, green: Double(rgb.1) / 255, blue: Double(rgb.2) / 255)
    }
}

enum PixelPalette {
    /// Individual color pairs (light, dark) from art/final/palette.json (B / Toy Chunky);
    /// kept clear of the state colors (error red, waiting yellow).
    static let individualPairs: [(PixelColor, PixelColor)] = [
        (PixelColor(0x5EC8FF), PixelColor(0x2A6FB0)), (PixelColor(0x6EE07A), PixelColor(0x2F8A4A)),
        (PixelColor(0xD78BFF), PixelColor(0x7E43B0)), (PixelColor(0x7A8CFF), PixelColor(0x3A47B0)),
        (PixelColor(0xF06BE6), PixelColor(0x9A2E92)), (PixelColor(0x5EF0E8), PixelColor(0x1F8F8A)),
        (PixelColor(0xF4F4FF), PixelColor(0x9A9AB8)), (PixelColor(0xA8F060), PixelColor(0x5A9A2A)),
    ]

    private static func wrap(_ index: Int) -> Int {
        ((index % individualPairs.count) + individualPairs.count) % individualPairs.count
    }

    static func individual(_ index: Int) -> PixelColor { individualPairs[wrap(index)].0 }
    static func individualDark(_ index: Int) -> PixelColor { individualPairs[wrap(index)].1 }

    static let waiting = PixelColor(0xFFC93C)
    static let error = PixelColor(0xFF4A3D)
    static let working = PixelColor(0x7FD6C6)
    static let done = PixelColor(0xB9F2A6)
    static let idle = PixelColor(0xC9B8D8)
    static let unknown = PixelColor(0x9A8F8A)
    static let exited = PixelColor(0x7A6A80)
}

extension AgentState {
    var color: Color {
        switch self {
        case .needsYou: PixelPalette.waiting.color
        case .error: PixelPalette.error.color
        case .working, .starting: PixelPalette.working.color
        case .done: PixelPalette.done.color
        case .idle: PixelPalette.idle.color
        case .unknown: PixelPalette.unknown.color
        case .exited: PixelPalette.exited.color
        }
    }

    /// Non-animated cue (SF Symbol) so state never depends on motion or color alone.
    var symbol: String {
        switch self {
        case .starting: "sparkles"
        case .working: "gearshape.fill"
        case .needsYou(.question): "questionmark.bubble.fill"
        case .needsYou(.permission): "hand.raised.fill"
        case .needsYou(.auth): "lock.fill"
        case .needsYou(.unspecified): "exclamationmark.bubble.fill"
        case .done: "checkmark.circle.fill"
        case .idle: "moon.zzz.fill"
        case .error: "xmark.octagon.fill"
        case .exited: "powersleep"
        case .unknown: "questionmark.circle"
        }
    }

    /// "Needs you · Question"
    var fullLabel: String {
        if let kind = blockedKind { return "\(label) · \(kind.label)" }
        return label
    }
}

enum Format {
    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static let clockSeconds: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// "3m", "2h 5m", "12s"
    static func duration(since date: Date?, now: Date) -> String {
        guard let date else { return "–" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }

    static func ago(_ date: Date?, now: Date) -> String {
        guard date != nil else { return "—" }
        return "\(duration(since: date, now: now)) ago"
    }

    static func abbreviatePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
