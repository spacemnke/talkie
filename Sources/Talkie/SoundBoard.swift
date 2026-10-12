import AVFoundation

/// The board's little sounds, synthesized once at launch. Output only; no microphone access.
@MainActor
final class SoundBoard {
    enum Sound: CaseIterable {
        case plug, unplug, open, close, key, click, over, buzz, deny, drop, stow
        /// A friend you added lands on the board.
        case accept
    }

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var started = false

    /// 0...1. Zero silences everything.
    var volume: Float = 0.63 {
        didSet { engine.mainMixerNode.outputVolume = volume }
    }

    init() {
        for _ in 0..<4 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = volume
        for s in Sound.allCases { buffers[s] = Self.render(s, format: format) }
    }

    func play(_ sound: Sound) {
        guard volume > 0, let buffer = buffers[sound] else { return }
        if !started {
            do { try engine.start() } catch { return }
            started = true
        }
        let p = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        p.stop()
        p.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        p.play()
    }

    private static func render(_ sound: Sound, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        var s = Synth(sampleRate: format.sampleRate)
        switch sound {
        case .plug:
            s.noise(at: 0, duration: 0.035, peak: 0.6, center: 3200, q: 1.2)
            s.tone(at: 0, duration: 0.1, peak: 0.5, from: 120, to: 50, wave: .sine)
        case .unplug:
            s.tone(at: 0, duration: 0.07, peak: 0.22, from: 520, to: 160, wave: .sine)
            s.noise(at: 0, duration: 0.03, peak: 0.25, center: 2600, q: 1)
        case .open:
            s.tone(at: 0, duration: 0.05, peak: 0.05, from: 880, to: 880, wave: .square)
            s.tone(at: 0.065, duration: 0.07, peak: 0.05, from: 1320, to: 1320, wave: .square)
        case .close:
            s.tone(at: 0, duration: 0.05, peak: 0.05, from: 1100, to: 1100, wave: .square)
            s.tone(at: 0.065, duration: 0.08, peak: 0.05, from: 660, to: 660, wave: .square)
        case .key:
            s.noise(at: 0, duration: 0.05, peak: 0.16, center: 1400, q: 0.7)
        case .click:
            s.tone(at: 0, duration: 0.025, peak: 0.06, from: 1900, to: 1900, wave: .square)
        case .over:
            // the "roger" beep after you let go
            s.noise(at: 0, duration: 0.12, peak: 0.22, center: 1800, q: 0.6)
            s.tone(at: 0.13, duration: 0.06, peak: 0.05, from: 1250, to: 1250, wave: .square)
            s.tone(at: 0.2, duration: 0.09, peak: 0.05, from: 940, to: 940, wave: .square)
        case .buzz:
            for i in 0..<6 {
                let f: Double = i % 2 == 0 ? 1040 : 1480
                s.tone(at: Double(i) * 0.1, duration: 0.085, peak: 0.06, from: f, to: f, wave: .square)
            }
        case .deny:
            s.tone(at: 0, duration: 0.14, peak: 0.08, from: 200, to: 200, wave: .square)
        case .drop:
            s.tone(at: 0, duration: 0.24, peak: 0.05, from: 900, to: 220, wave: .sine)
            s.noise(at: 0, duration: 0.08, peak: 0.12, center: 2200, q: 0.8)
            s.tone(at: 0.2, duration: 0.12, peak: 0.25, from: 140, to: 70, wave: .sine)
        case .stow:
            s.tone(at: 0, duration: 0.2, peak: 0.05, from: 220, to: 950, wave: .sine)
            s.noise(at: 0.16, duration: 0.05, peak: 0.1, center: 3000, q: 1)
        case .accept:
            s.tone(at: 0, duration: 0.07, peak: 0.05, from: 1046, to: 1046, wave: .square)
            s.tone(at: 0.08, duration: 0.12, peak: 0.05, from: 1568, to: 1568, wave: .square)
        }
        return s.buffer(format: format)
    }
}

/// A tiny offline synth: enveloped tones and band-passed noise mixed into one buffer.
private struct Synth {
    enum Wave { case sine, square }

    let sampleRate: Double
    var samples: [Float] = []

    init(sampleRate: Double) { self.sampleRate = sampleRate }

    private mutating func ensure(_ count: Int) {
        if samples.count < count { samples += [Float](repeating: 0, count: count - samples.count) }
    }

    /// Attack in 4 ms, then an exponential fall to silence by the end.
    private func envelope(_ t: Double, duration: Double, peak: Double) -> Double {
        let attack = 0.004
        if t < attack { return peak * t / attack }
        let floor = 0.0001
        return peak * pow(floor / peak, (t - attack) / max(duration - attack, 0.001))
    }

    mutating func tone(at start: Double, duration: Double, peak: Double, from f0: Double, to f1: Double, wave: Wave) {
        let first = Int(start * sampleRate)
        let count = Int(duration * sampleRate)
        ensure(first + count)
        var phase = 0.0
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let f = f0 * pow(f1 / f0, t / duration)
            phase += 2 * .pi * f / sampleRate
            let raw = sin(phase)
            let v = wave == .square ? (raw >= 0 ? 1.0 : -1.0) : raw
            samples[first + i] += Float(v * envelope(t, duration: duration, peak: peak))
        }
    }

    mutating func noise(at start: Double, duration: Double, peak: Double, center: Double, q: Double) {
        let first = Int(start * sampleRate)
        let count = Int(duration * sampleRate)
        ensure(first + count)
        // band-pass biquad (constant 0 dB peak gain)
        let w0 = 2 * .pi * center / sampleRate
        let alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha, a1 = -2 * cos(w0), a2 = 1 - alpha
        let b0 = alpha, b2 = -alpha
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in 0..<count {
            let x = Double.random(in: -1...1)
            let y = (b0 * x + b2 * x2 - a1 * y1 - a2 * y2) / a0
            x2 = x1; x1 = x; y2 = y1; y1 = y
            let t = Double(i) / sampleRate
            samples[first + i] += Float(y * 3 * envelope(t, duration: duration, peak: peak))
        }
    }

    func buffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let tail = Int(0.03 * sampleRate)
        let frames = AVAudioFrameCount(samples.count + tail)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            channel[i] = i < samples.count ? max(-1, min(1, samples[i])) : 0
        }
        return buffer
    }
}
