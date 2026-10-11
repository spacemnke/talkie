import SwiftUI
import TalkieCore

/// Draws the handheld mic. Works in the prototype's SVG units (viewBox 20 30 160 275),
/// so the drawing can be checked against design/prototype.html.
enum MicArt {
    static let viewBox = CGRect(x: 20, y: 30, width: 160, height: 275)
    /// Where the coiled cord leaves the mic, in viewBox units.
    static let cordExit = CGPoint(x: 110, y: 300)

    enum TagLamp { case on, blink, tx, rx }

    struct State {
        var squeezed: Bool
        var effectSlot: Int?
        /// 0...3 bars on the level lights.
        var level: Int
        var tag: String
        var tagLamp: TagLamp
        var blinkPhase: Bool
    }

    static func draw(_ ctx: inout GraphicsContext, _ s: State) {
        let ink = Palette.ink
        let line = StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        let thin = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)

        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, r: CGFloat = 0, fill: Color, stroke: StrokeStyle? = nil) {
            let rect = CGRect(x: x, y: y, width: w, height: h)
            let p = r > 0 ? Path(roundedRect: rect, cornerRadius: r) : Path(rect)
            ctx.fill(p, with: .color(fill))
            if let stroke { ctx.stroke(p, with: .color(ink), style: stroke) }
        }
        func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, fill: Color, stroke: StrokeStyle? = nil) {
            let p = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            ctx.fill(p, with: .color(fill))
            if let stroke { ctx.stroke(p, with: .color(ink), style: stroke) }
        }

        // Side keys, partly hidden behind the body: effect (orange), buzz (cream), and a spare.
        box(144, 58, 28, 30, r: 4, fill: Palette.orange, stroke: line)
        box(144, 106, 28, 28, r: 4, fill: Palette.plate, stroke: line)
        box(144, 194, 26, 24, r: 4, fill: Palette.plate, stroke: line)

        // The squeeze handle swings in toward the body while you talk.
        var handleCtx = ctx
        if s.squeezed {
            handleCtx.translateBy(x: 70, y: 206)
            handleCtx.rotate(by: .degrees(9))
            handleCtx.translateBy(x: -70, y: -206)
        }
        var handle = Path()
        handle.move(to: CGPoint(x: 70, y: 54))
        handle.addLine(to: CGPoint(x: 40, y: 62))
        handle.addQuadCurve(to: CGPoint(x: 31, y: 78), control: CGPoint(x: 28, y: 65))
        handle.addLine(to: CGPoint(x: 62, y: 206))
        handle.addLine(to: CGPoint(x: 70, y: 206))
        handle.closeSubpath()
        handleCtx.fill(handle, with: .color(Palette.orange))
        handleCtx.stroke(handle, with: .color(ink), style: line)

        // Grille
        box(62, 40, 96, 118, fill: Palette.micGrille, stroke: line)
        for row in 0..<11 {
            for col in 0..<9 {
                if col == 7 && ((1...4).contains(row) || (6...9).contains(row)) { continue }
                let edge = col == 0 || col == 8 || row == 0 || row == 10
                dot(69 + 10 * CGFloat(col), 47 + 10 * CGFloat(row), 3.7,
                    fill: edge ? Palette.dotRing : ink,
                    stroke: edge ? StrokeStyle(lineWidth: 1.2) : nil)
            }
        }

        // Effect lights (one per preset) and level lights.
        box(133, 51, 12, 42, r: 6, fill: Palette.pill, stroke: thin)
        box(133, 101, 12, 42, r: 6, fill: Palette.pill, stroke: thin)
        for k in 0..<4 {
            dot(139, 57 + 10 * CGFloat(k), 3.2, fill: s.effectSlot == k + 1 ? Palette.ledRed : Palette.ledOff, stroke: StrokeStyle(lineWidth: 1.2))
            let levelOn = k == 0 || 3 - k < s.level
            dot(139, 107 + 10 * CGFloat(k), 3.2, fill: levelOn ? Palette.ledWhite : Palette.ledOff, stroke: StrokeStyle(lineWidth: 1.2))
        }

        // Lower plate
        box(62, 158, 96, 92, fill: Palette.plate, stroke: line)
        for (x, y) in [(73.0, 169.0), (147.0, 169.0), (73.0, 239.0), (147.0, 239.0)] {
            dot(x, y, 5, fill: Palette.plate, stroke: thin)
        }
        ctx.draw(
            Text("TALKIE").font(Fonts.jura(19, "Regular")).tracking(0.8).foregroundStyle(ink),
            at: CGPoint(x: 110, y: 205),
            anchor: .center
        )

        // Strain relief where the cord leaves the mic
        box(104, 250, 12, 50, fill: Palette.slate, stroke: thin)
        for k in 0..<5 {
            box(96, 255 + 9 * CGFloat(k), 28, 5, fill: Palette.slate, stroke: thin)
        }

        // Name tag: who's on the line
        if !s.tag.isEmpty {
            let label = ctx.resolve(Text(s.tag).font(Fonts.jura(11, "Bold")).tracking(0.9).foregroundStyle(Palette.white))
            let textSize = label.measure(in: CGSize(width: 400, height: 40))
            let w = textSize.width + 30, h: CGFloat = 20
            let right: CGFloat = 86, bottom: CGFloat = 298
            box(right - w, bottom - h, w, h, fill: Palette.key, stroke: thin)
            let lampColor: Color
            switch s.tagLamp {
            case .on: lampColor = Palette.orange
            case .tx: lampColor = Palette.orange
            case .rx: lampColor = s.blinkPhase ? Palette.white : Palette.orange
            case .blink: lampColor = s.blinkPhase ? Palette.orange : Palette.lampOff
            }
            if s.tagLamp == .tx { dot(right - w + 11, bottom - h / 2, 7.5, fill: Palette.orangeGlow) }
            dot(right - w + 11, bottom - h / 2, 4.5, fill: lampColor, stroke: StrokeStyle(lineWidth: 1.2))
            ctx.draw(label, at: CGPoint(x: right - w + 20, y: bottom - h / 2), anchor: .leading)
        }
    }
}
