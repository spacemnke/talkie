import SwiftUI
import TalkieCore

private extension View {
    /// Reports this view's frame so cards know where to fly.
    func spot(_ spot: CardSpot) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: SpotKey.self, value: [spot: g.frame(in: .named(CardSpace.name))])
        })
    }
}

/// The card file: the punch with its code entry and OUT tray on the left, the Rolodex on the right.
struct CardFileView: View {
    let model: CardFileModel
    @FocusState private var codeFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            PunchColumn(model: model, codeFocused: $codeFocused)
                .frame(width: 256)
            RolodexColumn(model: model)
                .frame(width: 236)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 18, trailing: 16))
        .background(Palette.shell)
        .overlay(alignment: .topLeading) { GhostLayer(model: model) }
        .coordinateSpace(.named(CardSpace.name))
        .onPreferenceChange(SpotKey.self) { spots in
            MainActor.assumeIsolated { model.spots = spots }
        }
        .onChange(of: model.focusRequest) { _, _ in codeFocused = true }
    }
}

// MARK: The card

/// A line card: orange band, the friend's name, when you added them, and their own hole pattern.
struct LineCardView: View {
    enum Lift { case flat, resting, held }

    let card: LineCard
    let jack: Int?
    var lift = Lift.resting

    private static let shape = UnevenRoundedRectangle(
        topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 4, topTrailingRadius: 14
    )

    var body: some View {
        let size = CardSpace.card
        ZStack(alignment: .topLeading) {
            Palette.plate
            Rectangle()
                .fill(Palette.orange)
                .frame(height: 7)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.ink).frame(height: 1.5) }
            Text("LINE CARD")
                .font(Fonts.jura(8, "SemiBold"))
                .tracking(1.1)
                .foregroundStyle(Palette.mute)
                .offset(x: 10, y: 13)
            Text(card.name)
                .font(Fonts.jura(26, "Light"))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .offset(x: 10, y: 22)
            Text(card.meta)
                .font(Fonts.jura(8.5, "SemiBold"))
                .tracking(0.8)
                .foregroundStyle(Palette.mute)
                .lineLimit(1)
                .offset(x: 10, y: 57)
            CardHoles(bits: card.holes)
                .frame(width: size.width - 20, height: 15)
                .offset(x: 10, y: size.height - 14 - 15)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(Self.shape)
        .overlay(Self.shape.stroke(Palette.ink, lineWidth: 2))
        .overlay(alignment: .topTrailing) {
            if let jack { JackStamp(jack: jack) }
        }
        .overlay(alignment: .bottomLeading) { notches }
        .background(
            Self.shape
                .fill(Palette.plugShadow)
                .offset(x: lift == .held ? 9 : 3, y: lift == .held ? 13 : 4)
                .opacity(lift == .flat ? 0 : 1)
        )
    }

    /// Two notches in the bottom edge, like a real punched card.
    private var notches: some View {
        let x = (CardSpace.card.width * 0.27).rounded()
        return ZStack(alignment: .topLeading) {
            notch.offset(x: x)
            notch.offset(x: CardSpace.card.width - x - 20)
        }
        .frame(width: CardSpace.card.width, height: 8, alignment: .topLeading)
        .offset(y: 1)
    }

    private var notch: some View {
        NotchShape(closed: true)
            .fill(Palette.shell)
            .overlay(NotchShape(closed: false).stroke(Palette.ink, lineWidth: 2))
            .frame(width: 20, height: 8)
    }
}

private struct NotchShape: Shape {
    var closed: Bool

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.midX, y: r.minY - r.height))
        if closed { p.closeSubpath() }
        return p
    }
}

private struct CardHoles: View {
    let bits: [Bool]

    var body: some View {
        Canvas { ctx, size in
            let gap: CGFloat = 3
            let w = (size.width - gap * 13) / 14
            let h: CGFloat = 6
            for (i, punched) in bits.enumerated() {
                let r = CGRect(x: CGFloat(i % 14) * (w + gap), y: CGFloat(i / 14) * (h + gap), width: w, height: h)
                let hole = Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 1)
                if punched {
                    ctx.fill(hole, with: .color(Palette.ink))
                } else {
                    ctx.stroke(hole, with: .color(Palette.away), lineWidth: 1)
                }
            }
        }
    }
}

