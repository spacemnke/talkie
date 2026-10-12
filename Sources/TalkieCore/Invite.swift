import Foundation

/// Codes look like `TLK-7Q4F`. Everyone has one; a friend types yours into their board to add you.
public enum InviteCode {
    public static let prefix = "TLK-"

    /// Tidies what someone typed or pasted: case, spaces, dashes and the prefix are all optional,
    /// and a code pasted from a message ("Add me on Talkie: TLK-7Q4F") is picked out of it.
    /// Returns nil when nothing is left.
    public static func normalize(_ raw: String) -> String? {
        var text = raw.uppercased()
        if let tlk = text.range(of: "TLK") { text = String(text[tlk.upperBound...]) }
        let body = String(text.unicodeScalars.filter { ("A"..."Z").contains($0) || ("0"..."9").contains($0) })
        guard !body.isEmpty else { return nil }
        return prefix + body.prefix(4)
    }
}

/// Who a code belongs to, according to whoever hands them out (the server, later).
public struct Invite: Equatable, Sendable {
    public var code: String
    public var friend: Friend

    public init(_ code: String, _ friend: Friend) {
        self.code = code
        self.friend = friend
    }
}

public extension Invite {
    /// Everyone the simulated server knows: the example board's seven, three people who used to be on
    /// it, and two new friends.
    static let samples: [Invite] = [
        Invite("TLK-MAYA", Friend(id: 1, name: "MAYA")),
        Invite("TLK-OTTO", Friend(id: 2, name: "OTTO")),
        Invite("TLK-JUN5", Friend(id: 3, name: "JUN", online: false)),
        Invite("TLK-RUBY", Friend(id: 4, name: "RUBY", doNotDisturb: true)),
        Invite("TLK-LEO2", Friend(id: 5, name: "LEO", online: false)),
        Invite("TLK-INES", Friend(id: 6, name: "INÈS")),
        Invite("TLK-KAI9", Friend(id: 7, name: "KAI")),
        Invite("TLK-NICO", Friend(id: 8, name: "NICO")),
        Invite("TLK-BEA4", Friend(id: 9, name: "BEA", online: false)),
        Invite("TLK-TOM8", Friend(id: 10, name: "TOM")),
        Invite("TLK-ZOE7", Friend(id: 11, name: "ZOE")),
        Invite("TLK-PIP3", Friend(id: 12, name: "PIP"))
    ]

    static func lookup(_ code: String) -> Invite? {
        samples.first { $0.code == code }
    }
}

/// What entering a code on the board did.
public enum CodeResult: Equatable, Sendable {
    /// They're on the board now.
    case added(jack: Int)
    /// They were already there.
    case onBoard(jack: Int)
    /// All eight jacks are taken: eject someone first.
    case boardFull
    case ownCode
    case unknown
    case empty
}

/// Your line card: the card you send a friend so they can add you. A punched card with your name,
/// your code, and a hole pattern of its own.
public struct LineCard: Equatable, Sendable {
    public var name: String
    public var code: String

    public init(name: String, code: String) {
        self.name = name
        self.code = code
    }

    public var holes: [Bool] { Self.holes(for: name) }

    /// Two rows of 14, from the name: a little fingerprint. Matches `holesFor` in the prototype.
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
}
