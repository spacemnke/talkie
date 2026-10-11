import SwiftUI
import TalkieCore

enum BoardSpace {
    static let name = "board"
}

struct HoleKey: PreferenceKey {
    static let defaultValue: [Int: CGPoint] = [:]
    static func reduce(value: inout [Int: CGPoint], nextValue: () -> [Int: CGPoint]) {
        value.merge(nextValue()) { $1 }
    }
}

struct DockKey: PreferenceKey {
    static let defaultValue: [CordID: CGPoint] = [:]
    static func reduce(value: inout [CordID: CGPoint], nextValue: () -> [CordID: CGPoint]) {
        value.merge(nextValue()) { $1 }
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

/// The switchboard: identity panel, LCD, eight socket panels and the deck, with the cords on top.
struct BoardView: View {
    let model: BoardModel

    var body: some View {
        DeviceWindow(title: "SWITCHBOARD") {
            VStack(spacing: 0) {
                IdentityPanel(model: model).frame(height: 91)
                LCDPanel(model: model).frame(height: 119).padding(.top, 14)
                SocketField(model: model).padding(.top, 18)
                Deck(model: model).frame(height: 104).padding(.top, 28)
            }
            .padding(EdgeInsets(top: 16, leading: 18, bottom: 19, trailing: 18))
            .frame(width: 520)
            .overlay { CordsLayer(model: model) }
            .coordinateSpace(.named(BoardSpace.name))
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { model.boardSize = g.size }
                    .onChange(of: g.size) { _, size in
                        model.boardSize = size
                        model.resnapCords()
                    }
            })
            .onPreferenceChange(HoleKey.self) { holes in
                MainActor.assumeIsolated { model.holes = holes }
            }
            .onPreferenceChange(DockKey.self) { docks in
                MainActor.assumeIsolated { model.docks = docks }
            }
        }
    }
}

// MARK: Identity panel

private struct IdentityPanel: View {
    let model: BoardModel

    var body: some View {
        let flags = model.board.flags
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("TALKIE")
                    .font(Fonts.jura(34, "Light"))
                    .tracking(1)
                Text("PATCH INTERCOM")
                    .font(Fonts.jura(10, "SemiBold"))
                    .tracking(1.6)
                    .foregroundStyle(Palette.mute)
            }
            .padding(.leading, 18)
            .padding(.top, 14)
            Spacer(minLength: 0)
            SlotGrille()
                .frame(width: 112, height: 67)
                .padding(.top, 12)
            VStack(alignment: .leading, spacing: 13) {
                StatusLED(label: "NET", on: true)
                StatusLED(label: "MIC", on: model.board.talking)
                StatusLED(label: "SPKR", on: flags.rx)
            }
            .padding(.leading, 15)
            .padding(.trailing, 14)
            .padding(.top, 14)
        }
        .foregroundStyle(Palette.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .insetPanel()
        .overlay(alignment: .topLeading) { Screw().padding(7) }
        .overlay(alignment: .bottomTrailing) { Screw().padding(7) }
    }
}

/// Horizontal speaker slots.
private struct SlotGrille: View {
    var body: some View {
        VStack(spacing: 5.5) {
            ForEach(0..<9, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1).fill(Palette.ink).frame(height: 2.5)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct StatusLED: View {
    let label: String
    let on: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(on ? Palette.orange : Palette.lampOff)
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 0.7))
                .frame(width: 6, height: 6)
            Text(label)
                .font(Fonts.jura(8, "SemiBold"))
                .tracking(0.8)
                .foregroundStyle(Palette.mute)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(on ? "on" : "off")")
    }
}

