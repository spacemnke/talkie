import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import TalkieCore

final class PhysicsTests: XCTestCase {
    func testCordSettlesOnItsJack() {
        var cord = CordSim()
        let dock = CGPoint(x: 100, y: 600)
        let jack = CGPoint(x: 300, y: 250)
        cord.snap(dock: dock, target: dock)
        var frames = 0
        while cord.step(dock: dock, target: jack, reduceMotion: false) && frames < 2000 { frames += 1 }
        XCTAssertLessThan(frames, 2000, "the cord never came to rest")
        XCTAssertLessThan(cord.plug.distance(to: jack), 0.5)
    }

    func testDraggedPlugStaysWhereItIsHeld() {
        var cord = CordSim()
        cord.snap(dock: .zero, target: .zero)
        cord.dragging = true
        cord.plug = CGPoint(x: 50, y: 50)
        cord.step(dock: .zero, target: .zero, reduceMotion: false)
        XCTAssertEqual(cord.plug, CGPoint(x: 50, y: 50))
    }

    func testCoilRunsFromTheMicToTheMenuBar() {
        let start = CGPoint(x: 400, y: 500)
        let anchor = CGPoint(x: 900, y: 22)
        let points = Coil.points(from: start, to: anchor)
        XCTAssertGreaterThan(points.count, 140)
        XCTAssertLessThan(points.first!.distance(to: start), 0.01)
        XCTAssertLessThan(points.last!.distance(to: anchor), 0.01)

        // A cord leaving the top of the mic heads up, not down through the mic.
        let rising = Coil.points(from: start, to: anchor, rising: true)
        XCTAssertLessThan(rising[rising.count / 10].y, start.y)
    }

    private let bounds = CGRect(x: 0, y: 30, width: 1440, height: 870)
    private let size = CGSize(width: 110, height: 189)
    private let anchor = CGPoint(x: 1300, y: 22)

    private func settle(_ mic: inout FloatingMic, frames: Int = 1200) {
        for _ in 0..<frames {
            mic.step(anchor: anchor, bounds: bounds, size: size, reduceMotion: false)
            if mic.isAtRest && mic.mode != .dropping && mic.mode != .retracting { break }
        }
    }

    func testMicDropsAndSettlesUnderTheMenuBar() {
        var mic = FloatingMic()
        XCTAssertFalse(mic.isVisible)
        mic.drop(from: anchor)
        XCTAssertEqual(mic.mode, .dropping)
        settle(&mic)
        XCTAssertEqual(mic.mode, .floating)
        XCTAssertLessThan(mic.position.distance(to: mic.homePoint(anchor: anchor, bounds: bounds, size: size)), 1)
        XCTAssertEqual(mic.scale, 1)
    }

    func testMicRemembersWhereYouLeftIt() {
        var mic = FloatingMic()
        mic.drop(from: anchor)
        settle(&mic)

        let spot = CGPoint(x: 300, y: 600)
        mic.beginDrag()
        for i in 1...20 {
            let t = CGFloat(i) / 20
            mic.drag(to: CGPoint(x: mic.position.x + (spot.x - mic.position.x) * t, y: mic.position.y + (spot.y - mic.position.y) * t), bounds: bounds, size: size)
        }
        mic.drag(to: spot, bounds: bounds, size: size)
        mic.velocity = .zero
        mic.endDrag()
        settle(&mic)
        XCTAssertNotNil(mic.home)

        mic.stow()
        settle(&mic)
        XCTAssertEqual(mic.mode, .hidden)

        mic.drop(from: anchor)
        settle(&mic)
        XCTAssertLessThan(mic.position.distance(to: spot), 2)
    }

    func testFlungMicStaysOnScreen() {
        var mic = FloatingMic()
        mic.drop(from: anchor)
        settle(&mic)
        mic.beginDrag()
        mic.endDrag()
        mic.velocity = CGVector(dx: 400, dy: 300)
        settle(&mic)
        let p = mic.position
        XCTAssertGreaterThanOrEqual(p.x - size.width / 2, bounds.minX)
        XCTAssertLessThanOrEqual(p.x + size.width / 2, bounds.maxX)
        XCTAssertLessThanOrEqual(p.y + size.height / 2, bounds.maxY)
    }

    func testReduceMotionSkipsTheAnimation() {
        var mic = FloatingMic()
        mic.drop(from: anchor)
        mic.step(anchor: anchor, bounds: bounds, size: size, reduceMotion: true)
        XCTAssertEqual(mic.mode, .floating)
        mic.stow()
        mic.step(anchor: anchor, bounds: bounds, size: size, reduceMotion: true)
        XCTAssertEqual(mic.mode, .hidden)
    }
}
