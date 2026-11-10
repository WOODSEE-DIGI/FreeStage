//
//  GoStreamPanelView.swift
//  FreeStage
//
//  Hardware-mirror control surface for the OSEE GoStream Duet.
//
//  Layout is a 1:1 recreation of the physical panel per Figure 4.1-1 of the
//  OSEE GoStream Deck & Duet manual (V010000, 2024.04.11):
//
//    Top zone, left→right:  POWER · LIVE (STREAM) · AUDIO MIX 4-row grid with
//    encoder + AFV/ON · MACRO MEM1-8 with encoder + MENU · RECORD/PLAY
//    transport · NEXT TRANSITION keyer cluster · T-bar (far right, full height).
//
//    Bottom zone:  PGM bus row over PVW bus row (big 1-4 + AUX/STILL1/S·SRC/
//    STILL2 grid), transition cluster (MIX/DIP/WIPE/PREV + FTB, CUT/AUTO below)
//    to the right of the buses.
//
//  Both directions stay in sync over GSP. Buttons whose functions GSP does not
//  expose (BKGD arming, T-bar position, prev/next clip, power) are rendered for
//  layout fidelity but disabled, with tooltips.
//
//  Launch: Window "GoStream Panel" (footer button or Window menu).
//

import SwiftUI

struct GoStreamPanelView: View {
    @Environment(\.goStreamController) private var controller
    @State private var hostField: String = ""
    @State private var showConnection: Bool = false

    var body: some View {
        Group {
            if let controller {
                content(controller)
            } else {
                Text("GoStream controller not available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1180, minHeight: 540)
        // Force the backing NSWindow opaque: SwiftUI Window scenes composite
        // against system vibrancy, which shows the desktop/main window through
        // even fully-painted content.
        .background(OpaqueWindowBackground())
    }

    @ViewBuilder
    private func content(_ controller: GoStreamController) -> some View {
        VStack(spacing: 0) {
            header(controller)
            Divider()
            deviceSurface(controller)
        }
        .background(Color(white: 0.06))
        .task { controller.startDiscovery() }
        .onDisappear { controller.stopDiscovery() }
        // DIAG: confirm the view observes headphone-level pushes (MENU dial).
        .onChange(of: controller.headphoneLevelDB) { _, newValue in
            GoStreamLog.log("view: headphoneLevelDB observed → \(newValue.map(String.init) ?? "nil")")
        }
    }

    // MARK: - Header strip

    private func header(_ controller: GoStreamController) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor(controller.connectionState))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 1) {
                Text(controller.deviceName ?? "GoStream Duet")
                    .font(.headline)
                Text(subtitle(controller))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let error = controller.lastSendError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.red.opacity(0.12), in: Capsule())
            }

            if controller.isConnected {
                tallyBadge(controller)
            }

