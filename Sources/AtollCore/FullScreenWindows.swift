import CoreGraphics
import Foundation

/// One entry of a CGWindowList snapshot: only what can be read without Screen Recording.
public struct WindowSnapshot: Equatable, Sendable {
    public var layer: Int
    public var pid: Int
    /// CGWindowList coordinates: top-left origin on the primary display.
    public var bounds: CGRect

    public init(layer: Int, pid: Int, bounds: CGRect) {
        self.layer = layer
        self.pid = pid
        self.bounds = bounds
    }
}

public enum FullScreenWindows {
    /// The tallest menu bar (notched displays) the full-screen content may start below.
    static let maxMenuBarHeight: CGFloat = 60

    /// Whether `screen` (AppKit coordinates, bottom-left origin) shows a full-screen app.
    ///
    /// A native full-screen space shows a normal-layer content window spanning the screen width down
    /// to its bottom edge, starting at the top or just below a menu bar shown in full screen. Bounds
    /// alone can't tell it from a zoomed window when the Dock is auto-hidden, so the same app must
    /// also own the full-screen title-bar strip: a full-width sliver at the content's top edge, or
    /// parked just above it while the menu bar is hidden.
    public static func isFullScreen(_ windows: [WindowSnapshot], screen: CGRect, primaryHeight: CGFloat, ownPID: Int) -> Bool {
        let target = CGRect(x: screen.minX, y: primaryHeight - screen.maxY, width: screen.width, height: screen.height).integral
        let candidates = windows.filter { $0.layer == 0 && $0.pid != ownPID }
        func spansWidth(_ b: CGRect) -> Bool { b.minX == target.minX && b.width == target.width }
        return candidates.contains { content in
            let b = content.bounds.integral
            guard spansWidth(b), b.maxY == target.maxY,
                  b.minY >= target.minY, b.minY - target.minY <= maxMenuBarHeight
            else { return false }
            return candidates.contains { strip in
                let s = strip.bounds.integral
                return strip.pid == content.pid && spansWidth(s)
                    && s.height > 0 && s.height <= maxMenuBarHeight
                    && (s.minY == b.minY || s.maxY == b.minY)
            }
        }
    }
}
