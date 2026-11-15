//
//  PresenterSegmentEditor.swift
//  FreeStage
//
//  Shared segment editor body used by the Presenter workspace's expanded
//  segment editor and the Assemble workspace's cue-card editor.
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// Full editing controls for a single presenter segment: type, camera, framing,
/// gimbal, chroma key, placeholder/video source, auto-follow, and notes.
struct PresenterSegmentEditor: View {
    let segment: PresenterSegment
    @Environment(ShowStore.self) private var store
    @Environment(ThemeStore.self) private var theme
    @Environment(\.cameraControlService) private var cameraControlService
    @State private var isPickingChromaBackground = false
    @State private var isPickingVideo = false
    @State private var editingClipSegmentID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Name", text: nameBinding)
                .textFieldStyle(.roundedBorder)

            Picker("Type", selection: typeBinding) {
                ForEach(PresenterSegmentType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)

            if segment.type == .cameraGraphic {
                Picker("Camera", selection: cameraAngleBinding) {
                    ForEach(PresenterCameraAngle.allCases) { angle in
                        Text(angle.displayName).tag(angle)
                    }
                }
                .pickerStyle(.segmented)

                cameraSettingsSection
                gimbalSection
                chromaKeySection
            }

            if segment.type == .cameraGraphic || segment.type == .titleCard {
                placeholderPicker
            }

            if segment.type == .videoPackage {
                videoFileSection
            }

            Toggle("Auto-follow to next segment", isOn: autoFollowBinding)
                .foregroundStyle(theme.text)

            TextField("Notes", text: notesBinding)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fileImporter(
            isPresented: $isPickingChromaBackground,
            allowedContentTypes: [.image, .movie],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let url = urls.first else { return }
            let source: Source
            if let type = UTType(filenameExtension: url.pathExtension),
               type.conforms(to: .image) {
                source = .image(url: url)
            } else {
                source = .media(url: url)
            }
            store.updatePresenterSegment(id: segment.id) { segment in
                var filter = segment.chromaKeyFilter ?? ChromaKeyFilter(isEnabled: true)
                filter.backgroundSource = source
                segment.chromaKeyFilter = filter
            }
        }
        .fileImporter(
            isPresented: $isPickingVideo,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let url = urls.first else { return }
            let clip = VideoClip(sourceURL: url)
            store.updatePresenterSegment(id: segment.id) { $0.videoClip = clip }
            loadDuration(for: segment.id, url: url)
        }
        .sheet(isPresented: .init(
            get: { editingClipSegmentID != nil },
            set: { if !$0 { editingClipSegmentID = nil } }
        )) {
            if let segmentID = editingClipSegmentID, let binding = clipBinding(for: segmentID) {
                VideoClipEditorView(clip: binding)
                    .frame(minWidth: 820, minHeight: 600)
            }
        }
    }

    // MARK: - Camera settings