private struct JackStamp: View {
    let jack: Int

    var body: some View {
        Text("JACK " + String(format: "%02d", jack + 1))
            .font(Fonts.jura(9, "Bold"))
            .tracking(0.9)
            .foregroundStyle(Palette.orange)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(Rectangle().stroke(Palette.orange, lineWidth: 1.5))
            .rotationEffect(.degrees(6))
            .padding(.top, 15)
            .padding(.trailing, 9)
    }
}

/// A card in the tray or the Rolodex. Drag it to the punch; it stays behind, faded, while you do.
private struct DraggableCard: View {
    let model: CardFileModel
    let card: LineCard
    let source: CardFileModel.Source
    var lift = LineCardView.Lift.resting

    var body: some View {
        let picked = model.ghost?.card.id == card.id
        let jack = model.jack(of: card)
        LineCardView(card: card, jack: jack, lift: picked ? .flat : lift)
            .opacity(picked ? 0.25 : 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(CardSpace.name))
                    .onChanged { v in
                        model.cardDragChanged(card, from: source, location: v.location, start: v.startLocation)
                    }
                    .onEnded { _ in model.cardDragEnded() }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Line card: \(card.name)" + (jack.map { ", on jack \($0 + 1)" } ?? ", in the file"))
            .accessibilityHint("Drag it into the punch to put \(card.name) on your board.")
            .accessibilityAction(named: "Punch") { model.punchWithoutDragging(source) }
    }
}

/// The dragged card, drawn above everything. In the punch it's cut off at the slot.
private struct GhostLayer: View {
    let model: CardFileModel

    var body: some View {
        let ghost = model.ghost
        let cutoff = model.slotLine
        ZStack(alignment: .topLeading) {
            Color.clear
            if let ghost {
                LineCardView(
                    card: ghost.card,
                    jack: model.jack(of: ghost.card),
                    lift: ghost.inSlot ? .flat : (ghost.lifted ? .held : .resting)
                )
                .offset(x: ghost.origin.x, y: ghost.origin.y)
            }
        }
        .mask(alignment: .top) {
            Rectangle().frame(height: ghost?.inSlot == true ? max(cutoff, 0) : nil)
        }
        .allowsHitTesting(false)
    }
}

// MARK: The punch

