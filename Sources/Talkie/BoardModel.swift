import SwiftUI
import AppKit
import Observation
import TalkieCore

/// Everything the board window and the floating mic draw from.
/// Runs at 60 frames a second, but only publishes what actually changed.
@MainActor
@Observable
final class BoardModel {
    // Switchboard state (changes on events)
    private(set) var board = Switchboard()

    // Patch cords, in the board window's coordinates
    private(set) var cords: [CordID: CordSim] = [.a: CordSim(), .b: CordSim()]
    private(set) var zOrder: [CordID] = [.b, .a]
    private(set) var nearJack: Int?
    var holes: [Int: CGPoint] = [:]
    var docks: [CordID: CGPoint] = [:]
    var boardSize: CGSize = .zero

    // Levels for the meters (simulated until there's real audio)
    private(set) var meter: Double = 0
    private(set) var micLevel: Double = 0
    private(set) var friendLevel: Double = 0

    // The floating mic, in the overlay's coordinates
    private(set) var mic = FloatingMic()
    var overlayBounds: CGRect = .zero
    var anchor: CGPoint = .zero
    let micSize = CGSize(width: 110, height: 110 * 275 / 160)

    private(set) var volume: Double = 0.7
    private(set) var soundOn = true
    /// A jack whose name strip flashes because a friend just landed on it.
    private(set) var arriving: Int?

    let sound = SoundBoard()
    @ObservationIgnored var onFrame: (() -> Void)?
    /// Show the card file. True when it's because someone clicked a free jack.
    @ObservationIgnored var onOpenCardFile: ((_ forFreeJack: Bool) -> Void)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var plugDrags: [CordID: PlugDrag] = [:]
    @ObservationIgnored private var pendingSeat: Set<CordID> = []
    @ObservationIgnored private var micGrab: MicGrab?
    @ObservationIgnored private var cordsPlaced = false

    private struct PlugDrag {
        var offset: CGVector
        var start: CGPoint
        var moved = false
    }

    private struct MicGrab {
        var offset: CGVector
        var start: CGPoint
        var moved = false
        var talking = false
        var holdTimer: Timer?
    }

    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init() {
        // Start like the prototype: cord A is already in Maya's jack (simulated friend).
        let t = now
        _ = board.patch(.a, into: 0, now: t - Switchboard.connectDelay)
        _ = board.tick(now: t)
        sound.volume = Float(volume)
    }

    func start() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: Frame

    private func tick() {
        let t = now
        var b = board
        let events = b.tick(now: t)
        if b != board { board = b }
        handle(events)

        stepCords()

        let mine = board.talking ? simulatedVoice(t, seed: 0) : 0
        let theirs = board.flags.rx ? simulatedVoice(t, seed: 3.1) : 0
        micLevel = eased(micLevel, toward: mine)
        friendLevel = eased(friendLevel, toward: theirs)
        let m = max(micLevel, friendLevel)
        if abs(m - meter) > 0.004 { meter = m }

        if mic.isVisible, overlayBounds.width > 0 {
            var next = mic
            next.step(anchor: anchor, bounds: overlayBounds, size: micSize, reduceMotion: reduceMotion)
            if next != mic { mic = next }
        }
        onFrame?()
    }

    private func stepCords() {
        guard docks.count == CordID.allCases.count else { return }
        var next = cords
        var moved = false
        for c in CordID.allCases {
            guard let dock = docks[c], var sim = next[c] else { continue }
            let target = board.patches[c].flatMap { holes[$0.jack] } ?? dock
            if !cordsPlaced {
                sim.snap(dock: dock, target: target)
                moved = true
            } else if sim.step(dock: dock, target: target, reduceMotion: reduceMotion) {
                moved = true
            }
            if pendingSeat.contains(c), sim.plug.distance(to: target) < 6 {
                pendingSeat.remove(c)
                sound.play(.plug)
                Haptics.seat()
            }
            next[c] = sim
        }
        cordsPlaced = true
        if moved { cords = next }
    }

    /// When the window resizes or the jacks move, put the plugs straight back in place.
    func resnapCords() {
        cordsPlaced = false
    }

    private func eased(_ value: Double, toward target: Double) -> Double {
        let v = value + (target - value) * (target > value ? 0.45 : 0.12)
        return v < 0.002 ? 0 : v
    }

