//
//  SettingsView.swift
//  FreeStage
//
//  Application preferences for recording directory, format, and show behavior.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.cueTriggerServer) private var cueTriggerServer
    @Environment(\.oscCueServer) private var oscCueServer
    @State private var showingDirectoryPicker = false
    @State private var showingDocumentation = false
    @State private var showingStreamDestinations = false

    private enum ResolutionPreset: String, CaseIterable, Identifiable {
        case hd720 = "1280x720"
        case hd1080 = "1920x1080"
        case uhd4K = "3840x2160"

        var id: String { rawValue }
        var size: CGSize {
            switch self {
            case .hd720: return CGSize(width: 1280, height: 720)
            case .hd1080: return CGSize(width: 1920, height: 1080)
            case .uhd4K: return CGSize(width: 3840, height: 2160)
            }
        }
        var displayName: String {
            switch self {
            case .hd720: return "1280 × 720"
            case .hd1080: return "1920 × 1080"
            case .uhd4K: return "3840 × 2160"
            }
        }
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Recording") {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recording Directory")
                            .font(.headline)
                        Text(settings.recordingDirectory.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Choose…") {
                        showingDirectoryPicker = true
                    }
                }

                Picker("Format", selection: $settings.recordingFormat) {
                    ForEach(AppSettings.RecordingFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }

                Picker("Resolution", selection: resolutionBinding) {
                    ForEach(ResolutionPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }

                Picker("Frame Rate", selection: $settings.recordingFrameRate) {
                    Text("24 fps").tag(24)
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }

                if settings.recordingFormat.supportsBitrate {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Bitrate")
                            Spacer()
                            Text("\(settings.recordingBitrate / 1_000_000) Mbps")
                                .monospacedDigit()
                        }
                        Slider(
                            value: bitrateBinding,
                            in: 1_000_000...80_000_000,
                            step: 1_000_000
                        )
                    }
                }

                HStack {
                    Text("Auto-split every")
                    Spacer()
                    Picker("", selection: $settings.recordingAutoSplitMinutes) {
                        Text("Off").tag(0)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("60 min").tag(60)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .labelsHidden()
                }

                HStack {
                    Text("Min. free space")
                    Spacer()
                    TextField("MB", value: $settings.recordingMinFreeSpaceMB, format: .number)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section("Screen Capture") {
                Toggle("Hide desktop icons", isOn: $settings.hideDesktopIconsDuringCapture)
                    .help("Exclude Finder desktop windows from display capture so folders and files are not visible.")
            }

            Section("Show Mode") {
                Toggle("Record on GO", isOn: $settings.recordOnGo)
                    .help("Start/stop recording with the GO button while in Show mode.")

                Toggle("Stop recording at show end", isOn: $settings.autoStopRecordingOnShowEnd)
                    .help("Automatically stop recording after the last cue fires.")

                Toggle("Activate virtual camera in Show mode", isOn: $settings.startVirtualCameraOnShowMode)
                    .help("Turn on the virtual camera output when entering Show mode.")
            }

            Section("Streaming") {
                Button("Manage Stream Destinations…") {
                    showingStreamDestinations = true
                }
                .help("Add RTMP/RTMPS destinations for Twitch, YouTube, Facebook Live, or custom ingest servers.")

                if !isHaishinKitLinked {
                    Text("HaishinKit is not linked. Add the HaishinKit Swift Package to enable live streaming.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Help") {
                Button("Open FreeStage Help") {
                    showingDocumentation = true
                }
            }

            Section("External Control") {
                Toggle("Localhost only", isOn: $settings.cueTriggerServerLocalhostOnly)
                    .help("Reject connections from other devices on the network.")

                Toggle("Enable HTTP Trigger Server", isOn: $settings.cueTriggerServerEnabled)
                    .help("Listen for HTTP POST /cue/<uuid> requests.")

                HStack {
                    Text("HTTP Port")
                    Spacer()
                    TextField("Port", value: httpPortBinding, format: .number)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .disabled(settings.cueTriggerServerEnabled)
                }

                HStack {
                    Text("HTTP Status")
                    Spacer()
                    Text(httpServerStatus)
                        .font(.caption)
                        .foregroundStyle(cueTriggerServer?.isRunning == true ? .green : .secondary)
                }

                Toggle("Enable OSC Trigger Server", isOn: $settings.oscCueServerEnabled)
                    .help("Listen for OSC messages such as /freestage/cue/<uuid>.")

                HStack {
                    Text("OSC Port")
                    Spacer()
                    TextField("Port", value: oscPortBinding, format: .number)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .disabled(settings.oscCueServerEnabled)
                }

                HStack {
                    Text("OSC Status")
                    Spacer()
                    Text(oscServerStatus)
                        .font(.caption)
                        .foregroundStyle(oscCueServer?.isRunning == true ? .green : .secondary)
                }

                externalControlExamples
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, idealWidth: 520)
        .padding()
        .sheet(isPresented: $showingDirectoryPicker) {
            DirectoryPickerSheet(selectedURL: $settings.recordingDirectory)
        }
        .sheet(isPresented: $showingDocumentation) {
            DocumentationView()
                .frame(minWidth: 700, minHeight: 600)
        }
        .sheet(isPresented: $showingStreamDestinations) {
            StreamDestinationsSettingsView()
                .frame(minWidth: 560, minHeight: 480)
        }
    }

    private var isHaishinKitLinked: Bool {
        #if canImport(HaishinKit)
        return true
        #else
        return false
        #endif
    }

    private var bitrateBinding: Binding<Double> {
        Binding(
            get: { Double(settings.recordingBitrate) },
            set: { settings.recordingBitrate = Int($0) }
        )
    }

    private var resolutionBinding: Binding<ResolutionPreset> {
        Binding(
            get: {
                ResolutionPreset.allCases.first {
                    $0.size == settings.recordingResolution
                } ?? .hd1080
            },
            set: { settings.recordingResolution = $0.size }
        )
    }

    private var httpPortBinding: Binding<Int> {
        Binding(
            get: { Int(settings.cueTriggerServerPort) },
            set: { settings.cueTriggerServerPort = UInt16(clamping: $0) }
        )
    }

    private var httpServerStatus: String {
        guard let cueTriggerServer else { return "Not available" }
        if cueTriggerServer.isRunning {
            return "Listening on port \(cueTriggerServer.port)"
        }
        return settings.cueTriggerServerEnabled ? "Failed to start" : "Stopped"
    }

    private var oscPortBinding: Binding<Int> {
        Binding(
            get: { Int(settings.oscCueServerPort) },
            set: { settings.oscCueServerPort = UInt16(clamping: $0) }
        )
    }

    private var oscServerStatus: String {
        guard let oscCueServer else { return "Not available" }
        if oscCueServer.isRunning {
            return "Listening on port \(oscCueServer.port)"
        }
        return settings.oscCueServerEnabled ? "Failed to start" : "Stopped"
    }

    private var externalControlExamples: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Examples")
                .font(.caption)
                .foregroundStyle(.secondary)

            exampleRow(
                label: "Trigger a cue via HTTP:",
                value: "curl -X POST http://\(serverHost):\(settings.cueTriggerServerPort)/cue/<uuid>"
            )

            exampleRow(
                label: "List all cues via HTTP:",
                value: "curl http://\(serverHost):\(settings.cueTriggerServerPort)/cues"
            )

            exampleRow(
                label: "Trigger a cue via OSC:",
                value: "/freestage/cue/<uuid>"
            )

            exampleRow(
                label: "Trigger by cue number via OSC:",
                value: "/freestage/cue/number/<number>"
            )

            exampleRow(
                label: "Press GO via OSC:",
                value: "/freestage/cue/go"
            )

            Text("Right-click any cue in the cue list to copy its HTTP URL or OSC address.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(.top, 4)
    }

    private var serverHost: String {
        settings.cueTriggerServerLocalhostOnly ? "localhost" : "<this-mac-ip>"
    }

    private func exampleRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

/// Minimal directory picker sheet that updates a bound URL.
private struct DirectoryPickerSheet: View {
    @Binding var selectedURL: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose Recording Directory")
                .font(.headline)

            Text(selectedURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.directoryURL = selectedURL
                    panel.begin { result in
                        guard result == .OK, let url = panel.url else { return }
                        selectedURL = url
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 320)
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings())
}