private struct PunchColumn: View {
    @Bindable var model: CardFileModel
    var codeFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 0) {
            Feed(hot: model.feedHot)
                .frame(height: CardSpace.card.height + 14)
                .spot(.feed)
            device
            OutTray(model: model)
        }
    }

    private var device: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("CARD PUNCH").font(Fonts.jura(13, "Bold")).tracking(1)
                Spacer(minLength: 0)
                Text("READS LINE CARDS").font(Fonts.jura(10, "SemiBold")).tracking(1.2)
            }
            PunchLCD(readout: model.readout, lamps: model.lamps)
            codeEntry
            myCode
        }
        .foregroundStyle(Palette.ink)
        .padding(EdgeInsets(top: 16, leading: 12, bottom: 12, trailing: 12))
        .background(Palette.shell)
        .overlay(Rectangle().stroke(Palette.ink, lineWidth: 2))
        .overlay(alignment: .top) {
            // The slot cards go into.
            Capsule()
                .fill(Palette.lcd)
                .overlay(Capsule().stroke(Palette.ink, lineWidth: 2))
                .frame(width: CardSpace.card.width + 18, height: 14)
                .offset(y: -7)
        }
        .zIndex(1)
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("A FRIEND'S CODE").font(Fonts.jura(10, "SemiBold")).tracking(1.2)
            HStack(spacing: 8) {
                TextField("Code", text: $model.codeText, prompt: Text("TLK-····"))
                    .textFieldStyle(.plain)
                    .font(Fonts.lcd(18))
                    .foregroundStyle(Palette.lcdText)
                    .padding(.horizontal, 10)
                    .frame(height: 40)
                    .background(Palette.lcd)
                    .overlay(Rectangle().stroke(Palette.ink, lineWidth: 2))
                    .focused(codeFocused)
                    .onSubmit { model.checkCode() }
                    .onChange(of: model.codeText) { _, text in
                        let tidy = String(text.uppercased().prefix(9))
                        if tidy != text { model.codeText = tidy }
                    }
                    .accessibilityLabel("A friend's code")
                Button { model.checkCode() } label: {
                    Text("CHECK")
                        .font(Fonts.jura(12, "Bold"))
                        .tracking(0.6)
                        .foregroundStyle(Palette.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(HardKeyStyle(fill: Palette.orange, width: 70, height: 40))
            }
            // Until there's a server, these are the codes that work (and one that doesn't).
            HStack(spacing: 5) {
                Text("TRY").font(Fonts.jura(10, "SemiBold")).tracking(1).foregroundStyle(Palette.mute)
                ForEach(["TLK-ZOE7", "TLK-PIP3", "TLK-0000"], id: \.self) { code in
                    Button { model.tryCode(code) } label: { Chip(code) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var myCode: some View {
        HStack(spacing: 8) {
            Text("YOUR CODE").font(Fonts.jura(10, "SemiBold")).tracking(1)
            Text(model.file.myCode).font(Fonts.lcd(14)).tracking(1.2)
            Spacer(minLength: 0)
            Button { model.copyMyCode() } label: { Chip("COPY") }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy your code")
        }
        .padding(.top, 9)
        .overlay(alignment: .top) { Rectangle().fill(Palette.soft).frame(height: 1.5) }
    }
}

/// The dashed spot above the slot where you drop a card.
private struct Feed: View {
    let hot: Bool

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 4, topTrailingRadius: 14)
        Text("DROP A CARD HERE")
            .font(Fonts.jura(10, "SemiBold"))
            .tracking(1.2)
            .foregroundStyle(hot ? Palette.ink : Palette.mute)
            .frame(width: CardSpace.card.width, height: CardSpace.card.height)
            .background(shape.fill(hot ? Palette.orangeGlow : Color.clear))
            .overlay(shape.stroke(hot ? Palette.orange : Palette.away, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 4)
            .animation(.easeOut(duration: 0.15), value: hot)
            .accessibilityHidden(true)
    }
}

private struct PunchLCD: View {
    let readout: PunchReadout
    let lamps: CardFileModel.Lamps

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(readout.big)
                .font(Fonts.lcd(22))
                .tracking(1.5)
                .foregroundStyle(Palette.lcdText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(readout.sub)
                .font(Fonts.lcd(12, bold: false))
                .tracking(0.8)
                .foregroundStyle(Palette.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 6) {
                PunchFlag(text: "READ", state: lamps.read)
                PunchFlag(text: "OK", state: lamps.ok)
                PunchFlag(text: "ERR", state: lamps.err, error: true)
            }
            .padding(.top, 2)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.lcd)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Punch: \(readout.big), \(readout.sub)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct PunchFlag: View {
    let text: String
    let state: CardFileModel.LampState
    var error = false

    var body: some View {
        if state == .blink {
            TimelineView(.periodic(from: .now, by: 0.3)) { context in
                face(lit: Int(context.date.timeIntervalSinceReferenceDate / 0.3) % 2 == 0)
            }
        } else {
            face(lit: state == .on)
        }
    }

    private func face(lit: Bool) -> some View {
        let fill = error ? Palette.ledRed : Palette.orange
        return Text(text)
            .font(Fonts.jura(10, "SemiBold"))
            .tracking(0.8)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(lit ? (error ? Palette.white : Palette.lcd) : Palette.lcdDim)
            .background(lit ? fill : Color.clear)
            .overlay(Rectangle().stroke(lit ? fill : Palette.lcdDim, lineWidth: 1))
    }
}

private struct OutTray: View {
    let model: CardFileModel

    var body: some View {
        ZStack {
            if let card = model.file.tray {
                DraggableCard(model: model, card: card, source: .tray)
                    .transition(.offset(y: -36).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: CardSpace.card.height + 26)
        .spot(.tray)
        .background(Palette.soft)
        .overlay(alignment: .topLeading) {
            Text("OUT")
                .font(Fonts.jura(9, "SemiBold"))
                .tracking(1.3)
                .foregroundStyle(Palette.mute)
                .padding(.leading, 8)
                .padding(.top, 6)
        }
        .overlay(Rectangle().stroke(Palette.ink, lineWidth: 2))
        .padding(.top, -2)
    }
}

private struct Chip: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Fonts.jura(9.5, "Bold"))
            .tracking(0.6)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(Palette.white)
            .overlay(Rectangle().stroke(Palette.ink, lineWidth: 1.5))
            .contentShape(Rectangle())
    }
}

// MARK: The Rolodex

private struct RolodexColumn: View {
    let model: CardFileModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("ROLODEX").font(Fonts.jura(13, "Bold")).tracking(1)
                Spacer(minLength: 0)
                Text(model.file.counter).font(Fonts.jura(10, "SemiBold")).tracking(1.2)
            }
            Drum(model: model)
                .frame(maxWidth: .infinity)
                .frame(height: CardSpace.card.height + 56)
                .spot(.drum)
            HStack(spacing: 8) {
                Knob(symbol: "‹", label: "Previous card") { model.turn(-1) }
                Capsule()
                    .fill(Palette.key)
                    .overlay(Capsule().stroke(Palette.ink, lineWidth: 2))
                    .frame(height: 12)
                Knob(symbol: "›", label: "Next card") { model.turn(1) }
            }
            .padding(.top, -4)
            HStack(alignment: .center, spacing: 10) {
                Text(model.hint)
                    .font(Fonts.jura(11, "Medium"))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { model.eject() } label: {
                    KeyFace(title: "EJECT", detail: "FREE THE JACK", lit: model.canEject)
                }
                .buttonStyle(HardKeyStyle(fill: Palette.white, width: 96, height: 58))
                .disabled(!model.canEject)
                .opacity(model.canEject ? 1 : 0.55)
                .accessibilityHint("Takes the front card's friend off your board. The card stays here.")
            }
        }
        .foregroundStyle(Palette.ink)
    }
}

