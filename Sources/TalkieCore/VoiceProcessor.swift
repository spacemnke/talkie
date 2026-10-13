import Foundation

/// What the voice effects do to the sound of your voice, before it's sent.
///
/// Canyon comes back twice off the far wall, Tin Can is thin and crunchy, Helium is an octave up,
/// and Machine is ring-modulated. Mono, any block size, and nothing is allocated while processing,
/// so it can run on the audio thread. Changing the effect starts it fresh, without the old one's tail.
public struct VoiceProcessor {
    public private(set) var effect: Effect = .off
    public let sampleRate: Double

    // Canyon
    private var echo: DelayLine
    private var echoTone = OnePole()
    // Tin Can
    private var lowCut: Biquad
    private var highCut: Biquad
    private var can: DelayLine
    // Helium
    private var pitch: DelayLine
    private var pitchPhase = 0.0
    // Machine
    private var carrierPhase = 0.0
    private var buzz: DelayLine

    public init(sampleRate: Double) {
        let rate = max(sampleRate, 8000)
        self.sampleRate = rate
        echo = DelayLine(capacity: Int(rate * 0.6))
        lowCut = .highPass(600, q: 0.8, rate: rate)
        highCut = .lowPass(2800, q: 0.9, rate: rate)
        can = DelayLine(capacity: Int(rate * 0.004))
        pitch = DelayLine(capacity: Int(rate * Self.pitchWindow) + 4)
        buzz = DelayLine(capacity: Int(rate * 0.006))
    }

    public mutating func setEffect(_ next: Effect) {
        guard next != effect else { return }
        effect = next
        reset()
    }

    /// Processes samples in place. `scale` is what full level is in these samples: 1 for ordinary
    /// float audio, 32768 for the 16-bit range WebRTC hands over.
    public mutating func process(_ samples: UnsafeMutableBufferPointer<Float>, scale: Float = 1) {
        guard effect != .off, scale > 0 else { return }
        let inv = 1 / scale
        for i in samples.indices {
            let x = Double(samples[i] * inv)
            let y: Double
            switch effect {
            case .off: y = x
            case .canyon: y = canyon(x)
            case .tinCan: y = tinCan(x)
            case .helium: y = helium(x)
            case .machine: y = machine(x)
            }
            // Never louder than full scale: a soft ceiling rather than a hard clip.
            samples[i] = Float(tanh(y)) * scale
        }
    }

    /// Convenience for tests and previews.
    public mutating func process(_ samples: inout [Float], scale: Float = 1) {
        samples.withUnsafeMutableBufferPointer { process($0, scale: scale) }
    }

    // MARK: The effects

    private static let echoNear = 0.28, echoFar = 0.47

    /// Two echoes off the canyon walls; the far one keeps coming back, a little darker each time.
    private mutating func canyon(_ x: Double) -> Double {
        let near = echo.read(Self.echoNear * sampleRate)
        let far = echo.read(Self.echoFar * sampleRate)
        let fed = echoTone.lowPass(far, amount: 0.35)
        echo.write(x + 0.38 * fed)
        return x + 0.5 * near + 0.42 * far
    }

    /// Telephone band, driven hard, through a short tin resonance.
    private mutating func tinCan(_ x: Double) -> Double {
        let band = highCut.process(lowCut.process(x))
        let driven = tanh(band * 4.5) * 0.55
        let ring = can.read(0.0021 * sampleRate)
        can.write(driven + 0.45 * ring)
        return driven + 0.35 * ring
    }

    private static let pitchWindow = 0.045

    /// An octave up: two read heads sweep through a short delay at twice the speed, crossfading
    /// so neither is heard as it jumps back.
    private mutating func helium(_ x: Double) -> Double {
        pitch.write(x)
        let window = Self.pitchWindow * sampleRate
        let ratio = 2.0
        pitchPhase += (ratio - 1) / window
        if pitchPhase >= 1 { pitchPhase -= 1 }
        let other = pitchPhase >= 0.5 ? pitchPhase - 0.5 : pitchPhase + 0.5
        let a = pitch.read(1 + (1 - pitchPhase) * window) * sin(.pi * pitchPhase)
        let b = pitch.read(1 + (1 - other) * window) * sin(.pi * other)
        return a + b
    }

    /// Ring-modulated at 50 Hz, with a short metallic buzz.
    private mutating func machine(_ x: Double) -> Double {
        carrierPhase += 50 / sampleRate
        if carrierPhase >= 1 { carrierPhase -= 1 }
        let ring = x * sin(2 * .pi * carrierPhase) * 1.4
        let back = buzz.read(0.005 * sampleRate)
        buzz.write(ring + 0.4 * back)
        return ring + 0.3 * back
    }

    private mutating func reset() {
        echo.clear()
        echoTone = OnePole()
        lowCut.clear()
        highCut.clear()
        can.clear()
        pitch.clear()
        pitchPhase = 0
        carrierPhase = 0
        buzz.clear()
    }
}

/// A ring buffer you can read from any distance back, between samples too.
struct DelayLine {
    private var buffer: [Double]
    private var head = 0

    init(capacity: Int) {
        buffer = Array(repeating: 0, count: max(capacity, 2) + 2)
    }

    mutating func write(_ x: Double) {
        head += 1
        if head == buffer.count { head = 0 }
        buffer[head] = x
    }

    /// The sample written `delay` samples ago (0 is the newest), with linear interpolation.
    func read(_ delay: Double) -> Double {
        let d = min(max(delay, 0), Double(buffer.count - 2))
        let whole = Int(d)
        let frac = d - Double(whole)
        var i = head - whole
        if i < 0 { i += buffer.count }
        var j = i - 1
        if j < 0 { j += buffer.count }
        return buffer[i] + (buffer[j] - buffer[i]) * frac
    }

    mutating func clear() {
        for i in buffer.indices { buffer[i] = 0 }
        head = 0
    }
}

/// A one-pole low-pass, for darkening echoes.
struct OnePole {
    private var last = 0.0

    mutating func lowPass(_ x: Double, amount: Double) -> Double {
        last += (x - last) * (1 - amount)
        return last
    }
}

/// A second-order filter (the RBJ cookbook's low- and high-pass).
struct Biquad {
    private let b0, b1, b2, a1, a2: Double
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    private init(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) {
        self.b0 = b0 / a0
        self.b1 = b1 / a0
        self.b2 = b2 / a0
        self.a1 = a1 / a0
        self.a2 = a2 / a0
    }

    static func lowPass(_ cutoff: Double, q: Double, rate: Double) -> Biquad {
        let w = 2 * .pi * cutoff / rate, alpha = sin(w) / (2 * q), c = cos(w)
        return Biquad(b0: (1 - c) / 2, b1: 1 - c, b2: (1 - c) / 2, a0: 1 + alpha, a1: -2 * c, a2: 1 - alpha)
    }

    static func highPass(_ cutoff: Double, q: Double, rate: Double) -> Biquad {
        let w = 2 * .pi * cutoff / rate, alpha = sin(w) / (2 * q), c = cos(w)
        return Biquad(b0: (1 + c) / 2, b1: -(1 + c), b2: (1 + c) / 2, a0: 1 + alpha, a1: -2 * c, a2: 1 - alpha)
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }

    mutating func clear() {
        x1 = 0; x2 = 0; y1 = 0; y2 = 0
    }
}
