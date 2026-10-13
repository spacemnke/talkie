import Foundation
import LiveKit
import TalkieCore

/// Puts your voice effect on the microphone before LiveKit sends it, so the people on your line hear
/// it and you don't. WebRTC calls this on its audio thread in 10 ms chunks; the effect you pick is
/// handed across under a lock.
final class VoiceEffects: NSObject, AudioCustomProcessingDelegate, @unchecked Sendable {
    static let shared = VoiceEffects()

    private let lock = NSLock()
    private var wanted: Effect = .off
    private var processor: VoiceProcessor?
    private var installed = false

    /// WebRTC's samples are floats in the 16-bit range.
    private static let scale: Float = 32768

    /// Hooks into LiveKit's capture path. Called before joining a line; later calls do nothing.
    @MainActor
    func install() {
        guard !installed else { return }
        installed = true
        AudioManager.shared.capturePostProcessingDelegate = self
    }

    /// The effect for everything you say from now on.
    func set(_ effect: Effect) {
        lock.lock()
        wanted = effect
        lock.unlock()
    }

    var audioProcessingName: String { "talkie_voice_effects" }

    func audioProcessingInitialize(sampleRate sampleRateHz: Int, channels: Int) {
        lock.lock()
        processor = VoiceProcessor(sampleRate: Double(sampleRateHz))
        lock.unlock()
    }

    func audioProcessingProcess(audioBuffer: LKAudioBuffer) {
        lock.lock()
        defer { lock.unlock() }
        processor?.setEffect(wanted)
        guard wanted != .off, audioBuffer.channels > 0, audioBuffer.frames > 0 else { return }
        // The microphone is mono; any other channels get the same processed voice.
        let first = audioBuffer.rawBuffer(forChannel: 0)
        processor?.process(UnsafeMutableBufferPointer(start: first, count: audioBuffer.frames), scale: Self.scale)
        for channel in 1..<max(audioBuffer.channels, 1) {
            audioBuffer.rawBuffer(forChannel: channel).update(from: first, count: audioBuffer.frames)
        }
    }

    func audioProcessingRelease() {
        lock.lock()
        processor = nil
        lock.unlock()
    }
}
