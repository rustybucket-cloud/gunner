import AppKit

/// Renders a line containing ANSI escape codes. Keeps SGR colors and bold/dim; drops everything else.
enum ANSI {
    static func attributed(_ text: String, base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        // Fast path: most lines have no escapes.
        guard text.contains("\u{1B}") else { return NSAttributedString(string: text, attributes: base) }

        let result = NSMutableAttributedString()
        var color: NSColor?
        var bold = false
        var dim = false
        var run = ""

        func flush() {
            guard !run.isEmpty else { return }
            var attributes = base
            // Use dynamic system colors where possible: derived colors (withAlphaComponent)
            // get frozen to one appearance and can vanish in the other.
            if let color {
                attributes[.foregroundColor] = dim ? color.withAlphaComponent(0.6) : color
            } else if dim {
                attributes[.foregroundColor] = NSColor.secondaryLabelColor
            }
            if bold, let font = base[.font] as? NSFont {
                attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            result.append(NSAttributedString(string: run, attributes: attributes))
            run = ""
        }

        var scalars = text.unicodeScalars.makeIterator()
        while let scalar = scalars.next() {
            guard scalar == "\u{1B}" else {
                run.unicodeScalars.append(scalar)
                continue
            }
            flush()
            switch scalars.next() {
            case "[":
                // CSI: parameters, then a final byte in @...~
                var params = ""
                var final: Unicode.Scalar?
                while let next = scalars.next() {
                    if (0x40...0x7E).contains(next.value) {
                        final = next
                        break
                    }
                    params.unicodeScalars.append(next)
                }
                guard final == "m" else { continue }
                let codes = params.isEmpty ? [0] : params.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
                var i = 0
                while i < codes.count {
                    let code = codes[i]
                    switch code {
                    case 0: (color, bold, dim) = (nil, false, false)
                    case 1: bold = true
                    case 2: dim = true
                    case 22: (bold, dim) = (false, false)
                    case 39: color = nil
                    case 30...37: color = palette[code - 30]
                    case 90...97: color = palette[code - 90]
                    case 38, 48: i += codes.count > i + 1 && codes[i + 1] == 5 ? 2 : 4 // Skip 256/true color.
                    default: break
                    }
                    i += 1
                }
            case "]":
                // OSC: skip until BEL or ESC \
                while let next = scalars.next(), next != "\u{07}", next != "\u{1B}" {}
            default:
                break
            }
        }
        flush()
        return result
    }

    private static let palette: [NSColor] = [
        .secondaryLabelColor, .systemRed, .systemGreen, .systemYellow,
        .systemBlue, .systemPurple, .systemCyan, .labelColor,
    ]
}
