import AppKit
import AVFoundation
import AudioToolbox
import CoreAudio
import Observation

/// A microphone or speaker the Mac knows about.
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

/// Lists audio devices through Core Audio.
enum AudioDevices {
    static func all(input: Bool) -> [AudioDevice] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard channels(id, input: input) > 0,
                  let name = string(id, kAudioObjectPropertyName),
                  let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            return AudioDevice(id: id, uid: uid, name: name)
        }
    }

    static func defaultUID(input: Bool) -> String? {
        var address = Self.address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr else { return nil }
        return string(id, kAudioDevicePropertyDeviceUID)
    }

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func channels(_ id: AudioDeviceID, input: Bool) -> Int {
        var address = Self.address(kAudioDevicePropertyStreamConfiguration,
                                   scope: input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = Self.address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }
}

/// The live input level for the settings meter, from the microphone you picked (the Mac's default
/// if it's gone). Runs while Settings is open; keeps trying until microphone access is given, and
/// says why when it can't hear anything.
@MainActor
@Observable
final class InputLevel {
    private(set) var level: Double = 0
    /// Why the meter isn't moving, when we know.
    private(set) var problem: String?
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var deviceUID: String?
    @ObservationIgnored private var asking = false
    /// When the microphone last sent anything other than pure silence.
    @ObservationIgnored private var lastSignal = Date()

    /// Start listening (or switch to another microphone).
    func start(deviceUID: String?) {
        self.deviceUID = deviceUID
        stopEngine()
        attempt()
        if timer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        stopEngine()
        level = 0
        problem = nil
    }

    private func stopEngine() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    /// Once a second: try again if it isn't running, and notice a microphone sending nothing at all.
    private func check() {
        guard engine != nil else {
            attempt()
            return
        }
        // Real microphones always pick up a little noise; exact zeros mean nothing is coming through.
        if Date().timeIntervalSince(lastSignal) > 3 {
            problem = "NO SOUND FROM THIS MICROPHONE"
            level = 0
        }
    }

    private func attempt() {
        switch MicPermission.current {
        case .denied:
            problem = "ALLOW THE MICROPHONE IN SYSTEM SETTINGS"
            return
        case .undetermined:
            problem = "TALKIE NEEDS THE MICROPHONE"
            if !asking {
                asking = true
                Task {
                    _ = await MicPermission.request()
                    asking = false
                }
            }
            return
        case .granted:
            break
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        // The microphone you picked, if it's plugged in; otherwise the Mac's default.
        if let uid = deviceUID, let device = AudioDevices.all(input: true).first(where: { $0.uid == uid }),
           let unit = input.audioUnit {
            var id = device.id
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            problem = "NO MICROPHONE FOUND"
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let count = Int(buffer.frameLength)
            // The loudest channel: some microphones only send on one side.
            var loudest: Float = 0
            var signal = false
            for c in 0..<Int(buffer.format.channelCount) {
                var sum: Float = 0
                for i in 0..<count {
                    let x = channels[c][i]
                    sum += x * x
                    if x != 0 { signal = true }
                }
                loudest = max(loudest, (sum / Float(max(count, 1))).squareRoot())
            }
            let decibels = 20 * log10(max(loudest, 0.000_01))
            let value = Double(min(max((decibels + 55) / 50, 0), 1))
            Task { @MainActor in self?.heard(value, signal: signal) }
        }
        do {
            try engine.start()
            self.engine = engine
            lastSignal = Date()
            problem = nil
        } catch {
            input.removeTap(onBus: 0)
            problem = "THE MICROPHONE DIDN'T START"
        }
    }

    private func heard(_ value: Double, signal: Bool) {
        guard engine != nil else { return }
        level = value
        if signal {
            lastSignal = Date()
            if problem != nil { problem = nil }
        }
    }
}

/// Where microphone access stands.
enum MicPermission {
    case undetermined, granted, denied

    static var current: MicPermission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .undetermined
        default: return .denied
        }
    }

    static func request() async -> MicPermission {
        await AVCaptureDevice.requestAccess(for: .audio) ? .granted : .denied
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}
