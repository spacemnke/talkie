import Foundation
import TalkieCore

/// Screenshot scenes for the simulator (CI launches Talkie with TALKIE_DEMO set): the sample
/// friends from the Mac's practice board, never the network.
enum Demo {
    static func board(_ scene: String, now: TimeInterval) -> Switchboard {
        var b = Switchboard(friends: Friend.samples, myCode: "TLK-LJDF", simulated: true, plan: scene == "free" ? .free : .pro)
        switch scene {
        case "knock":
            _ = b.friendKnocks(0, now: now)
        case "call":
            _ = b.patch(.a, into: 1, now: now)
            _ = b.friendAnswers(1, now: now)
            b.friendTalks(1, for: 600, now: now)
        case "add":
            _ = b.startAdding(at: nil)
        case "empty", "welcome":
            b = Switchboard(friends: Array(repeating: nil, count: 8), myCode: "TLK-LJDF", simulated: true, plan: .free)
        default:
            break
        }
        return b
    }
}
