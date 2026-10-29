import AppKit

enum MenuBarIcon {
    /// The ring sight from the app icon, as an 18pt template image so macOS tints it
    /// for light/dark menu bars and the highlighted state.
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            let center = NSPoint(x: 9, y: 7.75)

            let outer = NSBezierPath(ovalIn: ring(center, radius: 6.5))
            outer.lineWidth = 1.5
            outer.stroke()

            let inner = NSBezierPath(ovalIn: ring(center, radius: 2.75))
            inner.lineWidth = 1.25
            inner.stroke()

            let spokes = NSBezierPath()
            spokes.lineWidth = 1.25
            for (dx, dy) in [(0.0, -1.0), (0, 1), (-1, 0), (1, 0)] {
                spokes.move(to: NSPoint(x: center.x + dx * 2.75, y: center.y + dy * 2.75))
                spokes.line(to: NSPoint(x: center.x + dx * 6.5, y: center.y + dy * 6.5))
            }
            spokes.stroke()

            // Mounting post.
            NSRect(x: center.x - 1, y: center.y + 6.5, width: 2, height: 18 - (center.y + 6.5)).fill()
            // Aiming bead.
            NSBezierPath(ovalIn: ring(center, radius: 1)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Gunner"
        return image
    }

    private static func ring(_ center: NSPoint, radius: CGFloat) -> NSRect {
        NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
