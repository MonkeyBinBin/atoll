import AppKit
import AtollCore
import SwiftUI

/// A sprite sheet in the app's asset format: transparent PNG + Aseprite-style JSON.
final class SpriteSheet: @unchecked Sendable {
    struct Frame {
        let rect: CGRect
        let duration: TimeInterval
    }

    struct Tag {
        let name: String
        let from: Int
        let to: Int
        let loop: Bool
        /// Tag to continue with after a one-shot (Done → idle).
        let next: String?

        var count: Int { to - from + 1 }
    }

    let frameSize: CGSize
    let frames: [Frame]
    let tags: [String: Tag]
    private let image: CGImage
    private let accessoryKey: (UInt8, UInt8, UInt8)?
    private let accessoryKeyDark: (UInt8, UInt8, UInt8)?
    private var recolored: [Int: CGImage] = [:]
    private var frameCache: [String: CGImage] = [:]
    private let lock = NSLock()

    init?(name: String) {
        guard let jsonURL = Self.resource(name, "json"),
              let data = try? Data(contentsOf: jsonURL),
              let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let meta = doc["meta"] as? [String: Any],
              let imageName = meta["image"] as? String,
              let imageURL = Self.resource((imageName as NSString).deletingPathExtension, "png"),
              let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        self.image = image
        let size = meta["frameSize"] as? [String: Any]
        frameSize = CGSize(width: size?["w"] as? Int ?? 16, height: size?["h"] as? Int ?? 16)
        frames = (doc["frames"] as? [[String: Any]] ?? []).map { f in
            let r = f["frame"] as? [String: Int] ?? [:]
            return Frame(
                rect: CGRect(x: r["x"] ?? 0, y: r["y"] ?? 0, width: r["w"] ?? 16, height: r["h"] ?? 16),
                duration: Double(f["duration"] as? Int ?? 250) / 1000
            )
        }
        var tags: [String: Tag] = [:]
        for t in meta["frameTags"] as? [[String: Any]] ?? [] {
            guard let name = t["name"] as? String else { continue }
            tags[name] = Tag(
                name: name,
                from: t["from"] as? Int ?? 0,
                to: t["to"] as? Int ?? 0,
                loop: t["loop"] as? Bool ?? true,
                next: t["next"] as? String
            )
        }
        self.tags = tags
        if let hex = meta["accessoryKey"] as? String, let rgb = Self.parseHex(hex) {
            accessoryKey = rgb
        } else {
            accessoryKey = nil
        }
        accessoryKeyDark = (meta["accessoryKeyDark"] as? String).flatMap(Self.parseHex)
    }

    /// Sprites/ inside the .app's Resources, else SwiftPM's resource bundle (`swift run`).
    static func resource(_ name: String, _ ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Sprites") { return url }
        if Bundle.main.bundleURL.pathExtension == "app" { return nil }
        return Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Sprites")
    }

    static func parseHex(_ hex: String) -> (UInt8, UInt8, UInt8)? {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return (UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF))
    }

    /// One frame with the accessory key swapped for the individual color.
    func frame(_ index: Int, colorIndex: Int) -> CGImage? {
        guard frames.indices.contains(index) else { return nil }
        let cacheKey = "\(index)-\(colorIndex)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = frameCache[cacheKey] { return cached }
        let sheet = recoloredSheet(colorIndex)
        guard let cropped = sheet.cropping(to: frames[index].rect) else { return nil }
        frameCache[cacheKey] = cropped
        return cropped
    }

    private func recoloredSheet(_ colorIndex: Int) -> CGImage {
        if let cached = recolored[colorIndex] { return cached }
        guard let key = accessoryKey else { return image }
        let target = PixelPalette.individual(colorIndex).rgb
        let targetDark = PixelPalette.individualDark(colorIndex).rgb
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] == 255 {
            if pixels[i] == key.0, pixels[i + 1] == key.1, pixels[i + 2] == key.2 {
                pixels[i] = target.0
                pixels[i + 1] = target.1
                pixels[i + 2] = target.2
            } else if let dark = accessoryKeyDark, pixels[i] == dark.0, pixels[i + 1] == dark.1, pixels[i + 2] == dark.2 {
                pixels[i] = targetDark.0
                pixels[i + 1] = targetDark.1
                pixels[i + 2] = targetDark.2
            }
        }
        let result = context.makeImage() ?? image
        recolored[colorIndex] = result
        return result
    }
}

@MainActor
enum SpriteLibrary {
    static let sheets: [AgentTool: SpriteSheet] = {
        var result: [AgentTool: SpriteSheet] = [:]
        result[.claudeCode] = SpriteSheet(name: "claude")
        result[.codex] = SpriteSheet(name: "codex")
        result[.generic] = SpriteSheet(name: "generic")
        return result
    }()

