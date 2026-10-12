import Foundation

public enum CordID: Int, CaseIterable, Hashable, Sendable {
    case a = 0, b = 1
    public var label: String { self == .a ? "A" : "B" }
}

public enum LineStatus: Equatable, Sendable {
    /// Plugged in and knocking: the line opens if they let you in.
    case knocking
    case open
    /// The friend is on do not disturb. The cord stays in and knocks when they switch it off.
    case waitingDND
    /// The friend's Talkie isn't running.
    case offline
}

public struct Patch: Equatable, Sendable {
    public var jack: Int
    public var status: LineStatus
    public var since: TimeInterval
}

public enum Lamp: Equatable, Sendable {
    /// `blink` is your knock going out; `knock` is a friend knocking on you.
    case off, blink, knock, on, tx, rx, dnd
}

/// Things the app should react to with a sound, a haptic or the mic.
public enum BoardEvent: Equatable, Sendable {
    case plugged, unplugged, lineOpened, lineClosed, denied, over, keyClick, click, buzz, micDrop, micStow
    /// A friend is knocking on you.
    case knockIn
    /// You knocked on a friend.
    case knockOut
    /// The board is waiting for a friend's code: put the cursor in the code field.
    case addFriend
}

public struct Message: Equatable, Sendable {
    public var big: String
    public var sub: String
    public var until: TimeInterval
}

public struct Readout: Equatable, Sendable {
    public var big: String
    public var sub: String
}

/// The board is taking a friend's code.
public struct Adding: Equatable, Sendable {
    /// The free jack you clicked. Nil means the first free one.
    public var jack: Int?
}

public struct Flags: Equatable, Sendable {
    public var a = false, b = false, tx = false, rx = false, dnd = false
    public var effect: String?
}

/// The rules of the board. Time is passed in, so it's deterministic and testable.
///
/// Every line starts with a knock. Plug a cord into a friend's jack and they hear a knock; if they
/// let you in, the line opens. If they decline, nothing is sent: on your side it's the same as no
/// answer, and after `knockTimeout` the cord drops out.
public struct Switchboard: Equatable, Sendable {
    /// How long a knock waits for an answer.
    public static let knockTimeout: TimeInterval = 20
    public static let replyDelay: TimeInterval = 0.9
    public static let replyLength: TimeInterval = 1.7

    public private(set) var friends: [Friend?]
    /// Your code, for friends to add you with.
    public let myCode: String
    /// Set while the board is taking a friend's code.
    public private(set) var adding: Adding?
    public private(set) var patches: [CordID: Patch] = [:]
    /// Lines a friend opened into your board, once you let them in (jack -> since).
    public private(set) var incoming: [Int: TimeInterval] = [:]
    /// Friends knocking on you right now (jack -> since).
    public private(set) var knocks: [Int: TimeInterval] = [:]
    /// Knocks that came while you were on do not disturb. They knock again when you switch it off.
    public private(set) var heldKnocks: Set<Int> = []
    public private(set) var talking = false
    public private(set) var friendTalking: Set<Int> = []
    /// Friends who muted you. Private: nothing on your board changes because of it.
    public private(set) var mutedYou: Set<Int> = []
    /// Friends you muted, by friend id. Only changes what you hear: nothing is sent to them,
    /// and it outlasts the call so they stay muted next time.
    public private(set) var muted: Set<Int> = []
    /// Simulated replies: when each friend will talk back.
    public private(set) var replies: [Int: ClosedRange<TimeInterval>] = [:]
    public private(set) var buzzing: [Int: TimeInterval] = [:]
    public private(set) var effect: Effect = .off
    public private(set) var doNotDisturb = false
    public private(set) var message: Message?
    /// The friend you last patched or who last patched you; they're the one who answers back.
    public private(set) var focus: Int?

    public init(friends: [Friend?] = Friend.samples, myCode: String = "TLK-7Q4F") {
        self.friends = friends
        self.myCode = myCode
    }

    // MARK: Lookups

    public func friend(_ jack: Int) -> Friend? {
        friends.indices.contains(jack) ? friends[jack] : nil
    }

    public func cord(at jack: Int) -> CordID? {
        CordID.allCases.first { patches[$0]?.jack == jack }
    }

    public var freeCord: CordID? {
        CordID.allCases.first { patches[$0] == nil }
    }

