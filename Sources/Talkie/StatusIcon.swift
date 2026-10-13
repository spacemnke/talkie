import AppKit

/// The menu bar icon: the smiling dot grille from the app icon, cut down to what reads at 18 points
/// (the tile and its face; the background dots would only be grey noise this small). Idle and
/// do-not-disturb are template images, so macOS tints them for light and dark menu bars; a live
/// line turns the tile signal orange; a knock (either way) blinks it. On do not disturb the face
/// closes its eyes.
enum StatusIcon {
    enum Look: Equatable { case idle, live, dim, doNotDisturb }

    /// The face on the logo's 9 × 9 grid (column, row from 0): two eyes, and a smile.
    private static let eyes: [(CGFloat, CGFloat)] = [(2, 2), (6, 2)]
    private static let smile: [(CGFloat, CGFloat)] = [(2, 5), (6, 5), (3, 6), (4, 6), (5, 6)]

    static func image(_ look: Look) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let tile = NSRect(x: 1, y: 1, width: 16, height: 16)
            // The logo's grid: dots 48 + 52n units across a 512 tile.
            func centre(_ col: CGFloat, _ row: CGFloat) -> NSPoint {
                NSPoint(x: tile.minX + (48 + 52 * col) / 512 * tile.width,
                        y: tile.minY + (48 + 52 * row) / 512 * tile.height)
            }
            func dot(_ col: CGFloat, _ row: CGFloat) -> NSBezierPath {
                let c = centre(col, row)
                return NSBezierPath(ovalIn: NSRect(x: c.x - 1, y: c.y - 1, width: 2, height: 2))
            }
            /// A short bar between two grid points: closed eyes, a flat mouth.
            func bar(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) -> NSBezierPath {
                let path = NSBezierPath()
                path.move(to: centre(a.0, a.1))
                path.line(to: centre(b.0, b.1))
                path.lineWidth = 1.8
                path.lineCapStyle = .round
                return path
            }

            let alpha: CGFloat = look == .dim ? 0.35 : 1
            let housing = NSBezierPath(roundedRect: tile, xRadius: 2, yRadius: 2)
            (look == .live ? Palette.orangeNS : NSColor.black).withAlphaComponent(alpha).setFill()
            housing.fill()

            // The face: white on the orange tile, otherwise cut out of the tile so the menu bar shows through.
            let context = NSGraphicsContext.current
            if look == .live {
                NSColor(srgbRed: 0xFB / 255, green: 0xFB / 255, blue: 0xF9 / 255, alpha: 1).set()
            } else {
                context?.compositingOperation = .destinationOut
                NSColor.black.set()
            }
            if look == .doNotDisturb {
                bar((1.6, 2), (2.4, 2)).stroke()
                bar((5.6, 2), (6.4, 2)).stroke()
                bar((3, 5.6), (5, 5.6)).stroke()
            } else {
                for (col, row) in eyes + smile { dot(col, row).fill() }
            }
            context?.compositingOperation = .sourceOver
            return true
        }
        image.isTemplate = look != .live
        image.accessibilityDescription = "Talkie"
        return image
    }
}
