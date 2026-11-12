import AppKit

/// Menu bar glyphs in the app's pixel style: the atoll ring from the app icon, drawn 1 pt per pixel
/// on a 16×16 grid so it stays crisp, as template images so the menu bar tints them.
enum MenuBarIcon {
    /// Robot standing in the lagoon, like the app icon.
    case idle
    /// Something needs you.
    case waiting
    /// Source offline: the ring broken into its corner arcs.
    case offline

    var grid: [String] {
        switch self {
        case .idle: [
            ".....######.....",
            "...##########...",
            "..###......###..",
            ".##..........##.",
            ".##..........##.",
            "##............##",
            "##............##",
            "##....####....##",
            "##...######...##",
            "##..##.##.##..##",
            "##...######...##",
            ".##...####...##.",
            ".##...#..#...##.",
            "..###......###..",
            "...##########...",
            ".....######.....",
        ]
        case .waiting: [
            ".....######.....",
            "...##########...",
            "..###......###..",
            ".##....##....##.",
            ".##....##....##.",
            "##.....##.....##",
            "##.....##.....##",
            "##.....##.....##",
            "##............##",
            "##.....##.....##",
            "##.....##.....##",
            ".##..........##.",
            ".##..........##.",
            "..###......###..",
            "...##########...",
            ".....######.....",
        ]
        case .offline: [
            "................",
            "...##......##...",
            "..###......###..",
            ".##..........##.",
            ".##..........##.",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            ".##..........##.",
            ".##..........##.",
            "..###......###..",
            "...##......##...",
            "................",
        ]
        }
    }

    var image: NSImage {
        let rows = grid
        let size = NSSize(width: rows.first?.count ?? 0, height: rows.count)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            for (y, row) in rows.enumerated() {
                for (x, pixel) in row.enumerated() where pixel == "#" {
                    NSRect(x: x, y: y, width: 1, height: 1).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
