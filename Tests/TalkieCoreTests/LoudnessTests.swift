import XCTest
@testable import TalkieCore

final class LoudnessTests: XCTestCase {
    func testTheMeterRunsFromQuietToLoud() {
        XCTAssertEqual(Loudness.meter(rms: 0), 0)
        XCTAssertEqual(Loudness.meter(rms: 1), 1)
        // -25 dB, an ordinary speaking level, sits in the middle.
        XCTAssertEqual(Loudness.meter(rms: Float(pow(10.0, -25.0 / 20))), 0.6, accuracy: 0.001)
    }

    func testFloatAndSixteenBitAgree() {
        let floats: [Float] = (0..<480).map { 0.3 * sin(Float($0) / 10) }
        let ints: [Int16] = floats.map { Int16($0 * 32768) }
        let a = floats.withUnsafeBufferPointer(Loudness.rms)
        let b = ints.withUnsafeBufferPointer(Loudness.rms)
        XCTAssertEqual(a, b, accuracy: 0.001)
        XCTAssertEqual(a, Float(0.3 / 2.0.squareRoot()), accuracy: 0.01)
    }
}
