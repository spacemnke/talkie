import XCTest
@testable import TalkieCore

/// A real board: the other end arrives from the network, nothing is simulated, one line at a time.
final class OnlineBoardTests: XCTestCase {
    private func board() -> Switchboard {
        var b = Switchboard(friends: [nil, nil, nil, nil, nil, nil, nil, nil], myCode: "TLK-AB12", simulated: false)
        b.loadBoard([Friend(id: 1, name: "SAM"), Friend(id: 2, name: "ALEX", online: false)])
        return b
    }

    func testTheBoardLoadsFromTheServer() {
        let b = board()
        XCTAssertEqual(b.myCode, "TLK-AB12")
        XCTAssertEqual(b.friends.count, 8)
        XCTAssertEqual(b.friend(0)?.name, "SAM")
        XCTAssertEqual(b.freeJack, 2)
        XCTAssertEqual(b.readout(now: 0), Readout(big: "READY TO PATCH", sub: "PLUG INTO A FRIEND"))
    }

    func testAnEmptyBoardSaysHowToFillIt() {
        let b = Switchboard(friends: Array(repeating: nil, count: 8), myCode: "TLK-AB12", simulated: false)
        XCTAssertEqual(b.readout(now: 0), Readout(big: "EMPTY BOARD", sub: "PRESS ADD · YOUR CODE IS TLK-AB12"))
    }

    func testFriendsDontAnswerByThemselves() {
        var b = board()
        _ = b.patch(.a, into: 0, now: 0)
        _ = b.friendAnswers(0, now: 1)
        _ = b.startTalking(now: 2)
        _ = b.stopTalking(now: 3)
        XCTAssertTrue(b.replies.isEmpty, "only the network says when they talk")
        b.setFriendTalking(0, true)
        XCTAssertTrue(b.flags.rx)
        b.setFriendTalking(0, false)
        XCTAssertFalse(b.flags.rx)
    }

    func testKnockingASecondFriendMakesItAGroupCall() {
        var b = board()
        _ = b.setFriendOnline(1, true, now: 0)
        _ = b.patch(.a, into: 0, now: 0)
        _ = b.friendAnswers(0, now: 1)
        XCTAssertEqual(b.patch(.b, into: 1, now: 2), [.plugged, .knockOut], "Alex can join Sam and you")
        XCTAssertEqual(b.callSize, 3)
        _ = b.friendAnswers(1, now: 3)
        XCTAssertEqual(b.openJacks, [0, 1])
        _ = b.tick(now: 6)
        XCTAssertEqual(b.readout(now: 6), Readout(big: "SAM + ALEX", sub: "3 PEOPLE ON THE LINE"))
    }

    func testLettingSomeoneInDuringACallBringsThemIn() {
        var b = board()
        _ = b.setFriendOnline(1, true, now: 0)
        _ = b.patch(.a, into: 0, now: 0)
        _ = b.friendAnswers(0, now: 1)
        _ = b.friendKnocks(1, now: 2)
        XCTAssertEqual(b.letIn(1, now: 3), [.lineOpened])
        XCTAssertEqual(b.openJacks, [0, 1])
    }

    func testAKnockFromSomeoneElsesCallMeansJoiningIt() {
        var b = board()
        _ = b.setFriendOnline(1, true, now: 0)
        _ = b.patch(.a, into: 0, now: 0)
        _ = b.friendKnocks(1, now: 1, fromCall: true)
        XCTAssertEqual(b.letIn(1, now: 2), [.lineOpened])
        XCTAssertNil(b.patches[.a], "your own knock gave way: you joined their call")

        _ = b.friendKnocks(0, now: 3, fromCall: true)
        XCTAssertEqual(b.letIn(0, now: 4), [.denied], "one call at a time")
        XCTAssertEqual(b.readout(now: 4), Readout(big: "SAM", sub: "ON ANOTHER CALL · HANG UP TO JOIN"))
    }

    func testPeopleOthersBroughtInShowOnTheLCD() {
        var b = board()
        _ = b.friendKnocks(0, now: 0)
        _ = b.letIn(0, now: 1)
        b.setOthers([Guest(id: "z", name: "ZOE", talking: true)])
        XCTAssertEqual(b.callSize, 3)
        XCTAssertTrue(b.flags.rx)
        _ = b.tick(now: 5)
        XCTAssertEqual(b.readout(now: 5), Readout(big: "SAM + ZOE", sub: "ZOE TALKING"))
        _ = b.friendHungUp(0, now: 6)
        XCTAssertTrue(b.others.isEmpty, "off the call, nobody else to hear")
        b.setOthers([Guest(id: "z", name: "ZOE")])
        XCTAssertTrue(b.others.isEmpty)
    }

    func testTheyHangUp() {
        var b = board()
        _ = b.patch(.a, into: 0, now: 0)
        _ = b.friendAnswers(0, now: 1)
        XCTAssertEqual(b.friendHungUp(0, now: 5), [.lineClosed, .micStow])
        XCTAssertNil(b.patches[.a], "the cord drops out")
        XCTAssertEqual(b.readout(now: 5), Readout(big: "SAM", sub: "HUNG UP"))
        XCTAssertEqual(b.friendHungUp(0, now: 6), [], "only once")
    }

    func testTheyGiveUpKnocking() {
        var b = board()
        _ = b.friendKnocks(0, now: 0)
        XCTAssertEqual(b.friendStoppedKnocking(0, now: 4), [.micStow])
        XCTAssertTrue(b.knocks.isEmpty)
        XCTAssertEqual(b.readout(now: 4).sub, "KNOCKED · MISSED")
    }

    func testACordWaitsForAnAwayFriendAndKnocksWhenTheyreBack() {
        var b = board()
        XCTAssertEqual(b.patch(.a, into: 1, now: 0), [.plugged])
        XCTAssertEqual(b.patches[.a]?.status, .offline)
        XCTAssertEqual(b.setFriendOnline(1, true, now: 5), [.knockOut])
        XCTAssertEqual(b.patches[.a]?.status, .knocking)
        XCTAssertEqual(b.patches[.a]?.since, 5)
    }

    func testReloadingTheBoardDropsLinesToFriendsWhoLeftIt() {
        var b = board()
        _ = b.patch(.a, into: 0, now: 0)
        b.loadBoard([nil, Friend(id: 2, name: "ALEX")])
        XCTAssertNil(b.patches[.a])
        XCTAssertNil(b.friend(0))
    }
}
