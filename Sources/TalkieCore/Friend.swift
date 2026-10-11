import Foundation

public enum Presence: Equatable, Sendable {
    case online, away, doNotDisturb
}

public struct Friend: Equatable, Identifiable, Sendable {
    public var id: Int
    public var name: String
    public var online: Bool
    public var doNotDisturb: Bool

    public init(id: Int, name: String, online: Bool = true, doNotDisturb: Bool = false) {
        self.id = id
        self.name = name
        self.online = online
        self.doNotDisturb = doNotDisturb
    }

    public var presence: Presence {
        if !online { return .away }
        return doNotDisturb ? .doNotDisturb : .online
    }
}

public extension Friend {
    /// The example board from the prototype: the first seven sample cards. The last jack is free.
    static let samples: [Friend?] = LineCard.samples.prefix(7).map { $0.friend } + [nil]
}