private struct Screw: View {
    var body: some View {
        ZStack {
            Circle().fill(Palette.plate).overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1))
            Rectangle().fill(Palette.ink).frame(width: 4, height: 0.7).rotationEffect(.degrees(-45))
        }
        .frame(width: 6, height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: LCD

private struct LCDPanel: View {
    let model: BoardModel

    var body: some View {
        let board = model.board
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let readout = board.readout(now: model.now)
            VStack(alignment: .leading, spacing: 0) {
                Text(readout.big)
                    .font(Fonts.lcd(26))
                    .tracking(2)
                    .foregroundStyle(Palette.lcdText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.top, 16)
                Text(readout.sub)
                    .font(Fonts.lcd(12, bold: false))
                    .tracking(1)
                    .foregroundStyle(Palette.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 8)
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    FlagRow(flags: board.flags)
                    Spacer(minLength: 0)
                    Meter(model: model)
                }
                .padding(.bottom, 13)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.lcd))
            .padding(7)
            .insetPanel(Palette.key)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct FlagRow: View {
    let flags: Flags

    var body: some View {
        HStack(spacing: 0) {
            flag("A", flags.a)
            flag("B", flags.b)
            flag("TX", flags.tx)
            flag("RX", flags.rx)
            flag("FX", flags.effect != nil)
            flag("DND", flags.dnd)
        }
    }

    private func flag(_ text: String, _ on: Bool) -> some View {
        Text(text)
            .font(Fonts.jura(10, "SemiBold"))
            .tracking(0.8)
            .foregroundStyle(on ? Palette.orange : Palette.lcdDim)
            .frame(width: 30, alignment: .leading)
    }
}

/// Twelve stepped bars, reading only the level so it can redraw every frame on its own.
private struct Meter: View {
    let model: BoardModel

    var body: some View {
        let lit = Int((model.meter * 12).rounded())
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<12, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < lit ? (i >= 10 ? Palette.lcdText : Palette.orange) : Palette.lcdDim)
                    .frame(width: 7, height: CGFloat(7 + i % 3))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: Sockets

private struct SocketField: View {
    let model: BoardModel

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(112), spacing: 12), count: 4), spacing: 15) {
            ForEach(model.board.friends.indices, id: \.self) { i in
                SocketPanel(model: model, index: i)
            }
        }
    }
}

/// One friend's socket: number, lamp, name, the jack, and presence as a shape plus a word.
private struct SocketPanel: View {
    let model: BoardModel
    let index: Int

    var body: some View {
        let friend = model.board.friend(index)
        let arriving = model.arriving == index
        let shape = RoundedRectangle(cornerRadius: Radius.inset, style: .continuous)
        Button {
            model.tapJack(index)
        } label: {
            VStack(spacing: 0) {
                HStack {
                    Text(String(format: "%02d", index + 1))
                        .font(Fonts.jura(9, "Medium"))
                        .foregroundStyle(Palette.mute)
                    Spacer(minLength: 0)
                    LampView(lamp: model.board.lamp(for: index), size: 8)
                }
                .frame(height: 12)
                .padding(.horizontal, 10)
                .padding(.top, 8)

                Text(friend?.name ?? "+ ADD")
                    .font(Fonts.jura(13, "Medium"))
                    .tracking(1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(nameColor(friend))
                    .frame(height: 16)
                    .padding(.horizontal, 8)
                    .padding(.top, 7)

                SocketHole(near: model.nearJack == index, free: friend == nil)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: HoleKey.self, value: [index: g.frame(in: .named(BoardSpace.name)).center])
                    })
                    .padding(.top, 9)

                PresenceTag(friend: friend)
                    .frame(height: 10)
                    .padding(.top, 1)
                Spacer(minLength: 0)
            }
            .frame(width: 112, height: 119)
            .background(shape.fill(arriving ? Palette.orangeGlow : Palette.paper))
            .overlay(shape.strokeBorder(Palette.ink, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText(friend))
        .accessibilityHint(friend == nil ? "Opens the card file." : "Patches the next free cord into this jack, or pulls it out.")
    }

    private func nameColor(_ friend: Friend?) -> Color {
        guard let friend else { return Palette.mute }
        return friend.online ? Palette.ink : Palette.away
    }

