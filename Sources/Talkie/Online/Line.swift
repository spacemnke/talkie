import Foundation
import LiveKit

/// The voice on an open line: a LiveKit room the two of you share, named after the knock.
/// Your microphone is published when you join and stays muted except while you hold to talk.
@MainActor
final class Line {
    /// What the token function hands back.
    struct Pass: Decodable, Sendable {
        let url: String
        let token: String
        let room: String
    }

    enum Event {
        /// They hung up, or their connection dropped.
        case peerLeft(UUID)
        /// Our own connection dropped.
        case dropped(UUID)
        case speaking(UUID, Bool)
        case buzz(UUID)
    }

    var onEvent: ((Event) -> Void)?
    /// Who's on the other end, by account id.
    private(set) var peer: UUID?
    private var room: Room?
    private var delegate: LineDelegate?
    /// Bumped on every join and leave, so events from an old room are ignored.
    private var generation = 0
    private var talking = false
    private var peerMuted = false
    private var peerSpeaking = false

    var isOpen: Bool { room != nil }

    func join(_ pass: Pass, peer: UUID, muted: Bool) async throws {
        await leave()
        generation += 1
        let gen = generation
        let delegate = LineDelegate { [weak self] event in
            Task { @MainActor in self?.handle(event, generation: gen) }
        }
        let room = Room(delegate: delegate)
        self.room = room
        self.delegate = delegate
        self.peer = peer
        peerMuted = muted
        peerSpeaking = false
        do {
            try await room.connect(url: pass.url, token: pass.token)
            // Publish the microphone once, then keep it muted until you talk.
            try await room.localParticipant.setMicrophone(enabled: true)
            if !talking { try await room.localParticipant.setMicrophone(enabled: false) }
            applyPeerVolume()
        } catch {
            if generation == gen {
                self.room = nil
                self.delegate = nil
                self.peer = nil
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
        peer = nil
        peerSpeaking = false
        await room.disconnect()
    }

    /// Hold to talk: the microphone goes live only while this is on.
    func setTalking(_ on: Bool) {
        talking = on
        guard let room else { return }
        Task { _ = try? await room.localParticipant.setMicrophone(enabled: on) }
    }

    /// Private mute: turns their voice down to nothing on this Mac only. Nothing is sent to them.
    func setPeerMuted(_ muted: Bool) {
        peerMuted = muted
        applyPeerVolume()
    }

    func buzz() {
        guard let room else { return }
        Task {
            try? await room.localParticipant.publish(data: Data("buzz".utf8), options: DataPublishOptions(topic: "buzz", reliable: true))
        }
    }

    private func applyPeerVolume() {
        guard let room, let peer else { return }
        for participant in room.remoteParticipants.values where participant.identity.flatMap({ UUID(uuidString: $0.stringValue) }) == peer {
            for publication in participant.audioTracks {
                (publication.track as? RemoteAudioTrack)?.volume = peerMuted ? 0 : 1
            }
        }
    }

    private func handle(_ event: LineDelegate.Event, generation gen: Int) {
        guard gen == generation, let peer else { return }
        switch event {
        case .left(let identity):
            guard UUID(uuidString: identity) == peer else { return }
            onEvent?(.peerLeft(peer))
        case .dropped:
            onEvent?(.dropped(peer))
        case .speaking(let identities):
            let now = identities.contains { UUID(uuidString: $0) == peer }
            guard now != peerSpeaking else { return }
            peerSpeaking = now
            onEvent?(.speaking(peer, now))
        case .data(let identity, let topic):
            guard topic == "buzz", UUID(uuidString: identity) == peer else { return }
            onEvent?(.buzz(peer))
        case .subscribed:
            applyPeerVolume()
        }
    }
}

/// Hears from LiveKit on its own threads and passes plain values on.
private final class LineDelegate: NSObject, RoomDelegate, @unchecked Sendable {
    enum Event: Sendable {
        case left(String)
        case dropped
        case speaking(Set<String>)
        case data(String, topic: String)
        case subscribed(String)
    }

    private let send: @Sendable (Event) -> Void

    init(_ send: @escaping @Sendable (Event) -> Void) {
        self.send = send
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
