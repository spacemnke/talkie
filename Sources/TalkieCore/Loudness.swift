import Foundation

/// How loud some audio is, as a meter reading from 0 (silence, below -55 dB) to 1 (-5 dB and up).
/// The same scale everywhere: the board's meter, the mic's lights and the Settings meter.
public enum Loudness {
    /// Root mean square of some samples (full scale is 1).
    public static func rms(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for x in samples { sum += x * x }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// The same for 16-bit samples.
    public static func rms(_ samples: UnsafeBufferPointer<Int16>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples {
            let x = Float(s) / 32768
            sum += x * x
        }
        return (sum / Float(samples.count)).squareRoot()
    }

    public static func meter(rms: Float) -> Double {
        meter(decibels: 20 * log10(max(Double(rms), 0.000_01)))
    }

    /// The same from a level already in decibels (0 is full scale), as macOS's capture meters give it.
    public static func meter(decibels: Double) -> Double {
        guard decibels.isFinite else { return 0 }
        return min(max((decibels + 55) / 50, 0), 1)
    }

    /// Below this, a microphone is sending pure digital silence: real ones always hiss a little.
    public static let silence: Double = -100
}
