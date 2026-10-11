import SwiftUI
import AppKit
import CoreText

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

/// The prototype's palette: light hardware grey, ink outlines, one signal orange.
enum Palette {
    static let paper = Color(hex: 0xF1F1EF)
    static let ink = Color(hex: 0x1B1B1B)
    static let shell = Color(hex: 0xD3D4D4)
    static let plate = Color(hex: 0xE7E4DD)
    static let white = Color(hex: 0xFBFBF9)
    static let orange = Color(hex: 0xE0663A)
    static let orangeGlow = Color(hex: 0xE0663A, opacity: 0.35)
    static let slate = Color(hex: 0x8B96A3)
    static let key = Color(hex: 0x242424)
    static let lcd = Color(hex: 0x131313)
    static let lcdText = Color(hex: 0xF1EDE3)
    static let lcdDim = Color(hex: 0x3A3A37)
    static let grille = Color(hex: 0x76787A)
    static let micGrille = Color(hex: 0x7D858D)
    static let dotRing = Color(hex: 0x4C535A)
    static let pill = Color(hex: 0x9AA1A8)
    static let ledOff = Color(hex: 0x8A9299)
    static let ledRed = Color(hex: 0xD63A26)
    static let ledWhite = Color(hex: 0xF7F7F2)
    static let lampOff = Color(hex: 0xB5B6B6)
    static let plugShadow = Color(hex: 0xA7A8A9)
    static let mute = Color(hex: 0x686865)
    static let away = Color(hex: 0xA9A9A6)
    static let soft = Color(hex: 0xDCDCDA)
    static let shadow = Color(hex: 0x1B1B1B, opacity: 0.16)

    static let orangeNS = NSColor(srgbRed: 0xE0 / 255, green: 0x66 / 255, blue: 0x3A / 255, alpha: 1)
}

/// Jura for labels and Doto for the LCD, bundled with the app. Falls back to system fonts.
enum Fonts {
    static func register() {
        for url in fontFiles() {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Weight is a Jura style name: Light, Regular, Medium, SemiBold or Bold.
    static func jura(_ size: CGFloat, _ weight: String = "Medium") -> Font {
        if let f = NSFont(name: "Jura-\(weight)", size: size) { return Font(f as CTFont) }
        return .system(size: size, weight: systemWeight(weight))
    }

    static func lcd(_ size: CGFloat, bold: Bool = true) -> Font {
        for name in bold ? ["Doto-ExtraBold", "Doto-Bold"] : ["Doto-SemiBold", "Doto-Medium"] {
            if let f = NSFont(name: name, size: size) { return Font(f as CTFont) }
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

    /// Finds the bundled .ttf files whether we run from Xcode, `swift run`, or a packaged Talkie.app.
    private static func fontFiles() -> [URL] {
        let fm = FileManager.default
        var roots: [URL] = []
        if let r = Bundle.main.resourceURL { roots.append(r) }
        if let e = Bundle.main.executableURL?.deletingLastPathComponent() { roots.append(e) }
        for root in roots {
            for name in ["Talkie_Talkie.bundle", "Fonts"] {
                let dir = root.appendingPathComponent(name)
                guard fm.fileExists(atPath: dir.path), let walker = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { continue }
                let found = walker.compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "ttf" }
                if !found.isEmpty { return found }
            }
        }
        return []
    }
}
