import Foundation
import Supabase
import TalkieCore

/// Where Talkie's operator lives. The key is the project's public (anon) key: it only identifies
/// the project, and row-level security decides what anyone signed in can see or change.
enum Backend {
    static let url = URL(string: "https://xakscsouugwlyefaieyl.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhha3Njc291dWd3bHllZmFpZXlsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE4Mjk2ODEsImV4cCI6MjEwNzQwNTY4MX0.TXm0gnDiNHm3On8pV5zSZ4Fjot7qq-_8uCNqVb9lnZQ"
}

/// Keeps the sign-in in Talkie's preferences rather than the keychain: test builds are signed
/// ad hoc, so every new build would otherwise have to ask for keychain access.
private struct DefaultsAuthStorage: AuthLocalStorage {
    private func key(_ key: String) -> String { "talkie.auth." + key }
    func store(key: String, value: Data) throws { UserDefaults.standard.set(value, forKey: self.key(key)) }
    func retrieve(key: String) throws -> Data? { UserDefaults.standard.data(forKey: self.key(key)) }
    func remove(key: String) throws { UserDefaults.standard.removeObject(forKey: self.key(key)) }
}

/// Talkie's operator: your account and code, your board on the server, who's around, and knocks.
/// Turns what arrives from the network into board changes, and board changes into network calls.
@MainActor
final class Operator {
    enum Status: Equatable {
        case connecting
        case online(code: String)
        case offline(String)
    }

    private(set) var status: Status = .connecting
    let line = Line()

    private unowned let model: BoardModel
    private let client: SupabaseClient
    private var me: UUID?
    /// Your account, once the operator has answered. Checkout tags purchases with it.
    var account: UUID? { me }
    /// Friends' accounts by the local id the switchboard knows them by, and back again.
    private var accounts: [Int: UUID] = [:]
    private var localIDs: [UUID: Int] = [:]
    /// Knocks in flight, by the friend's account.
    private var outgoing: [UUID: UUID] = [:]
    private var incoming: [UUID: UUID] = [:]
    /// Friends knocking from a call of their own (letting them in means joining it).
    private var incomingFromCall: Set<UUID> = []
    /// The call you're on or starting: its first knock, which names its room. Nil between calls.
    private var group: UUID?
    /// Knocks go out one after another, so a second one knows which call the first started.
    private var knockChain: Task<Void, Never>?
    /// Who was talking at last count, for people on the call who aren't on your lines.
    private var lastSpeaking: Set<UUID> = []
    /// Everything live comes down one channel: knocks to and from you, and friends' check-ins.
    private var channel: RealtimeChannelV2?
    private var listeners: [Task<Void, Never>] = []
    private var retry: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    /// When each friend last checked in, by this Mac's clock, and whether they're on DND.
    private var heardFrom: [UUID: Date] = [:]
    private var friendDND: [UUID: Bool] = [:]
    /// A friend who hasn't checked in for this long has gone away (they check in every 30 seconds).
    private static let awayAfter: TimeInterval = 75
    /// Your Pro columns as last seen, to notice when they change.
    private var proStamp: String?

    /// A friend's profile as it changes: they checked in, signed off or switched DND.
    /// Your own row comes through too, which is how going Pro arrives.
    private struct CheckIn: Decodable {
        let id: UUID
        let dnd: Bool
        let lastSeen: String?
        let pro: Bool?
        let proUntil: String?

        enum CodingKeys: String, CodingKey {
            case id, dnd, pro
            case lastSeen = "last_seen"
            case proUntil = "pro_until"
        }
    }

    private struct ProfileRow: Decodable {
        let id: UUID
        let code: String
        let name: String
        let pro: Bool?
        let proUntil: String?

        enum CodingKeys: String, CodingKey {
            case id, code, name, pro
            case proUntil = "pro_until"
        }
    }

    /// Your Pro columns, to notice when they change.
    private static func stamp(pro: Bool?, until: String?) -> String {
        "\(pro ?? false)|\(until ?? "")"
    }

