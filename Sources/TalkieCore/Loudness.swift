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
        let decibels = 20 * log10(max(Double(rms), 0.000_01))
        return min(max((decibels + 55) / 50, 0), 1)
    }
}
