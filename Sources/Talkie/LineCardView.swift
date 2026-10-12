import SwiftUI
import AppKit
import TalkieCore

/// Your line card: what you send a friend so they can add you. Orange band, your name, your code,
/// and a hole pattern of its own. Drawn at 288 × 153; smaller or larger copies are scaled.
struct LineCardView: View {
    static let size = CGSize(width: 288, height: 153)

    let card: LineCard

    var body: some View {
        let size = Self.size
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        ZStack(alignment: .topLeading) {
            Palette.plate
            Rectangle().fill(Palette.orange).frame(height: 12)
            Text("TALKIE LINE CARD")
                .font(Fonts.jura(9, "SemiBold"))
                .tracking(1.2)
                .foregroundStyle(Palette.mute)
                .offset(x: 16, y: 24)
            Text(card.name)
                .font(Fonts.jura(28, "Light"))
                .tracking(0.5)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 176, alignment: .leading)
                .offset(x: 16, y: 40)
            Text(card.code)
                .font(Fonts.lcd(16))
                .tracking(1.2)
                .foregroundStyle(Palette.ink)
                .offset(x: 16, y: 82)
            Text("PATCH ME IN")
                .font(Fonts.jura(8, "Bold"))
                .tracking(1)
                .foregroundStyle(Palette.orange)
                .frame(width: 74, height: 21)
                .overlay(Rectangle().strokeBorder(Palette.orange, lineWidth: 1))
                .offset(x: 198, y: 32)
            CardHoles(bits: card.holes)
                .frame(width: 13 * 17 + 10, height: 16)
                .offset(x: 16, y: 113)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.ink, lineWidth: 1.5))
        .overlay(alignment: .bottomLeading) { Notches().frame(width: size.width, height: 14) }
        .background(shape.fill(Palette.plugShadow).offset(x: 3, y: 4))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Line card: \(card.name), code \(card.code)")
    }
}

/// Two notches cut into the bottom edge.
private struct Notches: View {
    var body: some View {
        Canvas { ctx, size in
            for x in [CGFloat(42), size.width - 54] {
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addQuadCurve(to: CGPoint(x: x + 12, y: size.height), control: CGPoint(x: x + 6, y: size.height - 13))
                ctx.fill(p, with: .color(Palette.paper))
                ctx.stroke(p, with: .color(Palette.ink), lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Two rows of fourteen: punched holes are solid.
private struct CardHoles: View {
    let bits: [Bool]

    var body: some View {
        Canvas { ctx, _ in
            for (i, punched) in bits.enumerated() {
                let r = CGRect(x: CGFloat(i % 14) * 17, y: CGFloat(i / 14) * 10, width: 10, height: 6)
                if punched {
                    ctx.fill(Path(r), with: .color(Palette.ink))
                } else {
                    ctx.stroke(Path(r.insetBy(dx: 0.3, dy: 0.3)), with: .color(Palette.mute), lineWidth: 0.6)
                }
            }
        }
    }
}

// MARK: Sending it

/// The view a share menu points at.
final class ShareAnchorBox {
    weak var view: NSView?
}

/// Put behind a key so the share menu opens from it.
struct ShareAnchor: NSViewRepresentable {
    let box: ShareAnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        box.view = nsView
    }
}

@MainActor
enum CardSharing {
    /// The card as a picture, at three times size so it stays sharp in a message.
    static func image(of card: LineCard) -> NSImage? {
        let renderer = ImageRenderer(content: LineCardView(card: card).padding(10))
        renderer.scale = 3
        return renderer.nsImage
    }

    /// A message with the code in it, so pasting the whole thing into a board still works.
    static func message(for card: LineCard) -> String {
        "Add me on Talkie: \(card.code)\nhttps://switchtalkie.com"
    }

    /// Opens the share menu (Messages, Mail, AirDrop…) with the card and the message.
    /// Without a view to point from, copies the message instead.
    static func share(_ card: LineCard, from view: NSView?) {
        var items: [Any] = [message(for: card)]
        if let image = image(of: card) { items.insert(image, at: 0) }
        guard let view, view.window != nil else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message(for: card), forType: .string)
            return
        }
        NSSharingServicePicker(items: items).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}
