import SwiftUI
import AppKit
import TalkieCore

/// A transparent, screen-sized panel above every app (and the menu bar) that only draws the mic.
/// It ignores the mouse unless the pointer is over the mic, so the desktop underneath keeps working.
final class OverlayPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // Keep the mic out of screen shares and recordings.
        sharingType = .none
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Takes the clicks meant for the mic. Clicking it never activates Talkie or steals focus.
final class MicInputView: NSView {
    let model: BoardModel

    init(model: BoardModel) {
        self.model = model
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        return model.isMicGrabbed || model.micHitTest(p) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        model.micPointerDown(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        model.micPointerDragged(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        model.micPointerUp()
    }
}

@MainActor
final class MicOverlay {
    private let model: BoardModel
    private weak var statusButton: NSStatusBarButton?
    private var panel: OverlayPanel?
    private var input: MicInputView?
    private var screen: NSScreen?
    private var frames = 0

    init(model: BoardModel, statusButton: NSStatusBarButton?) {
        self.model = model
        self.statusButton = statusButton
    }

    func install() {
        rebuild()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Displays changed: a mic that's out stays on its screen if that screen is still there.
                let current = self.screen.flatMap { s in NSScreen.screens.first { Self.id($0) == Self.id(s) } }
                self.rebuild(on: self.model.mic.mode == .hidden ? nil : current)
            }
        }
    }

    /// Displays are told apart by their number; NSScreen objects come and go.
    private static func id(_ screen: NSScreen) -> NSNumber? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    }

    /// The screen whose menu bar the Talkie icon is in right now, going by where it actually is.
    private var iconScreen: NSScreen? {
        guard let f = statusButton?.window?.frame else { return nil }
        return NSScreen.screens.first { $0.frame.contains(CGPoint(x: f.midX, y: f.midY)) }
    }

    /// Puts the overlay on a screen: the one asked for, or the one whose menu bar has the Talkie icon.
    private func rebuild(on target: NSScreen? = nil) {
        panel?.orderOut(nil)
        guard let screen = target ?? iconScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        self.screen = screen
        let p = OverlayPanel(screen: screen)
        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        let host = NSHostingView(rootView: FloatingMicView(model: model))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        let input = MicInputView(model: model)
        input.frame = container.bounds
        input.autoresizingMask = [.width, .height]
        container.addSubview(host)
        container.addSubview(input)
        self.input = input
        p.contentView = container
        p.setFrame(screen.frame, display: false)
        p.orderFrontRegardless()
        panel = p
        updateGeometry()
    }

    /// Where the menu bar ends and where the Talkie icon sits, in the overlay's top-left coordinates.
    ///
    /// With a menu bar on every display, macOS moves the Talkie icon to whichever one you're using.
    /// While the mic is out, its cord only follows the icon within the menu bar of the screen the
    /// mic is on, so it stays where it came down from. While the mic is put away, the overlay moves
    /// to the screen the icon is on, so the next drop comes down where you are. Decided from where
    /// the icon actually is, not from which screen macOS says its window belongs to.
    private func updateGeometry() {
        guard let screen else { return }
        let menuBar = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        let bounds = CGRect(x: 0, y: menuBar, width: screen.frame.width, height: screen.frame.height - menuBar)
        if bounds != model.overlayBounds { model.overlayBounds = bounds }
        guard let window = statusButton?.window else { return }
        let f = window.frame
        let icon = CGPoint(x: f.midX, y: f.midY)
        // This screen's menu bar, a little generous at the top edge.
        let ourMenuBar = CGRect(x: screen.frame.minX, y: screen.frame.maxY - menuBar - 4,
                                width: screen.frame.width, height: menuBar + 8)
        guard ourMenuBar.contains(icon) else {
            if model.mic.mode == .hidden, let there = iconScreen, Self.id(there) != Self.id(screen) {
                rebuild(on: there)
            }
            return
        }
        let anchor = CGPoint(x: f.midX - screen.frame.minX, y: screen.frame.maxY - f.minY - 3)
        if anchor.distance(to: model.anchor) > 0.5 { model.anchor = anchor }
    }

    /// Opens a menu from the mic, at a point in the overlay's top-left coordinates.
    func popUp(_ menu: NSMenu, at point: CGPoint) {
        guard let input else { return }
        menu.popUp(positioning: nil, at: point, in: input)
    }

    /// Called every frame: re-anchor now and then, and decide whether the mouse belongs to the mic.
    func frame() {
        frames += 1
        if frames % 30 == 0 { updateGeometry() }
        guard let panel, let screen else { return }
        let mouse = NSEvent.mouseLocation
        let p = CGPoint(x: mouse.x - screen.frame.minX, y: screen.frame.maxY - mouse.y)
        let wantsMouse = model.isMicGrabbed || model.micHitTest(p)
        if panel.ignoresMouseEvents == wantsMouse { panel.ignoresMouseEvents = !wantsMouse }
    }
}

