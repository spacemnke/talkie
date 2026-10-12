import XCTest
@testable import TalkieCore

final class AddFriendTests: XCTestCase {
    // The sample board: MAYA … KAI (ids 1–7) on jacks 0–6. Jack 7 is free.
    // The sample server also knows NICO, BEA and TOM, who used to be on it, and ZOE and PIP.

    private func enter(_ code: String, on board: inout Switchboard, now: TimeInterval = 0) -> (result: CodeResult, events: [BoardEvent]) {
        board.enterCode(code, now: now, lookup: Invite.lookup)
    }

    func testSampleBoardComesFromTheDirectory() {
        let board = Switchboard()
        XCTAssertEqual(board.friends.compactMap { $0?.name }, ["MAYA", "OTTO", "JUN", "RUBY", "LEO", "INÈS", "KAI"])
        XCTAssertEqual(board.freeJack, 7)
        XCTAssertEqual(board.jack(of: 4), 3)
        XCTAssertNil(board.jack(of: 8))
        XCTAssertEqual(board.myCode, "TLK-7Q4F")
    }

    func testCodesAreTidiedUp() {
        XCTAssertEqual(InviteCode.normalize("tlk-zoe7"), "TLK-ZOE7")
        XCTAssertEqual(InviteCode.normalize(" zoe7 "), "TLK-ZOE7")
        XCTAssertEqual(InviteCode.normalize("TLK ZOE7 and more"), "TLK-ZOE7")
        XCTAssertEqual(InviteCode.normalize("Add me on Talkie: TLK-ZOE7 · switchtalkie.com"), "TLK-ZOE7")
        XCTAssertNil(InviteCode.normalize("tlk-"))
        XCTAssertNil(InviteCode.normalize("  "))
    }

    func testClickingAFreeJackTakesACodeForIt() {
        var board = Switchboard()
        XCTAssertEqual(board.tapJack(7, now: 0).events, [.addFriend])
        XCTAssertEqual(board.readout(now: 0), Readout(big: "ADD A FRIEND", sub: "JACK 08 · TYPE OR PASTE THEIR CODE"))

        let added = enter("tlk-zoe7", on: &board, now: 1)
        XCTAssertEqual(added.result, .added(jack: 7))
        XCTAssertEqual(added.events, [.plugged])
        XCTAssertEqual(board.friend(7)?.name, "ZOE")
        XCTAssertNil(board.adding, "adding someone ends add mode")
        XCTAssertEqual(board.readout(now: 1), Readout(big: "ZOE", sub: "NEW ON JACK 08"))
    }

    func testCodesThatDontAddAnyone() {
        var board = Switchboard()
        _ = board.startAdding()
        XCTAssertEqual(enter("", on: &board).result, .empty)
        XCTAssertEqual(enter("TLK-7Q4F", on: &board).result, .ownCode)
        XCTAssertEqual(board.readout(now: 0), Readout(big: "YOUR OWN CODE", sub: "SEND IT TO A FRIEND"))
        XCTAssertEqual(enter("TLK-0000", on: &board).events, [.denied])
        XCTAssertEqual(board.readout(now: 0), Readout(big: "UNKNOWN CODE", sub: "CHECK IT AND TRY AGAIN"))
        XCTAssertEqual(enter("TLK-MAYA", on: &board).result, .onBoard(jack: 0))
        XCTAssertEqual(board.readout(now: 0), Readout(big: "MAYA", sub: "ALREADY ON JACK 01"))
        XCTAssertNotNil(board.adding, "still waiting for a code")
        _ = board.tick(now: 5)
        XCTAssertEqual(board.readout(now: 5).big, "ADD A FRIEND")
    }

