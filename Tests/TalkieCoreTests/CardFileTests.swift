import XCTest
@testable import TalkieCore

final class CardFileTests: XCTestCase {
    // The sample Rolodex: MAYA … KAI (ids 1–7) on jacks 0–6, then NICO, BEA and TOM off the board. Jack 7 is free.

    private let today = Date(timeIntervalSince1970: 1_791_720_000) // 11 Oct 2026, noon UTC

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func testSampleBoardComesFromTheCards() {
        let board = Switchboard()
        XCTAssertEqual(board.friends.compactMap { $0?.name }, ["MAYA", "OTTO", "JUN", "RUBY", "LEO", "INÈS", "KAI"])
        XCTAssertEqual(board.freeJack, 7)
        XCTAssertEqual(board.jack(of: 4), 3)
        XCTAssertNil(board.jack(of: 8))
    }

    func testCodesAreTidiedUp() {
        XCTAssertEqual(InviteCode.normalize("tlk-zoe7"), "TLK-ZOE7")
        XCTAssertEqual(InviteCode.normalize(" zoe7 "), "TLK-ZOE7")
        XCTAssertEqual(InviteCode.normalize("TLK ZOE7 and more"), "TLK-ZOE7")
        XCTAssertNil(InviteCode.normalize("tlk-"))
        XCTAssertNil(InviteCode.normalize("  "))
    }

    func testCheckingACodeIssuesACardOnce() {
        var file = CardFile()
        guard case .issued(let card) = file.issue(code: "TLK-ZOE7", invite: Invite.samples["TLK-ZOE7"], on: today) else {
            return XCTFail("expected a card")
        }
        XCTAssertEqual(card.name, "ZOE")
        XCTAssertEqual(card.id, 11)
        XCTAssertEqual(file.tray, card)
        XCTAssertEqual(LineCard.stamp(card.added, calendar: utc), "11 OCT")
        XCTAssertEqual(card.meta.hasSuffix("· TLK-ZOE7"), true)

        // One card in the tray at a time.
        XCTAssertEqual(file.issue(code: "TLK-PIP3", invite: Invite.samples["TLK-PIP3"], on: today), .takeYourCard)

        var board = Switchboard()
        _ = file.punch(card.id, into: &board, now: 0)
        XCTAssertEqual(file.issue(code: "TLK-ZOE7", invite: Invite.samples["TLK-ZOE7"], on: today), .alreadyUsed)
        XCTAssertEqual(file.issue(code: "TLK-7Q4F", invite: nil, on: today), .ownCode)
        XCTAssertEqual(file.issue(code: "TLK-0000", invite: nil, on: today), .unknown)
        XCTAssertEqual(CodeCheck.unknown.readout, PunchReadout("UNKNOWN CODE", "CHECK IT AND TRY AGAIN"))
    }

    func testPunchingANewCardPutsTheFriendOnTheFreeJack() {
        var file = CardFile()
        var board = Switchboard()
        guard case .issued(let card) = file.issue(code: "TLK-ZOE7", invite: Invite.samples["TLK-ZOE7"], on: today) else {
            return XCTFail("expected a card")
        }
        let punched = file.punch(card.id, into: &board, now: 1)
        XCTAssertEqual(punched?.result, .accepted(jack: 7))
        XCTAssertEqual(punched?.events, [.plugged])
        XCTAssertEqual(board.friend(7)?.name, "ZOE")
        XCTAssertEqual(board.readout(now: 1), Readout(big: "ZOE", sub: "NEW ON JACK 08"))
        XCTAssertNil(file.tray)
        // Filed at the front of the Rolodex.
        XCTAssertEqual(file.frontCard?.name, "ZOE")
        XCTAssertEqual(file.cards.count, 11)
        XCTAssertEqual(file.counter, "01 / 11")
        XCTAssertEqual(PunchResult.accepted(jack: 7).readout(name: "ZOE"), PunchReadout("ACCEPTED", "ZOE · JACK 08"))

        // Punching the same card again changes nothing.
        XCTAssertEqual(file.punch(card.id, into: &board, now: 2)?.result, .onBoard(jack: 7))
    }

    func testAFullBoardRefusesTheCardUntilSomeoneIsEjected() {
        var file = CardFile()
        var board = Switchboard()
        guard case .issued(let zoe) = file.issue(code: "TLK-ZOE7", invite: Invite.samples["TLK-ZOE7"], on: today) else {
            return XCTFail("expected a card")
        }
        _ = file.punch(zoe.id, into: &board, now: 0)
        guard case .issued(let pip) = file.issue(code: "TLK-PIP3", invite: Invite.samples["TLK-PIP3"], on: today) else {
            return XCTFail("expected a card")
        }
        XCTAssertEqual(file.punch(pip.id, into: &board, now: 1)?.result, .boardFull)
        XCTAssertEqual(file.tray, pip, "a refused card stays in the tray")

        // Eject Maya: her jack frees up, her card stays.
        file.bringToFront(1)
        let ejected = file.eject(from: &board, now: 2)
        XCTAssertEqual(ejected?.jack, 0)
        XCTAssertNil(board.friend(0))
        XCTAssertNotNil(file.card(1))
        XCTAssertEqual(board.readout(now: 2), Readout(big: "JACK 01", sub: "FREE · MAYA IS IN THE ROLODEX"))

        XCTAssertEqual(file.punch(pip.id, into: &board, now: 3)?.result, .accepted(jack: 0))
        XCTAssertEqual(board.friend(0)?.name, "PIP")
    }

