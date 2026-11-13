import AtollCore
import SwiftUI

/// Where a character stands, for its islet in the backdrop (island-view coordinates).
struct Islet: Equatable {
    var midX: CGFloat
    /// Bottom of the 16px sprite: the islet's top.
    var feetY: CGFloat
    var state: AgentState
}

/// Island backdrop, "an atoll through the day": black at the top edge (so it still merges with the notch)
/// fading to a sky that follows the local time (night plum, dawn rose, day blue, dusk orange, see SkyPalette); along the bottom of the top row a pixel lagoon with drifting wave crests, each
/// character standing on its own sand islet, the water under a waiting / failing agent shimmering in
/// its state color, and now and then a fish jumping. Expanded: the sun or moon crossing the top row
/// with the hour, stars at night, and deep water under the content. A 1px rim along the bottom edge is tinted by the most urgent state.
struct IslandBackground: View {
    let layout: IslandLayout
    let width: CGFloat
    let expanded: Bool
    let offline: Bool
    let urgency: AgentState?
    let islets: [Islet]
    let decorations: Bool
    let animate: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var calm: Bool { !expanded && urgency == nil }

    static let plum = Color(red: 0x7A / 255, green: 0x3F / 255, blue: 0x6E / 255)

    enum Lagoon {
        static let water = PixelColor(0x1B4652).color
        static let waterDeep = PixelColor(0x12303C).color
        static let crest = PixelColor(0x7FD6C6).color
        static let foam = PixelColor(0xFFF8EC).color
        static let sandLight = PixelColor(0xFFE2B5).color
        static let sand = PixelColor(0xE39A63).color
        static let sandWet = PixelColor(0x9A5A48).color
        static let fish = PixelColor(0xFF9A6B).color
        static let moon = PixelColor(0xFFF8EC).color
        static let moonShade = PixelColor(0xC9B8D8).color
        static let sun = PixelColor(0xFFF1B8).color
        static let sunEdge = PixelColor(0xFFD873).color
        static let sunShade = PixelColor(0xF0A848).color
    }

    /// Rows of water along the bottom of the top row.
    static let waterRows = 4

    var body: some View {
        ZStack(alignment: .top) {
            if offline {
                Color(white: 0.2)
            } else if decorations {
                TimelineView(.everyMinute) { clock in
                    let hour = SkyClock.shared.hour(at: clock.date)
                    let palette = SkyPalette.at(hour: hour)
                    ZStack(alignment: .top) {
                        sky(palette)
                        if animate && !reduceMotion {
                            // Collapsed with nobody waiting, the lagoon drifts at a calmer 2 fps.
                            TimelineView(.animation(minimumInterval: calm ? 0.5 : 0.2)) { context in
                                scene(time: context.date.timeIntervalSinceReferenceDate, palette: palette, hour: hour)
                            }
                        } else {
                            scene(time: nil, palette: palette, hour: hour)
                        }
                        if expanded && palette.stars > 0.05 { stars.opacity(palette.stars) }
                    }
                }
            } else {
                Color.black
            }
        }
    }

