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
    /// The example board from the prototype. The last jack is free.
    static let samples: [Friend?] = [
        Friend(id: 0, name: "MAYA"),
        Friend(id: 1, name: "OTTO"),
        Friend(id: 2, name: "JUN", online: false),
        Friend(id: 3, name: "RUBY", doNotDisturb: true),
        Friend(id: 4, name: "LEO", online: false),
        Friend(id: 5, name: "INÈS"),
        Friend(id: 6, name: "KAI"),
        nil
    ]
}
