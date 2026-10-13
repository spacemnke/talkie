import XCTest
@testable import TalkieCore

/// Free: three jacks, ten-minute calls, no effects. Pro: eight jacks, no limit, effects.
final class PlanTests: XCTestCase {
    // The sample board: 0 MAYA, 1 OTTO, 2 JUN (away), 3 RUBY (do not disturb), 4 LEO (away), 5 INÈS, 6 KAI, 7 free.

    private func free() -> Switchboard {
        Switchboard(plan: .free)
    }

    /// An online free board with two friends on it.
    private func online(_ plan: Plan = .free) -> Switchboard {
        var b = Switchboard(friends: Array(repeating: nil, count: 8), myCode: "TLK-AB12", simulated: false, plan: plan)
        b.loadBoard([Friend(id: 1, name: "SAM"), Friend(id: 2, name: "ALEX")])
        return b
    }

    private func openLine(_ b: inout Switchboard, jack: Int = 0, at t: TimeInterval = 0) {
        _ = b.patch(.a, into: jack, now: t)
        _ = b.friendAnswers(jack, now: t)
        _ = b.tick(now: t + 2.5)
    }

    // MARK: Jacks

    func testFreeHasThreeJacksAndProHasEight() {
        XCTAssertEqual(Plan.free.jacks, 3)
        XCTAssertEqual(Plan.pro.jacks, 8)
        let b = free()
        XCTAssertEqual((0..<8).filter(b.isLocked), [3, 4, 5, 6, 7])
        XCTAssertNil(b.freeJack, "the three free jacks are taken")
        XCTAssertEqual(Switchboard().freeJack, 7)
    }

    func testPatchingAProJackAsksForPro() {
        var b = free()
        XCTAssertEqual(b.patch(.a, into: 5, now: 0), [.denied, .needsPro])
        XCTAssertNil(b.patches[.a])
        XCTAssertEqual(b.readout(now: 0), Readout(big: "PRO JACK", sub: "GO PRO FOR 8 JACKS"))
    }

    func testTappingAnEmptyProJackDoesntStartAdding() {
        var b = free()
        let tap = b.tapJack(7, now: 0)
        XCTAssertNil(tap.cord)
        XCTAssertEqual(tap.events, [.denied, .needsPro])
        XCTAssertNil(b.adding)
    }

    func testAKnockFromAProJackDoesntRing() {
        var b = free()
        XCTAssertEqual(b.friendKnocks(5, now: 0), [.click])
        XCTAssertTrue(b.knocks.isEmpty)
        XCTAssertFalse(b.wantsMic)
        XCTAssertEqual(b.readout(now: 0), Readout(big: "INÈS", sub: "TRIED TO KNOCK · PRO JACK"))
    }

    func testAFullFreeBoardSaysGoPro() {
        var b = online()
        XCTAssertEqual(b.freeJack, 2)
        _ = b.startAdding()
        let added = b.enterCode("TLK-ZOE7", now: 0) { Invite.lookup($0) }
        XCTAssertEqual(added.result, .added(jack: 2))

        _ = b.startAdding()
        XCTAssertEqual(b.readout(now: 10), Readout(big: "BOARD FULL", sub: "3 JACKS ON FREE · GO PRO FOR 8"))
        let full = b.enterCode("TLK-PIP3", now: 10) { Invite.lookup($0) }
        XCTAssertEqual(full.result, .boardFull)
        XCTAssertEqual(full.events, [.denied, .needsPro])
        XCTAssertEqual(b.readout(now: 10).sub, "BOARD FULL · GO PRO FOR 8 JACKS")
    }

    func testAddingOnAProJackGoesToAFreeOneInstead() {
        var b = online()
        _ = b.startAdding(at: 6)
        XCTAssertNil(b.adding?.jack)
        XCTAssertEqual(b.addingJack, 2)
        XCTAssertEqual(b.addFriend(Friend(id: 9, name: "PIP"), at: 6, now: 0), [], "nobody goes onto a pro jack")
    }

    // MARK: Call length

    func testAFreeCallWarnsAtOneMinuteAndEndsAtTen() {
        var b = online()
        openLine(&b)
        XCTAssertEqual(b.lineLimits[0], 600)
        XCTAssertEqual(b.timeLeft(now: 100), 500)
        XCTAssertEqual(b.tick(now: 539), [])
        XCTAssertEqual(b.tick(now: 540), [.timeWarning])
        XCTAssertEqual(b.tick(now: 541), [], "the warning sounds once")
        XCTAssertEqual(b.readout(now: 558), Readout(big: "SAM", sub: "FREE CALL · 00:42 LEFT"))

        XCTAssertEqual(b.tick(now: 600), [.lineClosed, .micStow])
        XCTAssertFalse(b.isLive)
        XCTAssertNil(b.patches[.a], "the cord comes out")
        XCTAssertTrue(b.lineLimits.isEmpty)
        XCTAssertEqual(b.readout(now: 600), Readout(big: "TIME'S UP", sub: "FREE CALLS END AT 10 MINUTES · GO PRO"))
    }