    private func sky(_ palette: SkyPalette) -> some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [.init(color: .black, location: 0), .init(color: .black, location: expanded ? 0.2 : 0.35),
                        .init(color: palette.horizon, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: layout.height)
            if expanded {
                LinearGradient(colors: [palette.seaTop, palette.seaBottom], startPoint: .top, endPoint: .bottom)
            }
        }
    }

    private var rimColor: Color {
        switch urgency {
        case .needsYou?: PixelPalette.waiting.color
        case .error?: PixelPalette.error.color
        default: Self.plum
        }
    }

    /// `time` nil: a still frame (animations off or Reduce Motion).
    private func scene(time: TimeInterval?, palette: SkyPalette, hour: Double) -> some View {
        Canvas { context, size in
            let h = layout.height
            let top = h - CGFloat(Self.waterRows)
            let step = time.map { Int($0 * 2.5) } ?? 0
            func px(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 1, _ color: Color) {
                context.fill(Path(CGRect(x: x, y: y, width: w, height: 1)), with: .color(color))
            }

            // First, behind the islets; clipped at the water line, so the sun / moon rises out of the lagoon.
            if expanded { celestial(context: context, size: size, hour: hour) }

            // Water, darker toward the bottom.
            for row in 0..<Self.waterRows {
                px(0, top + CGFloat(row), size.width, row < 2 ? palette.water : palette.waterDeep)
            }
            // Wave crests drifting right; a second, slower set one row lower.
            var x: CGFloat = 0
            while x < size.width {
                let i = Int(x)
                if (i - step).mod(14) < 3 { px(x, top, 1, palette.crest.opacity(0.75)) }
                if (i + step / 2 + 7).mod(19) < 2 { px(x, top + 1, 1, palette.crest.opacity(0.35)) }
                x += 1
            }

            // State shimmer: the water under a waiting / failing agent catches its light.
            for islet in islets {
                guard let color = Self.shimmer(islet.state) else { continue }
                for row in 1..<Self.waterRows {
                    let flicker = (step + row * 3 + Int(islet.midX)).mod(4)
                    let len: CGFloat = flicker == 0 ? 2 : 4
                    let offset = CGFloat((row * 5 + step).mod(7)) - 3
                    px((islet.midX - 13 + offset).rounded(), top + CGFloat(row), len, color.opacity(0.8))
                    px((islet.midX + 9 - offset).rounded(), top + CGFloat(row), len, color.opacity(0.8))
                }
            }

            // One sand islet per character: a little mound from its feet down into the water.
            for islet in islets {
                let feet = islet.feetY.rounded()
                var y = feet
                var w: CGFloat = 10
                while y < h {
                    let color: Color = y >= top + 2 ? Lagoon.sandWet : (y >= top ? Lagoon.sand : (y == feet ? Lagoon.sandLight : Lagoon.sand))
                    px((islet.midX - w / 2).rounded(), y, w, color)
                    if y == top { // foam where the islet meets the water
                        px((islet.midX - w / 2 - 1).rounded(), y, 1, Lagoon.foam.opacity(step.mod(2) == 0 ? 0.9 : 0.5))
                        px((islet.midX + w / 2).rounded(), y, 1, Lagoon.foam.opacity(step.mod(2) == 0 ? 0.5 : 0.9))
                    }
                    w = min(w + 2, 18)
                    y += 1
                }
            }

            if let time { fish(context: context, size: size, top: top, time: time) }

            // Bottom rim: one pixel, inset from the rounded corners.
            let inset: CGFloat = expanded ? 18 : max(h / 2, 10)
            px(inset, size.height - 1, max(size.width - inset * 2, 0), rimColor.opacity(urgency == nil ? 0.8 : 0.95))
        }
        .allowsHitTesting(false)
    }

    static func shimmer(_ state: AgentState) -> Color? {
        switch state {
        case .needsYou: PixelPalette.waiting.color
        case .error: PixelPalette.error.color
        default: nil
        }
    }

    /// Every 17 s a fish arcs out of open water (clear of the islets and the notch) and splashes back.
    private func fish(context: GraphicsContext, size: CGSize, top: CGFloat, time: TimeInterval) {
        let period = 17.0, jump = 1.4, span: CGFloat = 14
        let cycle = Int(time / period)
        let t = time - Double(cycle) * period
        guard t < jump + 0.4 else { return }
        // Open stretches of water, deterministic per cycle.
        let notchStart = expanded ? (width - layout.centerWidth) / 2 : layout.leftWidth
        let notchEnd = notchStart + layout.centerWidth
        var spots: [CGFloat] = []
        var x: CGFloat = 16
        while x + span < size.width - 16 {
            let clearOfNotch = layout.centerWidth < 8 || x + span < notchStart - 2 || x > notchEnd + 2
            let clearOfIslets = islets.allSatisfy { abs($0.midX - (x + span / 2)) > 9 + span / 2 }
            if clearOfNotch && clearOfIslets { spots.append(x) }
            x += 4
        }
        guard !spots.isEmpty else { return }
        let start = spots[(cycle &* 7919).mod(spots.count)]
        func px(_ x: CGFloat, _ y: CGFloat, _ color: Color) {
            context.fill(Path(CGRect(x: x.rounded(), y: y.rounded(), width: 1, height: 1)), with: .color(color))
        }
        if t < jump {
            let p = t / jump
            let fx = start + span * p
            let fy = top - 1 - 7 * CGFloat(sin(.pi * p))
            px(fx, fy, Lagoon.fish)
            px(fx - 1, fy, Lagoon.fish)
            px(fx - 2, fy + (p < 0.5 ? 1 : -1), Lagoon.fish.opacity(0.8)) // tail trails the arc
            if p < 0.15 { px(start - 1, top - 1, Lagoon.foam); px(start + 1, top - 1, Lagoon.foam) }
        } else {
            // Splash where it lands.
            let s = start + span
            let k = (t - jump) / 0.4
            px(s - 1 - CGFloat(k * 2), top - 1 - CGFloat(k * 2), Lagoon.foam.opacity(1 - k))
            px(s + 1 + CGFloat(k * 2), top - 1 - CGFloat(k * 2), Lagoon.foam.opacity(1 - k))
            px(s, top - 2 - CGFloat(k * 3), Lagoon.foam.opacity(1 - k))
        }
    }

    /// The sun (day) or a crescent moon (night) arcing across the expanded top row with the hour,
    /// clipped at the water line so it rises out of and sets into the lagoon.
    private func celestial(context: GraphicsContext, size: CGSize, hour: Double) {
        let sun = [
            "..sss..",
            ".sllls.",
            "sllllls",
            "slllllS",
            "sllllSS",
            ".slSSS.",
            "..SSS..",
        ]
        let moon = [
            "..mmm..",
            ".mmms..",
            "mmms...",
            "mmms...",
            "mmms...",
            ".mmms..",
            "..mmm..",
        ]
        let (isSun, progress) = SkyPalette.celestial(hour: hour)
        let waterTop = layout.height - CGFloat(Self.waterRows)
        let low = waterTop - 2, high: CGFloat = 1
        let x = (10 + (size.width - 27) * progress).rounded()
        let y = (low - (low - high) * sin(.pi * progress)).rounded()
        let colors: [Character: Color] = [
            "s": Lagoon.sunEdge, "l": Lagoon.sun, "S": Lagoon.sunShade, "m": Lagoon.moon,
        ]
        for (r, row) in (isSun ? sun : moon).enumerated() {
            let py = y + CGFloat(r)
            guard py < waterTop else { break }
            for (c, ch) in row.enumerated() where ch != "." {
                context.fill(Path(CGRect(x: x + CGFloat(c), y: py, width: 1, height: 1)),
                             with: .color(colors[ch] ?? Lagoon.moonShade))
            }
        }
    }

    /// A few stars in the expanded top row's free space, out of phase with each other.
    private var stars: some View {
        let side = (width - layout.centerWidth) / 2
        // Outer ends only: the hint and pinned characters hug the notch on the left, others start
        // right after it and the buttons sit at the far right.
        let spots: [(CGFloat, CGFloat, String, Int)] = [
            (26, 2, "twinkle", 0), (36, 11, "twinkle_teal", 2),
            (width - side * 0.42, 3, "twinkle_teal", 3), (width - side * 0.30, 12, "twinkle", 1),
            (width - side * 0.18, 6, "twinkle", 2),
        ]
        return ZStack(alignment: .topLeading) {
            ForEach(Array(spots.enumerated()), id: \.offset) { _, spot in
                TwinkleView(tag: spot.2, phase: spot.3, animate: animate)
                    .offset(x: spot.0.rounded(), y: spot.1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

private extension Int {
    /// Non-negative remainder.
    func mod(_ n: Int) -> Int { ((self % n) + n) % n }
}

struct TwinkleView: View {
    let tag: String
    let phase: Int
    let animate: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let sheet = SpriteLibrary.deco, let t = sheet.tags[tag] {
            if animate && !reduceMotion {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let step = Int(context.date.timeIntervalSinceReferenceDate * 2) + phase
                    frame(sheet, t.from + step % t.count)
                }
            } else {
                frame(sheet, t.from + 1)
            }
        }
    }

    @ViewBuilder
    private func frame(_ sheet: SpriteSheet, _ index: Int) -> some View {
        if let image = sheet.frame(index, colorIndex: 0) {
            Image(decorative: image, scale: 1).interpolation(.none).resizable().frame(width: 5, height: 5)
        }
    }
}
