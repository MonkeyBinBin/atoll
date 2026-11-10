import IslandCore
import SwiftUI

/// Island backdrop: black at the top edge (so it still merges with the notch), deep plum
/// toward the bottom, a 1px pixel rim tinted by the most urgent state, a dotted "stage"
/// under the characters, and twinkling pixel stars in the expanded top row.
struct IslandBackground: View {
    let layout: IslandLayout
    let width: CGFloat
    let expanded: Bool
    let offline: Bool
    let urgency: AgentState?
    let decorations: Bool
    let animate: Bool

    static let plum = Color(red: 0x7A / 255, green: 0x3F / 255, blue: 0x6E / 255)
    static let deepPlum = Color(red: 0x1C / 255, green: 0x0E / 255, blue: 0x1E / 255)

    var body: some View {
        ZStack(alignment: .top) {
            if offline {
                Color(white: 0.2)
            } else if decorations {
                LinearGradient(
                    stops: [.init(color: .black, location: 0), .init(color: .black, location: expanded ? 0.05 : 0.35),
                            .init(color: Self.deepPlum, location: 1)],
                    startPoint: .top, endPoint: .bottom
                )
                stage
                if expanded { stars }
            } else {
                Color.black
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

    /// Dotted 1px line along the bottom of the top row (under the characters), skipping the notch,
    /// plus the state-tinted rim along the bottom edge.
    private var stage: some View {
        Canvas { context, size in
            let rowBottom = layout.height - 2
            let gapStart = expanded ? (width - layout.centerWidth) / 2 : layout.leftWidth
            let gapEnd = gapStart + layout.centerWidth
            var x: CGFloat = 12
            while x < size.width - 12 {
                if layout.centerWidth < 8 || x < gapStart - 4 || x > gapEnd + 4 {
                    context.fill(Path(CGRect(x: x, y: rowBottom, width: 1, height: 1)), with: .color(Self.plum))
                }
                x += 3
            }
            // Bottom rim: one pixel, inset from the rounded corners.
            let inset: CGFloat = expanded ? 18 : max(layout.height / 2, 10)
            context.fill(Path(CGRect(x: inset, y: size.height - 1, width: max(size.width - inset * 2, 0), height: 1)),
                         with: .color(rimColor.opacity(urgency == nil ? 0.8 : 0.95)))
        }
        .allowsHitTesting(false)
    }

    /// A few stars in the expanded top row's free space, out of phase with each other.
    private var stars: some View {
        let side = (width - layout.centerWidth) / 2
        // Outer ends only: the hint and pinned characters hug the notch on the left, others start
        // right after it and the list button sits at the far right.
        let spots: [(CGFloat, CGFloat, String, Int)] = [
            (10, 4, "twinkle", 0), (26, 15, "twinkle_teal", 2),
            (width - side * 0.42, 5, "twinkle_teal", 3), (width - side * 0.30, 15, "twinkle", 1),
            (width - side * 0.18, 8, "twinkle", 2),
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
