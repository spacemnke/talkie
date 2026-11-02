import SwiftUI
import UIKit

/// The Relay hardware colours, the same as the Mac app's.
enum Palette {
    static let paper = Color(hex: 0xF1F1EF)
    static let ink = Color(hex: 0x1B1B1B)
    static let shell = Color(hex: 0xD3D4D4)
    static let plate = Color(hex: 0xE7E4DD)
    static let white = Color(hex: 0xFBFBF9)
    static let orange = Color(hex: 0xE0663A)
    static let orangeInk = Color(hex: 0xB8461E)
    static let orangeGlow = Color(hex: 0xE0663A, opacity: 0.35)
    static let key = Color(hex: 0x242424)
    static let lcd = Color(hex: 0x131313)
    static let lcdText = Color(hex: 0xF1EDE3)
    static let lcdDim = Color(hex: 0x3A3A37)
    static let lampOff = Color(hex: 0xB5B6B6)
    static let mute = Color(hex: 0x5F5F5C)
    static let away = Color(hex: 0xA9A9A6)
    static let soft = Color(hex: 0xDCDCDA)
    static let shadow = Color(hex: 0x1B1B1B, opacity: 0.16)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Jura for labels and Doto for the display, bundled with the app (UIAppFonts in Info.plist).
enum Fonts {
    /// Weight is a Jura style name: Light, Regular, Medium, SemiBold or Bold.
    static func jura(_ size: CGFloat, _ weight: String = "Medium") -> Font {
        if UIFont(name: "Jura-\(weight)", size: size) != nil { return .custom("Jura-\(weight)", fixedSize: size) }
        return .system(size: size, weight: systemWeight(weight))
    }

    static func lcd(_ size: CGFloat, bold: Bool = true) -> Font {
        for name in bold ? ["Doto-ExtraBold", "Doto-Bold"] : ["Doto-SemiBold", "Doto-Medium"] where UIFont(name: name, size: size) != nil {
            return .custom(name, fixedSize: size)
        }
        return .system(size: size, weight: bold ? .heavy : .semibold, design: .monospaced)
    }

    private static func systemWeight(_ name: String) -> Font.Weight {
        switch name {
        case "Light": return .light
        case "Regular": return .regular
        case "SemiBold": return .semibold
        case "Bold": return .bold
        default: return .medium
        }
    }
}

/// A raised hardware key: ink outline, a hard shadow under it, pressed down while held.
struct RelayKeyStyle: ButtonStyle {
    var fill: Color = Palette.white
    var height: CGFloat = 4

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Fonts.jura(13, "Bold"))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(Palette.ink)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fill)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.ink, lineWidth: 2))
            )
            .offset(y: configuration.isPressed ? height : 0)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Palette.ink)
                    .offset(y: height)
            )
            .animation(.easeOut(duration: 0.05), value: configuration.isPressed)
    }
}

/// Little taps you feel: a plug seating, a knock, a buzz.
@MainActor
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func thud() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
