import Foundation

/// A terminal color: one of the 256 palette entries or a 24-bit value.
public enum TermColor: Hashable, Sendable {
    case palette(UInt8)
    case rgb(UInt8, UInt8, UInt8)
}

/// The SGR attributes of a stretch of terminal text. The default value is plain text.
public struct TermStyle: Hashable, Sendable {
    public var foreground: TermColor?
    public var background: TermColor?
    public var bold = false
    public var dim = false
    public var italic = false
    public var underline = false
    public var inverse = false

    public init(foreground: TermColor? = nil, background: TermColor? = nil, bold: Bool = false, dim: Bool = false,
                italic: Bool = false, underline: Bool = false, inverse: Bool = false) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.dim = dim
        self.italic = italic
        self.underline = underline
        self.inverse = inverse
    }

    public var isPlain: Bool { self == TermStyle() }
}

/// A styled stretch of a text; `range` is in UTF-16 units, like `NSString`.
public struct StyledRun: Equatable, Sendable {
    public var range: NSRange
    public var style: TermStyle

    public init(range: NSRange, style: TermStyle) {
        self.range = range
        self.style = style
    }
}

/// Splits terminal output with escape sequences into plain text and its SGR style runs. Every other escape
/// (cursor moves, OSC titles / hyperlinks, DCS, charset switches) is dropped, except cursor-forward, which
/// becomes spaces. Carriage returns and other C0 controls are dropped; newlines and tabs are kept.
public enum ANSIParser {
    public static func parse(_ input: String) -> (text: String, runs: [StyledRun]) {
        var out = String.UnicodeScalarView()
        var runs: [StyledRun] = []
        var style = TermStyle()
        var runStart = 0
        var offset = 0
        let scalars = Array(input.unicodeScalars)
        var i = 0

        func closeRun() {
            guard offset > runStart, !style.isPlain else { return }
            if let last = runs.last, last.style == style, NSMaxRange(last.range) == runStart {
                runs[runs.count - 1].range.length += offset - runStart
            } else {
                runs.append(StyledRun(range: NSRange(location: runStart, length: offset - runStart), style: style))
            }
        }
        func append(_ scalar: Unicode.Scalar) {
            out.append(scalar)
            offset += scalar.utf16.count
        }

        while i < scalars.count {
            let s = scalars[i]
            if s.value == 0x1B {
                i += 1
                guard i < scalars.count else { break }
                switch scalars[i] {
                case "[":
                    i += 1
                    var params = ""
                    while i < scalars.count, !(0x40...0x7E).contains(scalars[i].value) {
                        params.unicodeScalars.append(scalars[i])
                        i += 1
                    }
                    guard i < scalars.count else { break }
                    let final = scalars[i]
                    i += 1
                    if final == "m" {
                        let next = applySGR(params, to: style)
                        if next != style {
                            closeRun()
                            style = next
                            runStart = offset
                        }
                    } else if final == "C", params.allSatisfy(\.isNumber) {
                        for _ in 0..<max(1, Int(params) ?? 1) { append(" ") }
                    }
                case "]", "P", "X", "^", "_":
                    // OSC ends with BEL or ST; DCS / SOS / PM / APC with ST.
                    let isOSC = scalars[i] == "]"
                    i += 1
                    while i < scalars.count {
                        if isOSC, scalars[i].value == 0x07 { i += 1; break }
                        if scalars[i].value == 0x1B, i + 1 < scalars.count, scalars[i + 1] == "\\" { i += 2; break }
                        i += 1
                    }
                case "(", ")", "*", "+", "#", "%":
                    i += 2
                default:
                    i += 1
                }
                continue
            }
            if s == "\n" || s == "\t" || s.value >= 0x20, s.value != 0x7F {
                append(s)
            }
            i += 1
        }
        closeRun()
        return (String(out), runs)
    }

    /// Applies one SGR parameter string ("1;38;5;208", "38:2::255:0:0", "") to a style.
    static func applySGR(_ params: String, to base: TermStyle) -> TermStyle {
        var style = base
        let groups = params.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        var index = 0

        func number(_ text: String) -> Int { Int(text) ?? 0 }
        /// An extended color from colon sub-parameters ("2::r:g:b", "2:r:g:b", "5:n") or the following groups.
        func extended(sub: [String]) -> TermColor? {
            if !sub.isEmpty {
                guard let mode = sub.first.map(number) else { return nil }
                if mode == 5, sub.count >= 2 { return .palette(UInt8(clamping: number(sub[1]))) }
                if mode == 2 {
                    let values = sub.count >= 5 ? Array(sub.suffix(3)) : Array(sub.dropFirst())
                    guard values.count == 3 else { return nil }
                    return .rgb(UInt8(clamping: number(values[0])), UInt8(clamping: number(values[1])),
                                UInt8(clamping: number(values[2])))
                }
                return nil
            }
            guard index + 1 < groups.count else { return nil }
            let mode = number(groups[index + 1])
            if mode == 5, index + 2 < groups.count {
                index += 2
                return .palette(UInt8(clamping: number(groups[index])))
            }
            if mode == 2, index + 4 < groups.count {
                let color = TermColor.rgb(UInt8(clamping: number(groups[index + 2])), UInt8(clamping: number(groups[index + 3])),
                                          UInt8(clamping: number(groups[index + 4])))
                index += 4
                return color
            }
            index += 1
            return nil
        }

        while index < groups.count {
            let parts = groups[index].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            let code = number(parts[0])
            let sub = Array(parts.dropFirst())
            switch code {
            case 0: style = TermStyle()
            case 1: style.bold = true
            case 2: style.dim = true
            case 3: style.italic = true
            case 4: style.underline = sub.first.map { number($0) != 0 } ?? true
            case 7: style.inverse = true
            case 21: style.underline = true
            case 22: style.bold = false; style.dim = false
            case 23: style.italic = false
            case 24: style.underline = false
            case 27: style.inverse = false
            case 30...37: style.foreground = .palette(UInt8(code - 30))
            case 38: if let color = extended(sub: sub) { style.foreground = color }
            case 39: style.foreground = nil
            case 40...47: style.background = .palette(UInt8(code - 40))
            case 48: if let color = extended(sub: sub) { style.background = color }
            case 49: style.background = nil
            case 90...97: style.foreground = .palette(UInt8(code - 90 + 8))
            case 100...107: style.background = .palette(UInt8(code - 100 + 8))
            default: break
            }
            index += 1
        }
        return style
    }
}