    static let icons = SpriteSheet(name: "icons")
    static let effects = SpriteSheet(name: "effects")
    static let ui = SpriteSheet(name: "ui")
    static let deco = SpriteSheet(name: "deco")

    static func sheet(for tool: AgentTool) -> SpriteSheet? {
        sheets[tool] ?? sheets[.generic]
    }

    static func tagName(for agent: Agent) -> String {
        if agent.interruptFeedback != nil { return "interrupted" }
        switch agent.state {
        case .starting: return "starting"
        case .working: return "working"
        case .needsYou: return "needs_you"
        case .done: return agent.acknowledged ? "idle" : "done"
        case .idle: return "idle"
        case .error: return "error"
        case .exited: return "exited"
        case .unknown: return "unknown"
        }
    }
}

/// Plays a sprite tag: loops, or plays once and holds / continues with `next`.
/// Integer nearest-neighbor scaling only. Reduced motion / animations off → frame 0.
struct SpriteView: View {
    let tool: AgentTool
    let tag: String
    let colorIndex: Int
    var scale: Int = 1
    var animate: Bool = true
    /// After this long in a looping state, calm down to slow breathing (collapsed island).
    /// nil plays the full loop indefinitely (panels the user is interacting with).
    var settleAfter: TimeInterval? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    var body: some View {
        let sheet = SpriteLibrary.sheet(for: tool)
        let size = (sheet?.frameSize ?? CGSize(width: 16, height: 16))
        let still = !animate || reduceMotion || (sheet?.tags[tag]?.count ?? 1) <= 1
        Group {
            if still || sheet == nil {
                frameImage(sheet: sheet, index: sheet?.tags[tag]?.from ?? 0)
            } else {
                TimelineView(SpriteSchedule(start: startedAt, tick: tickInterval(sheet: sheet!), settleAfter: settleAfter)) { context in
                    frameImage(sheet: sheet, index: frameIndex(sheet: sheet!, at: context.date))
                }
            }
        }
        .frame(width: size.width * CGFloat(scale), height: size.height * CGFloat(scale))
        .onChange(of: tag) { startedAt = Date() }
    }

    @ViewBuilder
    private func frameImage(sheet: SpriteSheet?, index: Int) -> some View {
        if let image = sheet?.frame(index, colorIndex: colorIndex) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
        } else {
            Circle().fill(.gray)
        }
    }

    /// Shortest frame duration of the tag (and its follow-up): idle breathing ticks at ~1 Hz.
    private func tickInterval(sheet: SpriteSheet) -> TimeInterval {
        var names = [tag]
        if let next = sheet.tags[tag]?.next { names.append(next) }
        let durations = names.compactMap { sheet.tags[$0] }.flatMap { t in
            (t.from...t.to).compactMap { sheet.frames.indices.contains($0) ? sheet.frames[$0].duration : nil }
        }
        return max(durations.min() ?? 0.25, 1.0 / 30)
    }

    private func frameIndex(sheet: SpriteSheet, at date: Date) -> Int {
        var elapsed = date.timeIntervalSince(startedAt)
        var current = sheet.tags[tag]
        var guardCount = 0
        while let t = current, guardCount < 4 {
            guardCount += 1
            let durations = (t.from...t.to).map { sheet.frames.indices.contains($0) ? sheet.frames[$0].duration : 0.25 }
            let total = durations.reduce(0, +)
            if total <= 0 { return t.from }
            if t.loop, let settleAfter, elapsed > settleAfter, t.count > 1 {
                // Calm breathing: alternate the tag's first two frames once a second.
                return t.from + Int(elapsed) % 2
            }
            if t.loop {
                elapsed = elapsed.truncatingRemainder(dividingBy: total)
            } else if elapsed >= total {
                if let next = t.next, let nextTag = sheet.tags[next] {
                    elapsed -= total
                    current = nextTag
                    continue
                }
                return t.to
            }
            var acc = 0.0
            for (offset, d) in durations.enumerated() {
                acc += d
                if elapsed < acc { return t.from + offset }
            }
            return t.to
        }
        return 0
    }

    /// Whether this tag is still moving (one-shots finish and stop the timeline).
    static func isAnimated(_ tag: String) -> Bool {
        !["exited", "unknown"].contains(tag)
    }
}

/// One-shot overlay effect (send / celebrate) drawn on top of a character; plays once.
struct EffectView: View {
    let tag: String
    let startedAt: Date
    var scale: Int = 1

