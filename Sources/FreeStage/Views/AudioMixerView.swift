//
//  AudioMixerView.swift
//  FreeStage
//
//  Audio mixer panel: input/output device selection, per-channel volume and EQ,
//  master volume, and recording status.
//

import SwiftUI
import AVFoundation

struct AudioMixerView: View {
    @Environment(\.audioMixer) private var mixer
    @Environment(\.recordingService) private var recordingService

    var body: some View {
        Group {
            if let mixer = mixer, let recordingService = recordingService {
                @Bindable var mixer = mixer

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        outputSection(
                            outputDevices: mixer.availableOutputDevices,
                            outputDeviceBinding: outputDeviceBinding(mixer: mixer),
                            isMuted: $mixer.isOutputMuted
                        )

                        inputSection(
                            inputDevices: mixer.availableInputDevices,
                            selectedInputDeviceID: $mixer.selectedInputDeviceID
                        )

                        Divider()

                        channelSection(
                            icon: "mic.fill",
                            label: "Microphone",
                            volume: $mixer.microphoneVolume,
                            lowGain: $mixer.microphoneLowGain,
                            midGain: $mixer.microphoneMidGain,
                            highGain: $mixer.microphoneHighGain
                        )

                        Divider()

                        channelSection(
                            icon: "speaker.wave.2.fill",
                            label: "System Audio",
                            volume: $mixer.systemVolume,
                            lowGain: $mixer.systemLowGain,
                            midGain: $mixer.systemMidGain,
                            highGain: $mixer.systemHighGain
                        )

                        Divider()

                        masterSection(volume: $mixer.masterVolume)

                        Divider()

                        StreamingStatusView()

                        Divider()

                        recordingStatusSection(recordingService: recordingService)

                        Divider()

                        engineSection(isRunning: mixer.isRunning) {
                            toggleAudioEngine(mixer: mixer)
                        }
                    }
                    .padding()
                }
            } else {
                Text("Audio services not available")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    private func outputDeviceBinding(mixer: AudioMixer) -> Binding<AudioDevice?> {
        Binding(
            get: {
                guard let id = mixer.selectedOutputDeviceID else { return nil }
                return mixer.availableOutputDevices.first { $0.id == id }
            },
            set: { mixer.selectedOutputDeviceID = $0?.id }
        )
    }

    // MARK: - Sections

    private func outputSection(
        outputDevices: [AudioDevice],
        outputDeviceBinding: Binding<AudioDevice?>,
        isMuted: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "hifispeaker.fill")
                Text("Output Device")
                    .font(.headline)
                Spacer()
            }

            Picker("Output", selection: outputDeviceBinding) {
                Text("System Default").tag(nil as AudioDevice?)
                ForEach(outputDevices) { device in
                    Text(device.name).tag(device as AudioDevice?)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Toggle("Mute Output", isOn: isMuted)
        }
    }

    private func inputSection(
        inputDevices: [AVCaptureDevice],
        selectedInputDeviceID: Binding<String?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "mic.fill")
                Text("Input Device")
                    .font(.headline)
                Spacer()
            }

            Picker("Input", selection: selectedInputDeviceID) {
                Text("System Default").tag(nil as String?)
                ForEach(inputDevices, id: \.uniqueID) { device in
                    Text(device.localizedName).tag(device.uniqueID as String?)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private func channelSection(
        icon: String,
        label: String,
        volume: Binding<Double>,
        lowGain: Binding<Double>,
        midGain: Binding<Double>,
        highGain: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                Text(label)
                    .font(.headline)
                Spacer()
                Text("\(volume.wrappedValue, specifier: "%.2f")")
                    .font(.caption.monospacedDigit())
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Volume")
                        .font(.caption)
                    Spacer()
                }
                Slider(value: volume, in: 0...2, step: 0.01)
            }

            HStack(spacing: 12) {
                eqSlider(label: "Low", value: lowGain)
                eqSlider(label: "Mid", value: midGain)
                eqSlider(label: "High", value: highGain)
            }
        }
    }

    private func eqSlider(label: String, value: Binding<Double>) -> some View {
        VStack(spacing: 4) {
            Text("\(value.wrappedValue, specifier: "%.1f") dB")
                .font(.caption2.monospacedDigit())
            Slider(value: value, in: -12...12, step: 0.5)
                .rotationEffect(.degrees(-90))
                .frame(width: 24, height: 80)
            Text(label)
                .font(.caption2)
        }
        .frame(maxWidth: .infinity)
    }

    private func masterSection(volume: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "speaker.fill")
                Text("Master")
                    .font(.headline)
                Spacer()
                Text("\(volume.wrappedValue, specifier: "%.2f")")
                    .font(.caption.monospacedDigit())
            }
            Slider(value: volume, in: 0...2, step: 0.01)
        }
    }

    private func recordingStatusSection(recordingService: RecordingService) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: recordingService.isRecording ? "record.circle.fill" : "record.circle")
                    .foregroundStyle(recordingService.isRecording ? .red : .secondary)
                Text(recordingService.isRecording ? "Recording" : (recordingService.isPaused ? "Paused" : "Not recording"))
                    .font(.caption)
                Spacer()
                if recordingService.isRecording || recordingService.isPaused {
                    Text(formatDuration(recordingService.recordingDuration))
                        .font(.caption.monospacedDigit())
                }
            }

            if recordingService.isRecording || recordingService.isPaused {
                HStack {
                    Text(formatFileSize(recordingService.recordedFileSize))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let url = recordingService.lastRecordingURL {
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 8) {
                    if recordingService.isRecording {
                        Button("Pause") {
                            Task { await recordingService.pauseRecording() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Split") {
                            Task { try? await recordingService.splitRecording() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else if recordingService.isPaused {
                        Button("Resume") {
                            _ = try? recordingService.resumeRecording()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private func engineSection(isRunning: Bool, toggle: @escaping () -> Void) -> some View {
        HStack {
            Button(isRunning ? "Stop Audio Engine" : "Start Audio Engine", action: toggle)
                .buttonStyle(.borderless)

            Spacer()

            Text(isRunning ? "Running" : "Stopped")
                .font(.caption)
                .foregroundStyle(isRunning ? .green : .secondary)
        }
    }

    private func toggleAudioEngine(mixer: AudioMixer) {
        if mixer.isRunning {
            mixer.stop()
        } else {
            do {
                try mixer.start()
            } catch {
                print("[FreeStage] Failed to start audio engine: \(error)")
            }
        }
    }
}

#Preview {
    AudioMixerView()
        .environment(\.audioMixer, AudioMixer())
        .environment(\.recordingService, RecordingService())
}
