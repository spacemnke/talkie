import SwiftUI
import AppKit
import ServiceManagement
import TalkieCore

// MARK: Shared pieces

/// A wide key with a label, for the bottom of panels.
struct WideKey: View {
    let title: String
    var width: CGFloat = 312
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).frame(width: width, height: 44)
        }
        .buttonStyle(RelayKeyStyle())
    }
}

struct Caption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Fonts.jura(8.5, "SemiBold"))
            .tracking(1.2)
            .foregroundStyle(Palette.mute)
    }
}

// MARK: Voice effects

/// Pick an effect, and hold TRY IT to hear it on your own voice. Anyone can try them; on Pro the
/// people on your line hear the one you pick.
struct EffectsView: View {
    let model: BoardModel
    @State private var preview = EffectPreview()
    /// On Free, the effect you're trying out (it isn't put on your calls).
    @State private var trying: Effect = .canyon

    var body: some View {
        let pro = model.board.plan.hasEffects
        let chosen = pro ? model.board.effect : trying
        DeviceWindow(title: "VOICE EFFECTS") {
            VStack(alignment: .leading, spacing: 0) {
                Text("CHANGE YOUR SIGNAL.")
                    .font(Fonts.jura(17, "Regular"))
                    .tracking(0.8)
                    .padding(.top, 22)
                Text(pro ? "The people on your line hear the effect." : "Try them on your own voice. Pro puts them on your calls.")
                    .font(Fonts.jura(11, "Regular"))
                    .foregroundStyle(Palette.mute)
                    .padding(.top, 8)
                VStack(spacing: 8) {
                    ForEach(Effect.allCases, id: \.self) { effect in
                        EffectRow(effect: effect, selected: chosen == effect, pro: !pro && effect != .off) {
                            if pro { model.setEffect(effect) } else { trying = effect }
                        }
                    }
                }
                .padding(.top, 18)
                TryKey(preview: preview, busy: model.board.isLive) {
                    preview.stopRecording(effect: chosen, volume: Float(model.volume))
                }
                .padding(.top, 14)
                if pro {
                    Caption(text: "SIDE KEY TO CYCLE · F ON THE BOARD")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                } else {
                    Button { model.onShowPro?() } label: {
                        Text("GO PRO TO USE THEM ON CALLS →")
                            .font(Fonts.jura(8.5, "SemiBold"))
                            .tracking(1.2)
                            .foregroundStyle(Palette.orange)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                }
            }
            .foregroundStyle(Palette.ink)
            .padding(EdgeInsets(top: 0, leading: 20, bottom: 18, trailing: 20))
            .frame(width: 330)
        }
        .onDisappear { preview.stopEverything() }
    }
}

/// Hold to record a few seconds of your voice; let go to hear it back through the effect.
private struct TryKey: View {
    let preview: EffectPreview
    /// A line is open: trying effects would play into the call.
    let busy: Bool
    let release: () -> Void
    @State private var holding = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
        VStack(spacing: 6) {
            Text(title)
                .font(Fonts.jura(11, "SemiBold"))
                .tracking(1.2)
                .foregroundStyle(preview.state == .recording ? Palette.white : Palette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(shape.fill(preview.state == .recording ? Palette.orange : Palette.white))
                .overlay(shape.strokeBorder(Palette.ink, lineWidth: 1.5))
                .background(shape.fill(Palette.ink).offset(y: holding ? 1 : 3))
                .offset(y: holding ? 2 : 0)
                .contentShape(shape)
                .opacity(busy ? 0.45 : 1)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !holding, !busy else { return }
                        holding = true
                        preview.startRecording()
                    }
                    .onEnded { _ in
                        guard holding else { return }
                        holding = false
                        release()
                    })
                .accessibilityElement()
                .accessibilityLabel("Try it")
                .accessibilityHint("Hold to record your voice, let go to hear it with the effect.")
                .accessibilityAddTraits(.isButton)
            // Always one line, so the window keeps its size.
            Caption(text: preview.problem ?? (busy ? "HANG UP TO TRY EFFECTS" : "PLAYS BACK WHAT YOU SAY"))
                .frame(height: 12)
        }
    }

    private var title: String {
        switch preview.state {
        case .idle: return "HOLD TO TRY IT"
        case .recording: return "TALK · LET GO TO HEAR IT"
        case .playing: return "PLAYING IT BACK…"
        }
    }
}