    var body: some View {
        if let sheet = SpriteLibrary.effects, let t = sheet.tags[tag] {
            let durations = (t.from...t.to).map { sheet.frames.indices.contains($0) ? sheet.frames[$0].duration : 0.1 }
            TimelineView(.periodic(from: startedAt, by: durations.min() ?? 0.1)) { context in
                let elapsed = context.date.timeIntervalSince(startedAt)
                if let index = Self.frame(elapsed: elapsed, from: t.from, durations: durations),
                   let image = sheet.frame(index, colorIndex: 0) {
                    Image(decorative: image, scale: 1)
                        .interpolation(.none)
                        .resizable()
                }
            }
            .frame(width: 16 * CGFloat(scale), height: 16 * CGFloat(scale))
            .allowsHitTesting(false)
        }
    }

    static func frame(elapsed: TimeInterval, from: Int, durations: [TimeInterval]) -> Int? {
        var acc = 0.0
        for (offset, d) in durations.enumerated() {
            acc += d
            if elapsed < acc { return from + offset }
        }
        return nil
    }

    static func duration(_ tag: String) -> TimeInterval {
        guard let sheet = SpriteLibrary.effects, let t = sheet.tags[tag] else { return 0 }
        return (t.from...t.to).reduce(0) { $0 + (sheet.frames.indices.contains($1) ? sheet.frames[$1].duration : 0) }
    }
}

/// A character with its kind bubble and one-shot effects: celebrate on a fresh Done,
/// message fly-out when a send is delivered (never on failure).
struct AgentSprite: View {
    let agent: Agent
    let store: AgentStore
    var scale: Int = 1
    var settleAfter: TimeInterval? = nil
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var effect: (tag: String, start: Date)?

    var body: some View {
        let tag = SpriteLibrary.tagName(for: agent)
        ZStack(alignment: .topTrailing) {
            SpriteView(tool: agent.tool, tag: tag, colorIndex: agent.colorIndex, scale: scale,
                       animate: settings.animationsEnabled, settleAfter: settleAfter)
            if let effect {
                EffectView(tag: effect.tag, startedAt: effect.start, scale: scale)
                    .id(effect.start)
            }
        }
        .overlay(alignment: .topLeading) {
            // Top-left: the raised hand of needs_you is on the right.
            if let kind = agent.state.blockedKind {
                StatusBubbleView(kind: kind, scale: scale)
                    .offset(x: -4 * CGFloat(scale), y: -3 * CGFloat(scale))
            }
        }
        .frame(width: 16 * CGFloat(scale), height: 16 * CGFloat(scale))
        .onChange(of: tag) { old, new in
            if new == "done", old != "done" { play("celebrate") }
        }
        .onChange(of: store.sendStates[agent.address]) { _, new in
            switch new {
            case .delivered, .started, .unconfirmed: play("send")
            default: break
            }
        }
    }

    private func play(_ name: String) {
        guard settings.animationsEnabled, !reduceMotion else { return }
        let start = Date()
        effect = (name, start)
        DispatchQueue.main.asyncAfter(deadline: .now() + EffectView.duration(name) + 0.05) {
            if effect?.start == start { effect = nil }
        }
    }
}

/// Fast ticks while a state animation plays, then 1 Hz once settled.
struct SpriteSchedule: TimelineSchedule {
    let start: Date
    let tick: TimeInterval
    let settleAfter: TimeInterval?

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next = max(startDate, start)
        let settleDate = settleAfter.map { start.addingTimeInterval($0) }
        return AnyIterator {
            let current = next
            let step = (settleDate.map { current >= $0 } ?? false) || mode == .lowFrequency ? 1.0 : tick
            next = current.addingTimeInterval(step)
            return current
        }
    }
}

/// A still pixel icon from the UI sheet (same pipeline and palette as the characters).
struct PixelIconView: View {
    let tag: String
    var scale: Int = 1

    var body: some View {
        if let sheet = SpriteLibrary.ui, let t = sheet.tags[tag], let image = sheet.frame(t.from, colorIndex: 0) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: sheet.frameSize.width * CGFloat(scale), height: sheet.frameSize.height * CGFloat(scale))
        }
    }
}

/// 8×8 pixel status bubble for blocked kinds.
struct StatusBubbleView: View {
    let kind: BlockedKind
    var scale: Int = 1

    var body: some View {
        let name = switch kind {
        case .question, .unspecified: "question"
        case .permission: "permission"
        case .auth: "auth"
        }
        if let sheet = SpriteLibrary.icons, let tag = sheet.tags[name], let image = sheet.frame(tag.from, colorIndex: 0) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: 8 * CGFloat(scale), height: 8 * CGFloat(scale))
        }
    }
}