    /// The first jack with nobody on it.
    public var freeJack: Int? {
        friends.firstIndex { $0 == nil }
    }

    /// The jack a friend is on, by their id.
    public func jack(of friendID: Int) -> Int? {
        friends.firstIndex { $0?.id == friendID }
    }

    public func isLineOpen(_ jack: Int) -> Bool {
        if incoming[jack] != nil { return true }
        guard let c = cord(at: jack) else { return false }
        return patches[c]?.status == .open
    }

    /// When the line on a jack opened, if it's open.
    public func openedAt(_ jack: Int) -> TimeInterval? {
        if let since = incoming[jack] { return since }
        guard let c = cord(at: jack), let p = patches[c], p.status == .open else { return nil }
        return p.since
    }

    /// Jacks with an open line, cords first, then incoming.
    public var openJacks: [Int] {
        let corded = CordID.allCases.compactMap { c -> Int? in
            guard let p = patches[c], p.status == .open else { return nil }
            return p.jack
        }
        return corded + incoming.keys.sorted()
    }

    /// True while a line is open.
    public var isLive: Bool {
        !openJacks.isEmpty
    }

    /// Who's knocking on you, first knock first.
    public var knockers: [Int] {
        knocks.sorted { ($0.value, $0.key) < ($1.value, $1.key) }.map(\.key)
    }

    /// Your knocks still waiting for an answer.
    public var knockingOut: [Int] {
        CordID.allCases.compactMap { c in patches[c].flatMap { $0.status == .knocking ? $0.jack : nil } }
    }

    /// The floating mic is out while a line is open or someone is knocking on you.
    public var wantsMic: Bool {
        isLive || !knocks.isEmpty
    }

    /// Everyone on an open line with you.
    public var liveNames: [String] {
        openJacks.compactMap { friend($0)?.name }
    }

    // MARK: Cords

    /// Plugging into a friend's jack knocks. Plugging into a jack that's knocking on you lets them in.
    public mutating func patch(_ cord: CordID, into jack: Int, now: TimeInterval) -> [BoardEvent] {
        guard friends.indices.contains(jack) else { return [] }
        guard let f = friends[jack] else {
            say("FREE JACK", "CLICK IT TO ADD A FRIEND", now: now)
            return [.denied]
        }
        if let other = self.cord(at: jack), other != cord {
            say("BUSY", "CORD \(other.label) IS IN \(f.name)", now: now)
            return [.denied]
        }
        let was = wantsMic
        if let old = patches.removeValue(forKey: cord) { clearFriend(old.jack) }
        var events: [BoardEvent] = [.plugged]
        let status: LineStatus
        var since = now
        if let incomingSince = incoming.removeValue(forKey: jack) {
            // You already let them in; your cord takes over the open line.
            status = .open
            since = incomingSince
        } else if knocks.removeValue(forKey: jack) != nil || heldKnocks.remove(jack) != nil {
            // They were knocking: plugging in lets them in.
            status = .open
            say(f.name, "LET IN · LINE OPEN", now: now)
            events.append(.lineOpened)
        } else if !f.online {
            status = .offline
        } else if f.doNotDisturb {
            status = .waitingDND
        } else {
            status = .knocking
            events.append(.knockOut)
        }
        patches[cord] = Patch(jack: jack, status: status, since: since)
        focus = jack
        return events + micTransition(was)
    }

    public mutating func unpatch(_ cord: CordID, now: TimeInterval) -> [BoardEvent] {
        let was = wantsMic
        guard let old = patches.removeValue(forKey: cord) else { return [] }
        clearFriend(old.jack)
        return [.unplugged] + micTransition(was)
    }

    /// Tapping a jack: pull its cord, hang up a line they opened, let a knock in, or send the next free cord into it.
    /// Returns the cord that is now flying in, if any.
    public mutating func tapJack(_ jack: Int, now: TimeInterval) -> (cord: CordID?, events: [BoardEvent]) {
        if let c = cord(at: jack) { return (nil, unpatch(c, now: now)) }
        if incoming[jack] != nil { return (nil, hangUp(jack, now: now)) }
        if knocks[jack] != nil || heldKnocks.contains(jack) { return (nil, letIn(jack, now: now)) }
        guard friend(jack) != nil else { return (nil, startAdding(at: jack)) }
        guard let free = freeCord else {
            say("NO CORD", "PULL A PLUG FIRST", now: now)
            return (nil, [.denied])
        }
        return (free, patch(free, into: jack, now: now))
    }

