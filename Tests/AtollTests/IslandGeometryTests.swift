import AppKit
import AtollCore
import Testing
@testable import Atoll

// A 14" MacBook Pro: 188pt notch between two 662pt menu bar areas, 32pt safe area.
private let laptop = ScreenGeometry.of(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
    safeAreaTop: 32,
    leftArea: CGRect(x: 0, y: 950, width: 662, height: 32),
    rightArea: CGRect(x: 850, y: 950, width: 662, height: 32)
)
// An external display to the laptop's right, 25pt menu bar.
private let external = ScreenGeometry.of(
    frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
    visibleFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1415),
    safeAreaTop: 0, leftArea: nil, rightArea: nil
)

private func agent(_ id: String, _ state: AgentState) -> Agent {
    Agent(address: id, name: "web", tool: .claudeCode, state: state)
}

private func agents(_ count: Int, _ state: AgentState) -> [Agent] {
    (0..<count).map { agent("a\($0)", state) }
}

/// What `IslandLayout.compute` reserves for a text, measured with the real font.
private func width(_ text: String, _ font: NSFont, extra: CGFloat) -> CGFloat {
    ceil((text as NSString).size(withAttributes: [.font: font]).width) + extra
}

private let slot = IslandLayout.slot
private let padding = IslandLayout.padding
private let buttons = IslandLayout.buttonsWidth

@Suite("ScreenGeometry")
struct ScreenGeometryTests {
    @Test("a notch: its position and the room beside it from the menu bar areas; the bar is the safe area")
    func notch() {
        #expect(laptop.hasNotch)
        #expect(laptop.notchMinX == 662)
        #expect(laptop.notchWidth == 188)
        #expect(laptop.leftRoom == 662)
        #expect(laptop.rightRoom == 662)
        #expect(laptop.barHeight == 32)
    }

    @Test("no notch: centered with half the screen on each side; the bar is the menu bar, 24…30pt")
    func noNotch() {
        #expect(!external.hasNotch)
        #expect(external.notchMinX == 2792)
        #expect(external.notchWidth == 0)
        #expect(external.leftRoom == 1280)
        #expect(external.rightRoom == 1280)
        #expect(external.barHeight == 25)
        func bar(menuBar: CGFloat) -> CGFloat {
            ScreenGeometry.of(
                frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800 - menuBar),
                safeAreaTop: 0, leftArea: nil, rightArea: nil
            ).barHeight
        }
        #expect(bar(menuBar: 0) == 24) // a hidden menu bar
        #expect(bar(menuBar: 40) == 30)
    }

    @Test("a safe area without the menu bar areas isn't a notch")
    func safeAreaAlone() {
        let geometry = ScreenGeometry.of(
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 775),
            safeAreaTop: 32, leftArea: nil, rightArea: nil
        )
        #expect(!geometry.hasNotch)
        #expect(geometry.barHeight == 25)
    }
}

@Suite("IslandLayout")
struct IslandLayoutTests {
    @Test("an empty island is a small capsule with the empty icon and the buttons")
    func empty() {
        let flat = IslandLayout.compute(agents: [], geometry: external, offlineText: nil)
        // 22pt high on a 25pt bar: the ends are inset 1pt past the rounding.
        #expect(flat.height == 22)
        #expect(flat.endInset == 1)
        #expect(flat.leftWidth == 0)
        #expect(flat.centerWidth == 0)
        #expect(flat.rightWidth == slot + padding * 2 + buttons + 1)

        let notched = IslandLayout.compute(agents: [], geometry: laptop, offlineText: nil)
        #expect(notched.height == 32)
        #expect(notched.endInset == 0)
        #expect(notched.leftWidth == padding)
        #expect(notched.centerWidth == 188)
        #expect(notched.rightWidth == slot + padding * 2 + buttons)
    }

    @Test("Needs you and Error are pinned left with a hint; the rest go right")
    func pinned() {
        let list = [agent("w", .working), agent("n1", .needsYou(.permission)), agent("e", .error), agent("n2", .needsYou(.question))]
        let layout = IslandLayout.compute(agents: list, geometry: external, offlineText: nil)
        #expect(layout.pinned.map(\.address) == ["n1", "e", "n2"])
        #expect(layout.others.map(\.address) == ["w"])
        #expect(layout.hint == "Claude Code · web needs you +2")
        let hint = width("Claude Code · web needs you +2", IslandLayout.hintFont, extra: 8)
        #expect(layout.leftWidth == padding * 2 + 3 * slot + hint + 1)
        #expect(layout.rightWidth == slot + padding * 2 + buttons + 1)
        #expect(layout.centerWidth == 6)

        let error = IslandLayout.compute(agents: [agent("e", .error)], geometry: external, offlineText: nil)
        #expect(error.hint == "Claude Code · web has an error")
    }

    @Test("an offline text replaces the hint, even with nothing pinned")
    func offline() {
        let layout = IslandLayout.compute(
            agents: [agent("n", .needsYou(.permission))], geometry: external, offlineText: "Herdr offline"
        )
        #expect(layout.hint == "Herdr offline")
        let quiet = IslandLayout.compute(agents: [], geometry: external, offlineText: "Herdr offline")
        let hint = width("Herdr offline", IslandLayout.hintFont, extra: 8)
        #expect(quiet.leftWidth == padding * 2 + hint + 1)
        // Not the empty capsule: the right wing has only the buttons.
        #expect(quiet.rightWidth == buttons + 1)
    }

