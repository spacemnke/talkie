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

private extension View {
    /// The 2pt ink rule between the board's sections.
    func sectionRule() -> some View {
        overlay(alignment: .bottom) { Rectangle().fill(Palette.ink).frame(height: 2) }
    }
}

/// The switchboard: status strip, nameplate, LCD, jack field and deck, with the cords on top.
struct BoardView: View {
    let model: BoardModel

    var body: some View {
        VStack(spacing: 0) {
            StatusStrip(model: model).sectionRule()
            Nameplate().sectionRule()
            LCDPanel(model: model).sectionRule()
            JackField(model: model).sectionRule()
            Deck(model: model)
        }
        .frame(width: 500)
        .background(Palette.shell)
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

// MARK: Status strip

private struct StatusStrip: View {
    let model: BoardModel

    var body: some View {
        let flags = model.board.flags
        HStack(spacing: 0) {
            cell("SPKR", lit: flags.rx)
            cell("MIC", lit: model.board.talking)
            HStack(spacing: 18) {
                Text("NET")
                Text("LINK")
            }
            .padding(.horizontal, 10)
            .frame(width: 170, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(Palette.key)
            .foregroundStyle(Palette.shell)
            Spacer(minLength: 0)
        }
        .font(Fonts.jura(10, "SemiBold"))
        .tracking(1)
        .frame(height: 24)
    }

    private func cell(_ label: String, lit: Bool) -> some View {
        Text(label)
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            .background(lit ? Palette.orange : Palette.shell)
            .foregroundStyle(lit ? Palette.white : Palette.ink)
            .overlay(alignment: .trailing) { Rectangle().fill(Palette.ink).frame(width: 1.5) }
    }
}

// MARK: Nameplate

private struct Nameplate: View {
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("TALKIE")
                    .font(Fonts.jura(42, "Light"))
                Text("PATCH INTERCOM")
                    .font(Fonts.jura(13, "SemiBold"))
                    .tracking(1.3)
                    .foregroundStyle(Palette.orange)
                    .padding(.top, 6)
                    .padding(.leading, 2)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Circle().stroke(Palette.ink, lineWidth: 1.5).frame(width: 9, height: 9)
                    Text("8 LINES · 2 CORDS").font(Fonts.jura(12, "Medium")).tracking(0.5)
                }
            }
            .foregroundStyle(Palette.ink)
            .padding(EdgeInsets(top: 16, leading: 24, bottom: 12, trailing: 20))
            .frame(width: 300, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(Palette.plate)
            .overlay { Screws() }
            .overlay(alignment: .trailing) { Rectangle().fill(Palette.ink).frame(width: 2) }

            Grille()
        }
        .frame(height: 132)
    }
}

private struct Screws: View {
    var body: some View {
        GeometryReader { g in
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(Palette.plate)
                    .overlay(Circle().stroke(Palette.ink, lineWidth: 1.5))
                    .frame(width: 12, height: 12)
                    .position(x: i % 2 == 0 ? 12 : g.size.width - 14, y: i < 2 ? 12 : g.size.height - 12)
            }
        }
    }
}

private struct Grille: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.grille))
            var y: CGFloat = 7.5
            while y < size.height {
                var x: CGFloat = 7.5
                while x < size.width {
                    let r = CGRect(x: x - 4.3, y: y - 4.3, width: 8.6, height: 8.6)
                    ctx.fill(Path(ellipseIn: r), with: .color(Palette.ink))
                    ctx.fill(Path(ellipseIn: r.insetBy(dx: 1.3, dy: 1.3)), with: .color(Palette.key))
                    x += 11
                }
                y += 11
            }
        }
    }
}

// MARK: LCD

private struct LCDPanel: View {
    let model: BoardModel

    var body: some View {
        let board = model.board
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let readout = board.readout(now: model.now)
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(readout.big)
                        .font(Fonts.lcd(32))
                        .tracking(2)
                        .foregroundStyle(Palette.lcdText)
                        .lineLimit(1)
                    Text(readout.sub)
                        .font(Fonts.lcd(13, bold: false))
                        .tracking(1)
                        .foregroundStyle(Palette.orange)
                        .lineLimit(1)
                    FlagRow(flags: board.flags)
                }
                Spacer(minLength: 0)
                Meter(model: model)
            }
            .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 14))
            .frame(maxWidth: .infinity)
            .background(Palette.lcd)
        }
    }
}

private struct FlagRow: View {
    let flags: Flags

    var body: some View {
        HStack(spacing: 6) {
            flag("A", flags.a)
            flag("B", flags.b)
            flag("TX", flags.tx)
            flag("RX", flags.rx)
            flag(flags.effect ?? "FX", flags.effect != nil)
            flag("DND", flags.dnd)
        }
    }

    private func flag(_ text: String, _ on: Bool) -> some View {
        Text(text)
            .font(Fonts.jura(10, "SemiBold"))
            .tracking(0.8)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(on ? Palette.lcd : Palette.lcdDim)
            .background(on ? Palette.orange : Color.clear)
            .overlay(Rectangle().stroke(on ? Palette.orange : Palette.lcdDim, lineWidth: 1))
    }
}

/// Twelve bars, reading only the level so it can redraw every frame on its own.
private struct Meter: View {
    let model: BoardModel

    var body: some View {
        let lit = Int((model.meter * 12).rounded())
        VStack(spacing: 2) {
            ForEach((0..<12).reversed(), id: \.self) { i in
                Rectangle()
                    .fill(i < lit ? (i >= 10 ? Palette.lcdText : Palette.orange) : Palette.lcdDim)
                    .frame(width: 16, height: 4)
            }
        }
    }
}

// MARK: Jacks