    public mutating func hangUp(_ jack: Int, now: TimeInterval) -> [BoardEvent] {
        let was = wantsMic
        guard incoming.removeValue(forKey: jack) != nil else { return [] }
        clearFriend(jack)
        return [.lineClosed] + micTransition(was)
    }

    /// Closes every line and stops every knock: cords out, incoming lines hung up.
    public mutating func hangUpAll(now: TimeInterval) -> [BoardEvent] {
        let was = wantsMic
        var events: [BoardEvent] = []
        for c in CordID.allCases where patches[c] != nil {
            let old = patches.removeValue(forKey: c)!
            clearFriend(old.jack)
            if !events.contains(.unplugged) { events.append(.unplugged) }
        }
        for jack in incoming.keys {
            incoming[jack] = nil
            clearFriend(jack)
        }
        knocks.removeAll()
        if was && !events.contains(.unplugged) { events.append(.lineClosed) }
        return events + micTransition(was)
    }

    // MARK: Knocks

    /// The friend you knocked on let you in.
    public mutating func friendAnswers(_ jack: Int, now: TimeInterval) -> [BoardEvent] {
        guard let c = cord(at: jack), patches[c]?.status == .knocking else { return [] }
        let was = wantsMic
        patches[c]?.status = .open
        patches[c]?.since = now
        if let f = friend(jack) { say(f.name, "LET YOU IN · LINE \(c.label) OPEN", now: now) }
        return [.lineOpened] + micTransition(was)
    }

    /// A friend on your board knocks. On do not disturb it waits until you switch it off.
    public mutating func friendKnocks(_ jack: Int, now: TimeInterval) -> [BoardEvent] {
        guard let f = friend(jack), f.online, incoming[jack] == nil, knocks[jack] == nil else { return [] }
        if let c = cord(at: jack) {
            // You're both knocking on each other: that's a yes from both of you.
            guard patches[c]?.status == .knocking else { return [] }
            return friendAnswers(jack, now: now)
        }
        if doNotDisturb {
            heldKnocks.insert(jack)
            say(f.name, "KNOCKED · WAITING FOR DND OFF", now: now)
            return []
        }
        let was = wantsMic
        knocks[jack] = now
        return [.knockIn] + micTransition(was)
    }

    /// Let a knocking friend in: the line opens and you can talk straight away.
    public mutating func letIn(_ jack: Int, now: TimeInterval) -> [BoardEvent] {
        let was = wantsMic
        guard knocks.removeValue(forKey: jack) != nil || heldKnocks.remove(jack) != nil, let f = friend(jack) else { return [] }
        incoming[jack] = now
        focus = jack
        say(f.name, "LET IN · LINE OPEN", now: now)
        return [.lineOpened] + micTransition(was)
    }

    /// Turn a knock away. Nothing is sent: on their side it looks like nobody answered.
    public mutating func decline(_ jack: Int, now: TimeInterval) -> [BoardEvent] {
        let was = wantsMic
        guard knocks.removeValue(forKey: jack) != nil || heldKnocks.remove(jack) != nil else { return [] }
        if let f = friend(jack) { say(f.name, "DECLINED · THEY WON'T KNOW", now: now) }
        return [.click] + micTransition(was)
    }

    /// Someone who isn't on your board (an ejected friend, say) tries to knock. Only the eight on your
    /// board can knock, so nothing rings; you get a note, and adding their code lets them in.
    /// On their side you just don't answer.
    public mutating func offBoardKnock(from name: String, now: TimeInterval) -> [BoardEvent] {
        say(name, "TRIED TO KNOCK · ADD THEM TO LET IN", now: now, for: 3)
        return [.click]
    }

    // MARK: Who's on the board

    /// Get ready for a friend's code. They'll go on `jack` if it's free, otherwise the first free jack.
    public mutating func startAdding(at jack: Int? = nil) -> [BoardEvent] {
        let target = jack.flatMap { friends.indices.contains($0) && friends[$0] == nil ? $0 : nil }
        adding = Adding(jack: target)
        message = nil
        return [.addFriend]
    }

    public mutating func stopAdding() {
        adding = nil
    }

    /// Where the next friend you add will go: the jack you clicked, or the first free one.
    public var addingJack: Int? {
        if let jack = adding?.jack, friends[jack] == nil { return jack }
        return freeJack
    }