    private struct BoardRow: Decodable {
        struct Profile: Decodable { let name: String }
        let jack: Int
        let friend: UUID
        let profile: Profile?
    }

    private struct KnockRow: Decodable {
        let id: UUID
        let caller: UUID
        let callee: UUID
        let callerName: String
        let callerCode: String
        let status: String
        /// The call this knock belongs to, if it isn't the first knock of one.
        let groupID: UUID?

        enum CodingKeys: String, CodingKey {
            case id, caller, callee, status
            case callerName = "caller_name"
            case callerCode = "caller_code"
            case groupID = "group_id"
        }

        /// The call's first knock, which names its room.
        var call: UUID { groupID ?? id }
    }

    private static let savedIDs = "onlineFriendIDs"

    init(model: BoardModel) {
        self.model = model
        client = SupabaseClient(
            supabaseURL: Backend.url,
            supabaseKey: Backend.anonKey,
            options: SupabaseClientOptions(auth: .init(storage: DefaultsAuthStorage(), emitLocalSessionAsInitialSession: true))
        )
        if let saved = UserDefaults.standard.dictionary(forKey: Self.savedIDs) as? [String: Int] {
            for (key, id) in saved {
                if let account = UUID(uuidString: key) { localIDs[account] = id }
            }
        }
        line.onEvent = { [weak self] event in self?.lineEvent(event) }
    }

    // MARK: Connecting

    func connect() {
        retry?.cancel()
        status = .connecting
        Task { await connectNow() }
    }

    /// Back to the practice board: sign off so friends see you go, then hang up everything.
    func disconnect() {
        retry?.cancel()
        Task {
            await signOff(timeout: 2)
            await teardown()
        }
    }

