import Foundation

public enum CordID: Int, CaseIterable, Hashable, Sendable {
    case a = 0, b = 1
    public var label: String { self == .a ? "A" : "B" }
}

public enum LineStatus: Equatable, Sendable {
    /// Plugged in, the line is being set up.
    case connecting
    case open
    /// The friend is on do not disturb. The cord stays in and the line opens when they switch it off.
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
    case off, blink, on, tx, rx, dnd
}

/// Things the app should react to with a sound, a haptic or the mic.
public enum BoardEvent: Equatable, Sendable {
    case plugged, unplugged, lineOpened, lineClosed, denied, over, keyClick, click, buzz, micDrop, micStow
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

public struct Flags: Equatable, Sendable {
    public var a = false, b = false, tx = false, rx = false, dnd = false
    public var effect: String?
}

/// The rules of the board. Time is passed in, so it's deterministic and testable.
public struct Switchboard: Equatable, Sendable {
    public static let connectDelay: TimeInterval = 0.75
    public static let replyDelay: TimeInterval = 0.9
    public static let replyLength: TimeInterval = 1.7
    public static let inviteCode = "TLK-7Q4F"

    public private(set) var friends: [Friend?]
    public private(set) var patches: [CordID: Patch] = [:]
    /// Lines a friend opened into your board (jack -> since).
    public private(set) var incoming: [Int: TimeInterval] = [:]
    public private(set) var talking = false
    public private(set) var friendTalking: Set<Int> = []
    /// Friends who muted you. Private: nothing on your board changes because of it.
    public private(set) var mutedYou: Set<Int> = []
    /// Simulated replies: when each friend will talk back.
    public private(set) var replies: [Int: ClosedRange<TimeInterval>] = [:]
    public private(set) var buzzing: [Int: TimeInterval] = [:]
    public private(set) var effect: Effect = .off
    public private(set) var doNotDisturb = false
    public private(set) var message: Message?
    /// The friend you last patched or who last patched you; they're the one who answers back.
    public private(set) var focus: Int?