    /// A friend's code, typed or pasted. `lookup` asks whoever hands out codes who it belongs to.
    /// Adding someone ends add mode; anything else leaves it open to try again.
    public mutating func enterCode(_ raw: String, now: TimeInterval, lookup: (String) -> Invite?) -> (result: CodeResult, events: [BoardEvent]) {
        func refuse(_ result: CodeResult, _ big: String, _ sub: String) -> (result: CodeResult, events: [BoardEvent]) {
            say(big, sub, now: now, for: 2.4)
            return (result, [.denied])
        }
        guard let code = InviteCode.normalize(raw) else {
            return refuse(.empty, "ENTER A CODE", "LIKE TLK-ZOE7")
        }
        if code == myCode { return refuse(.ownCode, "YOUR OWN CODE", "SEND IT TO A FRIEND") }
        guard let invite = lookup(code) else { return refuse(.unknown, "UNKNOWN CODE", "CHECK IT AND TRY AGAIN") }
        let name = invite.friend.name
        if let jack = self.jack(of: invite.friend.id) {
            return refuse(.onBoard(jack: jack), name, "ALREADY ON JACK " + Self.pad(jack))
        }
        guard let jack = addingJack else { return refuse(.boardFull, name, "BOARD FULL · EJECT SOMEONE FIRST") }
        adding = nil
        return (.added(jack: jack), addFriend(invite.friend, at: jack, now: now))
    }

    /// Puts a friend on a free jack.
    public mutating func addFriend(_ f: Friend, at jack: Int, now: TimeInterval) -> [BoardEvent] {
        guard friends.indices.contains(jack), friends[jack] == nil, self.jack(of: f.id) == nil else { return [] }
        friends[jack] = f
        say(f.name, "NEW ON JACK " + Self.pad(jack), now: now, for: 2.6)
        return [.plugged]
    }

    /// Ejects whoever is on a jack. Their cord comes out, a line they opened closes and a knock stops.
    /// Their code still works if you want them back.
    public mutating func removeFriend(at jack: Int, now: TimeInterval) -> [BoardEvent] {
        guard let f = friend(jack) else { return [] }
        let was = wantsMic
        var events: [BoardEvent] = []
        if let c = cord(at: jack) { events += unpatch(c, now: now) }
        if incoming[jack] != nil { events += hangUp(jack, now: now) }
        knocks[jack] = nil
        heldKnocks.remove(jack)
        clearFriend(jack)
        if focus == jack { focus = nil }
        friends[jack] = nil
        say("JACK " + Self.pad(jack), "FREE · \(f.name) IS OFF THE BOARD", now: now, for: 2.4)
        events = events.filter { $0 != .micStow && $0 != .micDrop }
        if !events.contains(.unplugged) { events.insert(.unplugged, at: 0) }
        return events + micTransition(was)
    }

    // MARK: Time

    public mutating func tick(now: TimeInterval) -> [BoardEvent] {
        var events: [BoardEvent] = []
        let was = wantsMic
        // Nobody answered (or they declined, which looks the same from here): the cord drops out.
        for (c, p) in patches where p.status == .knocking && now - p.since >= Self.knockTimeout {
            patches[c] = nil
            clearFriend(p.jack)
            say(friend(p.jack)?.name ?? "JACK " + Self.pad(p.jack), "NO ANSWER", now: now, for: 3)
            events.append(.unplugged)
        }
        // A knock you didn't answer stops on its own.
        for (jack, since) in knocks where now - since >= Self.knockTimeout {
            knocks[jack] = nil
            say(friend(jack)?.name ?? "JACK " + Self.pad(jack), "KNOCKED · MISSED", now: now, for: 4)
        }
        if let m = message, now >= m.until { message = nil }
        for (jack, window) in replies {
            if window.contains(now), !friendTalking.contains(jack), isLineOpen(jack) {
                friendTalking.insert(jack)
                events.append(.keyClick)
            }
            if now >= window.upperBound {
                replies[jack] = nil
                if friendTalking.remove(jack) != nil { events.append(.over) }
            }
        }
        for (jack, until) in buzzing where now >= until { buzzing[jack] = nil }
        return events + micTransition(was)
    }

    // MARK: Talking

    public mutating func startTalking(now: TimeInterval) -> [BoardEvent] {
        guard !talking else { return [] }
        talking = true
        return [.keyClick]
    }

