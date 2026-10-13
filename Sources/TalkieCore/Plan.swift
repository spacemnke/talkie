import Foundation

/// Free or Pro.
///
/// Free: three jacks, calls of up to ten minutes (no limit when the other person has Pro), your own
/// voice, and the standard knock. Pro: all eight jacks, no time limit, voice effects, and a knock
/// sound of your choosing for each friend.
public enum Plan: String, CaseIterable, Sendable {
    case free, pro

    /// How many jacks on the board you can use.
    public var jacks: Int { self == .free ? 3 : 8 }

    /// How many people a call can have when you're the one bringing them in, you included.
    public var groupSize: Int { self == .free ? 3 : 5 }

    /// Patch cords on the deck: one for each person you can bring in.
    public var cords: Int { groupSize - 1 }

    /// How long a call can last on your side, before the other end's plan is known. Nil is no limit.
    public var callLimit: TimeInterval? { self == .free ? Plan.freeCallLength : nil }

    public var hasEffects: Bool { self == .pro }
    public var hasKnockSounds: Bool { self == .pro }

    public var title: String { self == .free ? "FREE" : "PRO" }

    /// Ten minutes: a free call ends then, unless either of you has Pro.
    public static let freeCallLength: TimeInterval = 600
    /// The board starts counting down out loud this long before a free call ends.
    public static let warnBefore: TimeInterval = 60

    /// The prices, for the Pro window and the website. Payments aren't live yet.
    public static let monthly = "$4"
    public static let yearly = "$36"
}

/// One row of the Free vs Pro table, as the Pro window and the website show it.
public struct PlanFeature: Equatable, Sendable {
    public var name: String
    public var free: String
    public var pro: String

    public static let all: [PlanFeature] = [
        PlanFeature(name: "Friends on your board", free: "3 jacks", pro: "8 jacks"),
        PlanFeature(name: "Group calls", free: "3 people", pro: "5 people"),
        PlanFeature(name: "Call length", free: "10 minutes · no limit if your friend has Pro", pro: "No limit"),
        PlanFeature(name: "Voice effects", free: "—", pro: "Canyon, Tin Can, Helium, Machine"),
        PlanFeature(name: "Knock sounds", free: "The standard knock", pro: "Pick a knock for each friend"),
        PlanFeature(name: "Knocking, mic, do not disturb, private mute, buzz", free: "Yes", pro: "Yes"),
        PlanFeature(name: "Price", free: "Free", pro: "\(Plan.monthly) a month or \(Plan.yearly) a year"),
    ]
}

/// What a friend's knock sounds like. Everyone hears the standard knock; on Pro you pick one per friend.
public enum KnockSound: String, CaseIterable, Sendable {
    case knuckles, shaveAndAHaircut, woodblock, doorbell, bikeBell, telegraph

    public static let standard = KnockSound.knuckles

    public var title: String {
        switch self {
        case .knuckles: return "Knuckles"
        case .shaveAndAHaircut: return "Shave and a Haircut"
        case .woodblock: return "Woodblock"
        case .doorbell: return "Doorbell"
        case .bikeBell: return "Bike Bell"
        case .telegraph: return "Telegraph"
        }
    }

    public var detail: String {
        switch self {
        case .knuckles: return "Two knocks on a wooden door."
        case .shaveAndAHaircut: return "The knock everyone knows."
        case .woodblock: return "Three dry taps."
        case .doorbell: return "Ding-dong."
        case .bikeBell: return "Ring ring."
        case .telegraph: return "T-A-L-K in Morse."
        }
    }

    /// The knock to play for a friend: your pick on Pro, the standard knock otherwise.
    public static func forFriend(_ chosen: KnockSound?, plan: Plan) -> KnockSound {
        plan.hasKnockSounds ? chosen ?? .standard : .standard
    }
}
