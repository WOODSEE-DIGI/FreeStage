//
//  AudioMonitorView.swift
//  FreeStage
//
//  Compact retro audio level monitor for the bottom-right corner of the
//  presenter workspace. Shows microphone and output levels as LED bars,
//  mute status, and a quick way to start/stop the audio engine.
//

import SwiftUI
import OSLog

struct AudioMonitorView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.audioMixer) private var mixer
    @Environment(\.recordingService) private var recordingService
    @State private var showingAudioMixer = false

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
            HStack(spacing: 10) {
                channelMeter(
                    label: "MIC",
                    level: Double(mixer.microphoneLevel),
                    isMuted: false,
                    deviceName: activeInputName(mixer: mixer)
                )

                Divider()
                    .background(theme.border.opacity(0.4))

                channelMeter(
                    label: "SYS",
                    level: Double(mixer.systemLevel),
                    isMuted: false,
                    deviceName: "System"
                )

                Divider()
                    .background(theme.border.opacity(0.4))

                channelMeter(
                    label: "OUT",
                    level: Double(mixer.outputLevel),
                    isMuted: mixer.isOutputMuted,
                    deviceName: mixer.selectedOutputDeviceID == nil
                        ? "Default"
                        : (mixer.availableOutputDevices.first { $0.id == mixer.selectedOutputDeviceID }?.name ?? "Output")
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
        .frame(width: 220)
        .sheet(isPresented: $showingAudioMixer) {
            AudioMixerView()
                .frame(minWidth: 460, idealWidth: 520, minHeight: 880, idealHeight: 980)
        }
        .task {
            // Try to start the engine automatically when the monitor appears.
            // If it fails (e.g. no microphone permission) the power button stays
            // visible so the user can retry.
            guard !mixer.isRunning else { return }
            do {
                try mixer.start()
            } catch {
                audioMonitorLogger.error("Auto-start audio engine failed: \(error.localizedDescription)")
            }
        }
    }

    private func channelMeter(
        label: String,
        level: Double,
        isMuted: Bool,
        deviceName: String
    ) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.text)

            RetroLEDMeter(level: isMuted ? 0 : level, theme: theme)
                .frame(width: 24, height: 92)

            HStack(spacing: 2) {
                Circle()
                    .fill(isMuted ? Color.red : Color.green)
                    .frame(width: 6, height: 6)
                Text(isMuted ? "MUTE" : "LIVE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(isMuted ? Color.red : Color.green)
            }

            Text(deviceName)
                .font(.system(size: 8))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .frame(width: 58)
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
                    showingAudioMixer = true
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

    private func activeInputName(mixer: AudioMixer) -> String {
        let activeIDs = mixer.selectedInputDeviceIDs.compactMap { $0 }
        guard !activeIDs.isEmpty else { return "Default" }
        if activeIDs.count == 1,
           let device = mixer.availableInputDevices.first(where: { $0.uniqueID == activeIDs.first }) {
            return device.localizedName
        }
        return "\(activeIDs.count) Inputs"
    }
}

// MARK: - Retro LED meter

struct RetroLEDMeter: View {
    let level: Double
    let theme: ThemeStore
    private let segments = 20

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
