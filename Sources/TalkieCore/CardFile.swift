import Foundation

/// Two lines on the punch's LCD.
public struct PunchReadout: Equatable, Sendable {
    public var big: String
    public var sub: String

    public init(_ big: String, _ sub: String) {
        self.big = big
        self.sub = sub
    }
}

/// What checking a code gives you.
public enum CodeCheck: Equatable, Sendable {
    /// A fresh line card, now waiting in the OUT tray.
    case issued(LineCard)
    case empty
    /// There's already a card in the OUT tray.
    case takeYourCard
    case ownCode
    case alreadyUsed
    case unknown

    public var readout: PunchReadout {
        switch self {
        case .issued: return PunchReadout("CARD ISSUED", "DRAG IT TO THE SLOT")
        case .empty: return PunchReadout("ENTER A CODE", "LIKE TLK-ZOE7")
        case .takeYourCard: return PunchReadout("TAKE YOUR CARD", "IT'S IN THE OUT TRAY")
        case .ownCode: return PunchReadout("YOUR OWN CODE", "SEND IT TO A FRIEND")
        case .alreadyUsed: return PunchReadout("ALREADY USED", "EACH CODE WORKS ONCE")
        case .unknown: return PunchReadout("UNKNOWN CODE", "CHECK IT AND TRY AGAIN")
        }
    }
}

/// What the punch makes of a card once it has read it.
public enum PunchResult: Equatable, Sendable {
    case accepted(jack: Int)
    case onBoard(jack: Int)
    case boardFull

    public func readout(name: String) -> PunchReadout {
        switch self {
        case .accepted(let jack): return PunchReadout("ACCEPTED", "\(name) · JACK \(Self.pad(jack))")
        case .onBoard(let jack): return PunchReadout("ON BOARD", "ALREADY ON JACK \(Self.pad(jack))")
        case .boardFull: return PunchReadout("BOARD FULL", "EJECT SOMEONE FIRST")
        }
    }

    static func pad(_ jack: Int) -> String { String(format: "%02d", jack + 1) }
}

/// The card file: your code, the OUT tray and the Rolodex. Which jack a card is on is the board's
/// business, so anything that changes the board takes it as an argument.
public struct CardFile: Equatable, Sendable {
    public let myCode: String
    /// The Rolodex, in order. Every friend you have ever added.
    public private(set) var cards: [LineCard]
    /// Index of the card at the front of the Rolodex.
    public private(set) var front = 0
    /// A card that's been issued but not punched yet.
    public private(set) var tray: LineCard?
    public private(set) var usedCodes: Set<String> = []

    public init(myCode: String = "TLK-7Q4F", cards: [LineCard] = LineCard.samples) {
        self.myCode = myCode
        self.cards = cards
    }

    public var frontCard: LineCard? { cards.isEmpty ? nil : cards[front] }

    public func card(_ id: Int) -> LineCard? {
        if tray?.id == id { return tray }
        return cards.first { $0.id == id }
    }

    /// How far back a card sits behind the front one: 0 is the front card.
    public func depth(of id: Int) -> Int? {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return nil }
        return (i - front + cards.count) % cards.count
    }

    /// "01 / 10"
    public var counter: String {
        String(format: "%02d / %02d", cards.isEmpty ? 0 : front + 1, cards.count)
    }

    // MARK: The Rolodex

    public mutating func turn(_ step: Int) {
        guard !cards.isEmpty else { return }
        front = ((front + step) % cards.count + cards.count) % cards.count
    }

    public mutating func bringToFront(_ id: Int) {
        if let i = cards.firstIndex(where: { $0.id == id }) { front = i }
    }

    public func hint(on board: Switchboard) -> String {
        guard let card = frontCard else { return "Check a friend's code to get their line card." }
        if let jack = board.jack(of: card.id) {
            return "\(card.name) is on jack \(PunchResult.pad(jack)). Eject frees the jack; the card stays here."
        }
        return "Drag \(card.name)'s card into the punch to put them back on your board."
    }

    // MARK: Codes

    /// The punch has looked the code up (`invite` is what it found, if anything); issue the card or say why not.
    public mutating func issue(code: String, invite: Invite?, on date: Date) -> CodeCheck {
        if tray != nil { return .takeYourCard }
        if code == myCode { return .ownCode }
        if usedCodes.contains(code) { return .alreadyUsed }
        guard let invite else { return .unknown }
        usedCodes.insert(code)
        let id = (cards.map(\.id).max() ?? 0) + 1
        let card = LineCard(friend: Friend(id: id, name: invite.name, online: invite.online), code: code, added: date)
        tray = card
        return .issued(card)
    }

    // MARK: The punch

    /// Reads a card (from the tray or the Rolodex) and, if there's a free jack, puts the friend on the board.
    public mutating func punch(_ id: Int, into board: inout Switchboard, now: TimeInterval) -> (result: PunchResult, events: [BoardEvent])? {
        guard let card = card(id) else { return nil }
        if let jack = board.jack(of: id) { return (.onBoard(jack: jack), []) }
        guard let jack = board.freeJack else { return (.boardFull, []) }
        let events = board.addFriend(card.friend, at: jack, now: now)
        if tray?.id == id {
            tray = nil
            // A new card files in at the front.
            cards.insert(card, at: cards.isEmpty ? 0 : front)
        } else {
            bringToFront(id)
        }
        return (.accepted(jack: jack), events)
    }

    /// Takes the front card's friend off the board. The card stays in the Rolodex.
    public mutating func eject(from board: inout Switchboard, now: TimeInterval) -> (jack: Int, events: [BoardEvent])? {
        guard let card = frontCard, let jack = board.jack(of: card.id) else { return nil }
        // Keep what the board knew about them (presence) on the card.
        if let latest = board.friend(jack) { cards[front].friend = latest }
        return (jack, board.removeFriend(at: jack, now: now))
    }
}
