import SwiftUI
import AppKit

/// A device window: borderless and see-through, so its visible edge is the rounded shell that
/// `DeviceWindow` draws. The title strip moves it and carries Talkie's own window keys, which
/// take their clicks themselves rather than relying on a transparent title bar.
final class DeviceNSWindow: NSWindow {
    /// Called after the window closes, by its window key or by Talkie.
    var onClose: (() -> Void)?

    init(contentRect: NSRect) {
        // Miniaturizable, so the minimise key works on a window without a title bar.
        super.init(contentRect: contentRect, styleMask: [.borderless, .miniaturizable], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Borderless windows can't take the keyboard unless they say so.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func close() {
        super.close()
        onClose?()
    }
}

// MARK: Title strip

/// Behind the title strip: pressing anywhere on it drags the window.
struct WindowDragStrip: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragView { WindowDragView() }
    func updateNSView(_ nsView: WindowDragView, context: Context) {}
}

final class WindowDragView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// Close, minimise and zoom, drawn like the Relay drawings: hollow ink circles on the title strip.
struct WindowKeys: NSViewRepresentable {
    static var size: CGSize { WindowKeysView.size }

    func makeNSView(context: Context) -> WindowKeysView { WindowKeysView() }
    func updateNSView(_ nsView: WindowKeysView, context: Context) {}
}

final class WindowKeysView: NSView {
    static let diameter: CGFloat = 12
    static let gap: CGFloat = 8
    static var size: CGSize { CGSize(width: diameter * 3 + gap * 2, height: diameter) }

    private let keys = [WindowKeyView(kind: .close), WindowKeyView(kind: .minimize), WindowKeyView(kind: .zoom)]

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        for key in keys { addSubview(key) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        let d = Self.diameter
        for (i, key) in keys.enumerated() {
            key.frame = NSRect(x: CGFloat(i) * (d + Self.gap), y: (bounds.height - d) / 2, width: d, height: d)
        }
    }

    // Like the system's own: the glyphs show on all of them while the pointer is over any.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { keys.forEach { $0.showsGlyph = true } }
    override func mouseExited(with event: NSEvent) { keys.forEach { $0.showsGlyph = false } }

    /// The gaps between the keys still drag the window.
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

final class WindowKeyView: NSView {
    enum Kind { case close, minimize, zoom }

    let kind: Kind
    var showsGlyph = false {
        didSet { if showsGlyph != oldValue { needsDisplay = true } }
    }
    private var pressed = false {
        didSet { if pressed != oldValue { needsDisplay = true } }
    }
    /// The devices don't resize, so zoom is drawn but off, as on any fixed-size Mac window.
    private var isEnabled: Bool { kind != .zoom }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    // Works on the first click, even when Talkie isn't the active app.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        pressed = isEnabled
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = bounds.insetBy(dx: -3, dy: -3).contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard pressed else { return }
        pressed = false
        perform()
    }

    private func perform() {
        switch kind {
        case .close: window?.close()
        case .minimize: window?.miniaturize(nil)
        case .zoom: break
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let ink = NSColor(Palette.ink)
        let face = NSColor(Palette.plate)
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.75, dy: 0.75))
        circle.lineWidth = 1.5
        (pressed ? ink : face).setFill()
        circle.fill()
        (isEnabled ? ink : NSColor(Palette.mute)).setStroke()
        circle.stroke()

        guard showsGlyph, isEnabled else { return }
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        let r: CGFloat = 2.6
        let glyph = NSBezierPath()
        glyph.lineWidth = 1.3
        glyph.lineCapStyle = .round
        switch kind {
        case .close:
            glyph.move(to: NSPoint(x: c.x - r, y: c.y - r))
            glyph.line(to: NSPoint(x: c.x + r, y: c.y + r))
            glyph.move(to: NSPoint(x: c.x - r, y: c.y + r))
            glyph.line(to: NSPoint(x: c.x + r, y: c.y - r))
        case .minimize:
            glyph.move(to: NSPoint(x: c.x - r - 0.5, y: c.y))
            glyph.line(to: NSPoint(x: c.x + r + 0.5, y: c.y))
        case .zoom:
            break
        }
        (pressed ? face : ink).setStroke()
        glyph.stroke()
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    override func accessibilitySubrole() -> NSAccessibility.Subrole? {
        switch kind {
        case .close: return .closeButton
        case .minimize: return .minimizeButton
        case .zoom: return .zoomButton
        }
    }

    override func accessibilityLabel() -> String? {
        switch kind {
        case .close: return "Close"
        case .minimize: return "Minimize"
        case .zoom: return "Zoom"
        }
    }

    override func isAccessibilityEnabled() -> Bool { isEnabled }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        perform()
        return true
    }
}