    func testAFullBoardWaitsUntilSomeoneIsEjected() {
        var board = Switchboard()
        _ = enter("TLK-ZOE7", on: &board)
        _ = board.startAdding()
        XCTAssertEqual(board.readout(now: 0), Readout(big: "BOARD FULL", sub: "RIGHT-CLICK A JACK TO EJECT SOMEONE"))
        XCTAssertEqual(enter("TLK-PIP3", on: &board, now: 1).result, .boardFull)
        XCTAssertEqual(board.readout(now: 1), Readout(big: "PIP", sub: "BOARD FULL · EJECT SOMEONE FIRST"))

        // Eject Maya: her jack frees up and the board offers it.
        XCTAssertEqual(board.removeFriend(at: 0, now: 2), [.unplugged])
        XCTAssertNil(board.friend(0))
        XCTAssertEqual(board.readout(now: 2), Readout(big: "JACK 01", sub: "FREE · MAYA IS OFF THE BOARD"))
        _ = board.tick(now: 5)
        XCTAssertEqual(board.readout(now: 5), Readout(big: "ADD A FRIEND", sub: "JACK 01 · TYPE OR PASTE THEIR CODE"))

        XCTAssertEqual(enter("TLK-PIP3", on: &board, now: 6).result, .added(jack: 0))
        XCTAssertEqual(board.friend(0)?.name, "PIP")
    }

    func testTheAddKeyUsesTheFirstFreeJack() {
        var board = Switchboard()
        _ = board.removeFriend(at: 2, now: 0) // JUN
        _ = board.startAdding()
        XCTAssertEqual(board.addingJack, 2)
        // Clicking a free jack instead moves the friend there.
        _ = board.tapJack(7, now: 0)
        XCTAssertEqual(board.addingJack, 7)
        XCTAssertEqual(enter("TLK-NICO", on: &board).result, .added(jack: 7))
    }

    func testAnEjectedFriendComesBackWithTheirCode() {
        var board = Switchboard()
        board.mute(0, true)
        _ = board.unpatch(.a, now: 0)
        _ = board.removeFriend(at: 0, now: 0) // MAYA
        XCTAssertEqual(enter("TLK-MAYA", on: &board, now: 1).result, .added(jack: 0))
        XCTAssertTrue(board.isMuted(0), "she's the same friend, so she stays muted")
    }

    func testEjectingSomeoneOnALineHangsUp() {
        var board = Switchboard()
        _ = board.patch(.a, into: 0, now: 0)
        _ = board.tick(now: Switchboard.connectDelay)
        _ = board.friendPatchesIn(1, now: 1)
        XCTAssertEqual(board.openJacks, [0, 1])

        XCTAssertEqual(board.removeFriend(at: 0, now: 2), [.unplugged]) // MAYA, on cord A
        XCTAssertNil(board.patches[.a])

        XCTAssertEqual(board.removeFriend(at: 1, now: 3), [.unplugged, .lineClosed, .micStow]) // OTTO, who patched in to you
        XCTAssertFalse(board.isLive)
        // An ejected friend can't patch in.
        XCTAssertEqual(board.friendPatchesIn(1, now: 4), [])
    }

    func testSomeoneOffYourBoardOnlyKnocks() {
        var board = Switchboard()
        _ = board.unpatch(.a, now: 0)
        _ = board.removeFriend(at: 0, now: 0) // MAYA

        XCTAssertEqual(board.knock(from: "MAYA", now: 1), [.click])
        XCTAssertFalse(board.isLive, "no line opens")
        XCTAssertTrue(board.incoming.isEmpty)
        XCTAssertEqual(board.readout(now: 1), Readout(big: "MAYA", sub: "KNOCKED · ADD THEM TO LET IN"))

        // Adding her code puts her back on the board, and then she can patch in.
        guard case .added(let jack) = enter("TLK-MAYA", on: &board, now: 2).result else {
            return XCTFail("expected her to be added")
        }
        XCTAssertEqual(board.friendPatchesIn(jack, now: 3), [.lineOpened, .micDrop])
    }

    func testEveryCardHasItsOwnHoles() {
        // Same patterns as the prototype's holesFor().
        let bits: (String) -> String = { LineCard.holes(for: $0).map { $0 ? "1" : "0" }.joined() }
        XCTAssertEqual(bits("MAYA"), "1101011001110100001100100000")
        XCTAssertEqual(bits("INÈS"), "1000101101100000011101010101")
        XCTAssertEqual(bits("ZOE"), "1011111100100100100110111110")
    }
}
