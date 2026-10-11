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

/// The card file: your code across the top, the card punch on the left, the Rolodex on the right.
struct CardFileView: View {
    let model: CardFileModel
    @FocusState private var codeFocused: Bool

    var body: some View {
        DeviceWindow(title: "CARD FILE") {
            VStack(spacing: 0) {
                Header(model: model)
                    .frame(height: 69)
                Rectangle().fill(Palette.ink).frame(height: 1)
                HStack(alignment: .top, spacing: 20) {
                    PunchPanel(model: model, codeFocused: $codeFocused)
                        .frame(width: 356, height: 468)
                    RolodexColumn(model: model)
                        .frame(width: 376)
                }
                .padding(.top, 17)
            }
            .padding(EdgeInsets(top: 0, leading: 24, bottom: 25, trailing: 24))
            .frame(width: 800)
            .foregroundStyle(Palette.ink)
        }
        .overlay(alignment: .topLeading) { GhostLayer(model: model) }
        .coordinateSpace(.named(CardSpace.name))
        .onPreferenceChange(SpotKey.self) { spots in
            MainActor.assumeIsolated { model.spots = spots }
        }
        .onChange(of: model.focusRequest) { _, _ in codeFocused = true }
    }
}

// MARK: Header

private struct Header: View {
    let model: CardFileModel

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text("YOUR PEOPLE, ON FILE.")
                .font(Fonts.jura(22, "Light"))
                .tracking(0.6)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR CODE")
                    .font(Fonts.jura(9, "SemiBold"))
                    .tracking(1.2)
                    .foregroundStyle(Palette.mute)
                Text(model.file.myCode)
                    .font(Fonts.lcd(18))
                    .tracking(1.4)
                    .textSelection(.enabled)
            }
            Button { model.copyMyCode() } label: {
                Text("COPY").frame(width: 70, height: 30)
            }
            .buttonStyle(RelayKeyStyle())
            .padding(.leading, 26)
            .accessibilityLabel("Copy your code")
        }
        .padding(.top, 4)
    }
}

// MARK: The card punch

private struct PunchPanel: View {
    @Bindable var model: CardFileModel
    var codeFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CARD PUNCH")
                .font(Fonts.jura(15, "Medium"))
                .tracking(1.4)
                .padding(.top, 20)
            Reader(readout: model.readout, lamps: model.lamps)
                .frame(height: 56)
                .padding(.top, 14)
            Text("A FRIEND'S CODE")
                .font(Fonts.jura(9, "SemiBold"))
                .tracking(1.2)
                .foregroundStyle(Palette.mute)
                .padding(.top, 24)
            codeRow.padding(.top, 8)
            tryRow.padding(.top, 7)
            slot.padding(.top, 9)
            Text("DROP CARD HERE")
                .font(Fonts.jura(8, "SemiBold"))
                .tracking(1.2)
                .foregroundStyle(model.feedHot ? Palette.orange : Palette.mute)
                .frame(maxWidth: .infinity)
                .padding(.top, 11)
            OutTray(model: model).padding(.top, 8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 19)
        .insetPanel(radius: 14)
    }

    private var codeRow: some View {
        HStack(spacing: 12) {
            TextField("Code", text: $model.codeText, prompt: Text("TLK-····"))
                .textFieldStyle(.plain)
                .font(Fonts.lcd(17))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 12)
                .frame(height: 37)
                .background(RoundedRectangle(cornerRadius: Radius.key, style: .continuous).fill(Palette.white))
                .overlay(RoundedRectangle(cornerRadius: Radius.key, style: .continuous).strokeBorder(Palette.ink, lineWidth: 1.3))
                .focused(codeFocused)
                .onSubmit { model.checkCode() }
                .onChange(of: model.codeText) { _, text in
                    let tidy = String(text.uppercased().prefix(9))
                    if tidy != text { model.codeText = tidy }
                }
                .accessibilityLabel("A friend's code")
            Button { model.checkCode() } label: {
                Text("CHECK").frame(width: 80, height: 37)
            }
            .buttonStyle(RelayKeyStyle())
        }
    }

    // Until there's a server, these are the codes that work (and one that doesn't).
    private var tryRow: some View {
        HStack(spacing: 6) {
            Text("TRY")
                .font(Fonts.jura(8, "SemiBold"))
                .tracking(1)
                .foregroundStyle(Palette.mute)
            ForEach(["TLK-ZOE7", "TLK-PIP3", "TLK-0000"], id: \.self) { code in
                Button { model.tryCode(code) } label: {
                    Text(code)
                        .font(Fonts.jura(8.5, "Bold"))
                        .tracking(0.6)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.mute, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 16)
    }

    private var slot: some View {
        VStack(spacing: 0) {
            Text("CARD SLOT")
                .font(Fonts.jura(8, "SemiBold"))
                .tracking(1.2)
                .foregroundStyle(Palette.mute)
                .padding(.top, 13)
            Capsule()
                .fill(Palette.ink)
                .frame(height: 12)
                .spot(.slot)
                .padding(.horizontal, 18)
                .padding(.top, 9)
            Spacer(minLength: 0)
        }
        .frame(height: 69)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(model.feedHot ? Palette.orangeGlow : Palette.shell)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(model.feedHot ? Palette.orange : Palette.ink, lineWidth: 1.3)
        )
        .spot(.feed)
        .animation(.easeOut(duration: 0.15), value: model.feedHot)
        .accessibilityHidden(true)
    }
}