            Button {
                showConnection.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Connection settings")
            .popover(isPresented: $showConnection, arrowEdge: .bottom) {
                connectionPopover(controller)
                    .frame(width: 340)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func subtitle(_ controller: GoStreamController) -> String {
        var parts: [String] = [controller.statusText]
        if let fw = controller.firmwareVersion {
            parts.append("fw \(fw)")
        }
        if let type = controller.deviceType {
            parts.append(type == 1 ? "Duet" : "type \(type)")
        }
        return parts.joined(separator: " · ")
    }

    private func statusColor(_ state: GoStreamController.ConnectionState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting, .discovering, .reconnecting: return .yellow
        case .idle: return .gray
        case .failed: return .red
        }
    }

    private func tallyBadge(_ controller: GoStreamController) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(controller.pgmTally != nil ? Color.red : Color.clear)
                .frame(width: 8, height: 8)
            Text("TALLY")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(.thinMaterial))
    }

    // MARK: - Device surface (fixed geometry — the hardware is fixed)

    @ViewBuilder
    private func deviceSurface(_ controller: GoStreamController) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                topZone(controller)
                Spacer(minLength: 34)
                bottomZone(controller)
            }
            tbarColumn(controller)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(width: 1180, height: 472)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.10), Color(white: 0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.white.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity) // center in the window
    }

    // MARK: - Top zone

    private func topZone(_ controller: GoStreamController) -> some View {
        HStack(alignment: .top, spacing: 0) {
            leftColumn(controller)
                .frame(width: 56)
            audioSection(controller)
                .frame(width: 248)
                .padding(.leading, 8)
            macroSection(controller)
                .frame(width: 196)
                .padding(.leading, 14)
            transportSection(controller)
                .frame(width: 140)
                .padding(.leading, 16)
            nextTransitionSection(controller)
                .frame(width: 168)
                .padding(.leading, 18)
            Spacer(minLength: 0)
        }
    }

    // POWER at the top of the left edge; LIVE near the bottom of the top
    // zone, level with the audio section's last row — as silkscreened.

    private func leftColumn(_ controller: GoStreamController) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PowerButton()
                .help("Power (hardware only)")

            Spacer(minLength: 28)

            VStack(alignment: .leading, spacing: 4) {
                PanelButton(
                    title: "LIVE",
                    lit: controller.isLive ? .red : nil,
                    size: CGSize(width: 48, height: 28),
                    enabled: controller.isConnected
                ) {
                    controller.toggleLive()
                }
                .help("Stream on air (GSP: live)")
                .padding(.leading, 2)

                silkscreen("STREAM")
                    .padding(.leading, 6)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - AUDIO MIX

    // 4-row source grid; encoder to the right; AFV/ON in the last row beside
    // AUX/PGM, sitting under the knob. Blue-lit source = channel mixed.

    private func audioSection(_ controller: GoStreamController) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 18) {
                VStack(spacing: 6) {
                    audioPair(controller, [("MIC1", 1301), ("MIC2", 1302)])
                    audioPair(controller, [("IN1", 1), ("IN2", 2)])
                    audioPair(controller, [("IN3", 3), ("IN4", 4)])
                    audioPair(controller, [("AUX", 4001), ("PGM", 10010)])
                }

                VStack(spacing: 8) {
                    audioKnob(controller)
                    HStack(spacing: 8) {
                        PanelButton(
                            title: "AFV",
                            lit: isAudioSelected(controller, state: 2) ? .blue : nil,
                            size: CGSize(width: 52, height: 26),
                            enabled: audioControlsEnabled(controller)
                        ) {
                            controller.toggleAudioAFV()
                        }
                        .help("Audio Follows Video for the selected channel (mixState = AFV)")

                        PanelButton(
                            title: "ON",
                            lit: isAudioSelected(controller, state: 1) ? .blue : nil,
                            size: CGSize(width: 52, height: 26),
                            enabled: audioControlsEnabled(controller)
                        ) {
                            controller.toggleAudioOn()
                        }
                        .help("Always mix the selected channel (mixState = ON)")
                    }
                }
            }

            silkscreen("AUDIO MIX")
                .frame(maxWidth: .infinity)
                .padding(.top, 5)
        }
    }

    private func audioPair(_ controller: GoStreamController, _ pair: [(String, Int)]) -> some View {
        HStack(spacing: 8) {
            ForEach(pair, id: \.1) { name, source in
                let mixState = controller.audioChannels[source]?.mixState ?? 0
                let isSelected = controller.selectedAudioInput == source
                PanelButton(
                    title: name,
                    lit: mixState != 0 ? .blue : nil,
                    size: CGSize(width: 52, height: 26),
                    enabled: controller.isConnected,
                    selected: isSelected
                ) {
                    controller.selectAudioInput(source)
                }
                .help(source == 10010
                      ? "PGM output — its level shows as OUT on the knob (audioMixerHeadphone)"
                      : "Select \(name) for the knob / ON / AFV; blue = audio mixed")
            }
        }
    }

    private func audioKnob(_ controller: GoStreamController) -> some View {
        let source = controller.selectedAudioInput
        // No channel selected on the surface ⇒ the hardware knob drives the
        // monitor output ("OUT", GSP audioMixerHeadphone −31…0 dB — pushed
        // live while the physical knob turns). The PGM button shows the same
        // level. Otherwise: the selected channel's fader (pus-driven too).
        let showsOutput = source == nil || source == 10010
        let faderDB = source.flatMap { controller.audioChannels[$0]?.faderDB } ?? 0
        let db = showsOutput ? Double(controller.headphoneLevelDB ?? 0) : faderDB
        let fraction = showsOutput
            ? (max(-31, min(0, db)) + 31) / 31 // −31…0 dB → 0…1
            : (db + 75) / 85 // -75...+10 dB → 0...1
        return PanelKnob(
            angle: .degrees(-135 + 270 * fraction),
            valueText: showsOutput
                ? String(format: "OUT %.0f dB", db)
                : String(format: "%.1f dB", db),
            enabled: controller.isConnected
        ) { heightDelta in
            // Read live state per event: the closure may be re-evaluated
            // mid-drag after each optimistic update.
            if showsOutput {
                let current = Double(controller.headphoneLevelDB ?? 0)
                controller.setHeadphoneLevel(current - heightDelta * 0.25)
            } else if let source {
                let current = controller.audioChannels[source]?.faderDB ?? 0
                controller.setAudioFader(current - heightDelta * 0.25, for: source)
            }
        }
        .help(showsOutput
              ? "Monitor output level (GSP: audioMixerHeadphone, −31…0 dB); drag to set"
              : "Level for the selected channel (-75...+10 dB, GSP: audioMixerFader)")
    }

    private func isAudioSelected(_ controller: GoStreamController, state: Int) -> Bool {
        guard let source = controller.selectedAudioInput else { return false }
        return controller.audioChannels[source]?.mixState == state
    }

    private func audioControlsEnabled(_ controller: GoStreamController) -> Bool {
        guard controller.isConnected, let source = controller.selectedAudioInput else { return false }
        return source != 10010 // PGM output has no mixer channel on the Duet
    }

    // MARK: - MACRO

    // MEM1-8 grid; MENU encoder top-right; MENU below it (opens the software
    // connection settings — the hardware MENU stays on-device). The encoder
    // is repurposed as the monitor (headphone) output level: the hardware's
    // real MENU dial only navigates the device OSD, and GSP exposes no menu
    // commands (10 candidate ids probed — all silent). Riding 2301 here means
    // output volume stays adjustable while the main knob is on a channel.

    private func macroSection(_ controller: GoStreamController) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 6) {
                    macroPair(controller, 0, 1)
                    macroPair(controller, 2, 3)
                    macroPair(controller, 4, 5)
                    macroPair(controller, 6, 7)
                }

                VStack(spacing: 8) {
                    monitorKnob(controller)

                    PanelButton(
                        title: "MENU",
                        size: CGSize(width: 52, height: 26),
                        enabled: true
                    ) {
                        showConnection = true
                    }
                    .help("Connection settings (hardware MENU stays on-device)")
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }

            silkscreen("MACRO")
                .padding(.top, 5)
        }
    }

    /// The repurposed MENU encoder: monitor (headphone) output level, the
    /// same 2301 target the main knob drives in OUT mode — so both dials
    /// mirror it live, and physical-knob pushes move it too.
    private func monitorKnob(_ controller: GoStreamController) -> some View {
        let db = Double(controller.headphoneLevelDB ?? 0)
        let fraction = (max(-31, min(0, db)) + 31) / 31 // −31…0 dB → 0…1
        return PanelKnob(
            angle: .degrees(-135 + 270 * fraction),
            valueText: String(format: "OUT %.0f dB", db),
            enabled: controller.isConnected
        ) { heightDelta in
            let current = Double(controller.headphoneLevelDB ?? 0)
            controller.setHeadphoneLevel(current - heightDelta * 0.25)
        }
        .help("Monitor output level (repurposed MENU encoder; hw MENU navigates the device OSD — no GSP API)")
    }

    private func macroPair(_ controller: GoStreamController, _ a: Int, _ b: Int) -> some View {
        HStack(spacing: 8) {
            ForEach([a, b], id: \.self) { index in
                let macro = controller.macros[index]
                let stored = macro != nil && !(macro?.name.isEmpty ?? true)
                PanelButton(
                    title: "MEM\(index + 1)",
                    lit: stored ? .blue : nil,
                    size: CGSize(width: 52, height: 26),
                    enabled: controller.isConnected && stored
                ) {
                    controller.runMacro(index)
                }
                .help(stored ? "Run macro \(index + 1)" : "Macro \(index + 1) is empty")
            }
        }
    }

    // MARK: - RECORD / PLAY transport

    // Row 1: ● record · ⏮ · ⏭   Row 2: ■ stop · ▶ play · ⏸ pause.
    // ⏮/⏭ have no GSP API — present for layout, disabled.

    private func transportSection(_ controller: GoStreamController) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                transportButton("●", lit: controller.isRecording ? .red : nil,
                                enabled: controller.isConnected && !controller.isRecording,
                                help: "Start PGM recording (GSP: recordStart)") {
                    controller.startRecord()
                }
                transportButton("⏮", lit: nil, enabled: false,
                                help: "Previous clip (not exposed over GSP)") {}
                transportButton("⏭", lit: nil, enabled: false,
                                help: "Next clip (not exposed over GSP)") {}
            }
            HStack(spacing: 8) {
                transportButton("■", lit: nil,
                                enabled: controller.isConnected && controller.isRecording,
                                help: "Stop recording (GSP: recordStop)") {
                    controller.stopRecord()
                }
                transportButton("▶", lit: controller.playStatus == 1 ? .blue : nil,
                                enabled: controller.isConnected,
                                help: "Play (GSP: playPause)") {
                    controller.play()
                }
                transportButton("⏸", lit: controller.playStatus == 2 ? .blue : nil,
                                enabled: controller.isConnected,
                                help: "Pause (GSP: playPause)") {
                    controller.pausePlayback()
                }
            }
            HStack {
                silkscreen("RECORD")
                    .frame(width: 48, alignment: .leading)
                silkscreen("PLAY")
                    .padding(.leading, 4)
            }
            .padding(.top, 1)
        }
    }

    private func transportButton(
        _ title: String,
        lit: Color?,
        enabled: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        PanelButton(title: title, lit: lit, size: CGSize(width: 40, height: 26),
                    fontSize: 12, enabled: enabled, action: action)
            .help(help)
    }

    // MARK: - NEXT TRANSITION

    // ON AIR (USK | DSK) take keyers on air immediately (red); KEY/DSK/BKGD
    // arm them for the next transition (blue). BKGD has no GSP API.

    private func nextTransitionSection(_ controller: GoStreamController) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PanelButton(title: "ON AIR", lit: controller.uskOnAir ? .red : nil,
                            size: CGSize(width: 58, height: 28),
                            enabled: controller.isConnected) {
                    controller.toggleUSKOnAir()
                }
                .help("Upstream keyer ON AIR — take on/off immediately (GSP: keyOnAir)")

                PanelButton(title: "ON AIR", lit: dskOnAirLit(controller) ? .red : nil,
                            size: CGSize(width: 58, height: 28),
                            enabled: controller.isConnected) {
                    controller.toggleDSKOnAir(0)
                }
                .help("Downstream keyer ON AIR — take on/off immediately (GSP: dskOnAir)")
            }
            HStack(spacing: 8) {
                PanelButton(title: "KEY", lit: controller.uskArmed ? .blue : nil,
                            size: CGSize(width: 50, height: 26),
                            enabled: controller.isConnected) {
                    controller.toggleUSKArmed()
                }
                .help("Arm upstream keyer for the next transition (GSP: keyEnable)")

                PanelButton(title: "DSK", lit: controller.dskArmed ? .blue : nil,
                            size: CGSize(width: 50, height: 26),
                            enabled: controller.isConnected) {
                    controller.toggleDSKArmed()
                }
                .help("Arm downstream keyer for the next transition (GSP: dskEnable)")

                PanelButton(title: "BKGD", lit: .blue,
                            size: CGSize(width: 50, height: 26),
                            enabled: false) {}
                    .help("Background is always armed; GSP does not expose BKGD arming")
            }
            silkscreen("NEXT TRANSITION")
                .padding(.top, 1)
        }
    }

    private func dskOnAirLit(_ controller: GoStreamController) -> Bool {
        controller.dskOnAir.values.contains(true)
    }

    // MARK: - Bottom zone

    // PGM bus row stacked over PVW bus row; transition cluster to the right.

    private func bottomZone(_ controller: GoStreamController) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 10) {
                busRow(controller, title: "PGM", active: controller.pgmSource, color: .red) {
                    controller.setPGM($0)
                }
                busRow(controller, title: "PVW", active: controller.pvwSource, color: .green) {
                    controller.setPVW($0)
                }
            }
            transitionCluster(controller)
                .padding(.leading, 22)
                .padding(.top, 2)
            Spacer(minLength: 0)
        }
    }

    // One bus row: silkscreen label, four big input buttons, then the 2×2
    // grid of AUX / STILL1 / S/SRC / STILL2 as silkscreened on the hardware.

    private func busRow(
        _ controller: GoStreamController,
        title: String,
        active: Int?,
        color: Color,
        select: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 30, alignment: .leading)

            ForEach([1, 2, 3, 4], id: \.self) { source in
                busButton("\(source)", source: source, active: active, color: color,
                          size: CGSize(width: 78, height: 54), fontSize: 17,
                          select: select)
            }

            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    busButton(GoStreamSource.label(4001), source: 4001, active: active,
                              color: color, size: CGSize(width: 56, height: 25),
                              fontSize: 9, select: select)
                    busButton(GoStreamSource.label(3010), source: 3010, active: active,
                              color: color, size: CGSize(width: 56, height: 25),
                              fontSize: 9, select: select)
                }
                HStack(spacing: 4) {
                    busButton(GoStreamSource.label(5001), source: 5001, active: active,
                              color: color, size: CGSize(width: 56, height: 25),
                              fontSize: 9, select: select)
                    busButton(GoStreamSource.label(3020), source: 3020, active: active,
                              color: color, size: CGSize(width: 56, height: 25),
                              fontSize: 9, select: select)
                }
            }
            .padding(.leading, 6)
        }
    }

    private func busButton(
        _ title: String,
        source: Int,
        active: Int?,
        color: Color,
        size: CGSize,
        fontSize: CGFloat,
        select: @escaping (Int) -> Void
    ) -> some View {
        let isActive = active == source
        return PanelButton(title: title,
                           lit: isActive ? color : nil,
                           size: size,
                           fontSize: fontSize,
                           enabled: true) {
            select(source)
        }
        .help("\(title) — source \(source)")
    }

    // Transition cluster: MIX/DIP over WIPE/PREV, tall FTB to the right,
    // big CUT and AUTO underneath.

    private func transitionCluster(_ controller: GoStreamController) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 5) {
                    HStack(spacing: 6) {
                        styleButton(controller, "Mix")
                        styleButton(controller, "Dip")
                    }
                    HStack(spacing: 6) {
                        styleButton(controller, "Wipe")
                        PanelButton(
                            title: "PREV",
                            lit: controller.previewTransitionOn ? .blue : nil,
                            size: CGSize(width: 56, height: 26),
                            fontSize: 9,
                            enabled: controller.isConnected
                        ) {
                            controller.setPreviewTransition(!controller.previewTransitionOn)
                        }
                        .help("Preview the transition before taking it (GSP: previewTransition)")
                    }
                }

                PanelButton(
                    title: "FTB",
                    lit: controller.isFTBActive ? .red : nil,
                    size: CGSize(width: 96, height: 57),
                    fontSize: 14,
                    enabled: controller.isConnected
                ) {
                    controller.toggleFTB()
                }
                .help("Fade to black (GSP: ftb)")
            }

            HStack(spacing: 12) {
                PanelButton(
                    title: "CUT",
                    lit: .blue,
                    size: CGSize(width: 107, height: 44),
                    fontSize: 15,
                    enabled: controller.isConnected
                ) {
                    controller.cut()
                }
                .help("Cut PVW straight to PGM (GSP: cutTransition)")

                PanelButton(
                    title: "AUTO",
                    // Manual §4.1.3.6: AUTO illuminates red for the duration
                    // of the transition (T-bar sweeps and AUTO runs alike).
                    lit: controller.transitionInProgress ? .red : .blue,
                    size: CGSize(width: 107, height: 44),
                    fontSize: 15,
                    enabled: controller.isConnected
                ) {
                    controller.autoTransition()
                }
                .help("Run the selected transition (GSP: autoTransition)")
            }
        }
    }

    private func styleButton(_ controller: GoStreamController, _ style: String) -> some View {
        PanelButton(
            title: style.uppercased(),
            lit: controller.transitionStyle == style ? .blue : nil,
            size: CGSize(width: 56, height: 26),
            fontSize: 9,
            enabled: controller.isConnected
        ) {
            controller.setTransitionStyle(style)
        }
        .help("\(style) transition (GSP: transitionStyle)")
    }

    // MARK: - T-bar

    // The device exposes no usable tBar position (its "get" returns garbage
    // on fw 2.4.1 — verified with 923 samples during a physical sweep), so
    // the handle mirrors transitionStatus instead: [1] starts a sweep to the
    // far end, [0] completes it — then the target flips for the next one.
    // Status LED (green) and panel screw dots as on the hardware.

    private func tbarColumn(_ controller: GoStreamController) -> some View {
        // Indicators live inside TBarView so they share its position state.
        TBarView(active: controller.transitionInProgress)
            .frame(width: 68) // 8px indicator column + 6 spacing + 54 track
            .frame(maxHeight: .infinity)
            .padding(.top, 2)
            .help("T-bar — sweep state mirrored from transitionStatus (fw 2.4.1 sends no tBar position)")
    }

    // MARK: - Connection popover

    @ViewBuilder
    private func connectionPopover(_ controller: GoStreamController) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !controller.discoveredDevices.isEmpty {
                ForEach(controller.discoveredDevices) { device in
                    HStack {
                        Image(systemName: "network")
                            .foregroundStyle(.secondary)
                        Text(device.id)
                            .font(.caption)
                        Spacer()
                        Button("Connect") {
                            controller.connect(device: device)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(controller.isConnected)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("IP address", text: $hostField)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit { controller.connect(host: hostField) }

                if controller.isConnected {
                    Button("Disconnect") { controller.disconnect() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Button("Connect") { controller.connect(host: hostField) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            if case .failed(let reason) = controller.connectionState {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
    }

    // MARK: - Silkscreen label

    private func silkscreen(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(.white.opacity(0.35))
    }
}

// MARK: - Power button

/// The hardware POWER key: white cap with a red power glyph.
private struct PowerButton: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.96), Color(white: 0.82)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.black.opacity(0.15))
                )
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            Image(systemName: "power")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.red)
        }
        .frame(width: 44, height: 28)
    }
}