    /// Quitting: tell friends you've gone, so you show as away at once rather than after a minute.
    func signOff(timeout: TimeInterval) async {
        heartbeat?.cancel()
        let client = self.client, line = self.line
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = try? await client.rpc("sign_off").execute()
                await line.leave()
            }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)) }
            _ = await group.next()
            group.cancelAll()
        }
    }

    private func connectNow() async {
        await teardown()
        do {
            if (try? await client.auth.session) == nil {
                _ = try await client.auth.signInAnonymously()
            }
            let profile: ProfileRow = try await client.rpc("ensure_profile", params: ["display_name": model.myName]).execute().value
            me = profile.id
            proStamp = Self.stamp(pro: profile.pro, until: profile.proUntil)
            let plan = try await fetchPlan()
            let rows: [BoardRow] = try await client.from("board")
                .select("jack, friend, profile:profiles!board_friend_fkey(name)")
                .eq("owner", value: profile.id.uuidString.lowercased())
                .execute().value
            var friends = [Friend?](repeating: nil, count: 8)
            accounts = [:]
            for row in rows where friends.indices.contains(row.jack) {
                let id = localID(for: row.friend)
                friends[row.jack] = Friend(id: id, name: (row.profile?.name ?? "FRIEND").uppercased(), online: false)
            }
            model.operatorConnected(code: profile.code, friends: friends, plan: plan)
            try await listen(me: profile.id)
            await checkIn()
            await refreshPresence()
            await catchUpKnocks()
            status = .online(code: profile.code)
            startHeartbeat()
        } catch {
            let reason = Self.describe(error)
            status = .offline(reason)
            model.operatorFailed(reason)
            retry = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.connectNow()
            }
        }
    }

    private func teardown() async {
        heartbeat?.cancel()
        heartbeat = nil
        for task in listeners { task.cancel() }
        listeners = []
        await client.removeAllChannels()
        channel = nil
        heardFrom = [:]
        friendDND = [:]
        proStamp = nil
        outgoing = [:]
        incoming = [:]
        incomingFromCall = []
        group = nil
        lastSpeaking = []
    }

    /// A short reason for the LCD.
    static func describe(_ error: Error) -> String {
        let text = String(describing: error).lowercased()
        if text.contains("anonymous") { return "ANONYMOUS SIGN-INS ARE OFF" }
        if text.contains("livekit") { return "LIVEKIT ISN'T SET UP" }
        if case FunctionsError.httpError(let code, _) = error, code == 409 { return "THE CALL IS FULL" }
        if error is URLError || text.contains("offline") || text.contains("network") { return "NO CONNECTION" }
        return "THE OPERATOR DIDN'T ANSWER"
    }

    private func localID(for account: UUID) -> Int {
        let id: Int
        if let known = localIDs[account] {
            id = known
        } else {
            // Online friends are numbered from 1000, clear of the practice board's.
            id = max(999, localIDs.values.max() ?? 999) + 1
            localIDs[account] = id
            UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: localIDs.map { ($0.key.uuidString, $0.value) }), forKey: Self.savedIDs)
        }
        accounts[id] = account
        return id
    }

    private func jack(of account: UUID) -> Int? {
        localIDs[account].flatMap { model.board.jack(of: $0) }
    }

    // MARK: Listening

    /// One channel for everything live. Calling it again replaces the channel (the server sometimes
    /// drops one, and the SDK doesn't rejoin those).
    private func listen(me: UUID) async throws {
        for task in listeners { task.cancel() }
        listeners = []
        if let old = channel {
            channel = nil
            await client.removeChannel(old)
        }
        let id = me.uuidString.lowercased()
        let channel = client.channel("talkie-\(id)")
        let toMe = channel.postgresChange(InsertAction.self, schema: "public", table: "knocks", filter: .eq("callee", value: id))
        let toMeChanged = channel.postgresChange(UpdateAction.self, schema: "public", table: "knocks", filter: .eq("callee", value: id))
        let mineChanged = channel.postgresChange(UpdateAction.self, schema: "public", table: "knocks", filter: .eq("caller", value: id))
        // Row-level security limits these to your own profile and the people on your board.
        let checkIns = channel.postgresChange(UpdateAction.self, schema: "public", table: "profiles")
        listeners.append(Task { [weak self] in
            for await action in toMe { self?.knocked(try? action.decodeRecord(as: KnockRow.self, decoder: JSONDecoder())) }
        })
        listeners.append(Task { [weak self] in
            for await action in toMeChanged { self?.theirKnockChanged(try? action.decodeRecord(as: KnockRow.self, decoder: JSONDecoder())) }
        })
        listeners.append(Task { [weak self] in
            for await action in mineChanged { self?.myKnockChanged(try? action.decodeRecord(as: KnockRow.self, decoder: JSONDecoder())) }
        })
        listeners.append(Task { [weak self] in
            for await action in checkIns { self?.checkedIn(try? action.decodeRecord(as: CheckIn.self, decoder: JSONDecoder())) }
        })
        try await channel.subscribeWithError()
        self.channel = channel
    }

    /// Every ten seconds: friends who went quiet are away, a dropped channel is rebuilt (catching up
    /// on anything missed), and every thirty seconds you check in.
    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            var beat = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self, !Task.isCancelled else { return }
                beat += 1
                await self.pulse(checkIn: beat % 3 == 0)
            }
        }
    }

    private func pulse(checkIn due: Bool) async {
        guard let me, case .online = status else { return }
        let now = Date()
        for (account, heard) in heardFrom where now.timeIntervalSince(heard) >= Self.awayAfter {
            heardFrom[account] = nil
            showPresence(account)
        }
        if channel?.status == .unsubscribed {
            try? await listen(me: me)
            await refreshPresence()
            await catchUpKnocks()
        }
        if due { await checkIn() }
    }

    // MARK: Who's around

    /// Tell the operator you're here, and whether you're on do not disturb.
    private func checkIn() async {
        _ = try? await client.rpc("check_in", params: ["do_not_disturb": model.board.doNotDisturb]).execute()
    }

    /// Ask who on your board is around right now (on connecting, and after missing updates).
    private func refreshPresence() async {
        struct Here: Decodable { let id: UUID; let here: Bool; let dnd: Bool }
        guard let rows: [Here] = try? await client.rpc("friends_here").execute().value else { return }
        for row in rows {
            heardFrom[row.id] = row.here ? Date() : nil
            friendDND[row.id] = row.dnd
            showPresence(row.id)
        }
    }

    /// Free or Pro, as the server works it out (Pro can have an end date).
    private func fetchPlan() async throws -> Plan {
        let name: String = try await client.rpc("my_plan").execute().value
        return Plan(rawValue: name) ?? .free
    }

    /// A friend checked in, signed off or switched DND. Or your own row changed: maybe you went Pro.
    private func checkedIn(_ change: CheckIn?) {
        guard let change else { return }
        if change.id == me {
            let stamp = Self.stamp(pro: change.pro, until: change.proUntil)
            guard stamp != proStamp else { return }
            proStamp = stamp
            Task { if let plan = try? await fetchPlan() { model.operatorChangedPlan(plan) } }
            return
        }
        heardFrom[change.id] = change.lastSeen == nil ? nil : Date()
        friendDND[change.id] = change.dnd
        showPresence(change.id)
    }

    private func showPresence(_ account: UUID) {
        guard let jack = jack(of: account) else { return }
        let here = heardFrom[account].map { Date().timeIntervalSince($0) < Self.awayAfter } ?? false
        let dnd = friendDND[account] ?? false
        model.apply { b in
            var events = b.setFriendOnline(jack, here, now: model.now)
            if here { events += b.setFriendDoNotDisturb(jack, dnd, now: model.now) }
            return events
        }
    }

    // MARK: Knocks

    /// Knocks that arrived (or were answered) while the channel was down.
    private func catchUpKnocks() async {
        guard let me else { return }
        let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-Switchboard.knockTimeout))
        if let rows: [KnockRow] = try? await client.from("knocks").select()
            .eq("callee", value: me.uuidString.lowercased())
            .eq("status", value: "knocking")
            .gt("created_at", value: since)
            .execute().value {
            for knock in rows where incoming[knock.caller] != knock.id { knocked(knock) }
        }
        for knockID in Array(outgoing.values) {
            if let rows: [KnockRow] = try? await client.from("knocks").select()
                .eq("id", value: knockID.uuidString.lowercased())
                .execute().value, let knock = rows.first {
                myKnockChanged(knock)
            }
        }
    }

    /// Someone knocked. If they're on your board it rings; otherwise you only get a note.
    private func knocked(_ knock: KnockRow?) {
        guard let knock, knock.status == "knocking" else { return }
        guard let jack = jack(of: knock.caller) else {
            model.noteOffBoardKnock(name: knock.callerName.uppercased(), code: knock.callerCode)
            return
        }
        incoming[knock.caller] = knock.id
        if knock.groupID != nil { incomingFromCall.insert(knock.caller) } else { incomingFromCall.remove(knock.caller) }
        heardFrom[knock.caller] = Date()
        model.apply { b in
            // A knock means they're here, even if their check-in hasn't arrived yet.
            let here = b.setFriendOnline(jack, true, now: model.now)
            return here + b.friendKnocks(jack, now: model.now, fromCall: knock.groupID != nil)
        }
    }

    /// They gave up knocking before you answered.
    private func theirKnockChanged(_ knock: KnockRow?) {
        guard let knock, knock.status == "cancelled", incoming[knock.caller] == knock.id else { return }
        incoming[knock.caller] = nil
        incomingFromCall.remove(knock.caller)
        guard let jack = jack(of: knock.caller) else { return }
        model.apply { $0.friendStoppedKnocking(jack, now: model.now) }
    }

    /// They let you in: open the line and join the call (theirs, if they brought you into one).
    private func myKnockChanged(_ knock: KnockRow?) {
        guard let knock, knock.status == "answered", outgoing[knock.callee] == knock.id else { return }
        outgoing[knock.callee] = nil
        guard let jack = jack(of: knock.callee) else { return }
        group = knock.call
        model.apply { $0.friendAnswers(jack, now: model.now) }
        join(knock.id, peer: knock.callee)
    }

    /// Into the call's room for a knock that was let in. If you're already in it (you brought this
    /// person in), you stay put and just take the new line's time limit.
    private func join(_ knockID: UUID, peer: UUID) {
        VoiceEffects.shared.set(model.board.effect)
        Task {
            do {
                let pass: Line.Pass = try await client.functions.invoke(
                    "line-token",
                    options: FunctionInvokeOptions(body: ["knock_id": knockID.uuidString.lowercased()])
                )
                // The server knows everyone's plan: a free call's time left, or no limit.
                if let limit = pass.limit, let jack = jack(of: peer) {
                    model.apply { $0.setCallLimit(jack, limit); return [] }
                }
                try await line.join(pass, muted: mutedAccounts())
                // The line may have closed on the board meanwhile.
                if let jack = jack(of: peer), !model.board.isLineOpen(jack) {
                    if model.board.isLive { line.hangUp(on: peer) } else { await line.leave() }
                    return
                }
                refreshOthers()
                expectArrival(of: peer)
            } catch {
                lineFailed(peer, error)
            }
        }
    }

    /// Someone you're on a line with should be in the room soon. If they never come, the line ends.
    private func expectArrival(of peer: UUID) {
        Task {
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard let jack = jack(of: peer), model.board.isLineOpen(jack), line.isOpen, !line.has(peer) else { return }
            model.apply { b in
                let events = b.friendHungUp(jack, now: model.now)
                b.say(b.friend(jack)?.name ?? "LINE", "DIDN'T COME ON THE LINE", now: model.now, for: 3)
                return events
            }
        }
    }

    private func lineFailed(_ peer: UUID, _ error: Error) {
        guard let jack = jack(of: peer) else { return }
        let reason = Self.describe(error)
        model.apply { b in
            let events = b.friendHungUp(jack, now: model.now)
            b.say("LINE FAILED", reason, now: model.now, for: 4)
            return events
        }
    }

    private func lineEvent(_ event: Line.Event) {
        switch event {
        case .left(let id), .hungUp(let id):
            if let jack = jack(of: id), model.board.isLineOpen(jack) {
                model.apply { $0.friendHungUp(jack, now: model.now) }
            }
            refreshOthers()
        case .joined:
            refreshOthers()
        case .dropped:
            // Your own connection went: every line on the call ends.
            model.apply { b in
                var events: [BoardEvent] = []
                for jack in b.openJacks { events += b.friendHungUp(jack, now: model.now) }
                return events
            }
        case .speaking(let ids):
            lastSpeaking = ids
            model.apply { b in
                for jack in b.openJacks {
                    guard let account = b.friend(jack).flatMap({ accounts[$0.id] }) else { continue }
                    b.setFriendTalking(jack, ids.contains(account))
                }
                return []
            }
            refreshOthers()
        case .buzz(let id):
            if let jack = jack(of: id) {
                model.friendBuzzed(jack)
            } else if let name = line.members.first(where: { $0.id == id })?.name {
                model.guestBuzzed(name)
            }
        }
    }

    /// Everyone in the room who isn't on one of your lines: people someone else brought in.
    private func refreshOthers() {
        let board = model.board
        guard line.isOpen, board.isLive else {
            if !board.others.isEmpty { model.apply { $0.setOthers([]); return [] } }
            return
        }
        let onLines = Set(board.openJacks.compactMap { board.friend($0).flatMap { accounts[$0.id] } })
        let guests = line.members.filter { !onLines.contains($0.id) }.map { member in
            let name = jack(of: member.id).flatMap { board.friend($0)?.name } ?? (member.name.isEmpty ? "GUEST" : member.name)
            return Guest(id: member.id.uuidString, name: name, talking: lastSpeaking.contains(member.id))
        }
        guard guests != board.others else { return }
        model.apply { $0.setOthers(guests); return [] }
    }

    private func mutedAccounts() -> Set<UUID> {
        Set(model.board.muted.compactMap { accounts[$0] })
    }

    // MARK: Following the board

    /// Called after every change to the board: whatever you did that the other end should hear about.
    func sync(from old: Switchboard, to new: Switchboard) {
        func friendID(_ jack: Int, _ board: Switchboard) -> Int? { board.friend(jack)?.id }
        for c in CordID.allCases {
            let was = old.patches[c], now = new.patches[c]
            // A new knock: a cord went in, or one waiting on DND or an away friend started knocking.
            if let now, now.status == .knocking, !(was?.jack == now.jack && was?.status == .knocking),
               let id = friendID(now.jack, new) {
                knock(id)
            }
            // A knock withdrawn: the cord came out, moved, or nobody answered in time.
            if let was, was.status == .knocking, !(now?.jack == was.jack && (now?.status == .knocking || now?.status == .open)),
               let id = friendID(was.jack, old) {
                cancelKnock(id)
            }
            // A line closed.
            if let was, was.status == .open, !(now?.jack == was.jack && now?.status == .open), let id = friendID(was.jack, old) {
                hangUp(id)
            }
        }
        // Knocks you let in. A decline sends nothing, so it looks like no answer on their side.
        for jack in Set(old.knocks.keys).union(old.heldKnocks) where new.isLineOpen(jack) && !old.isLineOpen(jack) {
            if let id = friendID(jack, new) { answer(id) }
        }
        // Lines they opened that you closed.
        for jack in old.incoming.keys where !new.isLineOpen(jack) {
            if let id = friendID(jack, old) { hangUp(id) }
        }
        if old.doNotDisturb != new.doNotDisturb { Task { await checkIn() } }
        if old.talking != new.talking { line.setTalking(new.talking) }
        if old.effect != new.effect { VoiceEffects.shared.set(new.effect) }
        if old.muted != new.muted { line.setMuted(mutedAccounts()) }
        // Off the call: out of the room. Between calls, the next knock starts a new one.
        if old.isLive && !new.isLive {
            lastSpeaking = []
            Task { await line.leave() }
        }
        if !new.isLive && new.knockingOut.isEmpty { group = nil }
        if new.isLive, line.isOpen, Set(old.openJacks) != Set(new.openJacks) {
            Task { refreshOthers() }
        }
    }

    /// Knocks go out in order: the first knock of a call names it, and later ones join it.
    private func knock(_ friendID: Int) {
        guard me != nil, accounts[friendID] != nil else { return }
        let previous = knockChain
        knockChain = Task { [weak self] in
            await previous?.value
            await self?.sendKnock(friendID)
        }
    }

    private func sendKnock(_ friendID: Int, retried: Bool = false) async {
        guard let me, let account = accounts[friendID] else { return }
        func stillKnocking() -> Bool { model.board.knockingOut.contains { model.board.friend($0)?.id == friendID } }
        // The cord may have come out while earlier knocks went.
        guard stillKnocking() else { return }
        struct NewKnock: Encodable {
            let caller: UUID
            let callee: UUID
            let groupID: UUID?
            enum CodingKeys: String, CodingKey {
                case caller, callee
                case groupID = "group_id"
            }
        }
        struct Created: Decodable { let id: UUID }
        do {
            let created: Created = try await client.from("knocks")
                .insert(NewKnock(caller: me, callee: account, groupID: group), returning: .representation)
                .select("id")
                .single()
                .execute().value
            outgoing[account] = created.id
            guard stillKnocking() else {
                cancelKnock(friendID)
                return
            }
            // The first knock of a call names it.
            if group == nil { group = created.id }
        } catch {
            // A call that ended under us: start a new one instead.
            if !retried, group != nil, !model.board.isLive {
                group = nil
                await sendKnock(friendID, retried: true)
                return
            }
            let reason = Self.describe(error)
            guard let jack = model.board.jack(of: friendID), let c = model.board.cord(at: jack) else { return }
            model.apply { b in
                let events = b.unpatch(c, now: model.now)
                b.say("KNOCK FAILED", reason, now: model.now, for: 4)
                return events
            }
        }
    }

    private func cancelKnock(_ friendID: Int) {
        guard let account = accounts[friendID], let knockID = outgoing.removeValue(forKey: account) else { return }
        Task { try? await client.rpc("cancel_knock", params: ["knock_id": knockID.uuidString.lowercased()]).execute() }
    }

    /// Let a knock in: into your call if you're on one (or starting one), or into theirs if they
    /// knocked from a call.
    private func answer(_ friendID: Int) {
        guard let account = accounts[friendID], let knockID = incoming.removeValue(forKey: account) else { return }
        let fromCall = incomingFromCall.remove(account) != nil
        struct LetIn: Encodable {
            let knockID: String
            let intoGroup: String?
            enum CodingKeys: String, CodingKey {
                case knockID = "knock_id"
                case intoGroup = "into_group"
            }
        }
        struct Answered: Decodable {
            let id: UUID?
            let status: String?
            let groupID: UUID?
            enum CodingKeys: String, CodingKey {
                case id, status
                case groupID = "group_id"
            }
        }
        let params = LetIn(knockID: knockID.uuidString.lowercased(), intoGroup: fromCall ? nil : group?.uuidString.lowercased())
        Task {
            do {
                let answered: Answered? = try await client.rpc("let_in", params: params).execute().value
                guard let answered, answered.status == "answered" else {
                    // They gave up a moment before you answered, or their call can't join yours.
                    guard let jack = jack(of: account) else { return }
                    model.apply { b in
                        let events = b.friendHungUp(jack, now: model.now)
                        b.say(b.friend(jack)?.name ?? "TOO LATE", fromCall ? "ON ANOTHER CALL" : "STOPPED KNOCKING", now: model.now, for: 3)
                        return events
                    }
                    return
                }
                group = answered.groupID ?? answered.id ?? knockID
                join(knockID, peer: account)
            } catch {
                lineFailed(account, error)
            }
        }
    }

    /// You closed a line: tell them. If it was your last, sync takes you out of the room.
    private func hangUp(_ friendID: Int) {
        guard let account = accounts[friendID], line.isOpen else { return }
        line.hangUp(on: account)
    }

    func buzz() {
        line.buzz()
    }

    // MARK: Your board

    /// Who a code belongs to. Nil when nobody has it.
    func lookUp(_ code: String) async throws -> Invite? {
        struct Found: Decodable { let id: UUID; let name: String }
        let found: [Found] = try await client.rpc("lookup_code", params: ["friend_code": code]).execute().value
        guard let person = found.first else { return nil }
        let id = localID(for: person.id)
        // Whether they're around shows once they're saved to your board.
        return Invite(code, Friend(id: id, name: person.name.uppercased(), online: false))
    }

    /// A friend went onto a jack: save it and start watching for them.
    func saveFriend(_ friendID: Int, jack: Int) {
        guard let me, let account = accounts[friendID] else { return }
        struct Row: Encodable { let owner: UUID; let friend: UUID; let jack: Int }
        Task {
            do {
                try await client.from("board").upsert(Row(owner: me, friend: account, jack: jack), onConflict: "owner,friend").execute()
                await refreshPresence()
            } catch {
                let reason = Self.describe(error)
                model.apply { b in
                    let events = b.removeFriend(at: jack, now: model.now)
                    b.say("COULDN'T SAVE", reason, now: model.now, for: 4)
                    return events
                }
            }
        }
    }

    /// A friend was ejected: take them off the server's board too.
    func removeFriend(_ friendID: Int) {
        guard let me, let account = accounts[friendID] else { return }
        heardFrom[account] = nil
        Task {
            try? await client.from("board").delete()
                .eq("owner", value: me.uuidString.lowercased())
                .eq("friend", value: account.uuidString.lowercased())
                .execute()
        }
    }
}