    public mutating func stopTalking(now: TimeInterval) -> [BoardEvent] {
        guard talking else { return [] }
        talking = false
        var events: [BoardEvent] = []
        if !openJacks.isEmpty { events.append(.over) }
        // Simulated friend: whoever you're focused on answers, if they heard you.
        if let jack = focus, isLineOpen(jack), !mutedYou.contains(jack), !friendTalking.contains(jack) {
            let start = now + Self.replyDelay
            replies[jack] = start...(start + Self.replyLength)
        }
        return events
    }

    public mutating func cycleEffect(now: TimeInterval) -> [BoardEvent] {
        setEffect(effect.next, now: now)
    }

    public mutating func setEffect(_ e: Effect, now: TimeInterval) -> [BoardEvent] {
        effect = e
        say(e == .off ? "FX OFF" : e.title, e == .off ? e.blurb : "\(e.blurb) · HOLD TO HEAR", now: now, for: 2.2)
        return [.click]
    }

    public mutating func buzz(now: TimeInterval) -> [BoardEvent] {
        let open = openJacks
        guard !open.isEmpty else {
            say("BUZZ", "NO OPEN LINE", now: now)
            return [.denied]
        }
        for jack in open { buzzing[jack] = now + 1.7 }
        say("BUZZ", "BUZZING " + open.compactMap { friend($0)?.name }.joined(separator: " + "), now: now, for: 1.7)
        return [.buzz]
    }

    /// On do not disturb, knocks wait. Switching it off lets them knock.
    public mutating func setDoNotDisturb(_ on: Bool, now: TimeInterval) -> [BoardEvent] {
        let was = wantsMic
        doNotDisturb = on
        say(on ? "DND ON" : "DND OFF", on ? "KNOCKS WILL WAIT" : "YOU CAN BE KNOCKED AGAIN", now: now)
        var events: [BoardEvent] = [.click]
        if on {
            heldKnocks.formUnion(knocks.keys)
            knocks.removeAll()
        } else if !heldKnocks.isEmpty {
            for jack in heldKnocks { knocks[jack] = now }
            heldKnocks.removeAll()
            events.append(.knockIn)
        }
        return events + micTransition(was)
    }

    // MARK: The other end (simulated until there's a network)

    public mutating func setFriendDoNotDisturb(_ jack: Int, _ on: Bool, now: TimeInterval) -> [BoardEvent] {
        guard var f = friend(jack), f.online, f.doNotDisturb != on else { return [] }
        let was = wantsMic
        f.doNotDisturb = on
        friends[jack] = f
        var events: [BoardEvent] = []
        if let c = cord(at: jack) {
            if on {
                if patches[c]?.status == .open { events.append(.lineClosed) }
                clearFriend(jack)
                patches[c]?.status = .waitingDND
            } else if patches[c]?.status == .waitingDND {
                // The cord was waiting: now it knocks.
                patches[c]?.status = .knocking
                patches[c]?.since = now
                events.append(.knockOut)
            }
        }
        if on {
            if incoming.removeValue(forKey: jack) != nil {
                clearFriend(jack)
                events.append(.lineClosed)
            }
            knocks[jack] = nil
        }
        return events + micTransition(was)
    }

    public mutating func friendTalks(_ jack: Int, for seconds: TimeInterval, now: TimeInterval) {
        guard isLineOpen(jack) else { return }
        replies[jack] = now...(now + seconds)
    }

    /// Mute or unmute a friend for yourself.
    public mutating func mute(_ jack: Int, _ on: Bool) {
        guard let f = friend(jack) else { return }
        if on { muted.insert(f.id) } else { muted.remove(f.id) }
    }

    public mutating func setMutedFriends(_ ids: Set<Int>) {
        muted = ids
    }

    public func isMuted(_ jack: Int) -> Bool {
        friend(jack).map { muted.contains($0.id) } ?? false
    }

    /// Who you can hear talking right now: talking, on an open line, and not muted by you.
    public func isHeard(_ jack: Int) -> Bool {
        friendTalking.contains(jack) && isLineOpen(jack) && !isMuted(jack)
    }

    public mutating func setMuted(by jack: Int, _ muted: Bool) {
        if muted { mutedYou.insert(jack) } else { mutedYou.remove(jack) }
    }

    // MARK: What the board shows