// MARK: - Hardware-style button

/// A physical-panel button: dark unlit cap, or a lit backlight in the
/// hardware's LED colors (red = on-air/record, green = preview, blue = armed).
private struct PanelButton: View {
    let title: String
    var lit: Color? = nil
    var size: CGSize = CGSize(width: 46, height: 26)
    var fontSize: CGFloat = 10
    var enabled: Bool = true
    var selected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(lit == nil ? Color.white.opacity(0.75) : .white)
                .frame(width: size.width, height: size.height)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(fill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    selected ? Color.white.opacity(0.7)
                                             : .white.opacity(lit == nil ? 0.08 : 0.15),
                                    lineWidth: selected ? 1.5 : 1
                                )
                        )
                        .shadow(color: (lit ?? .clear).opacity(lit == nil ? 0 : 0.55),
                                radius: 5, y: 0)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private var fill: AnyShapeStyle {
        if let lit {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [lit.opacity(0.95), lit.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [Color(white: 0.22), Color(white: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Rotary knob

/// Rotary encoder lookalike with the hardware's arc indicator. Vertical drag
/// adjusts the mapped value; the marker rotates -135° (min) to +135° (max).
private struct PanelKnob: View {
    let angle: Angle
    let valueText: String
    var enabled: Bool = true
    let onDelta: (CGFloat) -> Void

    /// Last drag translation — converts the gesture's CUMULATIVE translation
    /// into per-event increments so callers can apply each delta to the
    /// live value (a cumulative translation re-applied on every re-render
    /// compounds and runs the value away).
    @State private var lastDragY: CGFloat?

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0.05), .white.opacity(0.35)],
                            center: .center,
                            startAngle: .degrees(135),
                            endAngle: .degrees(405)
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 64, height: 64)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.35), Color(white: 0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(Circle().strokeBorder(.white.opacity(0.12)))
                    .frame(width: 48, height: 48)

                Capsule()
                    .fill(.white.opacity(0.85))
                    .frame(width: 3, height: 14)
                    .offset(y: -13)
                    .rotationEffect(angle)
                    // Smooth the 0.5 dB steps arriving from physical knob
                    // pushes (~10/s) into a continuous sweep.
                    .animation(.linear(duration: 0.1), value: angle)
            }
            .opacity(enabled ? 1 : 0.5)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        guard enabled else { return }
                        let y = value.translation.height
                        if let last = lastDragY {
                            onDelta(y - last) // per-event increment only
                        }
                        lastDragY = y
                    }
                    .onEnded { _ in lastDragY = nil }
            )

            if !valueText.isEmpty {
                Text(valueText)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .help(enabled ? "Drag vertically to adjust" : "Not adjustable")
    }
}

