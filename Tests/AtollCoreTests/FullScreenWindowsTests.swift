import CoreGraphics
import Foundation
import Testing
@testable import AtollCore

/// Window lists recorded with CGWindowList on a 3840×1080 screen with a 30pt menu bar (ticket 53).
@Suite("Full-screen detection from window lists")
struct FullScreenWindowsTests {
    let screen = CGRect(x: 0, y: 0, width: 3840, height: 1080)
    let app = 100
    let atoll = 1

    func win(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, pid: Int? = nil, layer: Int = 0) -> WindowSnapshot {
        WindowSnapshot(layer: layer, pid: pid ?? app, bounds: CGRect(x: x, y: y, width: w, height: h))
    }

    func isFullScreen(_ windows: [WindowSnapshot], screen: CGRect? = nil, primaryHeight: CGFloat = 1080) -> Bool {
        FullScreenWindows.isFullScreen(windows, screen: screen ?? self.screen, primaryHeight: primaryHeight, ownPID: atoll)
    }

    @Test("native full screen with the menu bar hidden")
    func nativeMenuBarHidden() {
        #expect(isFullScreen([
            win(0, -32, 3840, 32),
            win(0, 0, 3840, 1080),
        ]))
    }

    @Test("native full screen with the menu bar shown in full screen")
    func nativeMenuBarShown() {
        #expect(isFullScreen([
            win(0, 0, 3840, 30, layer: 26),
            win(0, 0, 3840, 30, pid: 88, layer: 24),
            win(0, 30, 3840, 32),
            win(0, 30, 3840, 1050),
        ]))
    }

    @Test("a zoomed window with the Dock auto-hidden is not full screen")
    func zoomedWithDockHidden() {
        #expect(!isFullScreen([
            win(0, 0, 3840, 30, pid: 88, layer: 24),
            win(0, 30, 3840, 1050),
        ]))
    }

    @Test("a window filling the screen without the title-bar strip is not full screen")
    func fillsScreenWithoutStrip() {
        // Borderless window sized to the frame; also a zoomed window with both menu bar and Dock auto-hidden.
        #expect(!isFullScreen([
            win(0, 0, 3840, 1080, pid: 77, layer: 20),
            win(0, 0, 3840, 1080),
        ]))
    }

    @Test("Atoll's own windows never count")
    func ownWindows() {
        #expect(!isFullScreen([
            win(0, -32, 3840, 32, pid: atoll),
            win(0, 0, 3840, 1080, pid: atoll),
        ]))
    }

    // Recorded with three screens: the primary, a 1920×1080 one above it shifted right,
    // and a portrait 1080×1920 one to its right.
    let upper = CGRect(x: 1695, y: 1080, width: 1920, height: 1080)
    let portrait = CGRect(x: 3840, y: -246, width: 1080, height: 1920)

    @Test("full screen on a secondary screen counts only for that screen")
    func secondaryScreen() {
        let windows = [
            win(1695, -1080, 1920, 30, layer: 26),
            win(1695, -1050, 1920, 32),
            win(1695, -1050, 1920, 1050),
        ]
        #expect(isFullScreen(windows, screen: upper))
        #expect(!isFullScreen(windows))
        #expect(!isFullScreen(windows, screen: portrait))
    }

    @Test("full screen on a portrait screen")
    func portraitScreen() {
        #expect(isFullScreen([
            win(3840, -594, 1080, 30, layer: 26),
            win(3840, -564, 1080, 32),
            win(3840, -564, 1080, 1890),
        ], screen: portrait))
    }

    @Test("a zoomed window on a secondary screen is not full screen")
    func zoomedOnSecondary() {
        #expect(!isFullScreen([win(1695, -1050, 1920, 1050)], screen: upper))
        #expect(!isFullScreen([win(3840, -564, 1080, 1890)], screen: portrait))
    }
}