    func testAnOldCardPutsAFriendBack() {
        var file = CardFile()
        var board = Switchboard()
        file.bringToFront(8) // NICO
        XCTAssertEqual(file.hint(on: board), "Drag NICO's card into the punch to put them back on your board.")
        XCTAssertNil(file.eject(from: &board, now: 0), "nothing to eject: NICO isn't on the board")
        XCTAssertEqual(file.punch(8, into: &board, now: 0)?.result, .accepted(jack: 7))
        XCTAssertEqual(file.hint(on: board), "NICO is on jack 08. Eject frees the jack; the card stays here.")
        XCTAssertEqual(file.cards.count, 10, "an old card isn't filed twice")
    }

    func testEjectingSomeoneOnALineHangsUp() {
        var file = CardFile()
        var board = Switchboard()
        _ = board.patch(.a, into: 0, now: 0)
        _ = board.tick(now: Switchboard.connectDelay)
        _ = board.friendPatchesIn(1, now: 1)
        XCTAssertEqual(board.openJacks, [0, 1])

        file.bringToFront(1) // MAYA, on cord A
        XCTAssertEqual(file.eject(from: &board, now: 2)?.events, [.unplugged])
        XCTAssertNil(board.patches[.a])

        file.bringToFront(2) // OTTO, who patched in to you
        XCTAssertEqual(file.eject(from: &board, now: 3)?.events, [.unplugged, .lineClosed, .micStow])
        XCTAssertFalse(board.isLive)
        // An ejected friend can't patch in.
        XCTAssertEqual(board.friendPatchesIn(1, now: 4), [])
    }

    func testSomeoneOffYourBoardOnlyKnocks() {
        var file = CardFile()
        var board = Switchboard()
        file.bringToFront(1)
        _ = file.eject(from: &board, now: 0) // MAYA
        _ = board.unpatch(.a, now: 0)

        XCTAssertEqual(board.knock(from: "MAYA", now: 1), [.click])
        XCTAssertFalse(board.isLive, "no line opens")
        XCTAssertTrue(board.incoming.isEmpty)
        XCTAssertEqual(board.readout(now: 1), Readout(big: "MAYA", sub: "KNOCKED · PUNCH TO LET IN"))

        // Punching her card back puts her on the board, and then she can patch in.
        guard let jack = file.punch(1, into: &board, now: 2).flatMap({ out -> Int? in
            if case .accepted(let j) = out.result { return j } else { return nil }
        }) else { return XCTFail("expected her card to be accepted") }
        XCTAssertEqual(board.friendPatchesIn(jack, now: 3), [.lineOpened, .micDrop])
    }

    func testEjectKeepsTheirLatestPresenceOnTheCard() {
        var file = CardFile()
        var board = Switchboard()
        _ = board.setFriendDoNotDisturb(3, false, now: 0) // RUBY
        file.bringToFront(4)
        _ = file.eject(from: &board, now: 1)
        XCTAssertEqual(file.card(4)?.friend.doNotDisturb, false)
    }

    func testTheRolodexTurnsBothWays() {
        var file = CardFile()
        XCTAssertEqual(file.frontCard?.name, "MAYA")
        file.turn(-1)
        XCTAssertEqual(file.frontCard?.name, "TOM")
        XCTAssertEqual(file.counter, "10 / 10")
        file.turn(3)
        XCTAssertEqual(file.frontCard?.name, "JUN")
        XCTAssertEqual(file.depth(of: 3), 0)
        XCTAssertEqual(file.depth(of: 4), 1)
        XCTAssertEqual(file.depth(of: 2), 9)
    }

    func testEveryCardHasItsOwnHoles() {
        // Same patterns as the prototype's holesFor().
        let bits: (String) -> String = { LineCard.holes(for: $0).map { $0 ? "1" : "0" }.joined() }
        XCTAssertEqual(bits("MAYA"), "1101011001110100001100100000")
        XCTAssertEqual(bits("INÈS"), "1000101101100000011101010101")
        XCTAssertEqual(bits("ZOE"), "1011111100100100100110111110")
    }

    func testSampleStampsReadTheSameAsThePrototype() {
        XCTAssertEqual(LineCard.samples.map { LineCard.stamp($0.added, calendar: utc) },
                       ["12 MAR", "30 MAR", "04 APR", "21 APR", "09 JUN", "15 AUG", "02 SEP", "02 MAY", "19 JAN", "07 JUL"])
    }
}
