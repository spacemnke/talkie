import SwiftUI
import AppKit
import Observation
import TalkieCore

enum CardSpace {
    static let name = "cardfile"
    static let card = CGSize(width: 196, height: 110)
}

/// Places in the card file window that cards move between, in its coordinates.
enum CardSpot: Hashable {
    case feed, tray, drum
}

struct SpotKey: PreferenceKey {
    static let defaultValue: [CardSpot: CGRect] = [:]
    static func reduce(value: inout [CardSpot: CGRect], nextValue: () -> [CardSpot: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The card file window: checks codes, runs the punch and turns the Rolodex.
/// The rules live in `CardFile`; this adds the timing, the sounds and the card you drag around.
@MainActor
@Observable
final class CardFileModel {
    enum Source { case tray, file }
    enum LampState { case off, on, blink }

    struct Lamps: Equatable {
        var read = LampState.off
        var ok = LampState.off
        var err = LampState.off
    }

    /// The card under your pointer (or on its way into the punch). The original stays put, faded.
    struct Ghost: Equatable {
        var card: LineCard
        var source: Source
        /// Top-left corner, in the window's coordinates.
        var origin: CGPoint
        var lifted = true
        /// Inside the punch: everything below the slot is hidden.
        var inSlot = false
    }

    let boardModel: BoardModel
    private(set) var file = CardFile()
    var codeText = ""
    private(set) var readout = PunchReadout("INSERT CARD", "OR CHECK A CODE")
    private(set) var lamps = Lamps()
    private(set) var busy = false
    private(set) var ghost: Ghost?
    private(set) var feedHot = false
    /// Bumped to put the cursor in the code field.
    private(set) var focusRequest = 0
    var spots: [CardSpot: CGRect] = [:]

    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var drag: Drag?
    @ObservationIgnored private var lastWheel: TimeInterval = 0

    private struct Drag {
        var offset: CGVector
        var start: CGPoint
        var moved = false
        /// Clicking a card behind the front one turns the Rolodex to it instead of picking it up.
        var ignored = false
    }

    init(boardModel: BoardModel) {
        self.boardModel = boardModel
    }

    private var sound: SoundBoard { boardModel.sound }
    private var now: TimeInterval { boardModel.now }
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func jack(of card: LineCard) -> Int? {
        boardModel.board.jack(of: card.id)
    }

    var hint: String { file.hint(on: boardModel.board) }

    var canEject: Bool {
        guard let card = file.frontCard else { return false }
        return !busy && jack(of: card) != nil
    }

    /// Where the bottom of the slot is: a card going into the punch disappears below this line.
    var slotLine: CGFloat { spots[.feed]?.maxY ?? 0 }

    // MARK: The LCD

    private func say(_ r: PunchReadout) {
        idleTask?.cancel()
        readout = r
    }

    private func idleLater(_ seconds: Double) {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.lamps = Lamps()
            self.readout = self.file.tray != nil
                ? PunchReadout("CARD READY", "DRAG IT TO THE SLOT")
                : PunchReadout("INSERT CARD", "OR CHECK A CODE")
        }
    }

    private func pause(_ seconds: Double) async {
        let s = reduceMotion ? min(seconds, 0.06) : seconds
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }

    private func animate(_ animation: Animation, _ change: () -> Void) {
        if reduceMotion { change() } else { withAnimation(animation, change) }
    }

    /// Called when the window opens because someone clicked a free jack.
    func greetFreeJack() {
        guard !busy else { return }
        if let jack = boardModel.board.freeJack {
            say(PunchReadout("FREE JACK " + String(format: "%02d", jack + 1), "CHECK A CODE"))
            idleLater(3)
        }
        focusRequest += 1
    }

    // MARK: Codes

    func tryCode(_ code: String) {
        codeText = code
        focusRequest += 1
    }

    func checkCode() {
        guard !busy else { return }
        guard let code = InviteCode.normalize(codeText) else {
            refuse(CodeCheck.empty.readout, idle: 1.8)
            return
        }
        if file.tray != nil {
            refuse(CodeCheck.takeYourCard.readout, idle: 2)
            return
        }
        busy = true
        lamps = Lamps(read: .blink)
        say(PunchReadout("CHECKING", code))
        sound.play(.key)
        Task {
            await pause(0.9)
            // Until there's a server, the codes the sample friends sent you.
            let invite = Invite.samples[code]
            var result = CodeCheck.unknown
            animate(.easeOut(duration: 0.5)) {
                result = file.issue(code: code, invite: invite, on: Date())
            }
            if case .issued = result {
                lamps = Lamps(ok: .on)
                say(result.readout)
                sound.play(.print)
                codeText = ""
                idleLater(2.6)
            } else {
                refuse(result.readout, idle: 2.2)
            }
            busy = false
        }
    }

    private func refuse(_ r: PunchReadout, idle: Double) {
        lamps = Lamps(err: .on)
        say(r)
        sound.play(.deny)
        idleLater(idle)
    }

    func copyMyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(file.myCode, forType: .string)
        sound.play(.click)
        say(PunchReadout("COPIED", "SEND IT TO A FRIEND"))
        idleLater(1.8)
    }

    // MARK: The Rolodex

    func turn(_ step: Int) {
        guard drag == nil, !file.cards.isEmpty else { return }
        animate(.timingCurve(0.3, 0.7, 0.3, 1, duration: 0.35)) { file.turn(step) }
        sound.play(.flip)
    }

    /// A scroll over the Rolodex turns it, one card at a time.
    func wheel(at p: CGPoint, deltaY: CGFloat) {
        guard let drum = spots[.drum], drum.contains(p), abs(deltaY) >= 1 else { return }
        let t = now
        guard t - lastWheel > 0.12 else { return }
        lastWheel = t
        turn(deltaY < 0 ? 1 : -1)
    }

    func eject() {
        guard canEject, let card = file.frontCard else { return }
        var jack: Int?
        boardModel.apply { b in
            let out = file.eject(from: &b, now: now)
            jack = out?.jack
            return out?.events ?? []
        }
        guard let jack else { return }
        lamps = Lamps()
        say(PunchReadout("EJECTED", "\(card.name) · JACK \(String(format: "%02d", jack + 1)) IS FREE"))
        idleLater(2.2)
    }

    // MARK: Dragging a card

    private func home(for source: Source) -> CGPoint {
        let c = CardSpace.card
        switch source {
        case .tray:
            let r = spots[.tray] ?? .zero
            return CGPoint(x: r.midX - c.width / 2, y: r.midY - c.height / 2)
        case .file:
            let r = spots[.drum] ?? .zero
            return CGPoint(x: r.midX - c.width / 2, y: r.maxY - c.height)
        }
    }

    private var feedOrigin: CGPoint {
        let c = CardSpace.card
        let r = spots[.feed] ?? .zero
        return CGPoint(x: r.midX - c.width / 2, y: r.maxY - c.height - 4)
    }

    private func overFeed(_ origin: CGPoint) -> Bool {
        guard let r = spots[.feed] else { return false }
        let c = CGPoint(x: origin.x + CardSpace.card.width / 2, y: origin.y + CardSpace.card.height / 2)
        return c.x > r.minX - 30 && c.x < r.maxX + 30 && c.y > r.minY - 40 && c.y < r.maxY + 30
    }

    func cardDragChanged(_ card: LineCard, from source: Source, location: CGPoint, start: CGPoint) {
        if drag == nil {
            guard !busy, ghost == nil else { return }
            if source == .file, file.frontCard?.id != card.id {
                drag = Drag(offset: .zero, start: start, ignored: true)
                animate(.timingCurve(0.3, 0.7, 0.3, 1, duration: 0.35)) { file.bringToFront(card.id) }
                sound.play(.flip)
                return
            }
            let origin = home(for: source)
            drag = Drag(offset: CGVector(dx: origin.x - start.x, dy: origin.y - start.y), start: start)
            ghost = Ghost(card: card, source: source, origin: origin)
        }
        guard var d = drag, !d.ignored, var g = ghost else { return }
        if !d.moved && location.distance(to: d.start) > 4 { d.moved = true }
        drag = d
        g.origin = CGPoint(x: location.x + d.offset.dx, y: location.y + d.offset.dy)
        ghost = g
        let hot = overFeed(g.origin)
        if hot != feedHot { feedHot = hot }
    }

    func cardDragEnded() {
        guard let d = drag else { return }
        drag = nil
        feedHot = false
        guard !d.ignored, let g = ghost else { return }
        // Dropping it on the feed punches it. A plain click on the card in the OUT tray does too.
        if overFeed(g.origin) || (!d.moved && g.source == .tray) {
            busy = true
            Task { await punch(g) }
        } else {
            Task { await sendHome(g) }
        }
    }

    /// Keyboard and VoiceOver: punch the card in the tray, or the front card of the Rolodex.
    func punchWithoutDragging(_ source: Source) {
        guard !busy, ghost == nil else { return }
        guard let card = source == .tray ? file.tray : file.frontCard else { return }
        busy = true
        let g = Ghost(card: card, source: source, origin: home(for: source))
        ghost = g
        Task { await punch(g) }
    }

    private func sendHome(_ g: Ghost) async {
        animate(.easeOut(duration: 0.25)) {
            ghost?.origin = home(for: g.source)
            ghost?.lifted = false
        }
        await pause(0.26)
        ghost = nil
    }

    // MARK: The punch

    /// The card slides in, gets read, and either joins the board or comes back out.
    private func punch(_ g: Ghost) async {
        let card = g.card
        let above = feedOrigin
        animate(.easeOut(duration: 0.18)) {
            ghost?.origin = above
            ghost?.lifted = false
        }
        await pause(0.2)

        ghost?.inSlot = true
        animate(.timingCurve(0.5, 0, 0.8, 0.4, duration: 0.55)) {
            ghost?.origin = CGPoint(x: above.x, y: above.y + CardSpace.card.height + 12)
        }
        sound.play(.cardIn)
        lamps = Lamps(read: .blink)
        say(PunchReadout("READING", String(repeating: "▯", count: 8)))
        await pause(0.56)
        for i in 1...8 {
            readout.sub = String(repeating: "▮", count: i) + String(repeating: "▯", count: 8 - i) + "  " + card.name
            sound.play(.chunk)
            await pause(0.14)
        }
        lamps.read = .off

        // Back up out of the slot either way.
        animate(.easeOut(duration: 0.35)) { ghost?.origin = above }
        await pause(0.36)
        ghost?.inSlot = false

        var result: PunchResult?
        // Animated, so the Rolodex turns to the card while it flies back in.
        animate(.timingCurve(0.3, 0.7, 0.3, 1, duration: 0.35)) {
            boardModel.apply { b in
                let out = file.punch(card.id, into: &b, now: now)
                result = out?.result
                return out?.events ?? []
            }
        }
        guard let result else {
            ghost = nil
            busy = false
            return
        }

        if case .accepted(let jack) = result {
            lamps = Lamps(ok: .on)
            say(result.readout(name: card.name))
            sound.play(.accept)
            boardModel.flashArrival(jack)
            // File the card: it flies into the Rolodex.
            animate(.timingCurve(0.3, 0.7, 0.3, 1, duration: 0.45)) {
                ghost?.origin = home(for: .file)
            }
            await pause(0.46)
            ghost = nil
            idleLater(2.6)
        } else {
            lamps = Lamps(err: .on)
            say(result.readout(name: card.name))
            sound.play(.deny)
            await sendHome(g)
            idleLater(2.4)
        }
        busy = false
    }
}
