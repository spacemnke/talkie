import SwiftUI
import TalkieCore

/// The switchboard, one-handed: the nameplate, the display, the jacks, and the deck with the TALK
/// key at the bottom where your thumb is.
struct BoardScreen: View {
    let model: PhoneModel

    var body: some View {
        VStack(spacing: 0) {
            Nameplate(model: model)
            ScrollView {
                VStack(spacing: 14) {
                    DisplayPanel(model: model)
                    JackGrid(model: model)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .scrollBounceBehavior(.basedOnSize)
            Deck(model: model)
        }
        .background(Palette.shell.ignoresSafeArea())
        .overlay {
            if let jack = model.board.knockers.first, model.board.openJacks.isEmpty {
                KnockCard(model: model, jack: jack)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.board.knockers)
        .sheet(isPresented: Binding(get: { model.adding }, set: { if !$0 { model.closeAdd() } })) {
            AddFriendSheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: Nameplate

private struct Nameplate: View {
    let model: PhoneModel

    var body: some View {
        HStack(spacing: 12) {
            SmileyMark()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text("TALKIE")
                    .font(Fonts.jura(26, "Light"))
                    .tracking(0.6)
                Text("PATCH INTERCOM · \(model.board.plan.title.uppercased())")
                    .font(Fonts.jura(9.5, "SemiBold"))
                    .tracking(1.6)
                    .foregroundStyle(Palette.orangeInk)
            }
            Spacer(minLength: 8)
            Button(action: model.toggleDoNotDisturb) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.board.doNotDisturb ? Palette.orange : Palette.lampOff)
                        .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1.2))
                        .frame(width: 8, height: 8)
                    Text("DND")
                }
                .frame(width: 66, height: 34)
            }
            .buttonStyle(RelayKeyStyle(height: 3))
            .accessibilityLabel(model.board.doNotDisturb ? "Do not disturb, on" : "Do not disturb, off")
            Button(action: model.openAdd) {
                Text("ADD").frame(width: 56, height: 34)
            }
            .buttonStyle(RelayKeyStyle(fill: Palette.orange, height: 3))
            .accessibilityLabel("Add a friend")
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Palette.plate.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.ink).frame(height: 2) }
    }
}

/// The smiley dot grille from the app icon.
struct SmileyMark: View {
    private static let face: Set<Int> = [2 * 9 + 2, 2 * 9 + 6, 5 * 9 + 2, 5 * 9 + 6, 6 * 9 + 3, 6 * 9 + 4, 6 * 9 + 5]

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.width * 0.03), with: .color(Color(hex: 0x181818)))
            let pitch = size.width * 52 / 512, r = size.width * 16 / 512, start = size.width * 48 / 512
            for row in 0..<9 {
                for col in 0..<9 {
                    let c = CGPoint(x: start + CGFloat(col) * pitch, y: start + CGFloat(row) * pitch)
                    let dot = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                    ctx.fill(dot, with: .color(Self.face.contains(row * 9 + col) ? Palette.white : Color(hex: 0x414141)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: Display

/// The LCD: who's on the line and what's happening, the line flags and the level meter.
private struct DisplayPanel: View {
    let model: PhoneModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let readout = model.board.readout(now: model.now)
            let flags = model.board.flags
            VStack(alignment: .leading, spacing: 8) {
                Text(Self.phone(readout.big))
                    .font(Fonts.lcd(26))
                    .tracking(1.4)
                    .foregroundStyle(Palette.lcdText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(Self.phone(readout.sub))
                    .font(Fonts.lcd(12.5, bold: false))
                    .tracking(0.7)
                    .foregroundStyle(Palette.orange)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                HStack(alignment: .bottom) {
                    HStack(spacing: 11) {
                        flag("A", flags.a)
                        flag("B", flags.b)
                        if model.board.plan == .pro {
                            flag("C", flags.c)
                            flag("D", flags.d)
                        }
                        flag("TX", flags.tx)
                        flag("RX", flags.rx)
                        if flags.dnd { flag("DND", true) }
                    }
                    Spacer(minLength: 8)
                    Meter(level: max(model.micLevel, model.heardLevel))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.lcd))
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Palette.key))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Palette.ink, lineWidth: 1.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(readout.big). \(readout.sub)")
        }
    }

    private func flag(_ label: String, _ on: Bool) -> some View {
        Text(label)
            .font(Fonts.jura(10, "SemiBold"))
            .tracking(0.8)
            .foregroundStyle(on ? Palette.orange : Palette.lcdDim)
    }

    /// The board's words are written for a mouse; on a phone you tap and hold.
    static func phone(_ text: String) -> String {
        text.replacingOccurrences(of: "RIGHT-CLICK", with: "HOLD")
            .replacingOccurrences(of: "CLICK", with: "TAP")
            .replacingOccurrences(of: "PRESS ADD", with: "TAP ADD")
            .replacingOccurrences(of: "TYPE OR PASTE", with: "ENTER")
    }
}

private struct Meter: View {
    let level: Double

    var body: some View {
        let lit = Int((level * 10).rounded())
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<10, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < lit ? (i >= 8 ? Palette.lcdText : Palette.orange) : Palette.lcdDim)
                    .frame(width: 6, height: 7 + CGFloat(i % 3))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: Jacks

private struct JackGrid: View {
    let model: PhoneModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(0..<8, id: \.self) { jack in
                JackCell(model: model, jack: jack)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.plate))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.ink, lineWidth: 1.5))
    }
}

