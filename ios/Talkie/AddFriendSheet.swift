import SwiftUI
import UIKit
import TalkieCore

/// Your code to send, and a friend's code to add. Your knock only rings for someone who has you
/// on their board, so you both add each other.
struct AddFriendSheet: View {
    @Bindable var model: PhoneModel
    @FocusState private var typing: Bool
    @State private var copied = false
    @State private var linkingToMac = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("ADD A FRIEND")
                .font(Fonts.jura(24, "Light"))
                .tracking(0.6)
                .padding(.top, 22)

            VStack(alignment: .leading, spacing: 8) {
                label("YOUR CODE")
                HStack(spacing: 10) {
                    Text(model.board.myCode)
                        .font(Fonts.lcd(26))
                        .tracking(2)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button {
                        UIPasteboard.general.string = model.board.myCode
                        copied = true
                    } label: {
                        Text(copied ? "COPIED" : "COPY").frame(width: 70, height: 34)
                    }
                    .buttonStyle(RelayKeyStyle(height: 3))
                    ShareLink(item: model.shareText) {
                        Text("SEND").frame(width: 62, height: 34)
                    }
                    .buttonStyle(RelayKeyStyle(fill: Palette.orange, height: 3))
                }
                if !model.linked {
                    Button { linkingToMac = true } label: {
                        Text("SAME CODE AS YOUR MAC? LINK THIS IPHONE →")
                            .font(Fonts.jura(10, "SemiBold"))
                            .tracking(1.2)
                            .foregroundStyle(Palette.orangeInk)
                    }
                    .buttonStyle(.plain)
                }
            }

            Rectangle().fill(Palette.ink).frame(height: 1.5)

            VStack(alignment: .leading, spacing: 8) {
                label("THEIR CODE")
                HStack(spacing: 10) {
                    TextField("TLK-····", text: $model.codeText)
                        .font(Fonts.lcd(24))
                        .tracking(2)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($typing)
                        .onSubmit(model.checkCode)
                        .padding(.horizontal, 12)
                        .frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.white))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.ink, lineWidth: 1.5))
                    Button(action: model.checkCode) {
                        Text(model.checking ? "…" : "CHECK").frame(width: 84, height: 42)
                    }
                    .buttonStyle(RelayKeyStyle(fill: Palette.orange, height: 3))
                    .disabled(model.checking)
                }
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    let r = model.board.readout(now: model.now)
                    Text("\(r.big) · \(r.sub)".replacingOccurrences(of: "TYPE OR PASTE", with: "ENTER"))
                        .font(Fonts.jura(10, "SemiBold"))
                        .tracking(1)
                        .foregroundStyle(Palette.orangeInk)
                        .lineLimit(2)
                }
            }

            Text("Talkie on iPhone and Mac can call each other. Your knock rings only for someone who has you on their board, so add each other.")
                .font(.system(size: 14))
                .foregroundStyle(Palette.mute)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.shell.ignoresSafeArea())
        .onAppear { typing = model.demo == nil }
        .sheet(isPresented: $linkingToMac) {
            LinkSheet(model: model)
                .presentationDetents([.large])
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Fonts.jura(10, "SemiBold"))
            .tracking(1.6)
            .foregroundStyle(Palette.mute)
    }
}

/// First run: the name friends will see, then Talkie gets you a code.
struct WelcomeView: View {
    let model: PhoneModel
    @State private var name = ""
    @State private var linkingToMac = false
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 20)
            SmileyMark().frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 6) {
                Text("TALKIE")
                    .font(Fonts.jura(52, "Light"))
                    .tracking(1)
                Text("A WALKIE-TALKIE FOR YOUR FRIENDS")
                    .font(Fonts.jura(11, "SemiBold"))
                    .tracking(1.8)
                    .foregroundStyle(Palette.orangeInk)
            }
            Text("Put friends on your switchboard by their code. Tap a jack to knock; when they let you in, hold TALK. Works with Talkie on the Mac too.")
                .font(.system(size: 16))
                .foregroundStyle(Palette.mute)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Text("YOUR NAME, AS FRIENDS SEE IT")
                    .font(Fonts.jura(10, "SemiBold"))
                    .tracking(1.6)
                    .foregroundStyle(Palette.mute)
                TextField("NAME", text: $name)
                    .font(Fonts.jura(22, "SemiBold"))
                    .tracking(1)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($typing)
                    .onSubmit { model.setName(name) }
                    .padding(.horizontal, 12)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Palette.white))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.ink, lineWidth: 1.5))
            }
            Button { model.setName(name) } label: {
                Text("GET MY CODE").frame(maxWidth: .infinity).frame(height: 50)
            }
            .buttonStyle(RelayKeyStyle(fill: Palette.orange))
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            Button { linkingToMac = true } label: {
                Text("ALREADY ON TALKIE ON YOUR MAC? LINK THIS IPHONE →")
                    .font(Fonts.jura(10.5, "SemiBold"))
                    .tracking(1.2)
                    .foregroundStyle(Palette.orangeInk)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 20)
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Palette.shell.ignoresSafeArea())
        .sheet(isPresented: $linkingToMac) {
            LinkSheet(model: model)
                .presentationDetents([.large])
        }
        // The simulator's screenshot of linking.
        .onAppear { if model.demo == "link" { linkingToMac = true } }
    }
}
