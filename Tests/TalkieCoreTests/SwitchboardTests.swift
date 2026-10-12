import XCTest
@testable import TalkieCore

final class SwitchboardTests: XCTestCase {
    // Jacks on the sample board: 0 MAYA, 1 OTTO, 2 JUN (away), 3 RUBY (do not disturb), 4 LEO (away), 5 INÈS, 6 KAI, 7 free.

    private func openLine(_ b: inout Switchboard, cord: CordID = .a, jack: Int = 0, at t: TimeInterval = 0) {
        _ = b.patch(cord, into: jack, now: t)
        _ = b.tick(now: t + Switchboard.connectDelay)
    }

    func testPatchingOpensTheLineAndDropsTheMic() {
        var b = Switchboard()
        XCTAssertEqual(b.patch(.a, into: 0, now: 0), [.plugged, .micDrop])
        XCTAssertEqual(b.lamp(for: 0), .blink)
        XCTAssertEqual(b.readout(now: 0.1).sub, "PATCHING IN…")
        XCTAssertEqual(b.tick(now: 0.5), [])
        XCTAssertEqual(b.tick(now: 0.8), [.lineOpened])
        XCTAssertEqual(b.lamp(for: 0), .on)
        XCTAssertEqual(b.readout(now: 3.8), Readout(big: "MAYA", sub: "LINE A · OPEN · 00:03"))
    }

    func testPullingTheLastPlugStowsTheMic() {
        var b = Switchboard()
        openLine(&b)
        XCTAssertEqual(b.unpatch(.a, now: 2), [.unplugged, .micStow])
        XCTAssertFalse(b.isLive)
        XCTAssertEqual(b.readout(now: 2), Readout(big: "READY TO PATCH", sub: "PLUG INTO A FRIEND"))
    }

    func testDoNotDisturbHoldsThePatchUntilItsSwitchedOff() {
        var b = Switchboard()
        XCTAssertEqual(b.patch(.a, into: 3, now: 0), [.plugged])
        XCTAssertEqual(b.lamp(for: 3), .dnd)
        XCTAssertFalse(b.isLive)
        XCTAssertEqual(b.readout(now: 0).sub, "RUBY · DO NOT DISTURB · PATCH WAITS")

        XCTAssertEqual(b.setFriendDoNotDisturb(3, false, now: 1), [.micDrop])
        XCTAssertEqual(b.lamp(for: 3), .blink)
        XCTAssertEqual(b.tick(now: 1 + Switchboard.connectDelay), [.lineOpened])
        XCTAssertEqual(b.lamp(for: 3), .on)

        // Switching it back on mid-call closes the line but leaves the cord in.
        XCTAssertEqual(b.setFriendDoNotDisturb(3, true, now: 5), [.lineClosed, .micStow])
        XCTAssertEqual(b.lamp(for: 3), .dnd)
        XCTAssertEqual(b.cord(at: 3), .a)
    }

    func testAwayFriendStaysDark() {
        var b = Switchboard()
        XCTAssertEqual(b.patch(.a, into: 2, now: 0), [.plugged])
        XCTAssertEqual(b.lamp(for: 2), .off)
        XCTAssertEqual(b.readout(now: 0).sub, "JUN IS AWAY")
    }

    func testBusyAndFreeJacksAreRefused() {
        var b = Switchboard()
        openLine(&b)
        XCTAssertEqual(b.patch(.b, into: 0, now: 1), [.denied])
        XCTAssertNil(b.patches[.b])
        XCTAssertEqual(b.readout(now: 1).big, "BUSY")

        XCTAssertEqual(b.patch(.b, into: 7, now: 5), [.denied])
        XCTAssertEqual(b.readout(now: 5).sub, "CLICK IT TO ADD A FRIEND")
        // Clicking the free jack gets the board ready for a friend's code instead.
        XCTAssertEqual(b.tapJack(7, now: 6).events, [.addFriend])
        XCTAssertEqual(b.adding, Adding(jack: 7))
    }

    func testTappingAJackSendsTheNextFreeCord() {
        var b = Switchboard()
        let first = b.tapJack(0, now: 0)
        XCTAssertEqual(first.cord, .a)
        let second = b.tapJack(1, now: 0)
        XCTAssertEqual(second.cord, .b)
        let third = b.tapJack(5, now: 0)
        XCTAssertNil(third.cord)
        XCTAssertEqual(third.events, [.denied])
        // Tapping a patched jack pulls its cord.
        XCTAssertEqual(b.tapJack(0, now: 1).events, [.unplugged])
        XCTAssertNil(b.cord(at: 0))
    }

    func testTwoCordsMakeAConference() {
        var b = Switchboard()
        openLine(&b, cord: .a, jack: 0)
        openLine(&b, cord: .b, jack: 1, at: 1)
        XCTAssertEqual(b.readout(now: 3), Readout(big: "MAYA + OTTO", sub: "TWO CORDS · THREE PEOPLE"))
        XCTAssertEqual(b.liveNames, ["MAYA", "OTTO"])
    }

