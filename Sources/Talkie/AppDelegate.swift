import SwiftUI
import AppKit
import TalkieCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = BoardModel()
    private var statusItem: NSStatusItem?
    private var boardWindow: NSWindow?
    private var overlay: MicOverlay?
    private var hotKey: HotKey?
    private var keyMonitor: Any?
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
            let host = NSHostingView(rootView: BoardView(model: model))
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: host.fittingSize),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Talkie"
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.backgroundColor = NSColor(Palette.shell)
            window.center()
            boardWindow = window
        }
        boardWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
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
        add(menu, model.mic.isVisible ? "Put the Mic Away" : "Bring the Mic Out", #selector(toggleMicItem))
        add(menu, "Do Not Disturb", #selector(toggleDoNotDisturb)).state = model.board.doNotDisturb ? .on : .off
        add(menu, "Next Effect (\(model.board.effect.next.title.capitalized))", #selector(nextEffect))
        menu.addItem(.separator())

        let simulate = NSMenuItem(title: "Simulate", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        add(sub, "Otto Patches In", #selector(simulateOtto))
        add(sub, "Maya Talks", #selector(simulateMayaTalks))
        let rubyDND = model.board.friend(3)?.doNotDisturb ?? false
        add(sub, rubyDND ? "Ruby Turns Off Do Not Disturb" : "Ruby Turns On Do Not Disturb", #selector(simulateRubyDND))
        simulate.submenu = sub
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
    @objc private func simulateOtto() { model.simulateIncoming(1) }
    @objc private func simulateMayaTalks() { model.simulateFriendTalks(0) }
    @objc private func simulateRubyDND() {
        model.simulateFriendDoNotDisturb(3, !(model.board.friend(3)?.doNotDisturb ?? false))
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