/// The punch's display: what's happening, what to do next, and one status lamp.
private struct Reader: View {
    let readout: PunchReadout
    let lamps: CardFileModel.Lamps

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(readout.big)
                    .font(Fonts.lcd(17))
                    .tracking(1.2)
                    .foregroundStyle(Palette.lcdText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(readout.sub)
                    .font(Fonts.lcd(10, bold: false))
                    .tracking(0.8)
                    .foregroundStyle(Palette.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            ReaderLamp(lamps: lamps)
        }
        .padding(.horizontal, 15)
        .insetPanel(Palette.key, radius: 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Punch: \(readout.big), \(readout.sub)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct ReaderLamp: View {
    let lamps: CardFileModel.Lamps

    var body: some View {
        if lamps.read == .blink {
            TimelineView(.periodic(from: .now, by: 0.3)) { context in
                bulb(Int(context.date.timeIntervalSinceReferenceDate / 0.3) % 2 == 0 ? Palette.orange : Palette.lcdDim)
            }
        } else {
            bulb(lamps.err == .on ? Palette.ledRed : lamps.ok == .on ? Palette.orange : Palette.lcdDim)
        }
    }

    private func bulb(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 0.8))
            .frame(width: 8, height: 8)
    }
}

private struct OutTray: View {
    let model: CardFileModel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        ZStack(alignment: .topLeading) {
            Text("OUT")
                .font(Fonts.jura(8, "SemiBold"))
                .tracking(1.2)
                .foregroundStyle(Palette.mute)
                .padding(EdgeInsets(top: 10, leading: 13, bottom: 0, trailing: 0))
            Color.clear
                .frame(width: CardSpace.card.width * CardSpace.trayScale, height: CardSpace.card.height * CardSpace.trayScale)
                .spot(.trayCard)
                .padding(EdgeInsets(top: 13, leading: 64, bottom: 0, trailing: 0))
            if let card = model.file.tray {
                DraggableCard(model: model, card: card, source: .tray, scale: CardSpace.trayScale)
                    .padding(EdgeInsets(top: 13, leading: 64, bottom: 0, trailing: 0))
                    .transition(.offset(y: -36).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 127)
        .background(shape.fill(Palette.paper))
        .overlay(shape.strokeBorder(Palette.mute, lineWidth: 1))
    }
}

// MARK: The card

/// A line card: orange band, the friend's name, when you added them, and their own hole pattern.
/// Drawn at full size (288 × 153); smaller copies are scaled.
struct LineCardView: View {
    enum Lift { case flat, resting, held }

    let card: LineCard
    let jack: Int?
    var lift = Lift.resting

    var body: some View {
        let size = CardSpace.card
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        ZStack(alignment: .topLeading) {
            Palette.plate
            Rectangle().fill(Palette.orange).frame(height: 12)
            Text("LINE CARD")
                .font(Fonts.jura(9, "SemiBold"))
                .tracking(1.2)
                .foregroundStyle(Palette.mute)
                .offset(x: 16, y: 24)
            Text(card.name)
                .font(Fonts.jura(28, "Light"))
                .tracking(0.5)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .frame(width: size.width - 110, alignment: .leading)
                .offset(x: 16, y: 40)
            Text(card.meta)
                .font(Fonts.jura(9, "SemiBold"))
                .tracking(0.9)
                .foregroundStyle(Palette.mute)
                .lineLimit(1)
                .offset(x: 16, y: 85)
            if let jack {
                Text("JACK " + String(format: "%02d", jack + 1))
                    .font(Fonts.jura(8, "Bold"))
                    .tracking(1)
                    .foregroundStyle(Palette.orange)
                    .frame(width: 63, height: 21)
                    .overlay(Rectangle().strokeBorder(Palette.orange, lineWidth: 1))
                    .offset(x: 205, y: 32)
            }
            CardHoles(bits: card.holes)
                .frame(width: 13 * 17 + 10, height: 16)
                .offset(x: 16, y: 113)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.ink, lineWidth: 1.5))
        .overlay(alignment: .bottomLeading) { Notches().frame(width: size.width, height: 14) }
        .background(
            shape.fill(Palette.plugShadow)
                .offset(x: lift == .held ? 9 : 3, y: lift == .held ? 13 : 4)
                .opacity(lift == .flat ? 0 : 1)
        )
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

/// A card in the tray or at the front of the Rolodex. Drag it to the slot; it stays behind, faded, while you do.
private struct DraggableCard: View {
    let model: CardFileModel
    let card: LineCard
    let source: CardFileModel.Source
    let scale: CGFloat

