import Foundation
import LiveKit

/// The voice on a call: a LiveKit room named after the call's first knock, shared by everyone on
/// it (two people, or a group). Your microphone is published when you join and stays muted except
/// while you hold to talk.
@MainActor
final class Line {
    /// What the token function hands back.
    struct Pass: Decodable, Sendable {
        let url: String
        let token: String
        let room: String
        /// How long this line can last, from everyone's plans: `.some(nil)` is no limit (someone on
        /// the call has Pro), `.some(600)` is a free call. Nil when the server didn't say.
        let limit: TimeInterval??

        enum CodingKeys: String, CodingKey {
            case url, token, room
            case limit = "limit_seconds"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            url = try c.decode(String.self, forKey: .url)
            token = try c.decode(String.self, forKey: .token)
            room = try c.decode(String.self, forKey: .room)
            limit = try c.contains(.limit) ? .some(c.decodeIfPresent(Double.self, forKey: .limit)) : nil
        }
    }

    /// Someone else in the room, by account id, with the name they joined under.
    struct Member: Equatable {
        let id: UUID
        let name: String
    }

    enum Event {
        /// Someone left the room (hung up, or their connection dropped).
        case left(UUID)
        /// Someone came into the room.
        case joined(UUID)
        /// Our own connection dropped.
        case dropped
        /// Who's talking right now.
        case speaking(Set<UUID>)
        case buzz(UUID)
        /// Someone on the call hung up on you (pulled their cord) but stays on with the others.
        case hungUp(UUID)
    }

    var onEvent: ((Event) -> Void)?
    /// The room you're in, if any.
    private(set) var roomName: String?
    private var room: Room?
    private var delegate: LineDelegate?
    /// Bumped on every join and leave, so events from an old room are ignored.
    private var generation = 0
    private var talking = false
    /// People you muted for yourself.
    private var muted: Set<UUID> = []

    var isOpen: Bool { room != nil }

    /// Everyone else in the room.
    var members: [Member] {
        guard let room else { return [] }
        return room.remoteParticipants.values.compactMap { p in
            guard let id = p.identity.flatMap({ UUID(uuidString: $0.stringValue) }) else { return nil }
            return Member(id: id, name: (p.name ?? "").uppercased())
        }
        .sorted { $0.name < $1.name }
    }

    func has(_ id: UUID) -> Bool {
        members.contains { $0.id == id }
    }

    /// Into the call's room. Already in it (you brought this person in), nothing changes.
    func join(_ pass: Pass, muted: Set<UUID>) async throws {
        self.muted = muted
        if room != nil, roomName == pass.room {
            applyVolumes()
            return
        }
        await leave()
        generation += 1
        let gen = generation
        let delegate = LineDelegate { [weak self] event in
            Task { @MainActor in self?.handle(event, generation: gen) }
        }
        // Your voice effect goes on the microphone before it's sent, from the microphone you picked.
        VoiceEffects.shared.install()
        useChosenDevices()
        let room = Room(delegate: delegate)
        self.room = room
        self.delegate = delegate
        roomName = pass.room
        do {
            try await room.connect(url: pass.url, token: pass.token)
            // Publish the microphone once, then keep it muted until you talk.
            try await room.localParticipant.setMicrophone(enabled: true)
            if !talking { try await room.localParticipant.setMicrophone(enabled: false) }
            applyVolumes()
        } catch {
            if generation == gen {
                self.room = nil
                self.delegate = nil
                roomName = nil
            }
            await room.disconnect()
            throw error
        }
    }

    func leave() async {
        guard let room else { return }
        generation += 1
        self.room = nil
        delegate = nil
        roomName = nil
        await room.disconnect()
    }

