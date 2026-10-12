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

/// Relay geometry: rounded shoulders outside, inset panels inside, short raised keys.
enum Radius {
    static let window: CGFloat = 20
    static let panel: CGFloat = 12
    static let inset: CGFloat = 10
    static let key: CGFloat = 5
}

/// A Relay device window: the grey shell with rounded shoulders, a plate title strip with the
/// window keys, and a hard offset shadow. The NSWindow behind it is borderless and transparent;
/// dragging the title strip moves it.
struct DeviceWindow<Content: View>: View {
    static var titleHeight: CGFloat { 38 }
    /// Room around the shell for its outline and shadow.
    static var shadowInsets: EdgeInsets { EdgeInsets(top: 1, leading: 1, bottom: 9, trailing: 7) }

    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.window, style: .continuous)
        VStack(spacing: 0) {
            ZStack {
                WindowDragStrip()
                Text(title)
                    .font(Fonts.jura(11, "SemiBold"))
                    .tracking(1.6)
                    .foregroundStyle(Palette.ink)
                    .allowsHitTesting(false)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.titleHeight)
            .background(Palette.plate)
            .overlay(alignment: .leading) {
                WindowKeys()
                    .frame(width: WindowKeys.size.width, height: WindowKeys.size.height)
                    .padding(.leading, 15)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.ink).frame(height: 1.5) }
            content
        }
        .background(Palette.shell)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.ink, lineWidth: 2))
        .background(shape.fill(Palette.shadow).offset(x: 6, y: 8))
        .padding(Self.shadowInsets)
    }
}

/// An inset panel: plate (or another fill) with a thin ink outline.
struct InsetPanel: ViewModifier {
    var fill: Color = Palette.plate
    var radius: CGFloat = Radius.panel
    var line: CGFloat = 1.5

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(Palette.ink, lineWidth: line))
    }
}

extension View {
    func insetPanel(_ fill: Color = Palette.plate, radius: CGFloat = Radius.panel, line: CGFloat = 1.5) -> some View {
        modifier(InsetPanel(fill: fill, radius: radius, line: line))
    }
}

/// A short raised key: white face, 5pt corners, sitting on a 3pt ink base it drops onto when pressed.
struct RelayKeyStyle: ButtonStyle {
    var fill: Color = Palette.white
    var text: Color = Palette.ink

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
        return configuration.label
            .font(Fonts.jura(11, "SemiBold"))
            .tracking(1)
            .foregroundStyle(text)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(Palette.ink, lineWidth: 1.5))
            .offset(y: configuration.isPressed ? 3 : 0)
            .background(shape.fill(Palette.ink).offset(y: 3))
            .contentShape(shape)
    }
}

/// An on/off switch drawn like the rest of the hardware.
struct RelayToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                configuration.label
                Spacer(minLength: 0)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? Palette.ink : Palette.paper)
                    Capsule().strokeBorder(Palette.ink, lineWidth: 1.2)
                    Circle()
                        .fill(Palette.white)
                        .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1))
                        .frame(width: 14, height: 14)
                        .padding(3)
                }
                .frame(width: 36, height: 20)
                .animation(.easeOut(duration: 0.12), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}