    private func accessibilityText(_ friend: Friend?) -> String {
        guard let friend else { return "Jack \(index + 1): free, add a friend in the card file" }
        let presence: String
        switch friend.presence {
        case .online: presence = "here"
        case .away: presence = "away"
        case .doNotDisturb: presence = "do not disturb"
        }
        return "Jack \(index + 1): \(friend.name), \(presence)"
    }
}

private struct SocketHole: View {
    let near: Bool
    let free: Bool

    var body: some View {
        ZStack {
            Circle().fill(Palette.shell).overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1.5))
            Circle()
                .fill(near ? Palette.orange : Palette.white)
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1.5))
                .frame(width: 36, height: 36)
            Circle().fill(Palette.key).frame(width: 18, height: 18)
            if free {
                Text("+").font(Fonts.jura(12, "Bold")).foregroundStyle(Palette.white)
            }
        }
        .frame(width: 50, height: 50)
        .animation(.easeOut(duration: 0.12), value: near)
    }
}

/// Filled = here, hollow = away, a dash = do not disturb. The word says the same thing.
private struct PresenceTag: View {
    let friend: Friend?

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(friend?.presence == .online ? Palette.ink : Color.clear)
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 0.8))
                if friend?.presence == .doNotDisturb {
                    Rectangle().fill(Palette.ink).frame(width: 4, height: 0.9)
                }
            }
            .frame(width: 5, height: 5)
            Text(word)
                .font(Fonts.jura(8, "SemiBold"))
                .tracking(0.8)
                .foregroundStyle(Palette.mute)
        }
        .accessibilityHidden(true)
    }

    private var word: String {
        guard let friend else { return "ADD" }
        switch friend.presence {
        case .online: return "HERE"
        case .away: return "AWAY"
        case .doNotDisturb: return "DND"
        }
    }
}

struct LampView: View {
    let lamp: Lamp
    var size: CGFloat = 11

    var body: some View {
        switch lamp {
        case .blink:
            TimelineView(.periodic(from: .now, by: 0.18)) { context in
                let on = Int(context.date.timeIntervalSinceReferenceDate / 0.18) % 2 == 0
                bulb(on ? Palette.orange : Palette.lampOff)
            }
        case .rx:
            TimelineView(.periodic(from: .now, by: 0.08)) { context in
                let on = Int(context.date.timeIntervalSinceReferenceDate / 0.08) % 2 == 0
                bulb(on ? Palette.white : Palette.orange)
            }
        case .on:
            bulb(Palette.orange)
        case .tx:
            bulb(Palette.orange)
                .background(Circle().fill(Palette.orangeGlow).padding(-4))
        case .dnd:
            bulb(Palette.white)
                .overlay(Rectangle().fill(Palette.ink).frame(width: size - 3, height: 1.2))
        case .off:
            bulb(Palette.lampOff)
        }
    }

    private func bulb(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1))
            .frame(width: size, height: size)
    }
}

// MARK: Deck

private struct Deck: View {
    let model: BoardModel

