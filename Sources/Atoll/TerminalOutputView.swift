import AppKit
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
struct TerminalOutputView: NSViewRepresentable {
    let text: String
    let font: NSFont
    /// Wrap long lines to the view width (conversation text) instead of scrolling sideways (TUI screens).
    var wrap: Bool = false

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
        guard let textView = scroll.documentView as? NSTextView, let storage = textView.textStorage else { return }
        guard context.coordinator.text != text || context.coordinator.font != font || context.coordinator.wrap != wrap else { return }
        let wasAtBottom = context.coordinator.text.isEmpty || Self.isAtBottom(scroll)
        context.coordinator.text = text
        context.coordinator.font = font
        context.coordinator.wrap = wrap
        Self.applyWrap(wrap, scroll: scroll, textView: textView)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = wrap ? .byWordWrapping : .byClipping
        storage.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor(white: 0.86, alpha: 1),
            .paragraphStyle: paragraph,
        ]))
        textView.sizeToFit()
        if wasAtBottom {
            textView.scrollToEndOfDocument(nil)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.origin.y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
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
    }
}
