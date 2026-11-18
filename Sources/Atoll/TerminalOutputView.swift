import AppKit
import AtollCore
import SwiftUI

/// Monospace font with a fallback chain for terminal output: Nerd Font private-use icons,
/// box drawing and braille, then the system's CJK / emoji fallback.
enum TerminalFont {
    /// Families tried in order when the setting is "Automatic".
    static let preferredFamilies = [
        "JetBrainsMono Nerd Font Mono", "JetBrainsMonoNL Nerd Font Mono", "FiraCode Nerd Font Mono",
        "Hack Nerd Font Mono", "MesloLGS Nerd Font Mono", "SauceCodePro Nerd Font Mono",
    ]
    /// Symbol-only families appended so PUA icons render even with a plain primary font.
    static let symbolFamilies = ["Symbols Nerd Font Mono", "Symbols Nerd Font", "JetBrainsMono Nerd Font Mono", "Apple Symbols"]

    static let cjkFamilies = ["PingFang TC", "PingFang SC", "Hiragino Sans", "Apple SD Gothic Neo"]

    static var installedFamilies: [String] { NSFontManager.shared.availableFontFamilies }

    /// Monospaced families the user can pick in Settings.
    static var monospacedFamilies: [String] {
        installedFamilies.filter { family in
            guard !family.hasPrefix("."), let font = NSFont(name: family, size: 12) ?? NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 12) else { return false }
            return font.isFixedPitch || family.localizedCaseInsensitiveContains("mono")
        }.sorted()
    }

    static func font(family: String, size: CGFloat) -> NSFont {
        let installed = Set(installedFamilies)
        let primaryFamily: String? = {
            if !family.isEmpty, installed.contains(family) { return family }
            return preferredFamilies.first(where: installed.contains)
                ?? installedFamilies.first { $0.contains("Nerd Font Mono") }
        }()
        let base = primaryFamily.flatMap { NSFontManager.shared.font(withFamily: $0, traits: [], weight: 5, size: size) }
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        var cascade = symbolFamilies
            .filter { installed.contains($0) && $0 != primaryFamily }
            .map { NSFontDescriptor(fontAttributes: [.family: $0]) }
        // Wide (CJK / fullwidth) characters must take exactly two cells or tables drift.
        let cell = ("M" as NSString).size(withAttributes: [.font: base]).width
        for family in cjkFamilies where installed.contains(family) {
            cascade.append(NSFontDescriptor(fontAttributes: [.family: family, .fixedAdvance: cell * 2]))
            break
        }
        guard !cascade.isEmpty else { return base }
        let descriptor = base.fontDescriptor.addingAttributes([.cascadeList: cascade])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// The family actually used, for display in Settings.
    static func resolvedName(family: String) -> String {
        font(family: family, size: 12).familyName ?? "SF Mono"
    }
}

/// Read-only terminal text: no wrapping (TUI layouts stay intact), horizontal + vertical
/// scrolling, selectable, and pinned to the bottom when new output arrives.
/// Search matches are painted as temporary attributes (the text itself is untouched). While searching
/// there is no bottom pin: the view scrolls to the current match when the user moves it, and follows it
/// across a refresh only if it was in view.
struct TerminalOutputView: NSViewRepresentable {
    let text: String
    let font: NSFont
    /// Colors over `text` (UTF-16 ranges): the terminal's own, or the tool layout's.
    var styles: [StyledRun] = []
    /// Wrap long lines to the view width (conversation text) instead of scrolling sideways (TUI screens).
    var wrap: Bool = false
    /// Ranges in `text` to highlight, and which of them is current.
    var highlights: [NSRange] = []
    var current: Int?
    var searching = false
    /// Changes when the user types a query or steps to another match.
    var scrollRequest = 0

