import SwiftUI
import TalkieCore

/// Draws the Relay handset: a rounded body with a slotted grille, a round TALK key on the front,
/// the effect (orange) and buzz keys on the right side, a settings key on the left, and a name tag
/// riding on the cord above it. When someone knocks, the front key reads LET IN and the tag gets
/// a decline key. Works in the design's own units (the Relay master is 140 × 270).
enum MicArt {
    /// The part of the drawing that's on screen: from the name tag down to the body's shadow.
    static let viewBox = CGRect(x: 8, y: 52, width: 124, height: 196)
    /// Where the coiled cord from the menu bar joins: the top of the name tag.
    static let cordExit = CGPoint(x: 66, y: 56)
    /// The keys, for hit-testing clicks.
    static let effectKey = CGRect(x: 102, y: 116, width: 20, height: 28)
    static let buzzKey = CGRect(x: 102, y: 150, width: 20, height: 28)
    static let settingsKey = CGRect(x: 6, y: 116, width: 20, height: 28)
    static let frontKey = CGRect(x: 42, y: 181, width: 44, height: 44)
    /// The × at the right end of the name tag while someone is knocking.
    static let declineKey = CGRect(x: 94, y: 54, width: 31, height: 27)

    enum TagLamp { case on, blink, tx, rx }

    struct State {
        var squeezed: Bool
        /// Someone is knocking: the front key lets them in, the tag's × turns them away.
        var knocking = false
        /// 0 is off, 1...4 the four effects.
        var effectIndex: Int
        /// 0...5 input level lights.
        var level: Int
        var tag: String
        /// What the line is doing, at the right of the tag: A, B, A+B, IN, TX, RX or TX·RX.
        var tagLabel: String
        var tagLamp: TagLamp
        var blinkPhase: Bool
    }

    private static var body: Path {
        var p = Path()
        p.move(to: CGPoint(x: 32, y: 91))
        p.addLine(to: CGPoint(x: 96, y: 91))
        p.addQuadCurve(to: CGPoint(x: 108, y: 103), control: CGPoint(x: 108, y: 91))
        p.addLine(to: CGPoint(x: 108, y: 161))
        p.addQuadCurve(to: CGPoint(x: 99, y: 178), control: CGPoint(x: 108, y: 172))
        p.addLine(to: CGPoint(x: 95, y: 225))
        p.addQuadCurve(to: CGPoint(x: 82, y: 237), control: CGPoint(x: 94, y: 237))
        p.addLine(to: CGPoint(x: 46, y: 237))
        p.addQuadCurve(to: CGPoint(x: 33, y: 225), control: CGPoint(x: 34, y: 237))
        p.addLine(to: CGPoint(x: 29, y: 178))
        p.addQuadCurve(to: CGPoint(x: 20, y: 161), control: CGPoint(x: 20, y: 172))
        p.addLine(to: CGPoint(x: 20, y: 103))
        p.addQuadCurve(to: CGPoint(x: 32, y: 91), control: CGPoint(x: 20, y: 91))
        p.closeSubpath()
        return p
    }

    private static var lowerPlate: Path {
        var p = Path()
        p.move(to: CGPoint(x: 30, y: 176))
        p.addLine(to: CGPoint(x: 98, y: 176))
        p.addLine(to: CGPoint(x: 94, y: 225))
        p.addQuadCurve(to: CGPoint(x: 82, y: 234), control: CGPoint(x: 93, y: 234))
        p.addLine(to: CGPoint(x: 46, y: 234))
        p.addQuadCurve(to: CGPoint(x: 36, y: 225), control: CGPoint(x: 37, y: 234))
        p.closeSubpath()
        return p
    }

    static func draw(_ ctx: inout GraphicsContext, _ s: State) {
        let ink = Palette.ink

        func rect(_ r: CGRect, radius: CGFloat, fill: Color, line: CGFloat = 0) {
            let p = Path(roundedRect: r, cornerRadius: radius, style: .continuous)
            ctx.fill(p, with: .color(fill))
            if line > 0 { ctx.stroke(p, with: .color(ink), lineWidth: line) }
        }
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, fill: Color?, line: CGFloat = 0, lineColor: Color = Palette.ink) {
            let p = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            if let fill { ctx.fill(p, with: .color(fill)) }
            if line > 0 { ctx.stroke(p, with: .color(lineColor), lineWidth: line) }
        }
        func label(_ text: String, size: CGFloat, weight: String, color: Color, at p: CGPoint, anchor: UnitPoint = .center) {
            ctx.draw(Text(text).font(Fonts.jura(size, weight)).tracking(size * 0.06).foregroundStyle(color), at: p, anchor: anchor)
        }

