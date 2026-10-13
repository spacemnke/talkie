import SwiftUI
import AppKit
import TalkieCore

/// Free vs Pro, side by side, with the way to get Pro. Opens when you reach for something that
/// comes with Pro (a fourth jack, an effect on a call, a knock sound), or from the menu.
struct ProView: View {
    let model: BoardModel

    /// Where Pro is explained, for when the store isn't set up.
    static let pricing = URL(string: "https://switchtalkie.com/#pricing")!

    var body: some View {
        let plan = model.board.plan
        DeviceWindow(title: "TALKIE PRO") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("THE WHOLE BOARD.")
                        .font(Fonts.jura(22, "Light"))
                        .tracking(0.6)
                    Spacer(minLength: 0)
                    Caption(text: plan == .pro ? "YOU'RE ON PRO" : "YOU'RE ON FREE")
                }
                .padding(.top, 24)
                Text("Free keeps three friends a patch away. Pro opens all eight jacks and four cords for calls of five, lifts the time limit and gives you a voice of your own.")
                    .font(Fonts.jura(11, "Regular"))
                    .foregroundStyle(Palette.mute)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                PlanTable(current: plan)
                    .padding(.top, 20)

                if model.practice {
                    PracticePlanRow(model: model)
                        .padding(.top, 14)
                }

                keys(plan)
                    .padding(.top, 18)
                Caption(text: note(plan))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
            .foregroundStyle(Palette.ink)
            .padding(EdgeInsets(top: 0, leading: 32, bottom: 22, trailing: 32))
            .frame(width: 520)
        }
    }

    /// Buy (monthly or yearly), manage what you have, or nothing to do on the practice board.
    @ViewBuilder
    private func keys(_ plan: Plan) -> some View {
        if model.practice {
            WideKey(title: "GET PRO FROM YOUR REAL BOARD", width: 456) {}
                .disabled(true)
        } else if plan == .pro {
            WideKey(title: Checkout.manage == nil ? "YOU HAVE PRO" : "MANAGE YOUR SUBSCRIPTION", width: 456) {
                if let manage = Checkout.manage { NSWorkspace.shared.open(manage) }
            }
            .disabled(Checkout.manage == nil)
        } else if let monthly = Checkout.monthly, let yearly = Checkout.yearly {
            let account = model.account
            HStack(spacing: 10) {
                WideKey(title: "\(Plan.monthly) A MONTH", width: 223) { buy(monthly) }
                WideKey(title: "\(Plan.yearly) A YEAR", width: 223) { buy(yearly) }
            }
            .disabled(account == nil)
        } else {
            WideKey(title: "GET PRO · \(Plan.monthly)/MONTH", width: 456) {
                NSWorkspace.shared.open(Self.pricing)
            }
        }
    }

    private func note(_ plan: Plan) -> String {
        if model.practice { return "THE PRACTICE BOARD IS FOR TRYING · NOTHING IS CHARGED" }
        if plan == .pro { return Checkout.manage == nil ? "THANKS FOR BEING ON PRO" : "RECEIPTS, CARD AND CANCELLING ARE WITH LEMON SQUEEZY" }
        if Checkout.monthly == nil { return "PAYMENTS OPEN SOON · EVERYTHING ELSE WORKS ON FREE" }
        if model.account == nil { return "WAITING FOR THE OPERATOR" }
        return "A YEAR COMES TO $3 A MONTH · PRO SWITCHES ON BY ITSELF"
    }

    /// Opens the checkout in your browser, tagged with your account so Pro lands on your board.
    private func buy(_ base: URL) {
        guard let account = model.account else { return }
        NSWorkspace.shared.open(Checkout.link(base, account: account, code: model.board.myCode))
    }
}

/// The Free vs Pro table. Your plan's column has the orange dot.
private struct PlanTable: View {
    let current: Plan

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer().frame(width: 150)
                heading(.free)
                heading(.pro)
            }
            .padding(.bottom, 10)
            ForEach(PlanFeature.all, id: \.name) { feature in
                Divider().overlay(Palette.soft)
                HStack(alignment: .top, spacing: 10) {
                    Text(feature.name.uppercased())
                        .font(Fonts.jura(9, "SemiBold"))
                        .tracking(0.8)
                        .frame(width: 150, alignment: .leading)
                    cell(feature.free, dim: feature.free == "—")
                    cell(feature.pro, strong: true)
                }
                .padding(.vertical, 9)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 6, trailing: 16))
        .insetPanel(Palette.paper, radius: 14)
    }

    private func heading(_ plan: Plan) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(plan == current ? Palette.orange : Color.clear)
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1))
                .frame(width: 8, height: 8)
            Text(plan.title).font(Fonts.jura(11, "SemiBold")).tracking(1.2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(plan == current ? "\(plan.title), your plan" : plan.title)
    }

    private func cell(_ text: String, dim: Bool = false, strong: Bool = false) -> some View {
        Text(text)
            .font(Fonts.jura(10, strong ? "SemiBold" : "Regular"))
            .foregroundStyle(dim ? Palette.away : Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// On the practice board you can switch plans to see both.
private struct PracticePlanRow: View {
    let model: BoardModel

    var body: some View {
        HStack(spacing: 10) {
            Caption(text: "PRACTICE BOARD · TRY")
            Spacer(minLength: 0)
            ForEach(Plan.allCases, id: \.self) { plan in
                let on = model.board.plan == plan
                Button { model.setPracticePlan(plan) } label: {
                    Text(plan.title).frame(width: 80, height: 30)
                }
                    .buttonStyle(RelayKeyStyle(fill: on ? Palette.plate : Palette.white))
                    .overlay(alignment: .topTrailing) {
                        if on { Circle().fill(Palette.orange).frame(width: 6, height: 6).padding(5) }
                    }
                    .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// A small "PRO" tag for things that come with Pro.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(Fonts.jura(8, "Bold"))
            .tracking(1)
            .foregroundStyle(Palette.white)
            .padding(.horizontal, 6)
            .frame(height: 15)
            .background(Capsule().fill(Palette.orange))
            .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 1))
            .accessibilityLabel("Pro")
    }
}
