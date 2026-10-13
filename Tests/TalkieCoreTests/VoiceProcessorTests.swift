import XCTest
@testable import TalkieCore

final class VoiceProcessorTests: XCTestCase {
    private let rate = 48_000.0

    private func sine(_ hz: Double, seconds: Double = 0.5, level: Float = 0.3) -> [Float] {
        (0..<Int(rate * seconds)).map { level * Float(sin(2 * .pi * hz * Double($0) / rate)) }
    }

    /// How strong one frequency is in a stretch of sound (Goertzel).
    private func strength(_ samples: ArraySlice<Float>, at hz: Double) -> Double {
        let k = 2 * cos(2 * .pi * hz / rate)
        var s1 = 0.0, s2 = 0.0
        for x in samples {
            let s = Double(x) + k * s1 - s2
            s2 = s1
            s1 = s
        }
        return (s1 * s1 + s2 * s2 - k * s1 * s2).squareRoot() / Double(samples.count)
    }

    private func run(_ effect: Effect, _ input: [Float], block: Int = 480, scale: Float = 1) -> [Float] {
        var p = VoiceProcessor(sampleRate: rate)
        p.setEffect(effect)
        var out = input
        var start = 0
        while start < out.count {
            let end = min(start + block, out.count)
            out.withUnsafeMutableBufferPointer { all in
                p.process(UnsafeMutableBufferPointer(rebasing: all[start..<end]), scale: scale)
            }
            start = end
        }
        return out
    }

    func testOffLeavesYourVoiceAlone() {
        let input = sine(300)
        XCTAssertEqual(run(.off, input), input)
    }

    func testCanyonComesBackTwice() {
        var impulse = [Float](repeating: 0, count: Int(rate * 0.6))
        impulse[0] = 0.5
        let out = run(.canyon, impulse)
        let near = Int(rate * 0.28) + 1, far = Int(rate * 0.47) + 1
        XCTAssertGreaterThan(abs(out[near]), 0.15, "first echo")
        XCTAssertGreaterThan(abs(out[far]), 0.1, "second echo")
        XCTAssertEqual(out[near / 2], 0, "silence in between")
    }

    func testTinCanIsThin() {
        let low = run(.tinCan, sine(120))
        let mid = run(.tinCan, sine(1500))
        let tail = 12_000..<24_000
        XCTAssertGreaterThan(strength(mid[tail], at: 1500), strength(low[tail], at: 120) * 4, "lows are cut, the middle stays")
    }

    func testHeliumIsAnOctaveUp() {
        let out = run(.helium, sine(220, seconds: 1))
        let tail = out[24_000..<48_000]
        XCTAssertGreaterThan(strength(tail, at: 440), strength(tail, at: 220) * 3)
    }

    func testMachineRingModulates() {
        let out = run(.machine, sine(1000, seconds: 1))
        let tail = out[12_000..<48_000]
        XCTAssertGreaterThan(strength(tail, at: 1050), strength(tail, at: 1000) * 3, "the voice moves to the sidebands")
    }

    /// A voice-ish sound: a 140 Hz buzz with falling harmonics, syllables four times a second.
    private func voice(seconds: Double = 1) -> [Float] {
        (0..<Int(rate * seconds)).map { i in
            let t = Double(i) / rate
            let buzz = (1...12).reduce(0.0) { $0 + sin(2 * .pi * 140 * Double($1) * t) / Double($1) }
            return Float(0.12 * buzz * max(0, sin(2 * .pi * 4 * t)))
        }
    }

    private func rms(_ samples: [Float]) -> Double {
        (samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count)).squareRoot()
    }

    func testEffectsKeepYouAboutAsLoud() {
        let input = voice()
        for effect in Effect.allCases where effect != .off {
            let ratio = rms(run(effect, input)) / rms(input)
            XCTAssert((0.5...2).contains(ratio), "\(effect) changes the level by \(ratio)")
        }
    }

    func testNeverLouderThanFullScale() {
        let loud = sine(400, level: 3)
        for effect in Effect.allCases where effect != .off {
            XCTAssertLessThanOrEqual(run(effect, loud).map(abs).max() ?? 0, 1, "\(effect)")
        }
    }

    func testWorksOnSixteenBitLevelsToo() {
        let input = sine(220, seconds: 1)
        let scaled = run(.helium, input.map { $0 * 32768 }, scale: 32768).map { $0 / 32768 }
        let plain = run(.helium, input)
        for (a, b) in zip(scaled, plain) { XCTAssertEqual(a, b, accuracy: 1e-4) }
    }

    func testBlockSizeDoesntChangeTheSound() {
        let input = sine(330)
        for effect in Effect.allCases {
            let small = run(effect, input, block: 160)
            let big = run(effect, input, block: input.count)
            XCTAssertEqual(small, big, "\(effect)")
        }
    }

    func testSwitchingEffectsDropsTheOldTail() {
        var p = VoiceProcessor(sampleRate: rate)
        p.setEffect(.canyon)
        var shout = [Float](repeating: 0, count: 100)
        shout[0] = 0.8
        p.process(&shout)
        p.setEffect(.machine)
        p.setEffect(.canyon)
        var quiet = [Float](repeating: 0, count: Int(rate * 0.6))
        p.process(&quiet)
        XCTAssertEqual(quiet.map(abs).max(), 0, "no echo of what was said before the switch")
    }
}