        // The cord between the name tag and the body. With nobody on the line there's no tag, so
        // the cord runs all the way up to where the coil from the menu bar joins.
        var stub = Path()
        stub.move(to: CGPoint(x: 66, y: s.tag.isEmpty ? cordExit.y : 79))
        stub.addLine(to: CGPoint(x: 66, y: 92))
        ctx.stroke(stub, with: .color(ink), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        ctx.stroke(stub, with: .color(Palette.lampOff), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

        // Name tag: who's on the line, and what it's doing.
        if !s.tag.isEmpty {
            rect(CGRect(x: 13, y: 56, width: 110, height: 23), radius: 4, fill: Palette.key, line: 2)
            let lamp: Color
            switch s.tagLamp {
            case .on, .tx: lamp = Palette.orange
            case .rx: lamp = s.blinkPhase ? Palette.white : Palette.orange
            case .blink: lamp = s.blinkPhase ? Palette.orange : Palette.lampOff
            }
            if s.tagLamp == .tx { circle(25, 67.5, 6, fill: Palette.orangeGlow) }
            circle(25, 67.5, 3.3, fill: lamp, line: 0.7, lineColor: Palette.white)
            // Long names shrink to fit; the full list is in the accessibility label.
            let rightWidth: CGFloat
            if s.knocking {
                // The decline key: a little raised key with a ×.
                rect(CGRect(x: 99, y: 60, width: 18, height: 15), radius: 3, fill: Palette.ink)
                rect(CGRect(x: 99, y: 58.5, width: 18, height: 15), radius: 3, fill: Palette.plate, line: 1.2)
                var x = Path()
                x.move(to: CGPoint(x: 105, y: 63)); x.addLine(to: CGPoint(x: 111, y: 69))
                x.move(to: CGPoint(x: 111, y: 63)); x.addLine(to: CGPoint(x: 105, y: 69))
                ctx.stroke(x, with: .color(ink), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                rightWidth = 18
            } else {
                let right = ctx.resolve(Text(s.tagLabel).font(Fonts.jura(8, "Bold")).tracking(0.5).foregroundStyle(Palette.orange))
                rightWidth = right.measure(in: CGSize(width: 60, height: 20)).width
                ctx.draw(right, at: CGPoint(x: 117, y: 67.5), anchor: .trailing)
            }
            let room = 117 - rightWidth - 6 - 33
            var size: CGFloat = 11
            var name = ctx.resolve(Text(s.tag).font(Fonts.jura(size, "SemiBold")).tracking(0.6).foregroundStyle(Palette.white))
            while size > 7, name.measure(in: CGSize(width: 400, height: 30)).width > room {
                size -= 0.5
                name = ctx.resolve(Text(s.tag).font(Fonts.jura(size, "SemiBold")).tracking(0.6).foregroundStyle(Palette.white))
            }
            ctx.draw(name, at: CGPoint(x: 33, y: 67.5), anchor: .leading)
        }

        // One hard shadow for the body.
        ctx.fill(body.offsetBy(dx: 6, dy: 8), with: .color(Palette.shadow))

        // Side keys, tucked behind the body: effect and buzz on the right, settings on the left.
        rect(CGRect(x: 104, y: 118, width: 16, height: 24), radius: 4, fill: Palette.orange, line: 2)
        rect(CGRect(x: 104, y: 152, width: 16, height: 24), radius: 4, fill: Palette.plate, line: 2)
        label("FX", size: 5.6, weight: "Bold", color: ink, at: CGPoint(x: 114, y: 130))
        label("BZ", size: 5.6, weight: "Bold", color: ink, at: CGPoint(x: 114, y: 164))
        rect(CGRect(x: 8, y: 118, width: 16, height: 24), radius: 4, fill: Palette.plate, line: 2)
        for dy: CGFloat in [-4, 0, 4] { circle(14, 130 + dy, 1.15, fill: ink) }

        // Body and grille.
        ctx.fill(body, with: .color(Palette.shell))
        ctx.stroke(body, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        rect(CGRect(x: 29, y: 101, width: 70, height: 65), radius: 6, fill: Palette.micGrille, line: 1.5)
        for i in 0..<7 {
            rect(CGRect(x: 36, y: 110 + 7 * CGFloat(i), width: 42, height: 2.4), radius: 1, fill: ink)
        }

        // Input level (lights from the bottom up) and the effect in use (one of five).
        for i in 0..<5 {
            let lit = i >= 5 - s.level
            let square = Path(CGRect(x: 86, y: 111 + 6 * CGFloat(i), width: 3.5, height: 3.5))
            ctx.fill(square, with: .color(lit ? Palette.orange : Palette.lampOff))
            ctx.stroke(square, with: .color(ink), lineWidth: 0.7)
            circle(94, 113 + 6 * CGFloat(i), 1.8, fill: s.effectIndex == i ? Palette.white : Palette.lampOff, line: 0.7)
        }

        // Lower plate, screws and the round TALK key.
        ctx.fill(lowerPlate, with: .color(Palette.plate))
        var seam = Path()
        seam.move(to: CGPoint(x: 30, y: 176))
        seam.addLine(to: CGPoint(x: 98, y: 176))
        ctx.stroke(seam, with: .color(ink), lineWidth: 1.5)
        circle(26, 171, 1.9, fill: Palette.plate, line: 0.7)
        circle(102, 171, 1.9, fill: Palette.plate, line: 0.7)

        // A glow around the key while someone's waiting to be let in.
        if s.knocking { circle(64, 202, 25, fill: Palette.orangeGlow) }
        circle(64, 203, 20, fill: ink)
        let keyY: CGFloat = s.squeezed ? 203.5 : 201
        circle(64, keyY, 18, fill: s.squeezed || s.knocking ? Palette.orange : Palette.white, line: 1.5)
        // LET IN is wider than TALK, so the inner ring steps aside for it.
        if !s.knocking { circle(64, keyY, 12, fill: nil, line: 1) }
        label(s.knocking ? "LET IN" : "TALK", size: s.knocking ? 6 : 6.5, weight: "SemiBold", color: ink, at: CGPoint(x: 64, y: keyY))
        label("TALKIE", size: 7.7, weight: "Regular", color: ink, at: CGPoint(x: 64, y: 226.5))
    }
}
