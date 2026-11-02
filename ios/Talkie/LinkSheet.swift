import SwiftUI
import TalkieCore

/// One account on your Mac and iPhone: type the code Talkie on the Mac shows (Link iPhone…), and
/// this iPhone gets the same code, friends and plan. Friends' knocks ring on both; answer on either.
struct LinkSheet: View {
    let model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("LINK TO YOUR MAC")
                .font(Fonts.jura(24, "Light"))
                .tracking(0.6)
                .padding(.top, 22)
            Text("Use the same code, friends and plan as Talkie on your Mac. Friends' knocks ring on both, and you answer on either.")
                .font(.system(size: 15))
                .foregroundStyle(Palette.mute)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                step("1", "On your Mac, click Talkie in the menu bar and choose Link iPhone…")
                step("2", "Type the code it shows. It works once, for ten minutes.")
            }

            HStack(spacing: 10) {
                TextField("XXXX-XXXX", text: $code)
                    .font(Fonts.lcd(24))
                    .tracking(2)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($typing)
                    .onSubmit { model.link(code) }
                    .onChange(of: code) { _, _ in model.clearLinkProblem() }
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Palette.white))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.ink, lineWidth: 1.5))
                Button { model.link(code) } label: {
                    Text(model.linking ? "…" : "LINK").frame(width: 76, height: 42)
                }
                .buttonStyle(RelayKeyStyle(fill: Palette.orange, height: 3))
                .disabled(model.linking)
            }

            if let problem = model.linkProblem {
                Text(problem)
                    .font(Fonts.jura(10, "SemiBold"))
                    .tracking(1)
                    .foregroundStyle(Palette.orangeInk)
            } else if model.linking {
                Text("LINKING…")
                    .font(Fonts.jura(10, "SemiBold"))
                    .tracking(1)
                    .foregroundStyle(Palette.mute)
            }

            if model.hasOwnCode {
                Text("This iPhone's own code, \(model.board.myCode), stops working. Friends who added it should add your Mac's code instead.")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.mute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.shell.ignoresSafeArea())
        .onAppear { typing = model.demo == nil }
        .onChange(of: model.linked) { _, linked in if linked { dismiss() } }
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(n)
                .font(Fonts.jura(13, "Bold"))
                .frame(width: 16, alignment: .leading)
            Text(text)
                .font(.system(size: 15))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