    func testALineYouLetInIsTimedToo() {
        var b = online()
        _ = b.friendKnocks(1, now: 0)
        _ = b.letIn(1, now: 1)
        XCTAssertEqual(b.lineLimits[1], 600)
        XCTAssertEqual(b.tick(now: 601), [.lineClosed, .micStow])
        XCTAssertTrue(b.incoming.isEmpty)
    }

    func testNoLimitWhenTheOtherEndHasPro() {
        var b = online()
        openLine(&b)
        b.setCallLimit(0, nil)
        XCTAssertNil(b.timeLeft(now: 10))
        XCTAssertEqual(b.tick(now: 3600), [])
        XCTAssertTrue(b.isLive)
    }

    func testProCallsHaveNoLimit() {
        var b = online(.pro)
        openLine(&b)
        XCTAssertTrue(b.lineLimits.isEmpty)
        XCTAssertEqual(b.tick(now: 7200), [])
        XCTAssertTrue(b.isLive)
    }

    func testTheirSideEndingTheCallAtTheLimitReadsAsTimeUp() {
        var b = online()
        openLine(&b)
        XCTAssertEqual(b.friendHungUp(0, now: 599.4), [.lineClosed, .micStow])
        XCTAssertEqual(b.readout(now: 599.4).big, "TIME'S UP")

        openLine(&b, at: 1000)
        _ = b.friendHungUp(0, now: 1100)
        XCTAssertEqual(b.readout(now: 1100), Readout(big: "SAM", sub: "HUNG UP"))
    }

    // MARK: Effects

    func testEffectsArePro() {
        var b = free()
        XCTAssertEqual(b.setEffect(.helium, now: 0), [.denied, .needsPro])
        XCTAssertEqual(b.effect, .off)
        XCTAssertEqual(b.cycleEffect(now: 0), [.denied, .needsPro])
        XCTAssertEqual(b.readout(now: 0), Readout(big: "VOICE EFFECTS", sub: "PRO ONLY · GO PRO TO CHANGE YOUR VOICE"))
        XCTAssertEqual(b.setEffect(.off, now: 0), [.click], "switching off is always fine")

        var pro = Switchboard()
        XCTAssertEqual(pro.setEffect(.helium, now: 0), [.click])
        XCTAssertEqual(pro.effect, .helium)
    }

    // MARK: Changing plans

    func testGoingProOpensTheJacksAndLiftsTheLimit() {
        var b = online()
        openLine(&b)
        XCTAssertEqual(b.setPlan(.pro, now: 10), [.click])
        XCTAssertFalse(b.isLocked(7))
        XCTAssertTrue(b.lineLimits.isEmpty)
        XCTAssertEqual(b.readout(now: 10), Readout(big: "TALKIE PRO", sub: "8 JACKS · EFFECTS · NO TIME LIMIT"))
        XCTAssertEqual(b.setPlan(.pro, now: 11), [], "nothing to say when nothing changed")
    }

    func testGoingBackToFreeKeepsFriendsButClosesProJacks() {
        var b = Switchboard()
        _ = b.setEffect(.canyon, now: 0)
        _ = b.patch(.a, into: 5, now: 0)
        _ = b.friendAnswers(5, now: 1)
        _ = b.friendKnocks(6, now: 2)
        XCTAssertEqual(b.setPlan(.free, now: 3), [.click, .lineClosed, .micStow])
        XCTAssertEqual(b.effect, .off)
        XCTAssertNil(b.patches[.a])
        XCTAssertTrue(b.knocks.isEmpty)
        XCTAssertEqual(b.friend(5)?.name, "INÈS", "friends stay on the board")
        XCTAssertEqual(b.readout(now: 3), Readout(big: "TALKIE FREE", sub: "3 JACKS · 10-MINUTE CALLS"))
    }

    func testTheTableHasEveryFeature() {
        XCTAssertEqual(PlanFeature.all.map(\.name).first, "Friends on your board")
        XCTAssertTrue(PlanFeature.all.contains { $0.name == "Voice effects" && $0.free == "—" })
    }
}

final class KnockSoundTests: XCTestCase {
    func testFreeAlwaysHearsTheStandardKnock() {
        XCTAssertEqual(KnockSound.forFriend(.doorbell, plan: .free), .knuckles)
        XCTAssertEqual(KnockSound.forFriend(.doorbell, plan: .pro), .doorbell)
        XCTAssertEqual(KnockSound.forFriend(nil, plan: .pro), .knuckles)
    }

    func testEveryKnockHasAName() {
        XCTAssertEqual(KnockSound.allCases.count, 6)
        XCTAssertEqual(Set(KnockSound.allCases.map(\.title)).count, 6)
    }
}

extension PlanTests {
    func testThePracticeBoardCanSkipToTheLastMinute() {
        var b = Switchboard(plan: .free)
        _ = b.patch(.a, into: 0, now: 0)
        _ = b.friendAnswers(0, now: 0)
        b.endLinesSoon(in: 61, now: 30)
        XCTAssertEqual(b.timeLeft(now: 30), 61)
        XCTAssertEqual(b.tick(now: 31), [.timeWarning])
        XCTAssertEqual(b.tick(now: 91), [.lineClosed, .micStow])
    }
}