private struct EffectRow: View {
    let effect: Effect
    let selected: Bool
    /// Comes with Pro: on Free you can only try it here.
    var pro = false
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(selected ? Palette.orange : Palette.white)
                        .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1))
                    if selected { Circle().fill(Palette.ink).frame(width: 4, height: 4) }
                }
                .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 4) {
                    Text(effect.title).font(Fonts.jura(12, "Medium")).tracking(1)
                    Text(effect.detail).font(Fonts.jura(10, "Regular")).foregroundStyle(Palette.mute)
                }
                Spacer(minLength: 0)
                if pro { ProBadge() }
            }
            .padding(.horizontal, 13)
            .frame(height: 46)
            .background(shape.fill(selected ? Palette.plate : Palette.paper))
            .overlay(shape.strokeBorder(Palette.ink, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Settings

struct SettingsView: View {
    let model: BoardModel
    @State private var inputs: [AudioDevice] = []
    @State private var outputs: [AudioDevice] = []
    @AppStorage("inputDeviceUID") private var inputUID = ""
    @AppStorage("outputDeviceUID") private var outputUID = ""
    @State private var level = InputLevel()
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginProblem: String?

    var body: some View {
        DeviceWindow(title: "SETTINGS") {
            VStack(alignment: .leading, spacing: 0) {
                Text("MAKE YOURSELF AT HOME.")
                    .font(Fonts.jura(22, "Light"))
                    .tracking(0.6)
                    .padding(.top, 24)
                Caption(text: "A FEW CONTROLS. ALWAYS WITHIN REACH.")
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 16) {
                    Text("AUDIO").font(Fonts.jura(11, "SemiBold")).tracking(1.2)
                    row("MICROPHONE") { DevicePicker(devices: inputs, selection: $inputUID) }
                    row("OUTPUT") { DevicePicker(devices: outputs, selection: $outputUID) }
                    row("INPUT LEVEL") { LevelBars(level: level.level) }
                }
                .padding(20)
                .insetPanel(radius: 14)
                .padding(.top, 22)

                VStack(spacing: 0) {
                    HStack {
                        Text("PUSH TO TALK").font(Fonts.jura(11, "SemiBold")).tracking(1)
                        Spacer(minLength: 0)
                        Text("OPTION + SPACE")
                            .font(Fonts.jura(10, "SemiBold"))
                            .tracking(1)
                            .frame(width: 232, height: 35)
                            .background(RoundedRectangle(cornerRadius: Radius.key).fill(Palette.white))
                            .overlay(RoundedRectangle(cornerRadius: Radius.key).strokeBorder(Palette.ink, lineWidth: 1.5))
                            .background(RoundedRectangle(cornerRadius: Radius.key).fill(Palette.ink).offset(y: 3))
                            .accessibilityLabel("Push to talk: Option and Space")
                    }
                    .padding(.bottom, 14)
                    Divider().overlay(Palette.soft)
                    Toggle(isOn: Binding(get: { openAtLogin }, set: setOpenAtLogin)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("OPEN AT LOGIN").font(Fonts.jura(11, "SemiBold")).tracking(1)
                            if let loginProblem {
                                Text(loginProblem).font(Fonts.jura(9.5, "Regular")).foregroundStyle(Palette.mute)
                            }
                        }
                    }
                    .toggleStyle(RelayToggleStyle())
                    .padding(.vertical, 14)
                    Divider().overlay(Palette.soft)
                    Toggle(isOn: Binding(get: { model.soundOn }, set: { on in
                        if on != model.soundOn { model.toggleSound() }
                    })) {
                        Text("INTERACTION SOUNDS").font(Fonts.jura(11, "SemiBold")).tracking(1)
                    }
                    .toggleStyle(RelayToggleStyle())
                    .padding(.top, 14)
                }
                .padding(20)
                .insetPanel(Palette.paper, radius: 14)
                .padding(.top, 14)

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("PLAN · \(model.board.plan.title)").font(Fonts.jura(11, "SemiBold")).tracking(1)
                        Text(model.board.plan == .pro ? "Eight jacks, calls of five, no time limit, effects and knock sounds."
                            : "Three jacks, calls of three, ten minutes each. Pro opens the whole board.")
                            .font(Fonts.jura(10, "Regular"))
                            .foregroundStyle(Palette.mute)
                    }
                    Spacer(minLength: 0)
                    Button { model.onShowPro?() } label: {
                        Text(model.board.plan == .pro ? "PRO" : "SEE PRO").frame(width: 96, height: 32)
                    }
                    .buttonStyle(RelayKeyStyle())
                }
                .padding(20)
                .insetPanel(radius: 14)
                .padding(.top, 14)

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("REDUCE MOTION").font(Fonts.jura(11, "SemiBold")).tracking(1)
                        Text("Follows your Mac accessibility preference.")
                            .font(Fonts.jura(10, "Regular"))
                            .foregroundStyle(Palette.mute)
                    }
                    Spacer(minLength: 0)
                    Caption(text: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? "SYSTEM · ON" : "SYSTEM · OFF")
                }
                .padding(20)
                .insetPanel(radius: 14)
                .padding(.top, 14)

                Caption(text: "FLOATING MIC HIDDEN FROM SCREEN SHARES")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
            }
            .foregroundStyle(Palette.ink)
            .padding(EdgeInsets(top: 0, leading: 30, bottom: 22, trailing: 30))
            .frame(width: 520)
        }
        .onAppear {
            inputs = AudioDevices.all(input: true)
            outputs = AudioDevices.all(input: false)
            if inputUID.isEmpty { inputUID = AudioDevices.defaultUID(input: true) ?? "" }
            if outputUID.isEmpty { outputUID = AudioDevices.defaultUID(input: false) ?? "" }
            level.start()
        }
        .onDisappear { level.stop() }
    }

    private func row<Control: View>(_ label: String, @ViewBuilder _ control: () -> Control) -> some View {
        HStack {
            Caption(text: label).frame(width: 150, alignment: .leading)
            control()
        }
    }

    private func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginProblem = nil
        } catch {
            loginProblem = "macOS didn't allow it: \(error.localizedDescription)"
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// A white box showing the chosen device; click it for the list.
private struct DevicePicker: View {
    let devices: [AudioDevice]
    @Binding var selection: String

    var body: some View {
        let chosen = devices.first { $0.uid == selection }?.name ?? (devices.isEmpty ? "NO DEVICES FOUND" : "SYSTEM DEFAULT")
        let shape = RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
        Button {
            let menu = NSMenu()
            for device in devices {
                let item = ClosureMenuItem(title: device.name) { selection = device.uid }
                item.state = device.uid == selection ? .on : .off
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        } label: {
            HStack {
                Text(chosen.uppercased())
                    .font(Fonts.jura(9.5, "SemiBold"))
                    .tracking(0.6)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("▾").font(.system(size: 9))
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(shape.fill(Palette.white))
            .overlay(shape.strokeBorder(Palette.ink, lineWidth: 1.3))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(devices.isEmpty)
        .accessibilityValue(chosen)
    }
}

private struct LevelBars: View {
    let level: Double

    var body: some View {
        let lit = Int((level * 16).rounded())
        HStack(spacing: 3) {
            ForEach(0..<16, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < lit ? Palette.orange : Palette.white)
                    .overlay(RoundedRectangle(cornerRadius: 1).strokeBorder(i < lit ? Palette.ink : Palette.mute, lineWidth: 0.8))
                    .frame(width: 9, height: 14)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement()
        .accessibilityLabel("Input level")
        .accessibilityValue("\(lit) of 16")
    }
}

// MARK: First run

/// Three steps from first launch to first hello: meet Talkie, allow the microphone, share your code.
struct FirstRunView: View {
    let model: BoardModel
    let finish: () -> Void
    @State private var page = 0
    @State private var cardAnchor = ShareAnchorBox()
    @State private var mic = MicPermission.current
    @State private var asking = false

    var body: some View {
        DeviceWindow(title: "WELCOME TO TALKIE") {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    Caption(text: String(format: "%02d / 03", page + 1))
                }
                .padding(.top, 18)
                Group {
                    switch page {
                    case 0: meet
                    case 1: microphone
                    default: exchange
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                HStack(alignment: .center) {
                    PageDots(page: page)
                    Spacer(minLength: 0)
                    buttons
                }
            }
            .foregroundStyle(Palette.ink)
            .padding(EdgeInsets(top: 0, leading: 36, bottom: 30, trailing: 36))
            .frame(width: 580, height: 439)
        }
    }

    private var meet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("YOUR PEOPLE. ONE PATCH AWAY.")
                .font(Fonts.jura(20, "Regular"))
                .tracking(0.6)
                .padding(.top, 12)
            HStack(alignment: .center, spacing: 40) {
                MicIllustration().frame(width: 140, height: 260)
                VStack(alignment: .leading, spacing: 0) {
                    Text("PLUG IN.\nSTART TALKING.")
                        .font(Fonts.jura(20, "Regular"))
                        .tracking(0.6)
                        .lineSpacing(6)
                    Text("A switchboard for your closest people.\nA little mic that goes wherever you do.")
                        .font(Fonts.jura(11, "Regular"))
                        .foregroundStyle(Palette.mute)
                        .lineSpacing(6)
                        .padding(.top, 22)
                }
            }
            .padding(.top, 12)
        }
    }

    private var microphone: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("GIVE YOUR VOICE A WAY IN.")
                .font(Fonts.jura(20, "Regular"))
                .tracking(0.6)
                .padding(.top, 12)
            VStack(alignment: .leading, spacing: 12) {
                Text(mic == .denied ? "MICROPHONE IS OFF" : "MICROPHONE ACCESS")
                    .font(Fonts.jura(12, "SemiBold"))
                    .tracking(1.2)
                    .padding(.bottom, 4)
                if mic == .denied {
                    Text("Talkie can't send your voice until you allow it.")
                    Text("Turn on Talkie in System Settings → Privacy & Security → Microphone, then try again. You can still listen without it.")
                        .foregroundStyle(Palette.mute)
                } else {
                    Text("Your voice is sent while you hold Talk.")
                    Text("Release it, and your microphone goes quiet.")
                    Text(mic == .granted ? "Access is on. You're ready." : "Allow access in the macOS prompt to continue.")
                        .font(Fonts.jura(10.5, "Regular"))
                        .foregroundStyle(Palette.mute)
                        .padding(.top, 8)
                }
            }
            .font(Fonts.jura(13, "Regular"))
            .fixedSize(horizontal: false, vertical: true)
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .insetPanel(radius: 14)
            .padding(.top, 26)
            Text("You can change permission in System Settings.")
                .font(Fonts.jura(10.5, "Regular"))
                .foregroundStyle(Palette.mute)
                .padding(.top, 22)
        }
    }

    private var exchange: some View {
        let card = model.myCard
        return VStack(alignment: .leading, spacing: 0) {
            Text("MAKE YOUR FIRST CONNECTION.")
                .font(Fonts.jura(20, "Regular"))
                .tracking(0.6)
                .padding(.top, 12)
            HStack(alignment: .top, spacing: 30) {
                LineCardView(card: card)
                    .scaleEffect(1.08, anchor: .topLeading)
                    .frame(width: LineCardView.size.width * 1.08, height: LineCardView.size.height * 1.08, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 10) {
                    Caption(text: "YOUR CODE")
                    Text(card.code).font(Fonts.lcd(20)).tracking(1.4).textSelection(.enabled)
                    Button { model.copyMyCode() } label: {
                        Text("COPY CODE").frame(width: 150, height: 32)
                    }
                    .buttonStyle(RelayKeyStyle())
                    .padding(.top, 6)
                    Button { model.sendMyCard(from: cardAnchor.view) } label: {
                        Text("SEND YOUR CARD").frame(width: 150, height: 32)
                    }
                    .buttonStyle(RelayKeyStyle())
                    .background(ShareAnchor(box: cardAnchor))
                    .padding(.top, 4)
                }
                .padding(.top, 10)
            }
            .padding(.top, 34)
            Text("Send your card or your code to a friend.")
                .font(Fonts.jura(13, "Regular"))
                .padding(.top, 26)
            Text("To add theirs, press ADD on your switchboard and type it in.")
                .font(Fonts.jura(12, "Regular"))
                .foregroundStyle(Palette.mute)
                .padding(.top, 8)
        }
    }

    @ViewBuilder private var buttons: some View {
        switch page {
        case 0:
            WideKey(title: "LET'S GET STARTED") { page = 1 }
        case 1:
            if mic == .denied {
                HStack(spacing: 10) {
                    Button { page = 2 } label: { Text("NOT NOW").frame(width: 90, height: 44) }
                        .buttonStyle(RelayKeyStyle())
                    Button { MicPermission.openSystemSettings() } label: { Text("OPEN SETTINGS").frame(width: 130, height: 44) }
                        .buttonStyle(RelayKeyStyle())
                    Button {
                        mic = MicPermission.current
                        if mic == .granted { page = 2 }
                    } label: { Text("TRY AGAIN").frame(width: 100, height: 44) }
                        .buttonStyle(RelayKeyStyle())
                }
            } else if mic == .granted {
                WideKey(title: "CONTINUE") { page = 2 }
            } else {
                WideKey(title: asking ? "WAITING FOR MACOS…" : "ALLOW MICROPHONE") {
                    guard !asking else { return }
                    asking = true
                    Task {
                        mic = await MicPermission.request()
                        asking = false
                        if mic == .granted { page = 2 }
                    }
                }
            }
        default:
            WideKey(title: "OPEN MY BOARD", action: finish)
        }
    }
}

private struct PageDots: View {
    let page: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i == page ? Palette.ink : Color.clear)
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(page + 1) of 3")
    }
}

/// The Relay mic hanging on its coiled cord, for the welcome screen.
private struct MicIllustration: View {
    var body: some View {
        Canvas { ctx, size in
            let box = CGRect(x: 8, y: 0, width: 124, height: 248)
            let s = min(size.width / box.width, size.height / box.height)
            ctx.translateBy(x: (size.width - box.width * s) / 2, y: (size.height - box.height * s) / 2)
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            var coil = Path()
            coil.addLines(Coil.points(from: MicArt.cordExit, to: CGPoint(x: 66, y: 2), coils: 7, radius: 8, rising: true))
            ctx.stroke(coil, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            ctx.stroke(coil, with: .color(Palette.lampOff), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            var mic = ctx
            MicArt.draw(&mic, MicArt.State(
                squeezed: false, effectIndex: 0, level: 0,
                tag: "MAYA", tagLabel: "A", tagLamp: .on, blinkPhase: false
            ))
        }
        .accessibilityHidden(true)
    }
}