    var body: some View {
        let dnd = model.board.doNotDisturb
        HStack(alignment: .top, spacing: 0) {
            CordWell()
                .frame(width: 175, height: 78)
                .padding(EdgeInsets(top: 11, leading: 11, bottom: 0, trailing: 0))
            VolumeKnob(model: model)
                .frame(width: 64)
                .padding(EdgeInsets(top: 10, leading: 12, bottom: 0, trailing: 0))
            HStack(alignment: .top, spacing: 11) {
                DeckKey(title: "SND", caption: model.soundOn ? "SOUND ON" : "SOUND OFF", width: 54) { model.toggleSound() }
                DeckKey(title: "DND", caption: dnd ? "DND ON" : "AVAILABLE", width: 54, lit: dnd) { model.toggleDoNotDisturb() }
                DeckKey(title: "FILE", caption: "CARDS", width: 65) { model.openCardFile() }
                    .accessibilityLabel("Card file")
                    .accessibilityHint("Add friends with their codes, and keep their cards.")
            }
            .padding(EdgeInsets(top: 13, leading: 12, bottom: 0, trailing: 0))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .insetPanel()
    }
}

/// The dark well the cords live in. Each dock reports its centre so the plug knows where home is.
private struct CordWell: View {
    var body: some View {
        HStack(spacing: 0) {
            dock(.a).frame(width: 90)
            dock(.b).frame(width: 82)
            Spacer(minLength: 0)
        }
        .padding(.top, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .insetPanel(Palette.key, radius: 9)
    }

    private func dock(_ cord: CordID) -> some View {
        VStack(spacing: 8) {
            Circle()
                .fill(Palette.lcd)
                .overlay(Circle().strokeBorder(Palette.mute, lineWidth: 1.5))
                .frame(width: 36, height: 36)
                .background(GeometryReader { g in
                    Color.clear.preference(key: DockKey.self, value: [cord: g.frame(in: .named(BoardSpace.name)).center])
                })
            Text("CORD \(cord.label)")
                .font(Fonts.jura(8, "SemiBold"))
                .tracking(1)
                .foregroundStyle(Palette.shell)
        }
    }
}

private struct DeckKey: View {
    let title: String
    let caption: String
    let width: CGFloat
    var lit = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                Text(title)
                    .frame(width: width, height: 35)
            }
            .buttonStyle(RelayKeyStyle(fill: lit ? Palette.orange : Palette.white, text: lit ? Palette.white : Palette.ink))
            Text(caption)
                .font(Fonts.jura(7.5, "SemiBold"))
                .tracking(0.6)
                .foregroundStyle(Palette.mute)
                .lineLimit(1)
                .fixedSize()
                .frame(width: width)
                .padding(.top, 20)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct VolumeKnob: View {
    let model: BoardModel
    @State private var dragStart: Double?

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Palette.white).overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1.5))
                Circle().fill(Palette.plate).overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1)).frame(width: 32, height: 32)
                Rectangle()
                    .fill(Palette.ink)
                    .frame(width: 2, height: 9)
                    .offset(y: -20)
                    .rotationEffect(.degrees(-135 + 270 * model.volume))
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let start = dragStart ?? model.volume
                        if dragStart == nil { dragStart = start }
                        model.setVolume(start - v.translation.height / 160)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .accessibilityElement()
            .accessibilityLabel("Volume")
            .accessibilityValue("\(Int((model.volume * 10).rounded())) of 10")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: model.setVolume(model.volume + 0.1)
                case .decrement: model.setVolume(model.volume - 0.1)
                @unknown default: break
                }
            }
            Text("VOLUME")
                .font(Fonts.jura(7.5, "SemiBold"))
                .tracking(0.8)
                .foregroundStyle(Palette.mute)
        }
    }
}

// MARK: Keys shared with the card file

struct KeyFace: View {
    let title: String
    let detail: String
    let lit: Bool

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title).font(Fonts.jura(13, "Bold")).tracking(0.8)
                Spacer(minLength: 0)
                Circle()
                    .fill(lit ? Palette.orange : Palette.lampOff)
                    .overlay(Circle().stroke(Palette.ink, lineWidth: 1.5))
                    .frame(width: 8, height: 8)
            }
            Spacer(minLength: 0)
            Text(detail).font(Fonts.jura(9, "SemiBold")).tracking(0.7).opacity(0.85)
        }
        .foregroundStyle(Palette.ink)
    }
}

/// A hardware key: a hard ink shadow underneath that disappears as the key goes down.
struct HardKeyStyle: ButtonStyle {
    var fill: Color
    var width: CGFloat = 56
    var height: CGFloat = 72

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(width: width, height: height)
            .background(fill)
            .overlay(Rectangle().stroke(Palette.ink, lineWidth: 2))
            .offset(y: configuration.isPressed ? 3 : 0)
            .background(Rectangle().fill(Palette.ink).offset(y: 3))
            .contentShape(Rectangle())
    }
}
