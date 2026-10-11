import Foundation

/// A friend's line card. You get one by checking their code, punch it to put them on your board,
/// and keep it in the Rolodex afterwards, on the board or not.
public struct LineCard: Equatable, Identifiable, Sendable {
    /// The friend on the card. Its id is the card's id.
    public var friend: Friend
    /// The code that issued the card. Sample cards have none.
    public var code: String?
    public var added: Date

    public init(friend: Friend, code: String? = nil, added: Date) {
        self.friend = friend
        self.code = code
        self.added = added
    }

    public var id: Int { friend.id }
    public var name: String { friend.name }

    /// "ADDED 12 MAR · TLK-ZOE7"
    public var meta: String {
        "ADDED " + Self.stamp(added) + (code.map { " · " + $0 } ?? "")
    }

    /// The card's own hole pattern, from the friend's name: a little fingerprint.
    public var holes: [Bool] { Self.holes(for: name) }

    /// Two rows of 14. Matches `holesFor` in the prototype, so a card looks the same in both.
    public static func holes(for name: String) -> [Bool] {
        var h: UInt32 = 2_166_136_261
        for unit in name.utf16 {
            h ^= UInt32(unit)
            h = h &* 16_777_619
        }
        let g = (h ^ (h >> 15)) &* 2_246_822_507
        return (0..<28).map { i in
            ((i < 14 ? h : g) >> UInt32(i % 14 * 2)) & 1 == 1
        }
    }

    private static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    /// "12 MAR", the way the punch stamps it.
    public static func stamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.day, .month], from: date)
        return String(format: "%02d ", parts.day ?? 1) + months[((parts.month ?? 1) - 1) % 12]
    }
}

public extension LineCard {
    /// The prototype's Rolodex: seven friends on the board, three from the past.
    static let samples: [LineCard] = {
        func card(_ id: Int, _ name: String, online: Bool = true, dnd: Bool = false, _ day: Int, _ month: Int) -> LineCard {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            // Noon UTC, so the stamp reads the same day almost everywhere.
            let date = utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
            return LineCard(friend: Friend(id: id, name: name, online: online, doNotDisturb: dnd), added: date)
        }
        return [
            card(1, "MAYA", 12, 3),
            card(2, "OTTO", 30, 3),
            card(3, "JUN", online: false, 4, 4),
            card(4, "RUBY", dnd: true, 21, 4),
            card(5, "LEO", online: false, 9, 6),
            card(6, "INÈS", 15, 8),
            card(7, "KAI", 2, 9),
            card(8, "NICO", 2, 5),
            card(9, "BEA", online: false, 19, 1),
            card(10, "TOM", 7, 7)
        ]
    }()
}

/// Invite codes look like `TLK-7Q4F`.
public enum InviteCode {
    public static let prefix = "TLK-"

    /// Tidies what someone typed or pasted: case, spaces, dashes and the prefix are all optional.
    /// Returns nil when nothing is left.
    public static func normalize(_ raw: String) -> String? {
        var body = String(raw.uppercased().unicodeScalars.filter { ("A"..."Z").contains($0) || ("0"..."9").contains($0) })
        if body.hasPrefix("TLK") { body.removeFirst(3) }
        guard !body.isEmpty else { return nil }
        return prefix + body.prefix(4)
    }
}

/// What a code turns out to be, according to whoever hands them out (the server, later).
public struct Invite: Equatable, Sendable {
    public var code: String
    public var name: String
    public var online: Bool

    public init(code: String, name: String, online: Bool = true) {
        self.code = code
        self.name = name
        self.online = online
    }

    /// Codes the simulated friends could have sent you.
    public static let samples: [String: Invite] = [
        "TLK-ZOE7": Invite(code: "TLK-ZOE7", name: "ZOE"),
        "TLK-PIP3": Invite(code: "TLK-PIP3", name: "PIP")
    ]
}
