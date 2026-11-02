import SwiftUI
import UIKit
import Observation
import AVFoundation
import TalkieCore

/// Talkie on iPhone: the same switchboard as the Mac, the same operator (Operator.swift is shared
/// with the Mac app), the same calls. The board's rules live in TalkieCore; this just runs them,
/// plays the sounds and turns taps into board changes.
@MainActor
@Observable
final class PhoneModel: OperatorHost {
    private(set) var board: Switchboard
    /// The name friends see on their board. Asked for once, the first time Talkie opens.
    private(set) var name: String
    var myName: String { name }
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Levels for the meter: your microphone and the people you hear, 0...1.
    private(set) var micLevel: Double = 0
    private(set) var heardLevel: Double = 0
    /// The code being typed in Add a Friend.
    var codeText = ""
    private(set) var checking = false
    /// Add a Friend is open.
    var adding = false
    private(set) var soundOn: Bool
    /// A screenshot scene for the simulator (TALKIE_DEMO): the board with sample friends, offline.
    let demo: String?

    @ObservationIgnored private(set) var online: Operator?
    @ObservationIgnored private let sound = SoundBoard()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastKnockSound: TimeInterval = 0
    @ObservationIgnored private var backgroundedAt: TimeInterval?
    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Saved {
        static let name = "name"
        static let plan = "plan"
        static let muted = "muted"
        static let soundOn = "soundOn"
    }

    init() {
        let demo = ProcessInfo.processInfo.environment["TALKIE_DEMO"]
        self.demo = demo
        let defaults = UserDefaults.standard
        soundOn = defaults.object(forKey: Saved.soundOn) as? Bool ?? true
        if let demo {
            name = demo == "welcome" ? "" : "SPACEMONKE"
            board = Demo.board(demo, now: ProcessInfo.processInfo.systemUptime)
            adding = demo == "add"
        } else {
            name = defaults.string(forKey: Saved.name) ?? ""
            let plan = Plan(rawValue: defaults.string(forKey: Saved.plan) ?? "") ?? .free
            board = Switchboard(friends: Array(repeating: nil, count: 8), myCode: "TLK-····", simulated: false, plan: plan)
            board.setMutedFriends(Set(defaults.array(forKey: Saved.muted) as? [Int] ?? []))
        }
        sound.volume = soundOn ? 0.63 : 0
    }

