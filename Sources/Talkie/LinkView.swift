import SwiftUI
import TalkieCore

/// One account on your Mac and iPhone: a code for Talkie on the iPhone to type (on its first
/// screen, or from Add a Friend), after which it has this Mac's code, friends and plan.
struct LinkView: View {
    let model: BoardModel
    @State private var code: String?
    @State private var problem: String?
    @State private var expires = Date()

    var body: some View {
        DeviceWindow(title: "LINK IPHONE") {
            VStack(alignment: .leading, spacing: 0) {
                Text("ONE CODE, TWO DEVICES.")
                    .font(Fonts.jura(20, "Light"))
                    .tracking(0.6)
                    .padding(.top, 24)
                Text("Your iPhone gets this Mac's code, friends and plan. Friends' knocks ring on both, and you answer on either.")
                    .font(Fonts.jura(11, "Regular"))
                    .foregroundStyle(Palette.mute)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = expires.timeIntervalSince(context.date)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(code.map(Self.split) ?? "····-····")
                            .font(Fonts.lcd(34))
                            .tracking(4)
                            .foregroundStyle(code == nil ? Palette.lcdDim : Palette.lcdText)
                            .textSelection(.enabled)
                        Text(status(left: left))
                            .font(Fonts.lcd(12, bold: false))
                            .tracking(0.6)
                            .foregroundStyle(Palette.orange)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.lcd))
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Palette.key))
                }
                .padding(.top, 18)

                VStack(alignment: .leading, spacing: 8) {
                    step("1", "Install Talkie on your iPhone.")
                    step("2", "Choose LINK THIS IPHONE on its first screen (or in Add a Friend).")
                    step("3", "Type this code. It works once, for ten minutes.")
                }
                .padding(.top, 18)

                WideKey(title: "NEW CODE", width: 304) { Task { await fetch() } }
                    .padding(.top, 20)
            }
            .foregroundStyle(Palette.ink)
            .padding(EdgeInsets(top: 0, leading: 28, bottom: 22, trailing: 28))
            .frame(width: 360)
        }
        .task { await fetch() }
    }

    private func status(left: TimeInterval) -> String {
        if let problem { return problem }
        guard code != nil else { return "ASKING THE OPERATOR…" }
        if left <= 0 { return "OUT OF TIME · MAKE A NEW ONE" }
        return "GOOD FOR \(Switchboard.clock(left)) · ONCE"
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(n)
                .font(Fonts.jura(11, "Bold"))
                .frame(width: 12, alignment: .leading)
            Text(text)
                .font(Fonts.jura(11, "Regular"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fetch() async {
        code = nil
        problem = nil
        guard let online = model.online, !model.practice else {
            problem = "SWITCH TO YOUR REAL BOARD FIRST"
            return
        }
        do {
            code = try await online.startLink()
            expires = Date().addingTimeInterval(600)
        } catch {
            problem = Operator.describe(error)
        }
    }

    /// "ABCD-EFGH": easier to read across.
    static func split(_ code: String) -> String {
        code.count == 8 ? "\(code.prefix(4))-\(code.suffix(4))" : code
    }
}