    func testTalkingLightsTheLampAndTheFriendAnswers() {
        var b = Switchboard()
        openLine(&b)
        XCTAssertEqual(b.startTalking(now: 1), [.keyClick])
        XCTAssertEqual(b.lamp(for: 0), .tx)
        XCTAssertTrue(b.flags.tx)
        XCTAssertEqual(b.readout(now: 1).sub, "TALKING TO MAYA")

        XCTAssertEqual(b.stopTalking(now: 2), [.over])
        XCTAssertEqual(b.tick(now: 3), [.keyClick])
        XCTAssertEqual(b.lamp(for: 0), .rx)
        XCTAssertEqual(b.readout(now: 3).sub, "MAYA TALKING")
        XCTAssertEqual(b.tick(now: 5), [.over])
        XCTAssertEqual(b.lamp(for: 0), .on)
    }

    func testBothCanTalkAtOnce() {
        var b = Switchboard()
        openLine(&b)
        b.friendTalks(0, for: 10, now: 1)
        _ = b.tick(now: 1)
        _ = b.startTalking(now: 2)
        XCTAssertTrue(b.talking)
        XCTAssertTrue(b.friendTalking.contains(0))
        XCTAssertTrue(b.flags.tx)
        XCTAssertTrue(b.flags.rx)
    }

    func testMuteIsPrivate() {
        var b = Switchboard()
        openLine(&b)
        b.setMuted(by: 0, true)
        XCTAssertEqual(b.lamp(for: 0), .on)
        _ = b.startTalking(now: 1)
        XCTAssertEqual(b.lamp(for: 0), .tx)
        XCTAssertEqual(b.readout(now: 1).sub, "TALKING TO MAYA")
        _ = b.stopTalking(now: 2)
        // She didn't hear you, so she doesn't answer. Nothing else gives it away.
        XCTAssertTrue(b.replies.isEmpty)
    }

    func testYourMuteOnlyChangesWhatYouHear() {
        var b = Switchboard()
        openLine(&b)
        b.friendTalks(0, for: 2, now: 1)
        _ = b.tick(now: 1.1)
        XCTAssertTrue(b.flags.rx)

        b.mute(0, true)
        XCTAssertTrue(b.isMuted(0))
        XCTAssertFalse(b.flags.rx, "you don't hear her")
        XCTAssertNotEqual(b.readout(now: 1.2).sub, "MAYA TALKING")
        // Her side is untouched: she can still hear you and answer.
        XCTAssertTrue(b.mutedYou.isEmpty)

        // It's kept by friend, so it survives the call ending.
        _ = b.unpatch(.a, now: 2)
        openLine(&b, at: 3)
        XCTAssertTrue(b.isMuted(0))
        b.mute(0, false)
        XCTAssertFalse(b.isMuted(0))
    }

    func testIncomingPatchDropsTheMicAndCanBeHungUp() {
        var b = Switchboard()
        XCTAssertEqual(b.friendPatchesIn(1, now: 0), [.lineOpened, .micDrop])
        XCTAssertEqual(b.lamp(for: 1), .on)
        XCTAssertEqual(b.liveNames, ["OTTO"])
        let tap = b.tapJack(1, now: 3)
        XCTAssertNil(tap.cord)
        XCTAssertEqual(tap.events, [.lineClosed, .micStow])
    }

    func testYourDoNotDisturbHoldsIncomingPatches() {
        var b = Switchboard()
        _ = b.setDoNotDisturb(true, now: 0)
        XCTAssertTrue(b.flags.dnd)
        XCTAssertEqual(b.friendPatchesIn(1, now: 1), [])
        XCTAssertFalse(b.isLive)
    }

    func testEffectsCycleBackToOff() {
        var b = Switchboard()
        var seen: [Effect] = []
        for _ in 0..<Effect.allCases.count {
            _ = b.cycleEffect(now: 0)
            seen.append(b.effect)
        }
        XCTAssertEqual(seen, [.canyon, .tinCan, .helium, .machine, .off])
        XCTAssertEqual(Effect.machine.slot, 4)
        XCTAssertNil(Effect.off.slot)
    }

    func testBuzzNeedsAnOpenLine() {
        var b = Switchboard()
        XCTAssertEqual(b.buzz(now: 0), [.denied])
        openLine(&b, at: 1)
        XCTAssertEqual(b.buzz(now: 3), [.buzz])
        XCTAssertNotNil(b.buzzing[0])
    }

    func testMessagesExpire() {
        var b = Switchboard()
        b.say("HELLO", "WORLD", now: 0, for: 1)
        XCTAssertEqual(b.readout(now: 0.5).big, "HELLO")
        _ = b.tick(now: 1.1)
        XCTAssertEqual(b.readout(now: 1.1).big, "READY TO PATCH")
    }
}
