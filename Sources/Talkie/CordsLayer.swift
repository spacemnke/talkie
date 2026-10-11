import SwiftUI
import TalkieCore

/// The patch cords hanging over the board, and the plugs you drag around.
struct CordsLayer: View {
    let model: BoardModel

    var body: some View {
        // Read here, not inside the Canvas, so SwiftUI redraws when they change.
        let order = model.zOrder
        let docks = model.docks
        let cords = model.cords
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                for c in order {
                    guard let dock = docks[c], let sim = cords[c] else { continue }
                    Self.drawCord(&ctx, dock: dock, sim: sim, color: Self.color(c))
                }
            }
            .allowsHitTesting(false)

            ForEach(order, id: \.self) { c in
                if docks[c] != nil, let sim = cords[c] {
                    PlugView(color: Self.color(c), lifted: sim.dragging)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                        .position(sim.plug)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named(BoardSpace.name))
                                .onChanged { v in model.plugDragChanged(c, location: v.location, start: v.startLocation) }
                                .onEnded { _ in model.plugDragEnded(c) }
                        )
                        .accessibilityLabel("Cord \(c.label) plug")
                        .accessibilityHint("Drag it into a jack, or press to pull it out.")
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
    }

    private static func color(_ c: CordID) -> Color {
        c == .a ? Palette.orange : Palette.slate
    }

    private static func drawCord(_ ctx: inout GraphicsContext, dock: CGPoint, sim: CordSim, color: Color) {
        guard dock.distance(to: sim.plug) > 4 else { return }
        var path = Path()
        path.move(to: dock)
        path.addCurve(to: sim.plug, control1: sim.control1, control2: sim.control2)
        let round = StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
        ctx.stroke(path.offsetBy(dx: 3, dy: 5), with: .color(Palette.shadow), style: round)
        ctx.stroke(path, with: .color(Palette.ink), style: round)
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        ctx.stroke(path.offsetBy(dx: -1, dy: -1), with: .color(.white.opacity(0.4)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }
}

/// A plug seen end-on: a cap in the cord's colour over a grey shadow disc.
struct PlugView: View {
    let color: Color
    let lifted: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.plugShadow)
                .overlay(Circle().stroke(Palette.ink, lineWidth: 2))
                .offset(x: lifted ? 5 : 3, y: lifted ? 7 : 4)
            ZStack {
                Circle().fill(color)
                Circle().stroke(Palette.ink, lineWidth: 2)
                Circle().stroke(Palette.ink, lineWidth: 2).frame(width: 21, height: 21)
                Circle().fill(Palette.ink).frame(width: 11, height: 11)
            }
            .offset(x: lifted ? -3 : 0, y: lifted ? -4 : 0)
        }
        .animation(.easeOut(duration: 0.12), value: lifted)
    }
}