    public func lamp(for jack: Int) -> Lamp {
        if knocks[jack] != nil { return .knock }
        if let c = cord(at: jack), let p = patches[c] {
            switch p.status {
            case .knocking: return .blink
            case .waitingDND: return .dnd
            case .offline: return .off
            case .open: break
            }
        } else if incoming[jack] == nil {
            return .off
        }
        // Mute is private, so it never changes the lamp.
        if friendTalking.contains(jack) { return .rx }
        return talking ? .tx : .on
    }

    public var flags: Flags {
        Flags(
            a: patches[.a] != nil,
            b: patches[.b] != nil,
            tx: talking && !openJacks.isEmpty,
            rx: openJacks.contains { isHeard($0) },
            dnd: doNotDisturb,
            effect: effect == .off ? nil : effect.title
        )
    }

    public func readout(now: TimeInterval) -> Readout {
        if let m = message { return Readout(big: m.big, sub: m.sub) }
        if adding != nil {
            guard let jack = addingJack else { return Readout(big: "BOARD FULL", sub: "RIGHT-CLICK A JACK TO EJECT SOMEONE") }
            return Readout(big: "ADD A FRIEND", sub: "JACK \(Self.pad(jack)) · TYPE OR PASTE THEIR CODE")
        }
        let name: (Int) -> String = { self.friend($0)?.name ?? "?" }
        // Someone knocking on you comes first.
        let knocking = knockers
        if !knocking.isEmpty {
            return Readout(big: knocking.map(name).joined(separator: " + "), sub: "KNOCKING · CLICK THE JACK TO LET IN")
        }
        let corded = CordID.allCases.compactMap { c in patches[c].map { (cord: c, patch: $0) } }
        let names = corded.map { name($0.patch.jack) } + incoming.keys.sorted().map(name)
        let big = names.isEmpty ? "READY TO PATCH" : names.joined(separator: " + ")
        let open = openJacks
        let rx = open.filter { isHeard($0) }.map(name)
        let held = corded.filter { $0.patch.status == .waitingDND }.map { name($0.patch.jack) }

        let sub: String
        if !rx.isEmpty {
            sub = rx.joined(separator: " + ") + " TALKING"
        } else if talking && !open.isEmpty {
            sub = "TALKING TO " + open.map(name).joined(separator: " + ")
        } else if talking {
            sub = "NO OPEN LINE · MONITOR ONLY"
        } else if corded.contains(where: { $0.patch.status == .knocking }) {
            sub = "KNOCKING…"
        } else if open.count == 1 {
            if let line = corded.first(where: { $0.patch.status == .open }) {
                sub = "LINE \(line.cord.label) · OPEN · \(Self.clock(now - line.patch.since))"
                    + (held.isEmpty ? "" : " · " + held.joined(separator: " + ") + " DND")
            } else {
                sub = "LET IN · OPEN · \(Self.clock(now - (incoming[open[0]] ?? now)))"
            }
        } else if open.count > 1 {
            let bothCords = corded.filter { $0.patch.status == .open }.count == 2
            sub = bothCords ? "TWO CORDS · THREE PEOPLE" : "\(open.count + 1) PEOPLE ON THE LINE"
        } else if !held.isEmpty {
            sub = held.joined(separator: " + ") + " · DO NOT DISTURB · KNOCK WAITS"
        } else if let first = corded.first {
            sub = name(first.patch.jack) + " IS AWAY"
        } else {
            sub = "PLUG INTO A FRIEND"
        }
        return Readout(big: big, sub: sub)
    }

    public mutating func say(_ big: String, _ sub: String, now: TimeInterval, for seconds: TimeInterval = 1.9) {
        message = Message(big: big, sub: sub, until: now + seconds)
    }

    /// "08" for jack 7: jacks are numbered from 01 on the board.
    public static func pad(_ jack: Int) -> String {
        String(format: "%02d", jack + 1)
    }

    public static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: Helpers

    private mutating func clearFriend(_ jack: Int) {
        friendTalking.remove(jack)
        replies[jack] = nil
        mutedYou.remove(jack)
        buzzing[jack] = nil
    }

    /// The mic drops when a line opens or someone knocks, and winds back up when neither is true.
    private func micTransition(_ was: Bool) -> [BoardEvent] {
        if !was && wantsMic { return [.micDrop] }
        if was && !wantsMic { return [.micStow] }
        return []
    }
}