// MARK: - T-bar

private struct TBarView: View {
    /// `transitionStatus` from the device: true while a sweep is running.
    let active: Bool
    @State private var position: CGFloat = 0 // 0 = top, 1 = bottom
    @State private var target: CGFloat = 1 // far end of the running/next sweep

    var body: some View {
        HStack(spacing: 6) {
            indicatorColumn
            track
        }
    }

    // The two progress indicators beside the T-bar (manual §4.1.3.6 — "two
    // indicators … indicate the manual transition progress"): each lights
    // when the handle is on its half. The opacity change rides the same
    // animation transaction as the handle, so both track a live sweep and
    // land together when transitionStatus [0] snaps the position.
    private var indicatorColumn: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
                .shadow(color: .green, radius: 3)
                .opacity(position < 0.5 ? 1 : 0.14)
                .padding(.top, 24)
            Spacer()
            Circle()
                .fill(.green)
                .frame(width: 5, height: 5)
                .shadow(color: .green, radius: 3)
                .opacity(position >= 0.5 ? 1 : 0.14)
                .padding(.bottom, 30)
        }
        .frame(width: 8)
    }

    private var track: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.white.opacity(0.06))
                    )

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.75), Color(white: 0.45)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 44, height: 22)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
                    .position(
                        x: geo.size.width / 2,
                        y: 14 + position * max(0, geo.size.height - 46)
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let travel = geo.size.height - 46
                                guard travel > 0 else { return }
                                position = min(1, max(0, (value.location.y - 14) / travel))
                                // A parked bar arms the opposite end for the
                                // next sweep (mirrors the physical travel).
                                if !active {
                                    target = position >= 0.5 ? 0 : 1
                                }
                            }
                    )
            }
        }
        .onChange(of: active) { _, isActive in
            if isActive {
                // transitionStatus [1] — the sweep started (physical T-bar
                // motion or an AUTO): slide the handle to the far end. No
                // position data exists, so this is a timed approximation;
                // completion lands it exactly.
                withAnimation(.easeInOut(duration: 1.0)) {
                    position = target
                }
            } else {
                // [0] — completed: land without animation, then arm the
                // reverse sweep. Standalone pushes from cuts never see the
                // false→true edge, so they don't move the handle.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    position = target
                }
                target = target == 0 ? 1 : 0
            }
        }
    }
}

// MARK: - Opaque window

/// Forces the backing NSWindow fully opaque. SwiftUI `Window` scenes composite
/// against system vibrancy, which can show the desktop or other windows through
/// even fully-painted content.
private struct OpaqueWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.isOpaque = true
                window.backgroundColor = NSColor(srgbRed: 0.06, green: 0.06, blue: 0.06, alpha: 1)
                window.appearance = NSAppearance(named: .darkAqua)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            window.isOpaque = true
            window.backgroundColor = NSColor(srgbRed: 0.06, green: 0.06, blue: 0.06, alpha: 1)
        }
    }
}