    /// A stand-in voice level: syllables, phrases and a little jitter.
    private func simulatedVoice(_ t: TimeInterval, seed: Double) -> Double {
        let ms = t * 1000
        let envelope = abs(sin(ms / 140 + seed) * 0.6 + sin(ms / 53 + seed * 2) * 0.4)
        let phrase = sin(ms / 700 + seed) > -0.55 ? 1.0 : 0.12
        return min(1, (0.18 + envelope * 0.85) * phrase * Double.random(in: 0.8...1.1))
    }

    // MARK: Events

    /// Changes the board and plays whatever the change calls for. The card file uses this too.
    func apply(_ change: (inout Switchboard) -> [BoardEvent]) {
        var b = board
        let events = change(&b)
        board = b
        handle(events)
    }

    private func handle(_ events: [BoardEvent]) {
        for event in events {
            switch event {
            case .plugged: sound.play(.plug); Haptics.seat()
            case .unplugged: sound.play(.unplug)
            case .lineOpened: sound.play(.open)
            case .lineClosed: sound.play(.close)
            case .denied: sound.play(.deny)
            case .over: sound.play(.over)
            case .keyClick: sound.play(.key)
            case .click: sound.play(.click)
            case .buzz: sound.play(.buzz)
            case .micDrop: dropMic()
            case .micStow: stowMic()
            case .openCardFile: onOpenCardFile?(true)
            }
        }
    }

    // MARK: Plugs

    func plugDragChanged(_ c: CordID, location: CGPoint, start: CGPoint) {
        guard var sim = cords[c] else { return }
        var drag = plugDrags[c] ?? {
            raise(c)
            return PlugDrag(offset: CGVector(dx: sim.plug.x - start.x, dy: sim.plug.y - start.y), start: start)
        }()
        if !drag.moved && location.distance(to: start) > 5 {
            drag.moved = true
            pendingSeat.remove(c)
            if board.patches[c] != nil { apply { $0.unpatch(c, now: now) } }
        }
        plugDrags[c] = drag
        guard drag.moved else { return }
        sim.dragging = true
        sim.plug = CGPoint(
            x: min(max(location.x + drag.offset.dx, 14), max(boardSize.width - 14, 14)),
            y: min(max(location.y + drag.offset.dy, 14), max(boardSize.height - 14, 14))
        )
        sim.plugVelocity = .zero
        cords[c] = sim
        let near = nearestJack(to: sim.plug)
        if near != nearJack { nearJack = near }
    }

    func plugDragEnded(_ c: CordID) {
        guard let drag = plugDrags.removeValue(forKey: c) else { return }
        guard drag.moved else {
            if board.patches[c] != nil {
                apply { $0.unpatch(c, now: now) }
            } else {
                apply { $0.say("CORD \(c.label)", "DRAG IT INTO A JACK", now: now); return [] }
            }
            return
        }
        cords[c]?.dragging = false
        let jack = nearJack
        nearJack = nil
        if let jack { apply { $0.patch(c, into: jack, now: now) } }
    }

    func tapJack(_ jack: Int) {
        var b = board
        let result = b.tapJack(jack, now: now)
        board = b
        if let flying = result.cord {
            // The plug flies over; it clicks when it lands.
            raise(flying)
            pendingSeat.insert(flying)
            handle(result.events.filter { $0 != .plugged })
        } else {
            handle(result.events)
        }
    }

    private func nearestJack(to p: CGPoint) -> Int? {
        var best: Int?
        var bestDistance: CGFloat = 40
        for (jack, hole) in holes {
            let d = hole.distance(to: p)
            if d < bestDistance { best = jack; bestDistance = d }
        }
        return best
    }

    private func raise(_ c: CordID) {
        zOrder.removeAll { $0 == c }
        zOrder.append(c)
    }

    // MARK: Friends coming and going

    func openCardFile() {
        sound.play(.click)
        onOpenCardFile?(false)
    }

