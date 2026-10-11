import AppKit

/// The menu bar icon: a jack. Idle and do-not-disturb are template images, so macOS tints them for
/// light and dark menu bars; a live line is signal orange; connecting blinks the idle jack.
enum StatusIcon {
    enum Look: Equatable { case idle, live, dim, doNotDisturb }

    static func image(_ look: Look) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let ink = look == .live ? NSColor(srgbRed: 0x1B / 255, green: 0x1B / 255, blue: 0x1B / 255, alpha: 1) : NSColor.black
            let alpha: CGFloat = look == .dim ? 0.35 : 1
            let ring = NSBezierPath(ovalIn: NSRect(x: 9 - 7.5, y: 9 - 7.5, width: 15, height: 15))
            ring.lineWidth = 1.8
            if look == .live {
                Palette.orangeNS.setFill()
                NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 16, height: 16)).fill()
            }
            ink.withAlphaComponent(alpha).setStroke()
            ring.stroke()
            ink.withAlphaComponent(alpha).setFill()
            if look == .doNotDisturb {
                let dash = NSBezierPath()
                dash.move(to: NSPoint(x: 6, y: 9))
                dash.line(to: NSPoint(x: 12, y: 9))
                dash.lineWidth = 2
                dash.lineCapStyle = .round
                ink.setStroke()
                dash.stroke()
            } else {
                NSBezierPath(ovalIn: NSRect(x: 6.5, y: 6.5, width: 5, height: 5)).fill()
            }
            return true
        }
        image.isTemplate = look != .live
        image.accessibilityDescription = "Talkie"
        return image
    }
}
