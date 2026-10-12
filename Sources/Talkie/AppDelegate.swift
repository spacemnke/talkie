import SwiftUI
import AppKit
import TalkieCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = BoardModel()
    private var statusItem: NSStatusItem?
    private var boardWindow: DeviceNSWindow?
    private var effectsWindow: DeviceNSWindow?
    private var settingsWindow: DeviceNSWindow?
    private var welcomeWindow: DeviceNSWindow?
    private static let finishedWelcome = "didFinishFirstRun"
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
        // The mic's settings key: mute, do not disturb, effects and hanging up, right where you talk.
        model.onMicMenu = { [weak self] point in self?.showMicMenu(at: point) }
        // CI opens the packaged app once to prove it starts (its frameworks load), then quits.
        if ProcessInfo.processInfo.environment["TALKIE_SMOKE_TEST"] != nil {
            print("Talkie started")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
            return
        }
        model.start()
        let firstRun = !UserDefaults.standard.bool(forKey: Self.finishedWelcome)
        if firstRun { showWelcome() } else { showBoard() }

        // Hold ⌥Space to talk from any app.
        let hotKey = HotKey()
        hotKey.onPress = { [weak self] in MainActor.assumeIsolated { self?.model.startTalking() } }
        hotKey.onRelease = { [weak self] in MainActor.assumeIsolated { self?.model.stopTalking() } }
        self.hotKey = hotKey

        // Space to talk and F for effects while the board window is in front, plus ⌘W and ⌘, anywhere.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            let key = KeyPress(event)
            let consumed = MainActor.assumeIsolated { self?.handleKey(key) ?? false }
            return consumed ? nil : event
        }

        // The example board starts with a line open to Maya, so bring the mic down once everything is placed.
        if !firstRun { dropMicSoon() }
    }

    private func dropMicSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.board.isLive else { return }
                self.model.dropMic()
            }
        }
    }

    // MARK: Welcome, open line, effects, settings

    @objc func showWelcome() {
        if welcomeWindow == nil {
            let view = FirstRunView(model: model) { [weak self] in
                MainActor.assumeIsolated { self?.finishWelcome() }
            }
            let window = makeDeviceWindow(title: "Welcome to Talkie", content: view)
            // Closed before the last step: show the board anyway. Welcome comes back next launch.
            window.onClose = { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.welcomeWindow != nil else { return }
                    self.welcomeWindow = nil
                    self.showBoard()
                }
            }
            window.center()
            welcomeWindow = window
        }
        welcomeWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func finishWelcome() {
        let first = !UserDefaults.standard.bool(forKey: Self.finishedWelcome)
        UserDefaults.standard.set(true, forKey: Self.finishedWelcome)
        let window = welcomeWindow
        welcomeWindow = nil
        window?.close()
        showBoard()
        if first { dropMicSoon() }
    }

    // MARK: The mic's menu

    /// Everything about the line, from the mic's settings key: who's knocking, private mute for each
    /// person on the line, do not disturb, the voice effect, and hanging up.
    private func showMicMenu(at point: CGPoint) {
        let board = model.board
        let menu = NSMenu()
        func item(_ title: String, on: Bool = false, _ action: @escaping @MainActor () -> Void) {
            let item = ClosureMenuItem(title: title) { MainActor.assumeIsolated { action() } }
            item.state = on ? .on : .off
            menu.addItem(item)
        }
        func name(_ jack: Int) -> String { board.friend(jack)?.name.capitalized ?? "Them" }

        for jack in board.knockers {
            item("Let \(name(jack)) In") { [weak self] in self?.model.letIn(jack) }
            item("Decline \(name(jack))") { [weak self] in self?.model.decline(jack) }
        }
        if !board.knockers.isEmpty { menu.addItem(.separator()) }

        for jack in board.openJacks {
            let muted = board.isMuted(jack)
            item("Mute \(name(jack))", on: muted) { [weak self] in self?.model.setMuted(jack, !muted) }
        }
        item("Do Not Disturb", on: board.doNotDisturb) { [weak self] in self?.model.toggleDoNotDisturb() }
        let effects = NSMenu()
        for effect in Effect.allCases {
            let e = ClosureMenuItem(title: effect.title.capitalized) { [weak self] in
                MainActor.assumeIsolated { self?.model.setEffect(effect) }
            }
            e.state = board.effect == effect ? .on : .off
            effects.addItem(e)
        }
        let effectItem = NSMenuItem(title: "Voice Effect", action: nil, keyEquivalent: "")
        effectItem.submenu = effects
        menu.addItem(effectItem)
        menu.addItem(.separator())

        if board.isLive || !board.knockingOut.isEmpty {
            item("Hang Up") { [weak self] in self?.model.hangUpAll() }
        }
        item("Put the Mic Away") { [weak self] in self?.model.putMicAway() }
        item("Open Switchboard") { [weak self] in self?.showBoard() }
        item("Settings…") { [weak self] in self?.showSettings() }
        overlay?.popUp(menu, at: point)
    }

    @objc func showEffects() {
        if effectsWindow == nil {
            let window = makeDeviceWindow(title: "Voice Effects", content: EffectsView(model: model))
            placeUnderMenuBarIcon(window)
            effectsWindow = window
        }
        effectsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = makeDeviceWindow(title: "Settings", content: SettingsView(model: model))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Just under the Talkie icon in the menu bar, kept on screen.
    private func placeUnderMenuBarIcon(_ window: NSWindow) {
        guard let iconWindow = statusItem?.button?.window, let screen = iconWindow.screen ?? NSScreen.main else {
            window.center()
            return
        }
        let size = window.frame.size
        let visible = screen.visibleFrame
        var origin = NSPoint(x: iconWindow.frame.midX - size.width / 2, y: iconWindow.frame.minY - size.height - 6)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = max(origin.y, visible.minY + 8)
        window.setFrameOrigin(origin)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Signs off first, so friends see you go at once. Never waits more than two seconds.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let online = model.online else { return .terminateNow }
        Task {
            await online.signOff(timeout: 2)
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

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

    /// Opens the board ready for a friend's code.
    @objc func addFriend() {
        showBoard()
        model.startAdding()
    }

    /// A borderless window whose visible edge is the device's own rounded shell, drawn by
    /// DeviceWindow along with its title strip and window keys.
    private func makeDeviceWindow<Content: View>(title: String, content: Content) -> DeviceNSWindow {
        let host = NSHostingView(rootView: content)
        let window = DeviceNSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize))
        window.title = title
        window.contentView = host
        return window
    }

    /// True while a text field has the keyboard.
    private var isTyping: Bool {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        return editor.isEditable
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
        var command: Bool
        var character: String

        init(_ event: NSEvent) {
            windowNumber = event.windowNumber
            keyCode = event.keyCode
            isDown = event.type == .keyDown
            isRepeat = isDown && event.isARepeat
            plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            command = event.modifierFlags.intersection([.command, .control, .option]) == .command
            character = event.charactersIgnoringModifiers?.lowercased() ?? ""
        }
    }

    /// Returns true when the key was used.
    private func handleKey(_ key: KeyPress) -> Bool {
        if key.isDown, key.command {
            switch key.character {
            case ",":
                // ⌘, opens Talkie's settings from any of its windows.
                showSettings()
                return true
            case "w":
                // ⌘W closes the window in front, as its close key does.
                guard let window = NSApp.keyWindow as? DeviceNSWindow else { return false }
                window.close()
                return true
            case "x", "c", "v", "a":
                // Talkie has no menu bar, so send cut, copy, paste and select all to the text field ourselves.
                let actions = [
                    "x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)),
                    "v": #selector(NSText.paste(_:)), "a": #selector(NSText.selectAll(_:))
                ]
                guard isTyping, let action = actions[key.character] else { return false }
                return NSApp.sendAction(action, to: nil, from: nil)
            default:
                break
            }
        }
        guard let boardWindow, key.windowNumber == boardWindow.windowNumber else { return false }
        // Space and F are just letters while you type a code.
        if isTyping { return false }
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
        } else if model.board.wantsMic || model.mic.isVisible {
            model.toggleMic()
        } else {
            toggleBoard()
        }
    }

    private func updateStatusIcon() {
        let board = model.board
        let look: StatusIcon.Look
        if !board.knocks.isEmpty {
            // Someone's knocking: blink quickly until you answer.
            look = Int(model.now / 0.22) % 2 == 0 ? .live : .dim
        } else if board.doNotDisturb && !board.isLive {
            look = .doNotDisturb
        } else if !board.openJacks.isEmpty {
            look = .live
        } else if !board.knockingOut.isEmpty {
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
        // Where you are: online with your code, or on the practice board.
        let whereabouts = NSMenuItem(title: whereabouts(), action: nil, keyEquivalent: "")
        whereabouts.isEnabled = false
        menu.addItem(whereabouts)
        menu.addItem(.separator())
        add(menu, "Open Switchboard", #selector(showBoard))
        add(menu, "Add a Friend…", #selector(addFriend))
        add(menu, "Voice Effects…", #selector(showEffects))
        add(menu, model.mic.isVisible ? "Put the Mic Away" : "Bring the Mic Out", #selector(toggleMicItem))
        add(menu, "Do Not Disturb", #selector(toggleDoNotDisturb)).state = model.board.doNotDisturb ? .on : .off
        add(menu, "Next Effect (\(model.board.effect.next.title.capitalized))", #selector(nextEffect))
        menu.addItem(.separator())
        add(menu, "Practice Board", #selector(togglePractice)).state = model.practice ? .on : .off
        if model.practice { addSimulateMenu(to: menu) }

        menu.addItem(.separator())
        add(menu, "Settings…", #selector(showSettings))
        add(menu, "Welcome to Talkie…", #selector(showWelcome))
        add(menu, "Quit Talkie", #selector(quit))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    private func whereabouts() -> String {
        if model.practice { return "Practice board: simulated friends" }
        switch model.online?.status {
        case .online(let code)?: return "Online as \(code)"
        case .offline(let reason)?: return "Offline: \(reason.capitalized)"
        default: return "Connecting…"
        }
    }

    @objc private func togglePractice() { model.setPractice(!model.practice) }

    /// Pretend to be a friend on the practice board: knock, talk, or switch do not disturb.
    private func addSimulateMenu(to menu: NSMenu) {
        let simulate = NSMenuItem(title: "Simulate", action: nil, keyEquivalent: "")
        let friends = NSMenu()
        for (jack, friend) in model.board.friends.enumerated() {
            guard let friend else { continue }
            let item = NSMenuItem(title: friend.name.capitalized, action: nil, keyEquivalent: "")
            let actions = NSMenu()
            add(actions, "Knocks", #selector(simulateKnock(_:))).tag = jack
            add(actions, "Talks", #selector(simulateTalk(_:))).tag = jack
            let dnd = add(actions, "Do Not Disturb", #selector(simulateDoNotDisturb(_:)))
            dnd.tag = jack
            dnd.state = friend.doNotDisturb ? .on : .off
            let answers = add(actions, "Answers Your Knocks", #selector(simulateAnswers(_:)))
            answers.tag = jack
            answers.state = model.answersKnocks(jack) ? .on : .off
            item.submenu = actions
            friends.addItem(item)
        }
        // Anyone who isn't on the board can't really knock: you only get a note.
        let offBoard = Invite.samples.filter { model.board.jack(of: $0.friend.id) == nil }
        if !offBoard.isEmpty {
            friends.addItem(.separator())
            for invite in offBoard {
                friends.addItem(ClosureMenuItem(title: "\(invite.friend.name.capitalized) Tries to Knock") { [weak self] in
                    MainActor.assumeIsolated { self?.model.simulateOffBoardKnock(invite) }
                })
            }
        }
        simulate.submenu = friends
        menu.addItem(simulate)
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
    @objc private func simulateKnock(_ sender: NSMenuItem) { model.simulateKnock(sender.tag) }
    @objc private func simulateAnswers(_ sender: NSMenuItem) { model.setAnswersKnocks(sender.tag, !model.answersKnocks(sender.tag)) }
    @objc private func simulateTalk(_ sender: NSMenuItem) { model.simulateFriendTalks(sender.tag) }
    @objc private func simulateDoNotDisturb(_ sender: NSMenuItem) {
        model.simulateFriendDoNotDisturb(sender.tag, !(model.board.friend(sender.tag)?.doNotDisturb ?? false))
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