    public init(friends: [Friend?] = Friend.samples) {
        self.friends = friends
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

    public func isLineOpen(_ jack: Int) -> Bool {
        if incoming[jack] != nil { return true }
        guard let c = cord(at: jack) else { return false }
        return patches[c]?.status == .open
    }

    /// Jacks with an open line, cords first, then incoming.
    public var openJacks: [Int] {
        let corded = CordID.allCases.compactMap { c -> Int? in
            guard let p = patches[c], p.status == .open else { return nil }
            return p.jack
        }
        return corded + incoming.keys.sorted()
    }

    /// True while a line is open or opening. The floating mic is out while this is true.
    public var isLive: Bool {
        !incoming.isEmpty || patches.values.contains { $0.status == .open || $0.status == .connecting }
    }

    public var liveNames: [String] {
        let corded = CordID.allCases.compactMap { c -> String? in
            guard let p = patches[c], p.status == .open || p.status == .connecting else { return nil }
            return friend(p.jack)?.name
        }
        return corded + incoming.keys.sorted().compactMap { friend($0)?.name }
    }

    // MARK: Cords

    public mutating func patch(_ cord: CordID, into jack: Int, now: TimeInterval) -> [BoardEvent] {
        guard friends.indices.contains(jack) else { return [] }
        guard let f = friends[jack] else {
            say("+ ADD", "INVITE CODE \(Self.inviteCode)", now: now)
            return [.denied]
        }
        if let other = self.cord(at: jack), other != cord {
            say("BUSY", "CORD \(other.label) IS IN \(f.name)", now: now)
            return [.denied]
        }
        let wasLive = isLive
        if let old = patches.removeValue(forKey: cord) { clearFriend(old.jack) }
        let status: LineStatus
        var since = now
        if !f.online {
            status = .offline
        } else if f.doNotDisturb {
            status = .waitingDND
        } else if let incomingSince = incoming.removeValue(forKey: jack) {
            // They already patched into you; your cord takes over the open line.
            status = .open
            since = incomingSince
        } else {
            status = .connecting
        }
        patches[cord] = Patch(jack: jack, status: status, since: since)
        focus = jack
        return [.plugged] + liveTransition(wasLive)
    }

    public mutating func unpatch(_ cord: CordID, now: TimeInterval) -> [BoardEvent] {
        guard let old = patches.removeValue(forKey: cord) else { return [] }
        let wasLive = isLive || old.status == .open || old.status == .connecting
        clearFriend(old.jack)
        return [.unplugged] + liveTransition(wasLive)
    }

    /// Tapping a jack: pull its cord, hang up an incoming line, or send the next free cord into it.
    /// Returns the cord that is now flying in, if any.
    public mutating func tapJack(_ jack: Int, now: TimeInterval) -> (cord: CordID?, events: [BoardEvent]) {
        if let c = cord(at: jack) { return (nil, unpatch(c, now: now)) }
        if incoming[jack] != nil { return (nil, hangUp(jack, now: now)) }
        guard friend(jack) != nil else {
            say("+ ADD", "INVITE CODE \(Self.inviteCode)", now: now)
            return (nil, [.denied])
        }
        guard let free = freeCord else {
            say("NO CORD", "PULL A PLUG FIRST", now: now)
            return (nil, [.denied])
        }
        return (free, patch(free, into: jack, now: now))
    }

    public mutating func hangUp(_ jack: Int, now: TimeInterval) -> [BoardEvent] {
        guard incoming.removeValue(forKey: jack) != nil else { return [] }
        let wasLive = true
        clearFriend(jack)
        return [.lineClosed] + liveTransition(wasLive)
    }

    // MARK: Time

    public mutating func tick(now: TimeInterval) -> [BoardEvent] {
        var events: [BoardEvent] = []
        for (c, p) in patches where p.status == .connecting && now - p.since >= Self.connectDelay {
            patches[c]?.status = .open
            patches[c]?.since = now
            events.append(.lineOpened)
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
        return events
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

    public mutating func setDoNotDisturb(_ on: Bool, now: TimeInterval) -> [BoardEvent] {
        doNotDisturb = on
        say(on ? "DND ON" : "DND OFF", on ? "PATCHES TO YOU WILL WAIT" : "YOUR LINE IS OPEN AGAIN", now: now)
        return [.click]
    }

    // MARK: The other end (simulated until there's a network)

    public mutating func friendPatchesIn(_ jack: Int, now: TimeInterval) -> [BoardEvent] {
        guard let f = friend(jack), f.online, cord(at: jack) == nil, incoming[jack] == nil else { return [] }
        if doNotDisturb {
            say(f.name, "TRIED TO PATCH IN · DND", now: now)
            return []
        }
        let wasLive = isLive
        incoming[jack] = now
        focus = jack
        say(f.name, "PATCHED IN", now: now)
        return [.lineOpened] + liveTransition(wasLive)
    }

    public mutating func setFriendDoNotDisturb(_ jack: Int, _ on: Bool, now: TimeInterval) -> [BoardEvent] {
        guard var f = friend(jack), f.online, f.doNotDisturb != on else { return [] }
        let wasLive = isLive
        f.doNotDisturb = on
        friends[jack] = f
        var events: [BoardEvent] = []
        if let c = cord(at: jack) {
            if on {
                clearFriend(jack)
                patches[c]?.status = .waitingDND
                events.append(.lineClosed)
            } else if patches[c]?.status == .waitingDND {
                patches[c]?.status = .connecting
                patches[c]?.since = now
            }
        }
        if on, incoming.removeValue(forKey: jack) != nil {
            clearFriend(jack)
            events.append(.lineClosed)
        }
        return events + liveTransition(wasLive)
    }

    public mutating func friendTalks(_ jack: Int, for seconds: TimeInterval, now: TimeInterval) {
        guard isLineOpen(jack) else { return }
        replies[jack] = now...(now + seconds)
    }

    public mutating func setMuted(by jack: Int, _ muted: Bool) {
        if muted { mutedYou.insert(jack) } else { mutedYou.remove(jack) }
    }

    // MARK: What the board shows

    public func lamp(for jack: Int) -> Lamp {
        if let c = cord(at: jack), let p = patches[c] {
            switch p.status {
            case .connecting: return .blink
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
            rx: openJacks.contains { friendTalking.contains($0) },
            dnd: doNotDisturb,
            effect: effect == .off ? nil : effect.title
        )
    }

    public func readout(now: TimeInterval) -> Readout {
        if let m = message { return Readout(big: m.big, sub: m.sub) }
        let corded = CordID.allCases.compactMap { c in patches[c].map { (cord: c, patch: $0) } }
        let name: (Int) -> String = { self.friend($0)?.name ?? "?" }
        let names = corded.map { name($0.patch.jack) } + incoming.keys.sorted().map(name)
        let big = names.isEmpty ? "IDLE" : names.joined(separator: "+")
        let open = openJacks
        let rx = open.filter { friendTalking.contains($0) }.map(name)
        let held = corded.filter { $0.patch.status == .waitingDND }.map { name($0.patch.jack) }

        let sub: String
        if !rx.isEmpty {
            sub = rx.joined(separator: " + ") + " TALKING"
        } else if talking && !open.isEmpty {
            sub = "TALKING TO " + open.map(name).joined(separator: " + ")
        } else if talking {
            sub = "NO OPEN LINE · MONITOR ONLY"
        } else if corded.contains(where: { $0.patch.status == .connecting }) {
            sub = "PATCHING IN…"
        } else if open.count == 1 {
            if let line = corded.first(where: { $0.patch.status == .open }) {
                sub = "LINE \(line.cord.label) · OPEN · \(Self.clock(now - line.patch.since))"
                    + (held.isEmpty ? "" : " · " + held.joined(separator: " + ") + " DND")
            } else {
                sub = "INCOMING · OPEN · \(Self.clock(now - (incoming[open[0]] ?? now)))"
            }
        } else if open.count > 1 {
            sub = "\(open.count) LINES · CONFERENCE"
        } else if !held.isEmpty {
            sub = held.joined(separator: " + ") + " · DO NOT DISTURB · PATCH WAITS"
        } else if let first = corded.first {
            sub = name(first.patch.jack) + " IS AWAY"
        } else {
            sub = "DRAG A PLUG INTO A JACK"
        }
        return Readout(big: big, sub: sub)
    }

    public mutating func say(_ big: String, _ sub: String, now: TimeInterval, for seconds: TimeInterval = 1.9) {
        message = Message(big: big, sub: sub, until: now + seconds)
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

    private func liveTransition(_ wasLive: Bool) -> [BoardEvent] {
        if !wasLive && isLive { return [.micDrop] }
        if wasLive && !isLive { return [.micStow] }
        return []
    }
}