    func flashArrival(_ jack: Int) {
        arriving = jack
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.arriving == jack else { return }
                withAnimation(.easeOut(duration: 0.6)) { self.arriving = nil }
            }
        }
    }

    // MARK: Talking, effects, settings

    func startTalking() {
        if !mic.isVisible || mic.mode == .retracting { dropMic() }
        apply { $0.startTalking(now: now) }
    }

    func stopTalking() {
        apply { $0.stopTalking(now: now) }
    }

    func cycleEffect() { apply { $0.cycleEffect(now: now) } }
    func setEffect(_ e: Effect) { apply { $0.setEffect(e, now: now) } }
    func buzz() { apply { $0.buzz(now: now) } }
    func toggleDoNotDisturb() { apply { $0.setDoNotDisturb(!$0.doNotDisturb, now: now) } }

    func toggleSound() {
        soundOn.toggle()
        sound.volume = Float(soundOn ? volume : 0)
        if soundOn { sound.play(.click) }
    }

    func setVolume(_ v: Double) {
        volume = min(max(v, 0), 1)
        sound.volume = Float(soundOn ? volume : 0)
        let n = Int((volume * 10).rounded())
        apply {
            $0.say(String(format: "VOL %02d", n), String(repeating: "▮", count: n) + String(repeating: "▯", count: 10 - n), now: now, for: 1.2)
            return []
        }
    }

    // MARK: Simulated friends (until there's a network)

    func simulateIncoming(_ jack: Int) { apply { $0.friendPatchesIn(jack, now: now) } }
    func simulateFriendTalks(_ jack: Int) { apply { $0.friendTalks(jack, for: 2.5, now: now); return [] } }
    func simulateFriendDoNotDisturb(_ jack: Int, _ on: Bool) { apply { $0.setFriendDoNotDisturb(jack, on, now: now) } }

    // MARK: The floating mic

    func dropMic() {
        guard mic.mode == .hidden || mic.mode == .retracting else { return }
        mic.drop(from: anchor)
        sound.play(.drop)
    }

    func stowMic() {
        guard mic.mode != .hidden && mic.mode != .retracting else { return }
        releaseMic(cancelled: true)
        mic.stow()
        sound.play(.stow)
    }

    func toggleMic() {
        if mic.mode == .hidden || mic.mode == .retracting { dropMic() } else { stowMic() }
    }

    var isMicGrabbed: Bool { micGrab != nil }

    /// The mic's on-screen frame, ignoring its small tilt.
    var micFrame: CGRect {
        let w = micSize.width * mic.scale, h = micSize.height * mic.scale
        return CGRect(x: mic.position.x - w / 2, y: mic.position.y - h / 2, width: w, height: h)
    }

    func micHitTest(_ p: CGPoint) -> Bool {
        mic.isVisible && micFrame.insetBy(dx: -4, dy: -4).contains(p)
    }

    private enum MicKey { case effect, buzz }

    /// Which of the mic's side keys is under the pointer, in the drawing's own units.
    private func micKey(at p: CGPoint) -> MicKey? {
        let frame = micFrame
        guard frame.width > 0 else { return nil }
        let x = MicArt.viewBox.minX + (p.x - frame.minX) / frame.width * MicArt.viewBox.width
        let y = MicArt.viewBox.minY + (p.y - frame.minY) / frame.height * MicArt.viewBox.height
        guard x >= 146 else { return nil }
        if (48...98).contains(y) { return .effect }
        if (100...142).contains(y) { return .buzz }
        return nil
    }

    func micPointerDown(at p: CGPoint) {
        if let key = micKey(at: p) {
            switch key {
            case .effect: cycleEffect()
            case .buzz: buzz()
            }
            return
        }
        guard mic.mode == .floating || mic.mode == .dropping else { return }
        var grab = MicGrab(offset: CGVector(dx: mic.position.x - p.x, dy: mic.position.y - p.y), start: p)
        // A short hold talks; moving first means you're dragging it.
        let timer = Timer(timeInterval: 0.14, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.micHeld() }
        }
        RunLoop.main.add(timer, forMode: .common)
        grab.holdTimer = timer
        micGrab = grab
    }

    private func micHeld() {
        guard var grab = micGrab, !grab.moved else { return }
        grab.talking = true
        micGrab = grab
        startTalking()
    }

    func micPointerDragged(to p: CGPoint) {
        guard var grab = micGrab else { return }
        if !grab.moved && p.distance(to: grab.start) > 6 {
            grab.moved = true
            grab.holdTimer?.invalidate()
            mic.beginDrag()
        }
        micGrab = grab
        if mic.mode == .dragging {
            mic.drag(to: CGPoint(x: p.x + grab.offset.dx, y: p.y + grab.offset.dy), bounds: overlayBounds, size: micSize)
        }
    }

    func micPointerUp() {
        releaseMic(cancelled: false)
    }

    private func releaseMic(cancelled: Bool) {
        guard let grab = micGrab else { return }
        micGrab = nil
        grab.holdTimer?.invalidate()
        if grab.talking { stopTalking() }
        if mic.mode == .dragging {
            mic.endDrag()
        } else if !grab.moved && !grab.talking && !cancelled {
            apply { $0.say("HOLD", "HOLD THE MIC TO TALK", now: now, for: 1.4); return [] }
        }
    }
}

enum Haptics {
    /// The click you feel through the trackpad when a plug seats.
    @MainActor static func seat() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