    static let matchColor = NSColor.systemYellow.withAlphaComponent(0.3)
    static let currentColor = NSColor.systemOrange.withAlphaComponent(0.8)

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        let textChanged = coordinator.text != text || coordinator.font != font || coordinator.wrap != wrap
            || coordinator.styles != styles
        if textChanged {
            // The highlights for the new text arrive on a later pass; remember whether to follow them.
            if searching, let shown = coordinator.currentRange, Self.isVisible(shown, in: textView) {
                coordinator.followNextMatch = true
            }
            setText(scroll: scroll, textView: textView, coordinator: coordinator)
        }
        let length = (text as NSString).length
        let valid = highlights.indices.filter { NSMaxRange(highlights[$0]) <= length }
        if textChanged || coordinator.highlights != highlights || coordinator.current != current {
            coordinator.highlights = highlights
            coordinator.current = current
            guard let layout = textView.layoutManager else { return }
            layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: length))
            for index in valid {
                layout.addTemporaryAttribute(.backgroundColor, value: index == current ? Self.currentColor : Self.matchColor,
                                             forCharacterRange: highlights[index])
            }
        }
        if !searching { coordinator.followNextMatch = false }
        coordinator.currentRange = current.flatMap { valid.contains($0) ? highlights[$0] : nil }
        guard let target = coordinator.currentRange else { return }
        if coordinator.scrollRequest != scrollRequest || coordinator.followNextMatch {
            coordinator.scrollRequest = scrollRequest
            coordinator.followNextMatch = false
            textView.scrollRangeToVisible(target)
        }
    }

    static func isVisible(_ range: NSRange, in textView: NSTextView) -> Bool {
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return false }
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        return textView.visibleRect.intersects(rect)
    }

    private func setText(scroll: NSScrollView, textView: NSTextView, coordinator: Coordinator) {
        guard let storage = textView.textStorage else { return }
        // No bottom pin while searching: the current match decides where the view sits.
        let hadNoText = coordinator.text.isEmpty
        let wasAtBottom = !searching && (hadNoText || Self.isAtBottom(scroll))
        coordinator.text = text
        coordinator.font = font
        coordinator.wrap = wrap
        coordinator.styles = styles
        Self.applyWrap(wrap, scroll: scroll, textView: textView)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = wrap ? .byWordWrapping : .byClipping
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: TerminalPalette.defaultForeground,
            .paragraphStyle: paragraph,
        ])
        TerminalPalette.apply(styles, to: attributed, font: font)
        storage.setAttributedString(attributed)
        textView.sizeToFit()
        guard wasAtBottom else { return }
        Self.scrollToBottom(scroll, textView: textView)
        // A view just created (e.g. back from the changes view) gets its text before its first layout, which
        // undoes the scroll: pin it again once laid out.
        if hadNoText {
            DispatchQueue.main.async { Self.scrollToBottom(scroll, textView: textView) }
        }
    }

    static func scrollToBottom(_ scroll: NSScrollView, textView: NSTextView) {
        textView.scrollToEndOfDocument(nil)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.origin.y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    static func applyWrap(_ wrap: Bool, scroll: NSScrollView, textView: NSTextView) {
        let huge = CGFloat.greatestFiniteMagnitude
        scroll.hasHorizontalScroller = !wrap
        textView.isHorizontallyResizable = !wrap
        textView.autoresizingMask = wrap ? [.width] : []
        textView.textContainer?.widthTracksTextView = wrap
        if wrap {
            let width = scroll.contentSize.width
            textView.frame.size.width = width
            textView.textContainer?.containerSize = NSSize(width: width - textView.textContainerInset.width * 2, height: huge)
        } else {
            textView.textContainer?.containerSize = NSSize(width: huge, height: huge)
        }
    }

    static func isAtBottom(_ scroll: NSScrollView) -> Bool {
        guard let doc = scroll.documentView else { return true }
        let visible = scroll.contentView.bounds
        return visible.maxY >= doc.bounds.height - 4
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var text = ""
        var font: NSFont?
        var wrap: Bool?
        var styles: [StyledRun] = []
        var highlights: [NSRange] = []
        var current: Int?
        /// The current match as last highlighted, to tell whether it was in view before a refresh.
        var currentRange: NSRange?
        var scrollRequest = 0
        var followNextMatch = false
    }
}

/// Maps terminal colors to the dark panel: the 16 base colors are tuned to read on it, the rest follow xterm.
enum TerminalPalette {
    static let defaultForeground = NSColor(white: 0.86, alpha: 1)
    /// What inverse text uses as its color: the panel's background.
    static let defaultBackground = NSColor(white: 0.1, alpha: 1)

    static let base: [UInt32] = [
        0x3B3F46, 0xE06C75, 0x98C379, 0xE5C07B, 0x61AFEF, 0xC678DD, 0x56B6C2, 0xC8CCD4,
        0x7F848E, 0xFF7B86, 0xB5E890, 0xF0D197, 0x82C4FF, 0xDC9BF0, 0x7FD3DF, 0xFFFFFF,
    ]

    static func color(_ color: TermColor) -> NSColor {
        switch color {
        case .rgb(let r, let g, let b):
            return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        case .palette(let index):
            let i = Int(index)
            if i < 16 { return hex(base[i]) }
            if i < 232 {
                let levels: [CGFloat] = [0, 95, 135, 175, 215, 255]
                let n = i - 16
                return NSColor(srgbRed: levels[n / 36] / 255, green: levels[n / 6 % 6] / 255, blue: levels[n % 6] / 255, alpha: 1)
            }
            let gray = CGFloat(8 + (i - 232) * 10) / 255
            return NSColor(srgbRed: gray, green: gray, blue: gray, alpha: 1)
        }
    }

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    static func apply(_ runs: [StyledRun], to text: NSMutableAttributedString, font: NSFont) {
        guard !runs.isEmpty else { return }
        let length = text.length
        let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        for run in runs where NSMaxRange(run.range) <= length {
            let style = run.style
            var foreground = style.foreground.map(color) ?? defaultForeground
            var background = style.background.map(color)
            if style.inverse {
                (foreground, background) = (background ?? defaultBackground, foreground)
            }
            if style.dim { foreground = foreground.withAlphaComponent(0.55) }
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: foreground]
            if let background { attributes[.backgroundColor] = background }
            if style.bold { attributes[.font] = bold }
            if style.italic { attributes[.obliqueness] = 0.15 }
            if style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            text.addAttributes(attributes, range: run.range)
        }
    }
}