    var body: some View {
        let picked = model.ghost?.card.id == card.id
        let jack = model.jack(of: card)
        LineCardView(card: card, jack: jack, lift: picked ? .flat : .resting)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: CardSpace.card.width * scale, height: CardSpace.card.height * scale, alignment: .topLeading)
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
            .accessibilityHint("Drag it into the card slot to put \(card.name) on your board.")
            .accessibilityAction(named: "Punch") { model.punchWithoutDragging(source) }
    }
}

/// The dragged card, drawn above everything. In the slot it's cut off at the slot line.
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
                .scaleEffect(ghost.scale, anchor: .topLeading)
                .offset(x: ghost.origin.x, y: ghost.origin.y)
            }
        }
        .mask(alignment: .top) {
            Rectangle().frame(height: ghost?.inSlot == true ? max(cutoff, 0) : nil)
        }
        .allowsHitTesting(false)
    }
}

// MARK: The Rolodex

private struct RolodexColumn: View {
    let model: CardFileModel

    var body: some View {
        let front = model.file.frontCard
        let jack = front.flatMap { model.jack(of: $0) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("ROLODEX")
                    .font(Fonts.jura(15, "Medium"))
                    .tracking(1.4)
                Spacer(minLength: 0)
                Text(model.file.counter)
                    .font(Fonts.jura(10, "SemiBold"))
                    .tracking(1)
                    .foregroundStyle(Palette.mute)
                    .monospacedDigit()
            }
            .padding(.top, 16)
            .padding(.leading, 12)

            Group {
                Drum(model: model).frame(width: 290, height: 195).padding(.top, 33)
                HStack(spacing: 14) {
                    Button { model.turn(-1) } label: { Text("‹").font(Fonts.jura(16, "Bold")).frame(width: 43, height: 33) }
                        .buttonStyle(RelayKeyStyle())
                        .accessibilityLabel("Previous card")
                    Capsule().fill(Palette.key).frame(height: 7)
                    Button { model.turn(1) } label: { Text("›").font(Fonts.jura(16, "Bold")).frame(width: 43, height: 33) }
                        .buttonStyle(RelayKeyStyle())
                        .accessibilityLabel("Next card")
                }
                .frame(width: 290)
                .padding(.top, 21)
                VStack(spacing: 10) {
                    Text(status(front: front, jack: jack))
                        .font(Fonts.jura(13, "Medium"))
                        .tracking(1)
                    Text(detail(front: front, onBoard: jack != nil))
                        .font(Fonts.jura(12, "Regular"))
                        .foregroundStyle(Palette.mute)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 290)
                .padding(.top, 24)
                Button { model.eject() } label: {
                    Text("EJECT FROM BOARD").frame(width: 204, height: 35)
                }
                .buttonStyle(RelayKeyStyle())
                .disabled(!model.canEject)
                .opacity(model.canEject ? 1 : 0.45)
                .frame(width: 290)
                .padding(.top, 22)
                .accessibilityHint("Takes this friend off your board. The card stays here.")
            }
            .padding(.leading, 34)
        }
    }

    private func status(front: LineCard?, jack: Int?) -> String {
        guard let front else { return "NO CARDS YET" }
        guard let jack else { return "\(front.name) IS ON FILE" }
        return "\(front.name) IS ON JACK " + String(format: "%02d", jack + 1)
    }

    private func detail(front: LineCard?, onBoard: Bool) -> String {
        guard let front else { return "Check a friend's code to get their line card." }
        return onBoard
            ? "Eject frees a jack. The card stays here."
            : "Drag the card into the slot to put \(front.name) back on your board."
    }
}

/// The front card whole, three card tops peeking up behind it.
private struct Drum: View {
    let model: CardFileModel

    var body: some View {
        let file = model.file
        let behind = min(3, max(0, file.cards.count - 1))
        ZStack(alignment: .topLeading) {
            // Furthest back first: narrower and higher.
            ForEach((1...3).reversed(), id: \.self) { k in
                if k <= behind {
                    Button { model.turn(k) } label: {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Palette.shell)
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Palette.ink, lineWidth: 1))
                            .frame(width: 288 - CGFloat(k) * 12, height: 149)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 1 + CGFloat(k) * 6, y: 42 - CGFloat(k) * 14)
                    .accessibilityHidden(true)
                }
            }
            Color.clear
                .frame(width: CardSpace.card.width, height: CardSpace.card.height)
                .spot(.front)
                .offset(x: 1, y: 42)
            if let card = file.frontCard {
                DraggableCard(model: model, card: card, source: .file, scale: 1)
                    .id(card.id)
                    .transition(.asymmetric(insertion: .offset(y: -14).combined(with: .opacity), removal: .opacity))
                    .offset(x: 1, y: 42)
            }
        }
        .frame(width: 290, height: 195, alignment: .topLeading)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { model.turn(-1); return .handled }
        .onKeyPress(.upArrow) { model.turn(-1); return .handled }
        .onKeyPress(.rightArrow) { model.turn(1); return .handled }
        .onKeyPress(.downArrow) { model.turn(1); return .handled }
        .onKeyPress(.return) { model.punchWithoutDragging(.file); return .handled }
    }
}
