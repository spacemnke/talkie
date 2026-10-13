import AppKit
import AVFoundation
import CoreAudio
import Observation
import TalkieCore

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

/// The live input level for the Settings meter (and your level while you hold to talk on the
/// practice board), from the microphone picked in Settings, or the Mac's default if it's gone.
///
/// Listens through AVCaptureSession, which opens exactly the microphone asked for and meters it
/// itself. (An AVAudioEngine pointed at one microphone while the Mac plays through another can
/// hear nothing at all.) Keeps trying until microphone access is given, and says why when it
/// can't hear anything.
@MainActor
@Observable
final class InputLevel {
    private(set) var level: Double = 0
    /// Why the meter isn't moving, when we know.
    private(set) var problem: String?
    @ObservationIgnored private var session: AVCaptureSession?
    @ObservationIgnored private var output: AVCaptureAudioDataOutput?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var deviceUID: String?
    @ObservationIgnored private var deviceName = ""
    @ObservationIgnored private var asking = false
    /// When the microphone last sent anything other than pure silence.
    @ObservationIgnored private var lastSignal = Date()
    @ObservationIgnored private let sink = CaptureSink()
    @ObservationIgnored private let queue = DispatchQueue(label: "talkie.input-level")

    /// Start listening (or switch to another microphone).
    func start(deviceUID: String?) {
        self.deviceUID = deviceUID
        stopSession()
        attempt()
        if timer == nil {
            // Twenty readings a second for the bars; a retry once a second if it isn't running.
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        stopSession()
        level = 0
        problem = nil
    }

    private func stopSession() {
        guard let session else { return }
        self.session = nil
        output = nil
        queue.async { session.stopRunning() }
    }

    private func poll() {
        ticks += 1
        guard let output else {
            if ticks % 20 == 0 { attempt() }
            return
        }
        let decibels = output.connections.flatMap(\.audioChannels).map { Double($0.averagePowerLevel) }.max() ?? -.infinity
        level = Loudness.meter(decibels: decibels)
        if decibels > Loudness.silence {
            lastSignal = Date()
            if problem != nil { problem = nil }
        } else if Date().timeIntervalSince(lastSignal) > 3 {
            // Real microphones always pick up a little noise; nothing at all means nothing is coming through.
            problem = "NO SOUND FROM \(deviceName)"
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
        // The microphone you picked (Core Audio's id is the capture device's id), else the default.
        guard let device = deviceUID.flatMap({ AVCaptureDevice(uniqueID: $0) }) ?? AVCaptureDevice.default(for: .audio) else {
            problem = "NO MICROPHONE FOUND"
            return
        }
        let session = AVCaptureSession()
        let output = AVCaptureAudioDataOutput()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(output) else { throw CocoaError(.featureUnsupported) }
            session.addInput(input)
            output.setSampleBufferDelegate(sink, queue: queue)
            session.addOutput(output)
        } catch {
            problem = "\(device.localizedName.uppercased()) DIDN'T START"
            return
        }
        self.session = session
        self.output = output
        deviceName = device.localizedName.uppercased()
        lastSignal = Date()
        problem = nil
        queue.async { session.startRunning() }
    }
}

/// Takes the captured audio so it keeps flowing; the meter reads the session's own levels.
private final class CaptureSink: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {}
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
