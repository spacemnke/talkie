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

    func testOneLineAtATime() {
        var b = board()
        _ = b.setFriendOnline(1, true, now: 0)
        _ = b.patch(.a, into: 0, now: 0)
        XCTAssertEqual(b.patch(.b, into: 1, now: 1), [.denied], "still knocking on Sam")
        XCTAssertEqual(b.readout(now: 1), Readout(big: "ONE LINE AT A TIME", sub: "HANG UP ON SAM FIRST"))
        // Moving the same cord is fine: the knock on Sam ends.
        XCTAssertEqual(b.patch(.a, into: 1, now: 2), [.plugged, .knockOut])
        XCTAssertEqual(b.knockingOut, [1])
    }

    func testLettingSomeoneInDropsYourOwnKnockButNotAnOpenLine() {
        var b = board()
        _ = b.setFriendOnline(1, true, now: 0)
        _ = b.patch(.a, into: 0, now: 0)
        _ = b.friendKnocks(1, now: 1)
        XCTAssertEqual(b.letIn(1, now: 2), [.lineOpened])
        XCTAssertNil(b.patches[.a], "your knock on Sam gave way")
        XCTAssertEqual(b.openJacks, [1])

        _ = b.friendKnocks(0, now: 3)
        XCTAssertEqual(b.letIn(0, now: 4), [.denied])
        XCTAssertEqual(b.readout(now: 4).sub, "HANG UP ON ALEX FIRST")
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
