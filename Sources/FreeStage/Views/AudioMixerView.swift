//
//  AudioMixerView.swift
//  FreeStage
//
//  Audio mixer panel: input/output device selection, per-channel volume and EQ,
//  master volume, and recording status. Supports three independent input
//  channels plus system audio.
//

import SwiftUI
import AVFoundation

enum AudioMixerFocus: Hashable, Identifiable {
    case inputs
    case system
    case master

    var id: Self { self }
}

struct AudioMixerView: View {
    @Environment(\.audioMixer) private var mixer
    @Environment(\.recordingService) private var recordingService
    @Environment(\.dismiss) private var dismiss
    var focus: AudioMixerFocus?

    var body: some View {
        Group {
            if let mixer = mixer, let recordingService = recordingService {
                @Bindable var mixer = mixer

                VStack(spacing: 0) {
                    HStack {
                        Text("Audio Mixer")
                            .font(.headline)
                        Spacer()
                        Button("Done") {
                            dismiss()
                        }
                        .keyboardShortcut(.return, modifiers: [.command])
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                            outputSection(
                                outputDevices: mixer.availableOutputDevices,
                                outputDeviceBinding: outputDeviceBinding(mixer: mixer),
                                isMuted: $mixer.isOutputMuted
                            )

                            Divider()

                            inputChannelsSection(mixer: mixer)
                                .id(AudioMixerFocus.inputs)

                            Divider()

                            systemChannelSection(
                                mixer: mixer,
                                volume: $mixer.systemVolume,
                                isMuted: $mixer.systemMuted,
                                lowGain: $mixer.systemLowGain,
                                midGain: $mixer.systemMidGain,
                                highGain: $mixer.systemHighGain
                            )
                            .id(AudioMixerFocus.system)

                            Divider()

                            masterSection(volume: $mixer.masterVolume)
                                .id(AudioMixerFocus.master)

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
                        .onAppear {
                            if let focus {
                                withAnimation {
                                    proxy.scrollTo(focus, anchor: .top)
                                }
                            }
                        }
                    }
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

    private func inputChannelsSection(mixer: AudioMixer) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "mic.fill")
                Text("Input Channels")
                    .font(.headline)
                Spacer()
            }

            ForEach(0..<AudioMixer.inputChannelCount, id: \.self) { index in
                inputChannelRow(mixer: mixer, index: index)
                if index < AudioMixer.inputChannelCount - 1 {
                    Divider()
                }
            }
        }
    }

    private func inputChannelRow(mixer: AudioMixer, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Input \(index + 1)")
                    .font(.subheadline.bold())
                Spacer()
                if mixer.inputAutoGainEnabled(at: index) {
                    Text("AGC \(mixer.inputAutoGainDB(at: index), specifier: "%.1f") dB")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.green)
                }
                Toggle("Mute", isOn: inputMutedBinding(mixer: mixer, index: index))
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                Picker("Input \(index + 1)", selection: inputDeviceBinding(mixer: mixer, index: index)) {
                    Text("Off").tag(nil as String?)
                    ForEach(mixer.availableInputDevices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID as String?)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 220)
            }

            Toggle("Auto Gain (YouTube level)", isOn: inputAutoGainBinding(mixer: mixer, index: index))
                .toggleStyle(.checkbox)
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Volume")
                        .font(.caption)
                    Spacer()
                    Text("\(mixer.inputVolume(at: index), specifier: "%.2f")")
                        .font(.caption.monospacedDigit())
                }
                Slider(value: inputVolumeBinding(mixer: mixer, index: index), in: 0...2, step: 0.01)
            }

            HStack(spacing: 8) {
                compactEQSlider(label: "Low", value: inputLowGainBinding(mixer: mixer, index: index))
                compactEQSlider(label: "Mid", value: inputMidGainBinding(mixer: mixer, index: index))
                compactEQSlider(label: "High", value: inputHighGainBinding(mixer: mixer, index: index))
            }
        }
    }

    private func inputDeviceBinding(mixer: AudioMixer, index: Int) -> Binding<String?> {
        Binding(
            get: { mixer.inputDeviceID(at: index) },
            set: { mixer.setInputDeviceID($0, at: index) }
        )
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

    private func inputAutoGainBinding(mixer: AudioMixer, index: Int) -> Binding<Bool> {
        Binding(
            get: { mixer.inputAutoGainEnabled(at: index) },
            set: { mixer.setInputAutoGainEnabled($0, at: index) }
        )
    }

    private func inputLowGainBinding(mixer: AudioMixer, index: Int) -> Binding<Double> {
        Binding(
            get: { mixer.inputLowGain(at: index) },
            set: { mixer.setInputLowGain($0, at: index) }
        )
    }

    private func inputMidGainBinding(mixer: AudioMixer, index: Int) -> Binding<Double> {
        Binding(
            get: { mixer.inputMidGain(at: index) },
            set: { mixer.setInputMidGain($0, at: index) }
        )
    }

    private func inputHighGainBinding(mixer: AudioMixer, index: Int) -> Binding<Double> {
        Binding(
            get: { mixer.inputHighGain(at: index) },
            set: { mixer.setInputHighGain($0, at: index) }
        )
    }

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

            HStack(spacing: 8) {
                compactEQSlider(label: "Low", value: lowGain)
                compactEQSlider(label: "Mid", value: midGain)
                compactEQSlider(label: "High", value: highGain)
            }
        }
    }

    private func systemChannelSection(
        mixer: AudioMixer,
        volume: Binding<Double>,
        isMuted: Binding<Bool>,
        lowGain: Binding<Double>,
        midGain: Binding<Double>,
        highGain: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "speaker.wave.2.fill")
                Text("System Audio")
                    .font(.headline)
                Spacer()
                if mixer.systemAutoGainEnabled {
                    Text("AGC \(mixer.systemAutoGainDB, specifier: "%.1f") dB")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.green)
                }
                Toggle("Mute", isOn: isMuted)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                Text("\(volume.wrappedValue, specifier: "%.2f")")
                    .font(.caption.monospacedDigit())
            }

            Toggle("Auto Gain (YouTube level)", isOn: Binding(
                get: { mixer.systemAutoGainEnabled },
                set: { mixer.systemAutoGainEnabled = $0 }
            ))
                .toggleStyle(.checkbox)
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Volume")
                        .font(.caption)
                    Spacer()
                }
                Slider(value: volume, in: 0...2, step: 0.01)
            }

            HStack(spacing: 8) {
                compactEQSlider(label: "Low", value: lowGain)
                compactEQSlider(label: "Mid", value: midGain)
                compactEQSlider(label: "High", value: highGain)
            }
        }
    }

    private func compactEQSlider(label: String, value: Binding<Double>) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption2)
                Spacer()
                Text("\(value.wrappedValue, specifier: "%.1f") dB")
                    .font(.caption2.monospacedDigit())
            }
            Slider(value: value, in: -12...12, step: 0.5)
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