/// Draws the coiled cord from the menu bar icon and the mic on the end of it.
struct FloatingMicView: View {
    let model: BoardModel

    /// Everything the drawing needs, read in `body` so SwiftUI knows when to redraw.
    private struct Snapshot {
        var mic: FloatingMic
        var size: CGSize
        var anchor: CGPoint
        var board: Switchboard
        var micLevel: Double
        var friendLevel: Double
    }

    var body: some View {
        let snap = Snapshot(mic: model.mic, size: model.micSize, anchor: model.anchor, board: model.board,
                            micLevel: model.micLevel, friendLevel: model.friendLevel)
        TimelineView(.periodic(from: .now, by: 0.18)) { context in
            let blink = Int(context.date.timeIntervalSinceReferenceDate / 0.18) % 2 == 0
            Canvas { ctx, _ in
                Self.draw(&ctx, snap, blinkPhase: blink)
            }
        }
        .allowsHitTesting(false)
    }

    private static func draw(_ ctx: inout GraphicsContext, _ snap: Snapshot, blinkPhase: Bool) {
        let mic = snap.mic
        guard mic.isVisible else { return }
        let size = snap.size
        let board = snap.board

        // The cord leaves the bottom of the mic, so follow its tilt and scale.
        let radians = mic.angle * .pi / 180
        let ex = (MicArt.cordExit.x - MicArt.viewBox.midX) / MicArt.viewBox.width * size.width * mic.scale
        let ey = (MicArt.cordExit.y - MicArt.viewBox.midY) / MicArt.viewBox.height * size.height * mic.scale
        let exit = CGPoint(
            x: mic.position.x + ex * cos(radians) - ey * sin(radians),
            y: mic.position.y + ex * sin(radians) + ey * cos(radians)
        )
        // As thick as the cord stub drawn on the mic itself, so the two join up.
        let k = size.width / MicArt.viewBox.width * min(1, mic.scale * 1.2)
        var coil = Path()
        coil.addLines(Coil.points(from: exit, to: snap.anchor, radius: 5.5 * k, rising: true))
        ctx.stroke(coil, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 5 * k, lineCap: .round, lineJoin: .round))
        ctx.stroke(coil, with: .color(Palette.lampOff), style: StrokeStyle(lineWidth: 2.5 * k, lineCap: .round, lineJoin: .round))

        var m = ctx
        m.translateBy(x: mic.position.x, y: mic.position.y)
        m.rotate(by: .degrees(mic.angle))
        m.scaleBy(x: mic.scale, y: mic.scale)
        m.translateBy(x: -size.width / 2, y: -size.height / 2)
        m.scaleBy(x: size.width / MicArt.viewBox.width, y: size.height / MicArt.viewBox.height)
        m.translateBy(x: -MicArt.viewBox.minX, y: -MicArt.viewBox.minY)
        // One hard shadow for the whole mic, plus an orange glow while your friend is talking.
        m.addFilter(.shadow(color: Palette.shadow, radius: 0, x: 5, y: 9))
        if snap.friendLevel > 0.01 {
            m.addFilter(.shadow(color: Palette.orange.opacity(min(1, snap.friendLevel)), radius: 18 * snap.friendLevel))
        }

        let flags = board.flags
        // Someone knocking takes over the tag and the front key until you answer.
        let knocker = board.knockers.first.flatMap { board.friend($0)?.name }
        let tagLamp: MicArt.TagLamp = knocker != nil ? .blink : flags.rx ? .rx : (flags.tx ? .tx : (board.openJacks.isEmpty ? .blink : .on))
        let state = MicArt.State(
            squeezed: board.talking,
            knocking: knocker != nil,
            effectIndex: board.effect.rawValue,
            level: Int((snap.micLevel * 5).rounded()),
            tag: knocker ?? board.liveNames.joined(separator: "+"),
            tagLabel: tagLabel(board),
            tagLamp: tagLamp,
            blinkPhase: blinkPhase
        )
        m.drawLayer { layer in
            MicArt.draw(&layer, state)
        }
    }

    /// TX and RX can both be on: talking over each other is allowed.
    private static func tagLabel(_ board: Switchboard) -> String {
        let flags = board.flags
        if flags.tx && flags.rx { return "TX·RX" }
        if flags.tx { return "TX" }
        if flags.rx { return "RX" }
        let cords = CordID.allCases.filter { board.patches[$0] != nil }.map(\.label)
        if !cords.isEmpty { return cords.joined(separator: "+") }
        return board.incoming.isEmpty ? "" : "IN"
    }
}