private struct JackField: View {
    let model: BoardModel

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 4) {
            ForEach(model.board.friends.indices, id: \.self) { i in
                JackView(model: model, index: i)
            }
        }
        .padding(EdgeInsets(top: 16, leading: 10, bottom: 4, trailing: 10))
    }
}

private struct JackView: View {
    let model: BoardModel
    let index: Int

    var body: some View {
        let friend = model.board.friend(index)
        Button {
            model.tapJack(index)
        } label: {
            VStack(spacing: 7) {
                HStack {
                    LampView(lamp: model.board.lamp(for: index))
                    Spacer(minLength: 0)
                    Text(String(format: "%02d", index + 1))
                        .font(Fonts.jura(10, "Medium"))
                        .foregroundStyle(Palette.mute)
                }
                .frame(maxWidth: 78)

                NameStrip(friend: friend)

                Hole(near: model.nearJack == index, free: friend == nil)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: HoleKey.self, value: [index: g.frame(in: .named(BoardSpace.name)).center])
                    })
            }
            .padding(.bottom, 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText(friend))
    }

    private func accessibilityText(_ friend: Friend?) -> String {
        guard let friend else { return "Jack \(index + 1): free, invite a friend" }
        let presence: String
        switch friend.presence {
        case .online: presence = "online"
        case .away: presence = "away"
        case .doNotDisturb: presence = "do not disturb"
        }
        return "Jack \(index + 1): \(friend.name), \(presence)"
    }
}

private struct NameStrip: View {
    let friend: Friend?

    var body: some View {
        HStack(spacing: 4) {
            Text(friend?.name ?? "+ ADD")
                .lineLimit(1)
            if friend != nil {
                Spacer(minLength: 0)
                PresenceDot(presence: friend!.presence)
            }
        }
        .font(Fonts.jura(11, "SemiBold"))
        .tracking(0.7)
        .foregroundStyle(friend == nil ? Palette.mute : (friend!.online ? Palette.white : Palette.away))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: 78)
        .background(friend == nil ? Color.clear : Palette.key)
        .overlay(
            Rectangle().stroke(Palette.ink, style: StrokeStyle(lineWidth: 1.5, dash: friend == nil ? [3, 3] : []))
        )
    }
}

private struct PresenceDot: View {
    let presence: Presence

    var body: some View {
        ZStack {
            switch presence {
            case .online:
                Circle().fill(Palette.white)
            case .away:
                Circle().stroke(Palette.away, lineWidth: 1.5)
            case .doNotDisturb:
                Circle().stroke(Palette.white, lineWidth: 1.5)
                Rectangle().fill(Palette.white).frame(width: 8, height: 1.5)
            }
        }
        .frame(width: 8, height: 8)
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
                .overlay(Rectangle().fill(Palette.ink).frame(width: size - 4, height: 1.5))
        case .off:
            bulb(Palette.lampOff)
        }
    }

    private func bulb(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .overlay(Circle().stroke(Palette.ink, lineWidth: 1.5))
            .frame(width: size, height: size)
    }
}

private struct Hole: View {
    let near: Bool
    let free: Bool

    var body: some View {
        ZStack {
            Circle().fill(near ? Palette.orange : (free ? Palette.shell : Palette.white))
            Circle().stroke(Palette.ink, style: StrokeStyle(lineWidth: 2, dash: free ? [4, 3] : []))
            Circle().fill(Palette.ink).frame(width: 13, height: 13)
        }
        .frame(width: 34, height: 34)
    }
}

// MARK: Deck

private struct Deck: View {
    let model: BoardModel

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack {
                Spacer(minLength: 0)
                Dock(cord: .a)
                Spacer(minLength: 0)
                Dock(cord: .b)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(Palette.key)
            .overlay(Rectangle().stroke(Palette.ink, lineWidth: 2))

            VolumeKnob(model: model)

            Button { model.toggleSound() } label: {
                KeyFace(title: "SND", detail: model.soundOn ? "ON" : "OFF", lit: model.soundOn)
            }
            .buttonStyle(HardKeyStyle(fill: Palette.white))

            Button { model.toggleDoNotDisturb() } label: {
                KeyFace(title: "DND", detail: model.board.doNotDisturb ? "ON" : "OFF", lit: model.board.doNotDisturb)
            }
            .buttonStyle(HardKeyStyle(fill: Palette.white))
        }
        .padding(EdgeInsets(top: 14, leading: 12, bottom: 18, trailing: 12))
    }
}

private struct Dock: View {
    let cord: CordID

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(Palette.lcd)
                .overlay(Circle().stroke(Palette.lcdDim, lineWidth: 2).padding(1))
                .frame(width: 42, height: 42)
                .background(GeometryReader { g in
                    Color.clear.preference(key: DockKey.self, value: [cord: g.frame(in: .named(BoardSpace.name)).center])
                })
            Text("CORD \(cord.label)")
                .font(Fonts.jura(9, "SemiBold"))
                .tracking(1.1)
                .foregroundStyle(Palette.shell)
        }
    }
}

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

private struct VolumeKnob: View {
    let model: BoardModel
    @State private var dragStart: Double?

    var body: some View {
        VStack(spacing: 6) {
            Text("VOLUME").font(Fonts.jura(9, "SemiBold")).tracking(1.1)
            ZStack {
                Circle().fill(Palette.white)
                Circle().stroke(Palette.ink, lineWidth: 2)
                Circle().stroke(Palette.ink, lineWidth: 2).padding(11)
                Rectangle()
                    .fill(Palette.white)
                    .overlay(Rectangle().stroke(Palette.ink, lineWidth: 1.5))
                    .frame(width: 7, height: 8)
                    .offset(y: -18)
                    .rotationEffect(.degrees(-135 + 270 * model.volume))
            }
            .frame(width: 50, height: 50)
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
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 2)
    }
}
