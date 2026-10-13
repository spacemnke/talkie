import AVFoundation
import LiveKit
import TalkieCore

/// How loud the audio passing through LiveKit is: your microphone (after your voice effect) or
/// everyone you're hearing. LiveKit calls it on its audio threads; the board reads it each frame.
final class LevelMeter: NSObject, AudioRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = 0
    private var heardAt = Date.distantPast

    /// 0...1 on the board's meter scale. Falls to nothing when the audio stops coming.
    var level: Double {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSince(heardAt) < 0.25 ? value : 0
    }

    func render(pcmBuffer: AVAudioPCMBuffer) {
        let count = Int(pcmBuffer.frameLength)
        var loudest: Float = 0
        for c in 0..<Int(pcmBuffer.format.channelCount) {
            if let floats = pcmBuffer.floatChannelData {
                loudest = max(loudest, Loudness.rms(UnsafeBufferPointer(start: floats[c], count: count)))
            } else if let ints = pcmBuffer.int16ChannelData {
                loudest = max(loudest, Loudness.rms(UnsafeBufferPointer(start: ints[c], count: count)))
            }
        }
        let reading = Loudness.meter(rms: loudest)
        lock.lock()
        value = reading
        heardAt = Date()
        lock.unlock()
    }
}
