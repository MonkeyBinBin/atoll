import Observation
import SwiftUI

/// Local time of day for the island backdrop; the debug hook can pin an hour for previews.
@MainActor
@Observable
final class SkyClock {
    static let shared = SkyClock()
    /// 0..<24; nil = the real local time.
    var overrideHour: Double?

    func hour(at date: Date) -> Double {
        if let overrideHour { return overrideHour }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }
}

/// Backdrop colors for an hour of the day, blended between night, dawn, day and dusk keyframes.
/// The expanded content's sea stays dark at every hour so text keeps its contrast.
struct SkyPalette {
    var horizon: Color
    var water: Color
    var waterDeep: Color
    var crest: Color
    var seaTop: Color
    var seaBottom: Color
    /// 0 (day) … 1 (night).
    var stars: Double

    private struct Key {
        var hour: Double
        var horizon, water, waterDeep, crest, seaTop, seaBottom: UInt32
        var stars: Double
    }

    private static let night = Key(hour: 0, horizon: 0x1C0E1E, water: 0x1B4652, waterDeep: 0x12303C, crest: 0x7FD6C6,
                                   seaTop: 0x0E1C26, seaBottom: 0x1C0E1E, stars: 1)
    private static let dawn = Key(hour: 0, horizon: 0xA84C66, water: 0x3A5878, waterDeep: 0x263A58, crest: 0xFFB89A,
                                  seaTop: 0x1E1A2C, seaBottom: 0x1C1020, stars: 0.3)
    private static let day = Key(hour: 0, horizon: 0x3A86C8, water: 0x1E8FA8, waterDeep: 0x136478, crest: 0xBFF4EC,
                                 seaTop: 0x0E2436, seaBottom: 0x0B1A26, stars: 0)
    private static let dusk = Key(hour: 0, horizon: 0xC0583A, water: 0x5A3E66, waterDeep: 0x3A2848, crest: 0xFFC08A,
                                  seaTop: 0x22161E, seaBottom: 0x1E1018, stars: 0.3)

    private static let keys: [Key] = [
        (0, night), (4.75, night), (6, dawn), (7.5, day), (16.5, day), (18, dusk), (19.25, night), (24, night),
    ].map { hour, key in
        var k = key
        k.hour = hour
        return k
    }

    static func at(hour: Double) -> SkyPalette {
        let h = min(max(hour, 0), 24)
        let upper = keys.firstIndex { $0.hour >= h } ?? keys.count - 1
        let b = keys[upper]
        let a = keys[max(upper - 1, 0)]
        let t = b.hour > a.hour ? (h - a.hour) / (b.hour - a.hour) : 0
        func mix(_ x: UInt32, _ y: UInt32) -> Color {
            func channel(_ shift: UInt32) -> Double {
                let p = Double(x >> shift & 0xFF), q = Double(y >> shift & 0xFF)
                return (p + (q - p) * t) / 255
            }
            return Color(red: channel(16), green: channel(8), blue: channel(0))
        }
        return SkyPalette(
            horizon: mix(a.horizon, b.horizon), water: mix(a.water, b.water), waterDeep: mix(a.waterDeep, b.waterDeep),
            crest: mix(a.crest, b.crest), seaTop: mix(a.seaTop, b.seaTop), seaBottom: mix(a.seaBottom, b.seaBottom),
            stars: a.stars + (b.stars - a.stars) * t
        )
    }

    /// Sun by day (6–18), moon by night: which one, and how far along its arc (0 rise … 1 set).
    static func celestial(hour: Double) -> (sun: Bool, progress: Double) {
        if hour >= 6 && hour < 18 { return (true, (hour - 6) / 12) }
        let since = hour >= 18 ? hour - 18 : hour + 6
        return (false, since / 12)
    }
}
