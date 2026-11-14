//
//  AudioMonitorView.swift
//  FreeStage
//
//  Compact retro audio mixer for the bottom-right corner of the presenter
//  workspace. Shows live levels and vertical faders for each input channel,
//  system audio, and the master output.
//

import SwiftUI
import OSLog

struct AudioMonitorView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.audioMixer) private var mixer
    @Environment(\.recordingService) private var recordingService
    @State private var audioMixerFocus: AudioMixerFocus?

    var body: some View {
        Group {
            if let mixer = mixer {
                @Bindable var mixer = mixer
                monitorBody(mixer: mixer)
            } else {
                EmptyView()
            }
        }
    }

    private func monitorBody(mixer: AudioMixer) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                channelStrip(
                    mixer: mixer,
                    label: "IN 1",
                    deviceName: inputDeviceName(mixer: mixer, index: 0),
                    level: Double(mixer.inputLevel(at: 0)),
                    volume: inputVolumeBinding(mixer: mixer, index: 0),
                    isMuted: inputMutedBinding(mixer: mixer, index: 0),
                    focus: .inputs
                )

                Divider()
                    .background(theme.border.opacity(0.4))

                channelStrip(
                    mixer: mixer,
                    label: "IN 2",
                    deviceName: inputDeviceName(mixer: mixer, index: 1),
                    level: Double(mixer.inputLevel(at: 1)),
                    volume: inputVolumeBinding(mixer: mixer, index: 1),
                    isMuted: inputMutedBinding(mixer: mixer, index: 1),
                    focus: .inputs
                )

                Divider()
                    .background(theme.border.opacity(0.4))

                channelStrip(
                    mixer: mixer,
                    label: "IN 3",
                    deviceName: inputDeviceName(mixer: mixer, index: 2),
                    level: Double(mixer.inputLevel(at: 2)),
                    volume: inputVolumeBinding(mixer: mixer, index: 2),
                    isMuted: inputMutedBinding(mixer: mixer, index: 2),
                    focus: .inputs
                )

                Divider()
                    .background(theme.border.opacity(0.4))

                channelStrip(
                    mixer: mixer,
                    label: "SYS",
                    deviceName: "System",
                    level: Double(mixer.systemLevel),
                    volume: Binding(
                        get: { mixer.systemVolume },
                        set: { mixer.systemVolume = $0 }
                    ),
                    isMuted: Binding(
                        get: { mixer.systemMuted },
                        set: { mixer.systemMuted = $0 }
                    ),
                    focus: .system
                )

                Divider()
                    .background(theme.border.opacity(0.4))

                channelStrip(
                    mixer: mixer,
                    label: "OUT",
                    deviceName: outputDeviceName(mixer: mixer),
                    level: Double(mixer.outputLevel),
                    volume: Binding(
                        get: { mixer.masterVolume },
                        set: { mixer.masterVolume = $0 }
                    ),
                    isMuted: Binding(
                        get: { mixer.isOutputMuted },
                        set: { mixer.isOutputMuted = $0 }
                    ),
                    focus: .master
                )
            }

            footer(mixer: mixer)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.panelBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(theme.accent.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
        )
        .frame(width: 340)
        .sheet(item: $audioMixerFocus, onDismiss: { audioMixerFocus = nil }) { focus in
            AudioMixerView(focus: focus)
                .frame(minWidth: 460, idealWidth: 520, minHeight: 880, idealHeight: 980)
        }
        .task {
            guard !mixer.isRunning else { return }
            do {
                try mixer.start()
            } catch {
                audioMonitorLogger.error("Auto-start audio engine failed: \(error.localizedDescription)")
            }
        }
    }

    private func channelStrip(
        mixer: AudioMixer,
        label: String,
        deviceName: String,
        level: Double,
        volume: Binding<Double>,
        isMuted: Binding<Bool>,
        focus: AudioMixerFocus
    ) -> some View {
        Button {
            audioMixerFocus = focus
        } label: {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.text)

                muteButton(isMuted: isMuted)

                ZStack {
                    HStack(spacing: 4) {
                        RetroLEDMeter(level: isMuted.wrappedValue ? 0 : level, theme: theme)
                            .frame(width: 16, height: 110)

                        verticalFader(value: volume, theme: theme)
                            .frame(width: 22, height: 110)
                    }
                }

                HStack(spacing: 2) {
                    Circle()
                        .fill(isMuted.wrappedValue ? Color.red : Color.green)
                        .frame(width: 5, height: 5)
                    Text(isMuted.wrappedValue ? "MUTE" : "LIVE")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(isMuted.wrappedValue ? Color.red : Color.green)
                }

                Text(deviceName)
                    .font(.system(size: 7))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .frame(width: 54)

                Text(volume.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .help("Tap to adjust \(label) settings; drag fader to change level")
    }

    private func muteButton(isMuted: Binding<Bool>) -> some View {
        Button {
            isMuted.wrappedValue.toggle()
        } label: {
            Text("M")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isMuted.wrappedValue ? Color.red : theme.secondaryText)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isMuted.wrappedValue ? Color.red.opacity(0.15) : theme.border.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isMuted.wrappedValue ? Color.red.opacity(0.6) : theme.border.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("Mute/unmute channel")
    }

    private func verticalFader(value: Binding<Double>, theme: ThemeStore) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Track background.
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.border.opacity(0.25))
                    .frame(width: 6)

                // Fill up to current value.
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.accent)
                    .frame(width: 6, height: geometry.size.height * (value.wrappedValue / 2.0))

                // Draggable handle.
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height * (1.0 - value.wrappedValue / 2.0)
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { gesture in
                                let normalized = 1.0 - (gesture.location.y / geometry.size.height)
                                let clamped = max(0, min(2, normalized * 2))
                                value.wrappedValue = clamped
                            }
                    )
            }
        }
    }

    private func footer(mixer: AudioMixer) -> some View {
        HStack(spacing: 6) {
            if !mixer.isRunning {
                Button {
                    do {
                        try mixer.start()
                    } catch {
                        audioMonitorLogger.error("Failed to start audio engine: \(error.localizedDescription)")
                    }
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Start audio engine")
            } else {
                Button {
                    audioMixerFocus = .inputs
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Open Audio Mixer settings")
            }

            Spacer()

            if let recordingService = recordingService, recordingService.isRecording {
                HStack(spacing: 2) {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                    Text(formatDuration(recordingService.recordingDuration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                }
            }
        }
        .frame(height: 24)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func inputDeviceName(mixer: AudioMixer, index: Int) -> String {
        guard let id = mixer.inputDeviceID(at: index) else { return "Off" }
        return mixer.availableInputDevices.first { $0.uniqueID == id }?.localizedName ?? "Input"
    }

    private func outputDeviceName(mixer: AudioMixer) -> String {
        guard let id = mixer.selectedOutputDeviceID else { return "Default" }
        return mixer.availableOutputDevices.first { $0.id == id }?.name ?? "Output"
    }

    private func inputVolumeBinding(mixer: AudioMixer, index: Int) -> Binding<Double> {
        Binding(
            get: { mixer.inputVolume(at: index) },
            set: { mixer.setInputVolume($0, at: index) }
        )
    }

    private func inputMutedBinding(mixer: AudioMixer, index: Int) -> Binding<Bool> {
        Binding(
            get: { mixer.inputMuted(at: index) },
            set: { mixer.setInputMuted($0, at: index) }
        )
    }
}

// MARK: - Retro LED meter

struct RetroLEDMeter: View {
    let level: Double
    let theme: ThemeStore
    private let segments = 24

    var body: some View {
        GeometryReader { geometry in
            let segmentHeight = (geometry.size.height - CGFloat(segments - 1) * 2) / CGFloat(segments)
            VStack(spacing: 2) {
                ForEach((0..<segments).reversed(), id: \.self) { index in
                    let threshold = Double(index + 1) / Double(segments)
                    let isLit = level >= threshold
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isLit ? color(for: threshold) : Color.white.opacity(0.08))
                        .frame(height: segmentHeight)
                        .shadow(color: isLit ? color(for: threshold).opacity(0.8) : .clear, radius: 2, x: 0, y: 0)
                        .animation(.easeOut(duration: 0.05), value: level)
                }
            }
        }
    }

    private func color(for threshold: Double) -> Color {
        switch threshold {
        case 0.85...: return Color(red: 1.0, green: 0.15, blue: 0.15)
        case 0.65..<0.85: return Color(red: 1.0, green: 0.85, blue: 0.0)
        default: return Color(red: 0.25, green: 0.95, blue: 0.35)
        }
    }
}

private let audioMonitorLogger = Logger(subsystem: "com.woodseedigi.freestage", category: "AudioMonitorView")

#Preview {
    AudioMonitorView()
        .environment(ThemeStore(settings: AppSettings()))
        .environment(\.audioMixer, AudioMixer())
        .environment(\.recordingService, RecordingService())
}
