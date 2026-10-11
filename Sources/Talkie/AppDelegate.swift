import SwiftUI
import AppKit
import TalkieCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = BoardModel()
    private lazy var cards = CardFileModel(boardModel: model)
    private var statusItem: NSStatusItem?
    private var boardWindow: NSWindow?
    private var cardWindow: NSWindow?
    private var overlay: MicOverlay?
    private var hotKey: HotKey?
    private var keyMonitor: Any?
    private var wheelMonitor: Any?
    private var iconLook: StatusIcon.Look?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Talkie lives in the menu bar; no Dock icon.
        NSApp.setActivationPolicy(.accessory)
        Fonts.register()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusIcon.image(.live)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        let overlay = MicOverlay(model: model, statusButton: item.button)
        overlay.install()
        self.overlay = overlay

        model.onFrame = { [weak self] in
            self?.overlay?.frame()
            self?.updateStatusIcon()
        }
        model.onOpenCardFile = { [weak self] forFreeJack in
            guard let self else { return }
            self.showCardFile()
            guard forFreeJack else { return }
            // Once the window is up, so the code field can take the cursor.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.cards.greetFreeJack() }
            }
        }
        model.start()
        showBoard()

        // Hold ⌥Space to talk from any app.
        let hotKey = HotKey()
        hotKey.onPress = { [weak self] in MainActor.assumeIsolated { self?.model.startTalking() } }
        hotKey.onRelease = { [weak self] in MainActor.assumeIsolated { self?.model.stopTalking() } }
        self.hotKey = hotKey

        // Space to talk and F for effects while the board window is in front.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            let key = KeyPress(event)
            let consumed = MainActor.assumeIsolated { self?.handleKey(key) ?? false }
            return consumed ? nil : event
        }

        // Scrolling over the Rolodex turns it.
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let wheel = Wheel(event)
            MainActor.assumeIsolated { self?.handleWheel(wheel) }
            return event
        }

        // The example board starts with a line open to Maya, so bring the mic down once everything is placed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.board.isLive else { return }
                self.model.dropMic()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Board window

    @objc func showBoard() {
        if boardWindow == nil {
            let window = makeDeviceWindow(title: "Talkie", content: BoardView(model: model))
            window.center()
            boardWindow = window
        }
        boardWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: Card file window

    @objc func showCardFile() {
        if cardWindow == nil {
            let window = makeDeviceWindow(title: "Card File", content: CardFileView(model: cards))
            place(window, beside: boardWindow)
            cardWindow = window
        }
        cardWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// To the right of the switchboard (or its left) when there's room, otherwise centred.
    private func place(_ window: NSWindow, beside board: NSWindow?) {
        guard let board, board.isVisible, let screen = board.screen ?? NSScreen.main else {
            window.center()
            return
        }
        let size = window.frame.size
        let visible = screen.visibleFrame
        var origin = NSPoint(x: board.frame.maxX + 16, y: board.frame.maxY - size.height)
        if origin.x + size.width > visible.maxX { origin.x = board.frame.minX - 16 - size.width }
        guard origin.x >= visible.minX else {
            window.center()
            return
        }
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        window.setFrameOrigin(origin)
    }

    /// The parts of a scroll event we need, as plain values.
    private struct Wheel: Sendable {
        var windowNumber: Int
        var location: CGPoint
        var deltaY: CGFloat

        init(_ event: NSEvent) {
            windowNumber = event.windowNumber
            location = event.locationInWindow
            deltaY = event.scrollingDeltaY
        }
    }

    private func handleWheel(_ wheel: Wheel) {
        guard let window = cardWindow, wheel.windowNumber == window.windowNumber, let content = window.contentView else { return }
        let p = content.convert(wheel.location, from: nil)
        let y = content.isFlipped ? p.y : content.bounds.height - p.y
        cards.wheel(at: CGPoint(x: p.x, y: y), deltaY: wheel.deltaY)
    }

    /// A transparent window whose visible edge is the device's own rounded shell (drawn by
    /// DeviceWindow). The real traffic lights sit on its title strip.
    private func makeDeviceWindow<Content: View>(title: String, content: Content) -> NSWindow {
        let host = NSHostingView(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // An empty compact toolbar makes the title bar tall enough to centre the traffic lights on the strip.
        window.toolbar = NSToolbar(identifier: "device")
        window.toolbarStyle = .unifiedCompact
        window.titlebarSeparatorStyle = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.contentView = host
        window.isReleasedWhenClosed = false
        return window
    }

    private func toggleBoard() {
        if let w = boardWindow, w.isVisible, NSApp.isActive {
            w.orderOut(nil)
        } else {
            showBoard()
        }
    }

    /// The parts of a key event we need, as plain values.
    private struct KeyPress: Sendable {
        var windowNumber: Int
        var keyCode: UInt16
        var isDown: Bool
        var isRepeat: Bool
        var plain: Bool
        var character: String

        init(_ event: NSEvent) {
            windowNumber = event.windowNumber
            keyCode = event.keyCode
            isDown = event.type == .keyDown
            isRepeat = isDown && event.isARepeat
            plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            character = event.charactersIgnoringModifiers?.lowercased() ?? ""
        }
    }

    /// Returns true when the key was used.
    private func handleKey(_ key: KeyPress) -> Bool {
        guard let boardWindow, key.windowNumber == boardWindow.windowNumber else { return false }
        if key.keyCode == 49 { // space
            if key.isDown {
                if !key.isRepeat { model.startTalking() }
            } else {
                model.stopTalking()
            }
            return true
        }
        if key.isDown, key.plain, key.character == "f" {
            model.cycleEffect()
            return true
        }
        return false
    }

    // MARK: Menu bar

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else if model.board.isLive || model.mic.isVisible {
            model.toggleMic()
        } else {
            toggleBoard()
        }
    }

    private func updateStatusIcon() {
        let board = model.board
        let look: StatusIcon.Look
        if board.doNotDisturb && !board.isLive {
            look = .doNotDisturb
        } else if !board.openJacks.isEmpty {
            look = .live
        } else if board.isLive {
            look = Int(model.now / 0.36) % 2 == 0 ? .live : .dim
        } else {
            look = .idle
        }
        if look != iconLook {
            iconLook = look
            statusItem?.button?.image = StatusIcon.image(look)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        add(menu, "Open Switchboard", #selector(showBoard))
        add(menu, "Card File", #selector(showCardFile))
        add(menu, model.mic.isVisible ? "Put the Mic Away" : "Bring the Mic Out", #selector(toggleMicItem))
        add(menu, "Do Not Disturb", #selector(toggleDoNotDisturb)).state = model.board.doNotDisturb ? .on : .off
        add(menu, "Next Effect (\(model.board.effect.next.title.capitalized))", #selector(nextEffect))
        menu.addItem(.separator())

        // Pretend to be a friend on the board: patch in, talk, or switch do not disturb.
        let simulate = NSMenuItem(title: "Simulate", action: nil, keyEquivalent: "")
        let friends = NSMenu()
        for (jack, friend) in model.board.friends.enumerated() {
            guard let friend else { continue }
            let item = NSMenuItem(title: friend.name.capitalized, action: nil, keyEquivalent: "")
            let actions = NSMenu()
            add(actions, "Patches In", #selector(simulatePatchIn(_:))).tag = jack
            add(actions, "Talks", #selector(simulateTalk(_:))).tag = jack
            let dnd = add(actions, "Do Not Disturb", #selector(simulateDoNotDisturb(_:)))
            dnd.tag = jack
            dnd.state = friend.doNotDisturb ? .on : .off
            item.submenu = actions
            friends.addItem(item)
        }
        simulate.submenu = friends
        menu.addItem(simulate)

        menu.addItem(.separator())
        add(menu, "Quit Talkie", #selector(quit))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func toggleMicItem() { model.toggleMic() }
    @objc private func toggleDoNotDisturb() { model.toggleDoNotDisturb() }
    @objc private func nextEffect() { model.cycleEffect() }
    @objc private func simulatePatchIn(_ sender: NSMenuItem) { model.simulateIncoming(sender.tag) }
    @objc private func simulateTalk(_ sender: NSMenuItem) { model.simulateFriendTalks(sender.tag) }
    @objc private func simulateDoNotDisturb(_ sender: NSMenuItem) {
        model.simulateFriendDoNotDisturb(sender.tag, !(model.board.friend(sender.tag)?.doNotDisturb ?? false))
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