    // MARK: Running

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        if demo == nil, !name.isEmpty { goOnline() }
    }

    /// First run: the name friends will see. Then Talkie calls the operator and gets you a code.
    func setName(_ raw: String) {
        let tidy = String(raw.uppercased().filter { $0.isLetter || $0.isNumber || $0 == " " }.prefix(12))
            .trimmingCharacters(in: .whitespaces)
        guard !tidy.isEmpty else { return }
        name = tidy
        defaults.set(tidy, forKey: Saved.name)
        if demo == nil { goOnline() }
    }

    private func goOnline() {
        let op = online ?? Operator(model: self)
        online = op
        apply { $0.say("CONNECTING", "CALLING THE OPERATOR", now: now, for: 10); return [] }
        op.connect()
    }

    /// Off to the background. With a call open, iOS keeps Talkie running (background audio) and
    /// the call goes on. Without one, Talkie signs off so friends see you as away: a knock couldn't
    /// reach you anyway until you come back.
    func enteredBackground() {
        guard let online else { return }
        backgroundedAt = now
        guard board.openJacks.isEmpty, board.knockingOut.isEmpty else { return }
        let task = UIApplication.shared.beginBackgroundTask(withName: "Sign off")
        Task {
            await online.signOff(timeout: 3)
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    /// Back in front: if Talkie signed off (or iOS paused it), call the operator again for a
    /// fresh board, who's around and any knocks.
    func becameActive() {
        defer { backgroundedAt = nil }
        guard let online, backgroundedAt != nil, board.openJacks.isEmpty else { return }
        online.connect()
    }

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
        // A knock keeps knocking until you answer it.
        if !board.knocks.isEmpty, t - lastKnockSound >= 3 { playKnock(t) }

        let mine: Double, theirs: Double
        if let line = online?.line, line.isOpen {
            mine = line.micLevel
            theirs = line.heardLevel
        } else if demo == "call" {
            mine = 0
            theirs = 0.35 + 0.3 * abs(sin(t * 7))
        } else {
            mine = 0
            theirs = 0
        }
        let m = eased(micLevel, toward: mine), h = eased(heardLevel, toward: theirs)
        if m != micLevel { micLevel = m }
        if h != heardLevel { heardLevel = h }
    }

    private func eased(_ value: Double, toward target: Double) -> Double {
        let v = value + (target - value) * (target > value ? 0.45 : 0.12)
        return v < 0.002 ? 0 : v
    }

    // MARK: The operator's side (OperatorHost)

    /// Changes the board, plays whatever the change calls for, and tells the operator.
    func apply(_ change: (inout Switchboard) -> [BoardEvent]) {
        let old = board
        var b = board
        let events = change(&b)
        board = b
        online?.sync(from: old, to: b)
        handle(events)
    }

    func operatorConnected(code: String, friends: [Friend?], plan: Plan) {
        defaults.set(plan.rawValue, forKey: Saved.plan)
        var b = Switchboard(friends: friends, myCode: code, simulated: false, plan: plan)
        b.setMutedFriends(board.muted)
        b.say("ONLINE", "YOUR CODE IS \(code)", now: now, for: 3)
        board = b
    }

    func operatorFailed(_ reason: String) {
        apply { $0.say("OFFLINE", reason, now: now, for: 8); return [] }
    }

    func operatorChangedPlan(_ plan: Plan) {
        defaults.set(plan.rawValue, forKey: Saved.plan)
        apply { $0.setPlan(plan, now: now) }
    }

    func noteOffBoardKnock(name: String, code: String) {
        apply { $0.offBoardKnock(from: name, now: now) }
    }

    func friendBuzzed(_ jack: Int) {
        sound.play(.buzz)
        Haptics.thud()
        let name = board.friend(jack)?.name ?? "BUZZ"
        apply { $0.say(name, "BUZZED YOU", now: now, for: 1.7); return [] }
    }

    func guestBuzzed(_ name: String) {
        sound.play(.buzz)
        Haptics.thud()
        apply { $0.say(name, "BUZZED THE LINE", now: now, for: 1.7); return [] }
    }

    // MARK: Sounds

    private func handle(_ events: [BoardEvent]) {
        for event in events {
            switch event {
            case .plugged: sound.play(.plug); Haptics.tap()
            case .unplugged: sound.play(.unplug)
            case .lineOpened: sound.play(.open); Haptics.success()
            case .lineClosed: sound.play(.close)
            case .denied: sound.play(.deny); Haptics.warning()
            case .over: sound.play(.over)
            case .keyClick: sound.play(.key)
            case .click: sound.play(.click)
            case .buzz: sound.play(.buzz); Haptics.thud()
            case .micDrop, .micStow, .needsPro: break
            case .knockIn: playKnock(now)
            case .knockOut: sound.play(.knockSoft)
            case .addFriend: sound.play(.click); adding = true
            case .timeWarning: sound.play(.warn); Haptics.warning()
            }
        }
    }

    private func playKnock(_ t: TimeInterval) {
        lastKnockSound = t
        sound.play(KnockSound.forFriend(nil, plan: board.plan))
        Haptics.thud()
    }

    func toggleSound() {
        soundOn.toggle()
        sound.volume = soundOn ? 0.63 : 0
        defaults.set(soundOn, forKey: Saved.soundOn)
        if soundOn { sound.play(.click) }
    }

    // MARK: Your moves

    /// A jack: knock on a friend, pull the plug, let a knocking friend in, or add someone to an empty one.
    func tapJack(_ jack: Int) {
        apply { $0.tapJack(jack, now: now).events }
    }

    func letIn(_ jack: Int) { apply { $0.letIn(jack, now: now) } }

    /// Turn a knock away. They're never told.
    func decline(_ jack: Int) { apply { $0.decline(jack, now: now) } }

    func hangUpAll() { apply { $0.hangUpAll(now: now) } }

    /// Talking while someone knocks lets them in first: answering and talking are one move.
    func startTalking() {
        if board.openJacks.isEmpty, let jack = board.knockers.first { letIn(jack) }
        apply { $0.startTalking(now: now) }
    }

    func stopTalking() { apply { $0.stopTalking(now: now) } }

    func buzz() {
        let before = board.buzzing
        apply { $0.buzz(now: now) }
        if board.buzzing != before { online?.buzz() }
    }

    func toggleDoNotDisturb() { apply { $0.setDoNotDisturb(!$0.doNotDisturb, now: now) } }

    /// Mute a friend for yourself only. Nothing is sent to them.
    func setMuted(_ jack: Int, _ on: Bool) {
        apply { $0.mute(jack, on); return [.click] }
        defaults.set(Array(board.muted), forKey: Saved.muted)
    }

    /// Takes a friend off the board. Their code still works to bring them back.
    func eject(_ jack: Int) {
        let id = board.friend(jack)?.id
        apply { $0.removeFriend(at: jack, now: now) }
        if let id { online?.removeFriend(id) }
    }

    // MARK: Adding friends

    func openAdd() {
        guard !adding else { return }
        apply { $0.startAdding(at: nil) }
    }

    func closeAdd() {
        adding = false
        codeText = ""
        var b = board
        b.stopAdding()
        board = b
    }

    /// Asks the operator whose code it is and puts them on the board.
    func checkCode() {
        guard !checking else { return }
        let raw = codeText
        guard let code = InviteCode.normalize(raw), code != board.myCode else {
            finishCheck(raw, found: nil)
            return
        }
        guard let online else {
            // The simulator's screenshot scenes use the sample codes.
            if demo != nil { finishCheck(raw, found: Invite.lookup(code)) }
            else { apply { $0.say("OFFLINE", "WAIT FOR THE OPERATOR", now: now); return [.denied] } }
            return
        }
        checking = true
        apply { $0.say("CHECKING", code, now: now, for: 10); return [.keyClick] }
        Task {
            do {
                let found = try await online.lookUp(code)
                finishCheck(raw, found: found)
            } catch {
                checking = false
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
            sound.play(.accept)
            if let id = board.friend(jack)?.id { online?.saveFriend(id, jack: jack) }
            adding = false
            codeText = ""
        }
    }

    /// Your code, ready to send.
    var shareText: String {
        "Add me on Talkie: \(board.myCode). It's a walkie-talkie for iPhone and Mac: https://switchtalkie.com"
    }

    // MARK: Microphone

    /// Asks for the microphone once, before the first time you talk.
    func askForMicrophone() {
        guard AVAudioApplication.shared.recordPermission == .undetermined else { return }
        AVAudioApplication.requestRecordPermission { _ in }
    }

    var microphoneDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }
}