    private var cameraSettingsSection: some View {
        let binding = cameraSettingsBinding
        return GroupBox("Camera Framing") {
            VStack(alignment: .leading, spacing: 8) {
                Slider(value: binding.zoom, in: 0.1...3.0) {
                    Text("Zoom \(binding.wrappedValue.zoom, specifier: "%.2f")")
                }
                HStack {
                    Text("Pan X")
                    Slider(value: binding.panX, in: 0...1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Text("Pan Y")
                    Slider(value: binding.panY, in: 0...1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Gimbal

    private var gimbalSection: some View {
        let binding = cameraSettingsBinding
        return GroupBox("Gimbal") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Send to Gimbal", isOn: binding.gimbalActive)
                    .foregroundStyle(theme.text)

                HStack {
                    Text("Pan")
                    Slider(value: binding.gimbalPan, in: -90...90)
                    Text("\(binding.wrappedValue.gimbalPan, specifier: "%.0f")°")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Text("Tilt")
                    Slider(value: binding.gimbalTilt, in: -45...45)
                    Text("\(binding.wrappedValue.gimbalTilt, specifier: "%.0f")°")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let service = cameraControlService {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(service.isGimbalConnected ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(service.isGimbalConnected ? "Gimbal connected" : "Gimbal not connected")
                            .font(.caption2)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Chroma key

    private var chromaKeySection: some View {
        let binding = chromaKeyBinding
        return GroupBox("Chroma Key") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enabled", isOn: binding.isEnabled)
                    .foregroundStyle(theme.text)

                Picker("Preset", selection: binding.keyColorPreset) {
                    ForEach(ChromaKeyColorPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Hue")
                    Slider(value: binding.hueShift, in: -.pi...(.pi))
                    Text("\(binding.wrappedValue.hueShift * 180 / .pi, specifier: "%.0f")°")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text("Threshold")
                    Slider(value: binding.threshold, in: 0...1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Text("Smoothing")
                    Slider(value: binding.smoothing, in: 0...1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text("Edge Feather")
                    Slider(value: binding.edgeFeather, in: 0...0.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text("Edge Despill")
                    Slider(value: binding.edgeDespill, in: 0...2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text("Spill Suppression")
                    Slider(value: binding.spillSuppression, in: 0...2)
                        .help("Subtracts the selected key hue from foreground edges and adds back a complementary or skin-warm hue.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text("Spill Range")
                    Slider(value: binding.spillRange, in: 0...1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text("Skin Tone Protection")
                    Slider(value: binding.skinToneProtection, in: 0...1)
                        .help("Detects skin tones and removes spill with a skin-safe correction instead of the aggressive default despill.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                chromaKeyBackgroundSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var chromaKeyBackgroundSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Background")
                .font(.caption.bold())
                .foregroundStyle(theme.secondaryText)

            if let source = segment.chromaKeyFilter?.backgroundSource {
                HStack {
                    Text(source.defaultName)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Button("Clear") {
                        store.updatePresenterSegment(id: segment.id) { segment in
                            segment.chromaKeyFilter?.backgroundSource = nil
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }

                HStack {
                    Text("Zoom")
                    Slider(
                        value: Binding(
                            get: { segment.chromaKeyFilter?.backgroundTransform.scaleX ?? 1 },
                            set: { newValue in
                                store.updatePresenterSegment(id: segment.id) { segment in
                                    segment.chromaKeyFilter?.backgroundTransform.scaleX = newValue
                                    segment.chromaKeyFilter?.backgroundTransform.scaleY = newValue
                                }
                            }
                        ),
                        in: 0.1...5
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button {
                    isPickingChromaBackground = true
                } label: {
                    Label("Choose Image/Video…", systemImage: "photo")
                }
                .font(.caption)
            }

            Text("When no background is chosen, the keyed area is transparent.")
                .font(.caption2)
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.top, 4)
    }

    // MARK: - Placeholder & video

    private var placeholderPicker: some View {
        let binding = Binding<UUID?>(
            get: { segment.placeholderID },
            set: { newID in
                store.updatePresenterSegment(id: segment.id) { $0.placeholderID = newID }
            }
        )

        return Picker("Placeholder", selection: binding) {
            Text("None").tag(UUID?.none)
            if let placeholders = store.presenterRundown?.placeholders {
                ForEach(placeholders) { placeholder in
                    Text(placeholder.name).tag(UUID?.some(placeholder.id))
                }
            }
        }
        .pickerStyle(.menu)
    }

    private var videoFileSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Video")
                    .foregroundStyle(theme.text)
                Spacer()
                Button("Choose…") {
                    isPickingVideo = true
                }
            }
            if let url = segment.videoClip?.sourceURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            } else {
                Text("No video selected")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }

            if segment.videoClip != nil {
                Button("Open Clip Editor") {
                    editingClipSegmentID = segment.id
                }
                .help("Scrub, set in/out points, and export a subclip")
            }
        }
    }

    // MARK: - Bindings

    private var nameBinding: Binding<String> {
        Binding(
            get: { segment.name },
            set: { newName in
                store.updatePresenterSegment(id: segment.id) { $0.name = newName }
            }
        )
    }

    private var typeBinding: Binding<PresenterSegmentType> {
        Binding(
            get: { segment.type },
            set: { newType in
                store.updatePresenterSegment(id: segment.id) { $0.type = newType }
            }
        )
    }

    private var cameraAngleBinding: Binding<PresenterCameraAngle> {
        Binding(
            get: { segment.cameraAngle },
            set: { newAngle in
                store.updatePresenterSegment(id: segment.id) { $0.cameraAngle = newAngle }
            }
        )
    }

    private var autoFollowBinding: Binding<Bool> {
        Binding(
            get: { segment.autoFollow },
            set: { newValue in
                store.updatePresenterSegment(id: segment.id) { $0.autoFollow = newValue }
            }
        )
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { segment.notes },
            set: { newValue in
                store.updatePresenterSegment(id: segment.id) { $0.notes = newValue }
            }
        )
    }

    private var cameraSettingsBinding: Binding<CameraSettings> {
        Binding(
            get: { segment.cameraSettings ?? CameraSettings() },
            set: { newValue in
                store.updatePresenterSegment(id: segment.id) { $0.cameraSettings = newValue }
                if newValue.gimbalActive,
                   let service = cameraControlService,
                   let deviceID = store.presenterCameraID(for: segment.cameraAngle) {
                    service.apply(settings: newValue, to: deviceID)
                }
            }
        )
    }

    private var chromaKeyBinding: Binding<ChromaKeyFilter> {
        Binding(
            get: { segment.chromaKeyFilter ?? ChromaKeyFilter(isEnabled: false) },
            set: { newValue in
                store.updatePresenterSegment(id: segment.id) { $0.chromaKeyFilter = newValue }
            }
        )
    }

    private func clipBinding(for segmentID: UUID) -> Binding<VideoClip>? {
        guard let rundown = store.presenterRundown,
              let index = rundown.segments.firstIndex(where: { $0.id == segmentID }),
              rundown.segments[index].videoClip != nil else { return nil }
        return Binding<VideoClip>(
            get: { store.presenterRundown!.segments[index].videoClip! },
            set: { newClip in
                store.updatePresenterSegment(id: segmentID) { $0.videoClip = newClip }
            }
        )
    }

    private func loadDuration(for segmentID: UUID, url: URL) {
        Task {
            let asset = AVURLAsset(url: url)
            let duration = try? await asset.load(.duration).seconds
            await MainActor.run {
                store.updatePresenterSegment(id: segmentID) { $0.videoClip?.sourceDuration = duration }
            }
        }
    }
}