/// The front card whole, the next three peeking up behind it.
private struct Drum: View {
    let model: CardFileModel

    var body: some View {
        let file = model.file
        ZStack(alignment: .bottom) {
            ForEach(file.cards) { card in
                let k = file.depth(of: card.id) ?? 0
                let shown = min(k, 3)
                DraggableCard(model: model, card: card, source: .file, lift: k == 0 ? .resting : .flat)
                    .brightness(-0.07 * Double(shown))
                    .scaleEffect(1 - 0.045 * CGFloat(shown), anchor: .bottom)
                    .offset(y: -15 * CGFloat(min(k, 4)))
                    .opacity(k > 3 ? 0 : 1)
                    .zIndex(Double(10 - min(k, 9)))
                    .allowsHitTesting(k <= 3)
                    .accessibilityHidden(k != 0)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { model.turn(-1); return .handled }
        .onKeyPress(.upArrow) { model.turn(-1); return .handled }
        .onKeyPress(.rightArrow) { model.turn(1); return .handled }
        .onKeyPress(.downArrow) { model.turn(1); return .handled }
        .onKeyPress(.return) { model.punchWithoutDragging(.file); return .handled }
    }
}

private struct Knob: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(symbol)
                .font(Fonts.jura(18, "Bold"))
                .foregroundStyle(Palette.ink)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(KnobStyle())
        .accessibilityLabel(label)
    }
}

private struct KnobStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(Palette.white))
            .overlay(Circle().stroke(Palette.ink, lineWidth: 2))
            .offset(y: configuration.isPressed ? 3 : 0)
            .background(Circle().fill(Palette.ink).offset(y: 3))
            .contentShape(Circle())
    }
}