    /// The microphone and speaker picked in Settings, if they're plugged in; otherwise the Mac's
    /// defaults. Matched by Core Audio's device id, then by name.
    func useChosenDevices() {
        let defaults = UserDefaults.standard
        let audio = AudioManager.shared
        if let uid = defaults.string(forKey: "inputDeviceUID"), !uid.isEmpty {
            let name = AudioDevices.all(input: true).first { $0.uid == uid }?.name
            if let device = audio.inputDevices.first(where: { $0.deviceId == uid || $0.name == name }) {
                audio.inputDevice = device
            }
        }
        if let uid = defaults.string(forKey: "outputDeviceUID"), !uid.isEmpty {
            let name = AudioDevices.all(input: false).first { $0.uid == uid }?.name
            if let device = audio.outputDevices.first(where: { $0.deviceId == uid || $0.name == name }) {
                audio.outputDevice = device
            }
        }
    }

    /// Hold to talk: the microphone goes live only while this is on.
    func setTalking(_ on: Bool) {
        talking = on
        guard let room else { return }
        Task { _ = try? await room.localParticipant.setMicrophone(enabled: on) }
    }

    /// Private mute: turns these people down to nothing on this Mac only. Nothing is sent to them.
    func setMuted(_ ids: Set<UUID>) {
        muted = ids
        applyVolumes()
    }

    /// Buzzes everyone on the call.
    func buzz() {
        send("buzz", to: [])
    }

    /// Tells one person you've hung up on them. You stay on with anyone else.
    func hangUp(on id: UUID) {
        send("hangup", to: [id])
    }

    private func send(_ topic: String, to ids: [UUID]) {
        guard let room else { return }
        let to = ids.map { Participant.Identity(from: $0.uuidString.lowercased()) }
        Task {
            try? await room.localParticipant.publish(
                data: Data(topic.utf8),
                options: DataPublishOptions(destinationIdentities: to, topic: topic, reliable: true)
            )
        }
    }

    private func applyVolumes() {
        guard let room else { return }
        for participant in room.remoteParticipants.values {
            let id = participant.identity.flatMap { UUID(uuidString: $0.stringValue) }
            for publication in participant.audioTracks {
                (publication.track as? RemoteAudioTrack)?.volume = id.map(muted.contains) == true ? 0 : 1
            }
        }
    }

    private func handle(_ event: LineDelegate.Event, generation gen: Int) {
        guard gen == generation else { return }
        switch event {
        case .left(let identity):
            if let id = UUID(uuidString: identity) { onEvent?(.left(id)) }
        case .joined(let identity):
            if let id = UUID(uuidString: identity) { onEvent?(.joined(id)) }
        case .dropped:
            onEvent?(.dropped)
        case .speaking(let identities):
            onEvent?(.speaking(Set(identities.compactMap(UUID.init(uuidString:)))))
        case .data(let identity, let topic):
            guard let id = UUID(uuidString: identity) else { return }
            if topic == "buzz" { onEvent?(.buzz(id)) }
            if topic == "hangup" { onEvent?(.hungUp(id)) }
        case .subscribed:
            applyVolumes()
        }
    }
}

/// Hears from LiveKit on its own threads and passes plain values on.
private final class LineDelegate: NSObject, RoomDelegate, @unchecked Sendable {
    enum Event: Sendable {
        case left(String)
        case joined(String)
        case dropped
        case speaking(Set<String>)
        case data(String, topic: String)
        case subscribed(String)
    }

    private let send: @Sendable (Event) -> Void

    init(_ send: @escaping @Sendable (Event) -> Void) {
        self.send = send
    }

    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        if let identity = participant.identity?.stringValue { send(.joined(identity)) }
    }

    func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        if let identity = participant.identity?.stringValue { send(.left(identity)) }
    }

    func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        send(.dropped)
    }

    func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        send(.speaking(Set(participants.compactMap { ($0 as? RemoteParticipant)?.identity?.stringValue })))
    }

    func room(_ room: Room, participant: RemoteParticipant?, didReceiveData data: Data, forTopic topic: String, encryptionType: EncryptionType) {
        if let identity = participant?.identity?.stringValue { send(.data(identity, topic: topic)) }
    }

    func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        if let identity = participant.identity?.stringValue { send(.subscribed(identity)) }
    }
}
