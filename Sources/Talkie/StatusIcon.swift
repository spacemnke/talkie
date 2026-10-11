import AppKit

/// The menu bar icon: a jack. Orange when a line is open, blinking while one opens, a dash on do not disturb.
enum StatusIcon {
    enum Look: Equatable { case idle, live, dim, doNotDisturb }

    static func image(_ look: Look) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
            ring.lineWidth = 2
            if look == .live {
                Palette.orangeNS.setFill()
                ring.fill()
            }
            // labelColor resolves when drawn, so it suits light and dark menu bars.
            NSColor.labelColor.setStroke()
            ring.stroke()
            NSColor.labelColor.setFill()
            if look == .doNotDisturb {
                NSBezierPath(rect: NSRect(x: 5.5, y: 8, width: 7, height: 2)).fill()
            } else {
                NSBezierPath(ovalIn: NSRect(x: 6, y: 6, width: 6, height: 6)).fill()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Talkie"
        return image
    }
}
