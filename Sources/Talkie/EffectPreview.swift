import AVFoundation
import Observation
import TalkieCore

/// Hear an effect on your own voice: hold to record a few seconds, let go to hear it played back
/// with the effect. Anyone can try them; Pro puts them on your calls.
@MainActor
@Observable
final class EffectPreview {
    enum State { case idle, recording, playing }

    private(set) var state: State = .idle
    private(set) var problem: String?

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var player: AVAudioPlayerNode?
    @ObservationIgnored private let take = Take()

    /// The longest take, in seconds.
    private static let longest = 6.0

    func startRecording() {
        guard state != .recording else { return }
        stopEverything()
        problem = nil
        switch MicPermission.current {
        case .granted: break
        case .undetermined:
            Task {
                if await MicPermission.request() == .denied { problem = "TALKIE NEEDS THE MICROPHONE" }
            }
            return
        case .denied:
            problem = "ALLOW THE MICROPHONE IN SYSTEM SETTINGS"
            return
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            problem = "NO MICROPHONE"
            return
        }
        take.start(sampleRate: format.sampleRate, limit: Int(format.sampleRate * Self.longest))
        let take = self.take
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            take.append(samples, count: Int(buffer.frameLength))
        }
        do {
            try engine.start()
            self.engine = engine
            state = .recording
        } catch {
            input.removeTap(onBus: 0)
            problem = "THE MICROPHONE DIDN'T START"
        }
    }

    /// Let go: play back what you said, through the effect.
    func stopRecording(effect: Effect, volume: Float) {
        guard state == .recording else { return }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        let (recorded, rate) = take.finish()
        var samples = recorded
        guard samples.count > Int(rate * 0.2) else {
            state = .idle
            problem = "HOLD A LITTLE LONGER"
            return
        }
        var processor = VoiceProcessor(sampleRate: rate)
        processor.setEffect(effect)
        processor.process(&samples)
        play(samples, sampleRate: rate, volume: volume)
    }

    func stopEverything() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        player?.stop()
        player = nil
        state = .idle
    }

    private func play(_ samples: [Float], sampleRate: Double, volume: Float) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            state = .idle
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = max(volume, 0.3)
        do {
            try engine.start()
        } catch {
            state = .idle
            problem = "COULDN'T PLAY IT BACK"
            return
        }
        self.engine = engine
        self.player = player
        state = .playing
        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                guard let self, self.player === player else { return }
                self.stopEverything()
            }
        }
        player.play()
    }
}

/// The samples recorded so far. Filled on the audio thread, read on the main one.
private final class Take: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var rate = 48_000.0
    private var limit = 0

    func start(sampleRate: Double, limit: Int) {
        lock.lock()
        samples = []
        samples.reserveCapacity(limit)
        rate = sampleRate
        self.limit = limit
        lock.unlock()
    }

    func append(_ data: UnsafePointer<Float>, count: Int) {
        lock.lock()
        let room = max(0, min(count, limit - samples.count))
        samples.append(contentsOf: UnsafeBufferPointer(start: data, count: room))
        lock.unlock()
    }

    func finish() -> ([Float], Double) {
        lock.lock()
        defer {
            samples = []
            lock.unlock()
        }
        return (samples, rate)
    }
}