    @Test("the right wing shows up to 8 characters, then scrolls")
    func rightWing() {
        let eight = IslandLayout.compute(agents: agents(8, .working), geometry: external, offlineText: nil)
        #expect(eight.rightWidth == 8 * slot + padding * 2 + buttons + 1)
        #expect(!eight.rightScrolls)
        let twelve = IslandLayout.compute(agents: agents(12, .working), geometry: external, offlineText: nil)
        #expect(twelve.rightWidth == eight.rightWidth)
        #expect(twelve.rightScrolls)
    }

    @Test("each wing stops 40pt short of the room beside the notch, 360pt without one")
    func wingLimits() {
        let narrow = ScreenGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 600, height: 400), hasNotch: true,
            notchMinX: 200, notchWidth: 200, barHeight: 32, leftRoom: 200, rightRoom: 200
        )
        let many = agents(12, .needsYou(.permission)) + agents(12, .working)
        let tight = IslandLayout.compute(agents: many, geometry: narrow, offlineText: nil)
        #expect(tight.leftWidth == 160)
        #expect(tight.rightWidth == 160 + buttons)
        #expect(tight.rightScrolls)

        let flat = IslandLayout.compute(agents: agents(30, .needsYou(.permission)), geometry: external, offlineText: nil)
        #expect(flat.leftWidth == 361)
    }

    @Test("with a notch, each wing keeps at least its padding")
    func notchPadding() {
        let onlyPinned = IslandLayout.compute(agents: [agent("n", .needsYou(.permission))], geometry: laptop, offlineText: nil)
        #expect(onlyPinned.rightWidth == padding + buttons)
        let onlyOthers = IslandLayout.compute(agents: [agent("w", .working)], geometry: laptop, offlineText: nil)
        #expect(onlyOthers.leftWidth == padding)
    }

    @Test("a space label sits before the characters, capped at 110pt, and stays with none left to show")
    func spaceLabel() {
        let label = width("atoll +3", IslandLayout.spaceFont, extra: 4)
        let two = IslandLayout.compute(agents: agents(2, .working), geometry: external, offlineText: nil, spaceLabel: "atoll +3")
        #expect(two.spaceLabel == "atoll +3")
        #expect(two.rightWidth == 2 * slot + padding * 2 + label + buttons + 1)

        let none = IslandLayout.compute(agents: [], geometry: external, offlineText: nil, spaceLabel: "atoll +3")
        #expect(none.rightWidth == padding * 2 + label + buttons + 1)
        #expect(none.leftWidth == 0)

        let long = String(repeating: "a-very-long-space-name ", count: 4)
        let capped = IslandLayout.compute(agents: [], geometry: external, offlineText: nil, spaceLabel: long)
        #expect(capped.rightWidth == padding * 2 + 110 + buttons + 1)
    }
}

@Suite("Island window frame")
struct IslandFrameTests {
    private func layout(left: CGFloat, center: CGFloat, right: CGFloat, height: CGFloat) -> IslandLayout {
        IslandLayout(
            pinned: [], others: [], hint: nil, leftWidth: left, rightWidth: right,
            centerWidth: center, height: height, rightScrolls: false
        )
    }

    @Test("collapsed under a notch: the left wing ends where the notch starts, flush with the top")
    func notchCollapsed() {
        let frame = laptop.islandFrame(layout: layout(left: 100, center: 188, right: 150, height: 32), expanded: nil)
        #expect(frame == CGRect(x: 562, y: 950, width: 438, height: 32))
        #expect(frame.minX + 100 == laptop.notchMinX)
    }

    @Test("collapsed without a notch: centered on the screen, 2pt below its top")
    func flatCollapsed() {
        let frame = external.islandFrame(layout: layout(left: 0, center: 0, right: 100, height: 22), expanded: nil)
        #expect(frame == CGRect(x: 1512 + 1280 - 50, y: 1440 - 2 - 22, width: 100, height: 22))
    }

    @Test("expanded: centered on the notch (or the screen), the content below the row")
    func expanded() {
        let row = layout(left: 100, center: 188, right: 150, height: 32)
        let notched = laptop.islandFrame(layout: row, expanded: (width: 480, contentHeight: 300))
        #expect(notched == CGRect(x: 662 + 94 - 240, y: 982 - 332, width: 480, height: 332))
        let flat = external.islandFrame(layout: layout(left: 0, center: 0, right: 100, height: 22), expanded: (width: 480, contentHeight: 300))
        #expect(flat.midX == external.screenFrame.midX)
        #expect(flat.maxY == 1438)
    }

    @Test("kept on its screen, and rounded to whole points")
    func clampedAndRounded() {
        let edge = ScreenGeometry(
            screenFrame: CGRect(x: 1512, y: 0, width: 1000, height: 800), hasNotch: true,
            notchMinX: 1522, notchWidth: 100, barHeight: 32, leftRoom: 10, rightRoom: 890
        )
        let left = edge.islandFrame(layout: layout(left: 100, center: 100, right: 50, height: 32), expanded: nil)
        #expect(left.minX == 1512)
        let wide = external.islandFrame(layout: layout(left: 0, center: 0, right: 10, height: 22), expanded: (width: 3000, contentHeight: 0))
        #expect(wide.maxX == external.screenFrame.maxX)
        let fractional = external.islandFrame(layout: layout(left: 0, center: 0, right: 100.2, height: 21.5), expanded: nil)
        #expect(fractional.width == 101)
        #expect(fractional.height == 22)
    }
}
