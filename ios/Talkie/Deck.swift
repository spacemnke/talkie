import SwiftUI
import TalkieCore

/// The bottom of the board: BUZZ, the round TALK key you hold, and HANG UP.
struct Deck: View {
    let model: PhoneModel

    var body: some View {
        let board = model.board
        let onLine = !board.openJacks.isEmpty
        let busy = onLine || !board.knockingOut.isEmpty || !board.incoming.isEmpty
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                SideKey(title: "BUZZ", caption: "EVERYONE", enabled: onLine, action: model.buzz)
                Spacer()
                TalkKey(model: model)
                Spacer()
                SideKey(title: "HANG UP", caption: "ALL LINES", enabled: busy, action: model.hangUpAll)
            }
            Text(caption(board))
                .font(Fonts.jura(9.5, "SemiBold"))
                .tracking(1.4)
                .foregroundStyle(model.microphoneDenied ? Palette.orangeInk : Palette.mute)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(Palette.plate.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Palette.ink).frame(height: 2) }
    }

    private func caption(_ board: Switchboard) -> String {
        if model.microphoneDenied { return "ALLOW THE MICROPHONE IN SETTINGS → TALKIE" }
        if !board.knockers.isEmpty { return "HOLD TALK TO LET IN AND TALK AT ONCE" }
        if board.openJacks.isEmpty { return "TAP A FRIEND'S JACK TO KNOCK" }
        return "HOLD TO TALK · LET GO TO LISTEN"
    }
}

private struct SideKey: View {
    let title: String
    let caption: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Text(title).frame(width: 92, height: 40)
            }
            .buttonStyle(RelayKeyStyle(height: 3))
            .opacity(enabled ? 1 : 0.45)
            .disabled(!enabled)
            Text(caption)
                .font(Fonts.jura(8, "SemiBold"))
                .tracking(1)
                .foregroundStyle(Palette.mute)
        }
    }
}

/// Hold to talk. While a friend knocks, holding it lets them in and talks at once.
private struct TalkKey: View {
    let model: PhoneModel
    @State private var holding = false

    var body: some View {
        let board = model.board
        let knocking = !board.knockers.isEmpty && board.openJacks.isEmpty
        let lit = holding || board.talking
        ZStack {
            if knocking { Circle().fill(Palette.orangeGlow).frame(width: 118, height: 118) }
            Circle().fill(Palette.ink).frame(width: 98, height: 98).offset(y: 4)
            Circle()
                .fill(lit || knocking ? Palette.orange : Palette.white)
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2))
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1).padding(14).opacity(knocking ? 0 : 1))
                .overlay(
                    Text(knocking ? "LET IN" : "TALK")
                        .font(Fonts.jura(knocking ? 15 : 17, "SemiBold"))
                        .tracking(1.6)
                        .foregroundStyle(Palette.ink)
                )
                .frame(width: 98, height: 98)
                .offset(y: holding ? 4 : 0)
        }
        .frame(width: 118, height: 118)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !holding else { return }
                    holding = true
                    model.askForMicrophone()
                    model.startTalking()
                }
                .onEnded { _ in
                    holding = false
                    model.stopTalking()
                }
        )
        .animation(.easeOut(duration: 0.06), value: holding)
        .accessibilityLabel(knocking ? "Let in" : "Talk")
        .accessibilityHint("Touch and hold to talk")
        .accessibilityAddTraits(.isButton)
    }
}

/// A friend knocking: let them in, or turn them away (they're never told).
struct KnockCard: View {
    let model: PhoneModel
    let jack: Int

    var body: some View {
        let name = model.board.friend(jack)?.name ?? "A FRIEND"
        ZStack(alignment: .bottom) {
            // Dims the board, but taps go through: holding TALK lets them in and talks at once.
            Palette.ink.opacity(0.22).ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("KNOCK KNOCK · JACK \(Switchboard.pad(jack))")
                        .font(Fonts.jura(10, "SemiBold"))
                        .tracking(1.6)
                        .foregroundStyle(Palette.orangeInk)
                    Spacer()
                    Button { model.decline(jack) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 34, height: 30)
                    }
                    .buttonStyle(RelayKeyStyle(fill: Palette.plate, height: 3))
                    .accessibilityLabel("Turn \(name.capitalized) away")
                }
                Text(name)
                    .font(Fonts.jura(40, "Light"))
                    .tracking(1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("wants to talk. Let them in and the line opens; turn them away and they're never told.")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.mute)
                    .fixedSize(horizontal: false, vertical: true)
                Button { model.letIn(jack) } label: {
                    Text("LET IN").frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(RelayKeyStyle(fill: Palette.orange))
            }
            .foregroundStyle(Palette.ink)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.shell)
                    .overlay(alignment: .top) {
                        UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18, style: .continuous)
                            .fill(Palette.orange)
                            .frame(height: 10)
                    }
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.ink, lineWidth: 2))
            .shadow(color: Palette.shadow, radius: 0, x: 5, y: 7)
            .padding(.horizontal, 16)
            .padding(.bottom, 190)
        }
    }
}