private struct JackCell: View {
    let model: PhoneModel
    let jack: Int

    var body: some View {
        let board = model.board
        let friend = board.friend(jack)
        let locked = board.isLocked(jack)
        let lamp = board.lamp(for: jack)
        let plugged = board.cord(at: jack) != nil || board.incoming[jack] != nil
        Button { model.tapJack(jack) } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(Switchboard.pad(jack))
                        .font(Fonts.jura(10, "SemiBold"))
                        .foregroundStyle(Palette.mute)
                    if let c = board.cord(at: jack) {
                        Text(c.label)
                            .font(Fonts.jura(10, "Bold"))
                            .foregroundStyle(Palette.orangeInk)
                    }
                    Spacer()
                    LampView(lamp: lamp)
                }
                HStack(spacing: 10) {
                    Hole(plugged: plugged, locked: locked)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(locked ? "PRO" : friend?.name ?? "ADD")
                            .font(Fonts.jura(14, friend == nil ? "Medium" : "SemiBold"))
                            .tracking(0.8)
                            .foregroundStyle(nameColor(friend: friend, locked: locked))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(status(friend: friend, locked: locked, lamp: lamp))
                            .font(Fonts.jura(8.5, "SemiBold"))
                            .tracking(1)
                            .foregroundStyle(Palette.mute)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(locked ? Palette.soft : Palette.paper))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Palette.ink, style: StrokeStyle(lineWidth: 1, dash: locked ? [4, 3] : []))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if friend != nil, !locked {
                let muted = board.isMuted(jack)
                Button(muted ? "Unmute" : "Mute for Me", systemImage: muted ? "speaker.wave.2" : "speaker.slash") {
                    model.setMuted(jack, !muted)
                }
                Button("Take Off the Board", systemImage: "eject", role: .destructive) {
                    model.eject(jack)
                }
            }
        }
        .accessibilityLabel(accessibility(friend: friend, locked: locked, lamp: lamp))
    }

    private func nameColor(friend: Friend?, locked: Bool) -> Color {
        if locked || friend == nil { return Palette.mute }
        return friend?.presence == .online ? Palette.ink : Palette.away
    }

    /// What the jack is doing, under the name.
    private func status(friend: Friend?, locked: Bool, lamp: Lamp) -> String {
        if locked { return "8 JACKS ON PRO" }
        guard let friend else { return "A FRIEND'S CODE" }
        if model.board.isMuted(jack) && lamp != .off { return "ON THE LINE · MUTED" }
        switch lamp {
        case .knock: return "KNOCKING"
        case .blink: return "KNOCKING…"
        case .dnd: return "DND · YOUR KNOCK WAITS"
        case .on: return "ON THE LINE"
        case .tx: return "ON THE LINE · TALKING"
        case .rx: return "TALKING"
        case .off: break
        }
        switch friend.presence {
        case .online: return "HERE"
        case .away: return "AWAY"
        case .doNotDisturb: return "DO NOT DISTURB"
        }
    }

    private func accessibility(friend: Friend?, locked: Bool, lamp: Lamp) -> String {
        let n = "Jack \(jack + 1)"
        if locked { return "\(n), Pro only" }
        guard let friend else { return "\(n), empty. Add a friend." }
        return "\(n), \(friend.name.capitalized), \(status(friend: friend, locked: false, lamp: lamp).lowercased())"
    }
}

/// The jack's lamp: off, steady orange on a line, blinking while knocking.
private struct LampView: View {
    let lamp: Lamp

    var body: some View {
        TimelineView(.periodic(from: .now, by: lamp == .knock || lamp == .rx ? 0.16 : 0.36)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate / (lamp == .knock || lamp == .rx ? 0.16 : 0.36)) % 2 == 0
            ZStack {
                if lamp == .tx { Circle().fill(Palette.orangeGlow).frame(width: 18, height: 18) }
                Circle()
                    .fill(fill(phase))
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1))
                    .frame(width: 10, height: 10)
                if lamp == .dnd { Rectangle().fill(Palette.ink).frame(width: 6, height: 1.2) }
            }
            .frame(width: 18, height: 18)
        }
        .accessibilityHidden(true)
    }

    private func fill(_ phase: Bool) -> Color {
        switch lamp {
        case .off: return Palette.lampOff
        case .on, .tx: return Palette.orange
        case .rx: return phase ? Palette.orange : Palette.white
        case .blink, .knock: return phase ? Palette.orange : Palette.lampOff
        case .dnd: return Palette.white
        }
    }
}

/// The jack's socket, with a plug in it while a cord is patched.
private struct Hole: View {
    let plugged: Bool
    let locked: Bool

    var body: some View {
        ZStack {
            Circle().fill(Palette.shell).overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1.5))
            Circle()
                .fill(plugged ? Palette.orange : Palette.white)
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1.5))
                .padding(5)
            Circle().fill(locked ? Palette.mute : Palette.key).frame(width: 13, height: 13)
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}
