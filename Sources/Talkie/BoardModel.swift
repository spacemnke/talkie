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
    /// The practice board, with simulated friends. Otherwise your real board, through the operator.
    private(set) var practice = false
    /// Talkie's operator (accounts, codes, knocks and the voice line). Nil on the practice board.
    @ObservationIgnored private(set) var online: Operator?

    // Patch cords, in the board window's coordinates
    private(set) var cords: [CordID: CordSim] = Dictionary(uniqueKeysWithValues: CordID.allCases.map { ($0, CordSim()) })
    private(set) var zOrder: [CordID] = CordID.allCases.reversed()
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
    /// 198pt wide: big enough to grab and read from across the screen.
    let micSize = CGSize(width: 198, height: 198 * MicArt.viewBox.height / MicArt.viewBox.width)

    private(set) var volume: Double = 0.7
    private(set) var soundOn = true
    /// A jack whose name strip flashes because a friend just landed on it.
    private(set) var arriving: Int?

    // Adding a friend, on the board itself
    /// What's typed in the code field.
    var codeText = ""
    /// Asking who a code belongs to.
    private(set) var checking = false
    /// Bumped to put the cursor in the code field.
    private(set) var focusRequest = 0
    /// Your name on the line card you send: the first word of your Mac account's name.
    let myName = BoardModel.cardName()

    let sound = SoundBoard()
    @ObservationIgnored var onFrame: (() -> Void)?
    /// The mic's settings key was pressed, at this point in the overlay.
    @ObservationIgnored var onMicMenu: ((CGPoint) -> Void)?
    /// Show what Pro is: you reached for something that comes with it, or asked.
    @ObservationIgnored var onShowPro: (() -> Void)?
    /// Your pick of knock for each friend, by friend id (Pro).
    private(set) var knockSounds: [Int: KnockSound] = [:]
    /// Simulated friends (by id) who don't answer your knocks.
    @ObservationIgnored private(set) var unanswering: Set<Int> = []
    @ObservationIgnored private var lastKnockSound: TimeInterval = 0
    /// Who last tried to knock from off the board, so the add panel can offer their code.
    @ObservationIgnored private var lastKnock: (code: String, at: TimeInterval)?
    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Saved {
        static let soundOn = "soundOn"
        static let volume = "volume"
        static let micHome = "micHome"
        static let muted = "mutedFriends"
        static let practice = "practiceBoard"
        /// Your plan as the operator last said it, so the board starts out right before it answers.
        static let plan = "plan"
        /// The practice board's plan, to try Free and Pro without paying.
        static let practicePlan = "practicePlan"
        static let knockSounds = "knockSounds"
    }
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
        practice = UserDefaults.standard.bool(forKey: Saved.practice)
        board = practice ? Self.practiceBoard(now: ProcessInfo.processInfo.systemUptime, plan: Self.savedPlan(Saved.practicePlan, or: .pro))
            : Self.waitingBoard(plan: Self.savedPlan(Saved.plan, or: .free))

        // What you set last time: sound, volume, who you muted, where you left the mic.
        if defaults.object(forKey: Saved.soundOn) != nil { soundOn = defaults.bool(forKey: Saved.soundOn) }
        if defaults.object(forKey: Saved.volume) != nil { volume = min(max(defaults.double(forKey: Saved.volume), 0), 1) }
        if let ids = defaults.array(forKey: Saved.muted) as? [Int] { board.setMutedFriends(Set(ids)) }
        if let saved = defaults.dictionary(forKey: Saved.knockSounds) as? [String: String] {
            for (id, raw) in saved {
                if let id = Int(id), let k = KnockSound(rawValue: raw) { knockSounds[id] = k }
            }
        }
        if let home = defaults.array(forKey: Saved.micHome) as? [Double], home.count == 2 {
            mic.home = CGPoint(x: home[0], y: home[1])
        }
        sound.volume = Float(soundOn ? volume : 0)
    }

    func start() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if !practice { goOnline() }
    }

    // MARK: Practice board or the real one

    private static func savedPlan(_ key: String, or fallback: Plan) -> Plan {
        UserDefaults.standard.string(forKey: key).flatMap(Plan.init(rawValue:)) ?? fallback
    }

    /// Like the prototype: cord A is in Maya's jack and she has let you in.
    private static func practiceBoard(now t: TimeInterval, plan: Plan) -> Switchboard {
        var b = Switchboard(plan: plan)
        _ = b.patch(.a, into: 0, now: t - 3)
        _ = b.friendAnswers(0, now: t - 3)
        _ = b.tick(now: t)
        return b
    }

    /// Your real board before the operator has answered: empty, with no code yet.
    private static func waitingBoard(plan: Plan) -> Switchboard {
        Switchboard(friends: Array(repeating: nil, count: 8), myCode: "TLK-····", simulated: false, plan: plan)
    }

    func setPractice(_ on: Bool) {
        guard on != practice else { return }
        practice = on
        defaults.set(on, forKey: Saved.practice)
        stowMic()
        if on {
            online?.disconnect()
            online = nil
            replaceBoard(Self.practiceBoard(now: now, plan: Self.savedPlan(Saved.practicePlan, or: .pro)))
            dropMic()
        } else {
            replaceBoard(Self.waitingBoard(plan: Self.savedPlan(Saved.plan, or: .free)))
            goOnline()
        }
    }

    private func goOnline() {
        let op = online ?? Operator(model: self)
        online = op
        apply { $0.say("CONNECTING", "CALLING THE OPERATOR", now: now, for: 10); return [] }
        op.connect()
    }

    /// The operator answered: here's your code, your plan and your board.
    func operatorConnected(code: String, friends: [Friend?], plan: Plan) {
        defaults.set(plan.rawValue, forKey: Saved.plan)
        var b = Switchboard(friends: friends, myCode: code, simulated: false, plan: plan)
        b.setMutedFriends(board.muted)
        b.say("ONLINE", "YOUR CODE IS \(code)", now: now, for: 3)
        replaceBoard(b)
    }

    func operatorFailed(_ reason: String) {
        apply { $0.say("OFFLINE", reason, now: now, for: 8); return [] }
    }

    /// A whole new board (practice or real): cords go home, nothing is sent anywhere.
    private func replaceBoard(_ b: Switchboard) {
        var next = b
        next.setMutedFriends(board.muted)
        next.restoreEffect(board.effect)
        board = next
        resnapCords()
    }

    // MARK: Frame

    private func tick() {
        let t = now
        var b = board
        let events = b.tick(now: t)
        if b != board {
            let old = board
            board = b
            online?.sync(from: old, to: b)
        }
        handle(events)
        if practice { answerKnocks(t) }
        // A knock keeps knocking until you answer it.
        if !board.knocks.isEmpty, t - lastKnockSound >= 3 { playKnock(t) }

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
            if let home = next.home, home != mic.home {
                defaults.set([Double(home.x), Double(home.y)], forKey: Saved.micHome)
            }
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

    /// Changes the board and plays whatever the change calls for.
    func apply(_ change: (inout Switchboard) -> [BoardEvent]) {
        let old = board
        var b = board
        let events = change(&b)
        board = b
        online?.sync(from: old, to: b)
        handle(events)
    }

    private func playKnock(_ t: TimeInterval) {
        lastKnockSound = t
        sound.play(knockSound(for: board.knockers.first))
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
            case .knockIn: playKnock(now)
            case .knockOut: sound.play(.knockSoft)
            case .addFriend: sound.play(.click); focusRequest += 1
            case .needsPro: onShowPro?()
            case .timeWarning: sound.play(.warn)
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
        let old = board
        var b = board
        let result = b.tapJack(jack, now: now)
        board = b
        online?.sync(from: old, to: b)
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

    var isAdding: Bool { board.adding != nil }

    func toggleAdding() {
        if isAdding { stopAdding() } else { startAdding() }
    }

    /// Opens the add panel. The friend goes on `jack` if it's free, otherwise the first free jack.
    func startAdding(at jack: Int? = nil) {
        apply { $0.startAdding(at: jack) }
        // Someone just knocked? Offer their code.
        if codeText.isEmpty, let knock = lastKnock, now - knock.at < 60 { codeText = knock.code }
    }

    func stopAdding() {
        guard isAdding else { return }
        apply { $0.stopAdding(); return [.click] }
        codeText = ""
    }

    /// The code field changed: keep it short and capitalised, and pick the code out of a pasted message.
    func tidyCode(_ text: String) {
        let tidy = text.count > 9 ? (InviteCode.normalize(text) ?? "") : text.uppercased()
        if tidy != codeText { codeText = tidy }
    }

    /// Asks who the code belongs to (a moment on CHECKING, as if asking the operator) and puts them on the board.
    func checkCode() {
        guard !checking else { return }
        let raw = codeText
        guard let code = InviteCode.normalize(raw) else {
            finishCheck(raw, found: nil)
            return
        }
        checking = true
        apply { $0.say("CHECKING", code, now: now, for: 10); return [.keyClick] }
        guard let online, code != board.myCode else {
            // The practice board's codes, after a moment.
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.1 : 0.7)) { [weak self] in
                MainActor.assumeIsolated { self?.finishCheck(raw, found: Invite.lookup(code)) }
            }
            return
        }
        Task {
            do {
                let found = try await online.lookUp(code)
                finishCheck(raw, found: found)
            } catch {
                checking = false
                focusRequest += 1
                apply { $0.say("CAN'T CHECK", Operator.describe(error), now: now, for: 3); return [.denied] }
            }
        }
    }

    private func finishCheck(_ raw: String, found: Invite?) {
        checking = false
        var result = CodeResult.empty
        apply { b in
            let out = b.enterCode(raw, now: now) { _ in found }
            result = out.result
            return out.events
        }
        if case .added(let jack) = result {
            codeText = ""
            sound.play(.accept)
            flashArrival(jack)
            if let id = board.friend(jack)?.id { online?.saveFriend(id, jack: jack) }
        } else {
            // Leave what they typed so they can fix it.
            focusRequest += 1
        }
    }

    /// Takes a friend off the board. Their code still works to bring them back.
    func eject(_ jack: Int) {
        let id = board.friend(jack)?.id
        apply { $0.removeFriend(at: jack, now: now) }
        if let id { online?.removeFriend(id) }
    }

    func copyMyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(board.myCode, forType: .string)
        apply { $0.say("COPIED", "SEND IT TO A FRIEND", now: now); return [.click] }
    }

    var myCard: LineCard { LineCard(name: myName, code: board.myCode) }

    /// Your line card as a picture, with your code in words, through the share menu.
    func sendMyCard(from view: NSView?) {
        CardSharing.share(myCard, from: view)
        apply { $0.say("YOUR CARD", "SEND IT TO A FRIEND", now: now); return [.click] }
    }

    nonisolated private static func cardName() -> String {
        let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        let letters = first.uppercased().filter { $0.isLetter }
        return letters.isEmpty ? "YOUR LINE" : String(letters.prefix(10))
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

    // MARK: Knocks

    /// Let a knocking friend in.
    func letIn(_ jack: Int) {
        apply { $0.letIn(jack, now: now) }
    }

    /// Turn a knock away. They're never told.
    func decline(_ jack: Int) {
        apply { $0.decline(jack, now: now) }
    }

    func hangUpAll() {
        apply { $0.hangUpAll(now: now) }
    }

    /// Simulated friends let you in after a moment, unless you've told one not to answer.
    private func answerKnocks(_ t: TimeInterval) {
        for jack in board.knockingOut {
            guard let p = board.cord(at: jack).flatMap({ board.patches[$0] }), t - p.since >= 1.6,
                  let f = board.friend(jack), !unanswering.contains(f.id) else { continue }
            apply { $0.friendAnswers(jack, now: t) }
        }
    }

    func answersKnocks(_ jack: Int) -> Bool {
        guard let f = board.friend(jack) else { return false }
        return !unanswering.contains(f.id)
    }

    func setAnswersKnocks(_ jack: Int, _ on: Bool) {
        guard let f = board.friend(jack) else { return }
        if on { unanswering.remove(f.id) } else { unanswering.insert(f.id) }
    }

    // MARK: Talking, effects, settings

    /// Talking while someone knocks lets them in first: answering and talking are one move.
    func startTalking() {
        if board.openJacks.isEmpty, let jack = board.knockers.first { letIn(jack) }
        if !mic.isVisible || mic.mode == .retracting { dropMic() }
        apply { $0.startTalking(now: now) }
    }

    func stopTalking() {
        apply { $0.stopTalking(now: now) }
    }

    func cycleEffect() { apply { $0.cycleEffect(now: now) } }
    func setEffect(_ e: Effect) { apply { $0.setEffect(e, now: now) } }
    func buzz() {
        let before = board.buzzing
        apply { $0.buzz(now: now) }
        if board.buzzing != before { online?.buzz() }
    }

    /// A friend on the line pressed their buzz key.
    func friendBuzzed(_ jack: Int) {
        sound.play(.buzz)
        let name = board.friend(jack)?.name ?? "BUZZ"
        apply { $0.say(name, "BUZZED YOU", now: now, for: 1.7); return [] }
    }

    /// Someone on the call who isn't on your board buzzed.
    func guestBuzzed(_ name: String) {
        sound.play(.buzz)
        apply { $0.say(name, "BUZZED THE LINE", now: now, for: 1.7); return [] }
    }

    /// Someone who isn't on your board tried to knock. Nothing rings; ADD will offer their code.
    func noteOffBoardKnock(name: String, code: String) {
        lastKnock = (code, now)
        apply { $0.offBoardKnock(from: name, now: now) }
    }
    func toggleDoNotDisturb() { apply { $0.setDoNotDisturb(!$0.doNotDisturb, now: now) } }

    func toggleSound() {
        soundOn.toggle()
        sound.volume = Float(soundOn ? volume : 0)
        defaults.set(soundOn, forKey: Saved.soundOn)
        if soundOn { sound.play(.click) }
    }

    /// Mute a friend for yourself only. Nothing is sent to them.
    func setMuted(_ jack: Int, _ on: Bool) {
        apply { $0.mute(jack, on); return [.click] }
        defaults.set(Array(board.muted), forKey: Saved.muted)
    }

    func setVolume(_ v: Double) {
        volume = min(max(v, 0), 1)
        sound.volume = Float(soundOn ? volume : 0)
        defaults.set(volume, forKey: Saved.volume)
        let n = Int((volume * 10).rounded())
        apply {
            $0.say(String(format: "VOL %02d", n), String(repeating: "▮", count: n) + String(repeating: "▯", count: 10 - n), now: now, for: 1.2)
            return []
        }
    }

    // MARK: Free or Pro

    /// Your plan changed on the server (you went Pro, or Pro ran out).
    func operatorChangedPlan(_ plan: Plan) {
        defaults.set(plan.rawValue, forKey: Saved.plan)
        apply { $0.setPlan(plan, now: now) }
    }

    /// The practice board's plan: try Free and Pro without paying.
    func setPracticePlan(_ plan: Plan) {
        guard practice else { return }
        defaults.set(plan.rawValue, forKey: Saved.practicePlan)
        apply { $0.setPlan(plan, now: now) }
    }

    /// The knock you hear when the friend on `jack` knocks.
    func knockSound(for jack: Int?) -> KnockSound {
        KnockSound.forFriend(jack.flatMap { board.friend($0) }.flatMap { knockSounds[$0.id] }, plan: board.plan)
    }

    /// Pick a friend's knock (Pro). You hear it straight away.
    func setKnockSound(_ knock: KnockSound, for jack: Int) {
        guard board.plan.hasKnockSounds else {
            apply { $0.say("KNOCK SOUNDS", "PRO ONLY · PICK A KNOCK PER FRIEND", now: now, for: 2.6); return [.denied, .needsPro] }
            return
        }
        guard let f = board.friend(jack) else { return }
        knockSounds[f.id] = knock == .standard ? nil : knock
        defaults.set(Dictionary(uniqueKeysWithValues: knockSounds.map { (String($0.key), $0.value.rawValue) }), forKey: Saved.knockSounds)
        sound.play(knock)
        apply { $0.say(f.name, "KNOCKS WITH \(knock.title.uppercased())", now: now, for: 2); return [] }
    }

    func previewKnock(_ knock: KnockSound) {
        sound.play(knock)
    }

    // MARK: Simulated friends (until there's a network)

    func simulateKnock(_ jack: Int) { apply { $0.friendKnocks(jack, now: now) } }
    /// Jump a free call to its last minute (practice board).
    func simulateLastMinute() { apply { $0.endLinesSoon(in: Plan.warnBefore + 1, now: now); return [] } }
    func simulateOffBoardKnock(_ invite: Invite) {
        lastKnock = (invite.code, now)
        apply { $0.offBoardKnock(from: invite.friend.name, now: now) }
    }
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
        if mic.mode == .hidden || mic.mode == .retracting { dropMic() } else { putMicAway() }
    }

    /// Putting the mic away while someone knocks turns them away, the same as its × key.
    func putMicAway() {
        for jack in board.knockers { decline(jack) }
        stowMic()
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

    private enum MicKey { case effect, buzz, settings, letIn, decline }

    /// Which of the mic's keys is under the pointer, in the drawing's own units.
    /// The front key is only a key of its own while someone knocks; otherwise the whole mic talks.
    private func micKey(at p: CGPoint) -> MicKey? {
        let frame = micFrame
        guard frame.width > 0 else { return nil }
        let x = MicArt.viewBox.minX + (p.x - frame.minX) / frame.width * MicArt.viewBox.width
        let y = MicArt.viewBox.minY + (p.y - frame.minY) / frame.height * MicArt.viewBox.height
        let point = CGPoint(x: x, y: y)
        if MicArt.effectKey.contains(point) { return .effect }
        if MicArt.buzzKey.contains(point) { return .buzz }
        if MicArt.settingsKey.contains(point) { return .settings }
        if !board.knocks.isEmpty {
            if MicArt.declineKey.contains(point) { return .decline }
            if MicArt.frontKey.contains(point) { return .letIn }
        }
        return nil
    }

    func micPointerDown(at p: CGPoint) {
        if let key = micKey(at: p) {
            switch key {
            case .effect: cycleEffect()
            case .buzz: buzz()
            case .settings: onMicMenu?(p)
            case .decline: if let jack = board.knockers.first { decline(jack) }
            case .letIn:
                // Let them in, and keep holding to talk straight away.
                if let jack = board.knockers.first { letIn(jack) }
            }
            if key != .letIn { return }
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
