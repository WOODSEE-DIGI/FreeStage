//
//  PresenterWorkspaceView.swift
//  FreeStage
//
//  Streamlined workspace for presenter-to-camera shows. Replaces the theatre
//  cue/scene/layer UI with a segment rundown, live camera monitor, preview,
//  and placeholder panel.
//

import SwiftUI
import AVFoundation
import Combine
import UniformTypeIdentifiers

struct PresenterWorkspaceView: View {
    @Environment(ShowStore.self) private var store
    @Environment(ThemeStore.self) private var theme
    @Environment(\.cameraCaptureManager) private var cameraCaptureManager
    @Environment(\.screenCaptureManager) private var screenCaptureManager
    @Environment(\.cameraControlService) private var cameraControlService
    @State private var cameras: [CameraDevice] = []
    @State private var editingSegmentID: UUID?
    @State private var isSegmentEditorExpanded = false
    @State private var playbackRefreshID = UUID()
    @State private var isPickingChromaBackground = false
    @State private var isPickingGlobalBackground = false
    @State private var isPickingGlobalLayerImage = false
    @State private var isPickingGlobalLayerVideo = false
    @State private var selectedGlobalLayerID: UUID?
    private let iconStripWidth: CGFloat = 72
    private let playbackTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var isEditingClip: Binding<Bool> {
        Binding(
            get: { editingSegmentID != nil },
            set: { if !$0 { editingSegmentID = nil } }
        )
    }

    private var requiredCameraIDs: Set<String> {
        var ids = Set<String>()
        ids.formUnion(cameraIDs(for: store.presenterLiveScene))
        ids.formUnion(cameraIDs(for: store.presenterActiveScene))
        // Keep configured cameras awake even when the current segment is a
        // title/break, so selecting a camera in Show Setup immediately turns it on.
        if let primaryID = store.presenterCameraID(for: .primary) {
            ids.insert(primaryID)
        }
        if let secondaryID = store.presenterCameraID(for: .secondary) {
            ids.insert(secondaryID)
        }
        return ids
    }

    private var requiredScreenIDs: Set<CGDirectDisplayID> {
        // Presenter mode does not use screen-capture sources directly.
        []
    }

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()

            VStack(spacing: 12) {
                headerBar
                    .padding(.horizontal)

                PresenterSplitView(
                    isSegmentEditorExpanded: isSegmentEditorExpanded,
                    leftContent: AnyView(leftPanel),
                    centreContent: AnyView(
                        VStack(spacing: 12) {
                            liveMonitor
                            previewMonitor
                        }
                    ),
                    rightContent: AnyView(placeholderPanel)
                )
                .padding(.horizontal)

                transportBar
                    .padding(.horizontal)
                    .padding(.bottom)
            }
            .padding(.vertical, 8)
            .frame(minWidth: 1200, minHeight: 800)
            .background(WindowFrameInitializer(minSize: NSSize(width: 1200, height: 800)))
        }
        .onChange(of: requiredCameraIDs) { _, _ in
            updateCameraCapture()
        }
        .task {
            updateCameraCapture()
        }
        .onReceive(playbackTimer) { _ in
            playbackRefreshID = UUID()
        }
        .sheet(isPresented: isEditingClip) {
            if let segmentID = editingSegmentID, let binding = clipBinding(for: segmentID) {
                VideoClipEditorView(clip: binding)
                    .frame(minWidth: 820, minHeight: 600)
            }
        }
        .fileImporter(
            isPresented: $isPickingChromaBackground,
            allowedContentTypes: [.image, .movie],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let url = urls.first,
                  let segmentID = store.activeSegmentID else { return }
            let source: Source
            if let type = UTType(filenameExtension: url.pathExtension),
               type.conforms(to: .image) {
                source = .image(url: url)
            } else {
                source = .media(url: url)
            }
            store.updatePresenterSegment(id: segmentID) { segment in
                var filter = segment.chromaKeyFilter ?? ChromaKeyFilter(isEnabled: true)
                filter.backgroundSource = source
                segment.chromaKeyFilter = filter
            }
        }
        .fileImporter(
            isPresented: $isPickingGlobalBackground,
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
            guard var rundown = store.presenterRundown else { return }
            rundown.backgroundSource = source
            rundown.backgroundTransform = .identity
            store.show.presenterRundown = rundown
        }
        .fileImporter(
            isPresented: $isPickingGlobalLayerImage,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let url = urls.first else { return }
            let id = store.addPresenterGlobalLayer(source: .image(url: url))
            selectedGlobalLayerID = id
        }
        .fileImporter(
            isPresented: $isPickingGlobalLayerVideo,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let url = urls.first else { return }
            let id = store.addPresenterGlobalLayer(source: .media(url: url))
            selectedGlobalLayerID = id
        }
    }

    // MARK: - Capture management

    private func updateCameraCapture() {
        let ids = Array(requiredCameraIDs)
        print("[PresenterWorkspaceView] required camera IDs: \(ids)")
        cameraCaptureManager?.syncCaptures(requiredIDs: requiredCameraIDs)
    }

    private func cameraIDs(for scene: Scene?) -> Set<String> {
        guard let scene else { return [] }
        var ids = Set<String>()
        for layer in scene.layers {
            if case .camera(let deviceID) = layer.source {
                ids.insert(deviceID)
            }
        }
        return ids
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

    // MARK: - Layout sizing

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.show.name)
                    .font(.title2.bold())
                    .foregroundStyle(theme.text)
                Text("Presenter Mode")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
        }
    }

    // MARK: - Left panel (rundown + segment editor)

    /// Left column: full rundown list when collapsed, icon strip + expanded
    /// editor when expanded. The GeometryReader measures the actual width
    /// allocated by the split view so the editor can be pinned without the
    /// ScrollView creating a layout feedback loop.
    private var leftPanel: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let editorWidth = max(0, totalWidth - iconStripWidth - 1)
            HStack(spacing: 0) {
                if isSegmentEditorExpanded, let segment = store.activeSegment {
                    iconRundown
                        .frame(width: iconStripWidth)
                    Divider()
                    expandedSegmentEditor(segment)
                        .frame(minWidth: editorWidth, maxWidth: editorWidth, maxHeight: .infinity)
                } else {
                    expandedRundownList
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(theme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Full-height, named rundown list. Selecting a cue expands the editor and
    /// collapses this list down to the icon strip.
    private var expandedRundownList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Rundown")
                    .font(.headline)
                    .foregroundStyle(theme.text)
                Spacer()
                Button {
                    store.addPresenterSegment(type: .cameraGraphic, after: store.activeSegmentID)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add segment after the selected one")
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            if let segments = store.presenterRundown?.segments, !segments.isEmpty {
                List(selection: .constant(store.activeSegmentID)) {
                    ForEach(segments) { segment in
                        segmentRow(segment)
                            .listRowBackground(rowBackground(for: segment))
                            .tag(segment.id)
                    }
                    .onMove { source, destination in
                        store.movePresenterSegment(from: source, to: destination)
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { index in
                            let id = segments[index].id
                            store.deletePresenterSegment(id: id)
                        }
                    }
                }
                .listStyle(.plain)
            } else {
                ContentUnavailableView("No Segments", systemImage: "list.bullet.rectangle")
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }

    /// Icon-only rundown used when the segment editor is expanded.
    /// Shows cue number and type icon; live/active/auto-follow badges overlay
    /// the top-right corner. Icons are constrained to a fixed template frame
    /// and scaled to fit so wide SF Symbols never overflow the strip.
    private var iconRundown: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(Array((store.presenterRundown?.segments ?? []).enumerated()), id: \.element.id) { index, segment in
                    Button {
                        store.selectSegment(id: segment.id)
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            VStack(spacing: 2) {
                                Image(systemName: segment.type.iconName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .foregroundStyle(
                                        segment.id == store.liveSegmentID ? .red :
                                        (segment.id == store.activeSegmentID ? theme.selected : theme.text)
                                    )
                                Text("\(index + 1)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(theme.secondaryText)
                            }
                            .frame(width: 56, height: 56)
                            .background(rowBackground(for: segment))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            if segment.id == store.liveSegmentID {
                                Image(systemName: "record.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red)
                                    .offset(x: 5, y: -5)
                            } else if segment.id == store.activeSegmentID {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.selected)
                                    .offset(x: 5, y: -5)
                            } else if segment.autoFollow {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.green)
                                    .offset(x: 5, y: -5)
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    .help("\(index + 1). \(segment.name)")
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: iconStripWidth)
    }

    // MARK: - Segment editor

    /// The editor controls without a header. Wrapped by compact/expanded panels.
    private func segmentEditorBody(_ segment: PresenterSegment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Name", text: nameBinding(for: segment))
                .textFieldStyle(.roundedBorder)

            Picker("Type", selection: typeBinding(for: segment)) {
                ForEach(PresenterSegmentType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)

            if segment.type == .cameraGraphic {
                Picker("Camera", selection: cameraAngleBinding(for: segment)) {
                    ForEach(PresenterCameraAngle.allCases) { angle in
                        Text(angle.displayName).tag(angle)
                    }
                }
                .pickerStyle(.segmented)

                cameraSettingsSection(for: segment)
                gimbalSection(for: segment)
                chromaKeySection(for: segment)
            }

            if segment.type == .cameraGraphic || segment.type == .titleCard {
                placeholderPicker(for: segment)
            }

            if segment.type == .videoPackage {
                videoFileSection(for: segment)
            }

            Toggle("Auto-follow to next segment", isOn: autoFollowBinding(for: segment))
                .foregroundStyle(theme.text)

            TextField("Notes", text: notesBinding(for: segment))
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Full-height editor shown beside the icon rundown when expanded.
    /// The parent HStack pins this view to a fixed width so the ScrollView
    /// cannot create a layout feedback loop by proposing its own width.
    private func expandedSegmentEditor(_ segment: PresenterSegment) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Selected Segment")
                    .font(.subheadline.bold())
                    .foregroundStyle(theme.text)
                Spacer()
                Button {
                    isSegmentEditorExpanded = false
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(theme.text)
                }
                .buttonStyle(.borderless)
                .help("Collapse segment editor")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                segmentEditorBody(segment)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Camera settings in segment editor

    private func cameraSettingsSection(for segment: PresenterSegment) -> some View {
        let binding = cameraSettingsBinding(for: segment)
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

    private func gimbalSection(for segment: PresenterSegment) -> some View {
        let binding = cameraSettingsBinding(for: segment)
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

    private func chromaKeySection(for segment: PresenterSegment) -> some View {
        let binding = chromaKeyBinding(for: segment)
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

                chromaKeyBackgroundSection(for: segment)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chromaKeyBackgroundSection(for segment: PresenterSegment) -> some View {
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

    private func cameraSettingsBinding(for segment: PresenterSegment) -> Binding<CameraSettings> {
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

    private func chromaKeyBinding(for segment: PresenterSegment) -> Binding<ChromaKeyFilter> {
        Binding(
            get: { segment.chromaKeyFilter ?? ChromaKeyFilter(isEnabled: false) },
            set: { newValue in
                store.updatePresenterSegment(id: segment.id) { $0.chromaKeyFilter = newValue }
            }
        )
    }

    private func placeholderPicker(for segment: PresenterSegment) -> some View {
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

    private func videoFileSection(for segment: PresenterSegment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Video")
                    .foregroundStyle(theme.text)
                Spacer()
                Button("Choose…") {
                    pickVideoForSegment(segment)
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
                    editingSegmentID = segment.id
                }
                .help("Scrub, set in/out points, and export a subclip")
            }
        }
    }

    private func pickVideoForSegment(_ segment: PresenterSegment) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let clip = VideoClip(sourceURL: url)
            store.updatePresenterSegment(id: segment.id) { $0.videoClip = clip }
            loadDuration(for: segment.id, url: url)
        }
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

    private func nameBinding(for segment: PresenterSegment) -> Binding<String> {
        Binding(
            get: { segment.name },
            set: { newName in
                store.updatePresenterSegment(id: segment.id) { $0.name = newName }
            }
        )
    }

    private func typeBinding(for segment: PresenterSegment) -> Binding<PresenterSegmentType> {
        Binding(
            get: { segment.type },
            set: { newType in
                store.updatePresenterSegment(id: segment.id) { $0.type = newType }
            }
        )
    }

    private func cameraAngleBinding(for segment: PresenterSegment) -> Binding<PresenterCameraAngle> {
        Binding(
            get: { segment.cameraAngle },
            set: { newAngle in
                store.updatePresenterSegment(id: segment.id) { $0.cameraAngle = newAngle }
            }
        )
    }

    private func autoFollowBinding(for segment: PresenterSegment) -> Binding<Bool> {
        Binding(
            get: { segment.autoFollow },
            set: { newValue in
                store.updatePresenterSegment(id: segment.id) { $0.autoFollow = newValue }
            }
        )
    }

    private func notesBinding(for segment: PresenterSegment) -> Binding<String> {
        Binding(
            get: { segment.notes },
            set: { newValue in
                store.updatePresenterSegment(id: segment.id) { $0.notes = newValue }
            }
        )
    }

    private func segmentRow(_ segment: PresenterSegment) -> some View {
        HStack(spacing: 8) {
            Image(systemName: segment.type.iconName)
                .foregroundStyle(theme.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(segment.name)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(segment.type.displayName)
                        .font(.caption2)
                        .foregroundStyle(theme.secondaryText)
                    if segment.type == .cameraGraphic {
                        Text("· \(segment.cameraAngle.displayName)")
                            .font(.caption2)
                            .foregroundStyle(theme.secondaryText)
                    }
                    if segment.autoFollow {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            if segment.id == store.liveSegmentID {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
            } else if segment.id == store.activeSegmentID {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(theme.selected)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectSegment(id: segment.id)
            isSegmentEditorExpanded = true
        }
        .contextMenu {
            Button("Duplicate") {
                store.duplicatePresenterSegment(id: segment.id)
            }
            Button("Delete", role: .destructive) {
                store.deletePresenterSegment(id: segment.id)
            }
        }
    }

    private func rowBackground(for segment: PresenterSegment) -> some View {
        // Only the live segment gets a tinted row background. The selected/
        // preview segment is indicated by the List selection highlight and the
        // icon colour in the icon strip, so two rows are no longer highlighted
        // at once.
        let isLive = segment.id == store.liveSegmentID
        return isLive ? theme.selected.opacity(0.25) : Color.clear
    }

    // MARK: - Monitors

    /// The first media source in the live scene, if any. Used to wire
    /// transport controls to the active video package.
    private var liveMediaSource: Source? {
        firstMediaSource(in: store.presenterLiveScene)
    }

    /// The first media source in the preview (active) scene, if any.
    private var activeMediaSource: Source? {
        firstMediaSource(in: store.presenterActiveScene)
    }

    private func firstMediaSource(in scene: Scene?) -> Source? {
        guard let scene else { return nil }
        for layer in scene.layers {
            switch layer.source {
            case .media, .mediaClip:
                return layer.source
            default:
                continue
            }
        }
        return nil
    }

    private var liveMonitor: some View {
        StageMonitorView(
            scene: store.presenterLiveScene,
            title: "Live",
            isLive: true,
            isEditable: false
        )
    }

    private var previewMonitor: some View {
        StageMonitorView(
            scene: store.presenterActiveScene,
            title: "Preview",
            isLive: false,
            isEditable: false
        )
    }

    // MARK: - Show setup panel

    private var placeholderPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Show Setup")
                .font(.headline)
                .foregroundStyle(theme.text)
                .padding([.horizontal, .top])
                .padding(.bottom, 8)

            cameraSection
                .padding(.horizontal)
                .padding(.bottom, 12)

            backgroundSection
                .padding(.horizontal)
                .padding(.bottom, 12)

            Divider()
                .padding(.horizontal)
                .padding(.bottom, 8)

            HStack {
                Text("Placeholders")
                    .font(.subheadline.bold())
                    .foregroundStyle(theme.text)
                Spacer()
                Button {
                    store.addPresenterPlaceholder()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add a new placeholder")
            }
            .padding(.horizontal)

            if let placeholders = store.presenterRundown?.placeholders, !placeholders.isEmpty {
                List {
                    ForEach(placeholders) { placeholder in
                        placeholderRow(placeholder)
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { index in
                            store.deletePresenterPlaceholder(id: placeholders[index].id)
                        }
                    }
                }
                .listStyle(.plain)
            } else {
                ContentUnavailableView("No Placeholders", systemImage: "square.dashed")
                    .foregroundStyle(theme.secondaryText)
            }

            if let placeholder = store.placeholder(id: store.selectedPlaceholderID) {
                placeholderEditor(placeholder)
                    .padding()
                    .background(theme.background.opacity(0.5))
            }

            Divider()
                .padding(.horizontal)
                .padding(.vertical, 8)

            globalLayersSection
                .padding(.horizontal)
                .padding(.bottom, 12)

            Spacer()
        }
        .background(theme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear(perform: refreshCameras)
    }

    private var cameraSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Cameras")
                    .font(.subheadline.bold())
                    .foregroundStyle(theme.text)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") {
                    refreshCameras()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            cameraPicker(angle: .primary, label: "Primary")
            cameraPicker(angle: .secondary, label: "Secondary")
        }
    }

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Background")
                    .font(.subheadline.bold())
                    .foregroundStyle(theme.text)
                Spacer()
            }

            if let source = store.presenterRundown?.backgroundSource {
                HStack {
                    Text(source.defaultName)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(theme.text)
                    Spacer()
                    Button("Clear") {
                        guard var rundown = store.presenterRundown else { return }
                        rundown.backgroundSource = nil
                        rundown.backgroundTransform = .identity
                        store.show.presenterRundown = rundown
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }

                HStack {
                    Text("Zoom")
                        .font(.caption)
                        .foregroundStyle(theme.text)
                    Slider(
                        value: Binding(
                            get: { store.presenterRundown?.backgroundTransform.scaleX ?? 1 },
                            set: { newValue in
                                guard var rundown = store.presenterRundown else { return }
                                rundown.backgroundTransform.scaleX = newValue
                                rundown.backgroundTransform.scaleY = newValue
                                store.show.presenterRundown = rundown
                            }
                        ),
                        in: 0.1...5
                    )
                }
            } else {
                Button {
                    isPickingGlobalBackground = true
                } label: {
                    Label("Choose Image/Video…", systemImage: "photo")
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Global layers (show in all scenes)

    private var globalLayersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Global Layers")
                    .font(.subheadline.bold())
                    .foregroundStyle(theme.text)
                Spacer()
                Menu {
                    Button("Image…") { isPickingGlobalLayerImage = true }
                    Button("Video…") { isPickingGlobalLayerVideo = true }
                    Button("Color") {
                        let id = store.addPresenterGlobalLayer(
                            source: .color(CGColorComponents(r: 1, g: 0, b: 0, a: 1)),
                            name: "Color"
                        )
                        selectedGlobalLayerID = id
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .help("Add a layer shown in every segment")
            }

            if let layers = store.presenterRundown?.globalLayers, !layers.isEmpty {
                List(selection: .constant(selectedGlobalLayerID)) {
                    ForEach(layers) { layer in
                        globalLayerRow(layer)
                            .tag(layer.id)
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { index in
                            let id = layers[index].id
                            store.deletePresenterGlobalLayer(id: id)
                            if selectedGlobalLayerID == id { selectedGlobalLayerID = nil }
                        }
                    }
                }
                .listStyle(.plain)
                .frame(height: min(CGFloat(layers.count) * 32 + 8, 120))

                if let layer = store.presenterRundown?.globalLayers.first(where: { $0.id == selectedGlobalLayerID }) {
                    globalLayerEditor(layer)
                }
            } else {
                ContentUnavailableView("No Global Layers", systemImage: "square.3.layers.3d")
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }

    private func globalLayerRow(_ layer: Layer) -> some View {
        HStack {
            Image(systemName: iconName(for: layer.source))
                .foregroundStyle(theme.accent)
            Text(layer.name)
                .foregroundStyle(theme.text)
                .lineLimit(1)
            Spacer()
            Text(layer.placement == .background ? "BG" : "FG")
                .font(.caption2.bold())
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(theme.secondaryText.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Button {
                store.updatePresenterGlobalLayer(id: layer.id) { $0.isVisible.toggle() }
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedGlobalLayerID = layer.id
        }
        .background(selectedGlobalLayerID == layer.id ? theme.selected.opacity(0.12) : Color.clear)
    }

    private func iconName(for source: Source) -> String {
        switch source {
        case .image: return "photo"
        case .media, .mediaClip: return "film"
        case .color: return "paintpalette"
        default: return "questionmark.square"
        }
    }

    private func globalLayerEditor(_ layer: Layer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: Binding(
                get: { layer.name },
                set: { newValue in
                    store.updatePresenterGlobalLayer(id: layer.id) { $0.name = newValue }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)

            Picker("Placement", selection: Binding(
                get: { layer.placement },
                set: { newValue in
                    store.updatePresenterGlobalLayer(id: layer.id) { $0.placement = newValue }
                }
            )) {
                Text("Background").tag(Layer.Placement.background)
                Text("Foreground").tag(Layer.Placement.foreground)
            }
            .pickerStyle(.segmented)
            .font(.caption)

            HStack {
                Text("X")
                    .frame(width: 16)
                Slider(value: Binding(
                    get: { layer.transform.x },
                    set: { newValue in
                        store.updatePresenterGlobalLayer(id: layer.id) { $0.transform.x = newValue }
                    }
                ), in: 0...1)
            }
            HStack {
                Text("Y")
                    .frame(width: 16)
                Slider(value: Binding(
                    get: { layer.transform.y },
                    set: { newValue in
                        store.updatePresenterGlobalLayer(id: layer.id) { $0.transform.y = newValue }
                    }
                ), in: 0...1)
            }
            HStack {
                Text("Size")
                    .frame(width: 28)
                Slider(value: Binding(
                    get: { layer.transform.scaleX },
                    set: { newValue in
                        store.updatePresenterGlobalLayer(id: layer.id) {
                            $0.transform.scaleX = newValue
                            $0.transform.scaleY = newValue
                        }
                    }
                ), in: 0.1...3)
            }
            HStack {
                Text("Opacity")
                    .frame(width: 44)
                Slider(value: Binding(
                    get: { layer.opacity },
                    set: { newValue in
                        store.updatePresenterGlobalLayer(id: layer.id) { $0.opacity = newValue }
                    }
                ), in: 0...1)
            }
        }
        .padding()
        .background(theme.background.opacity(0.5))
    }

    private func cameraPicker(angle: PresenterCameraAngle, label: String) -> some View {
        let selectedID = store.presenterCameraID(for: angle)
        let selection = Binding<String?>(
            get: { selectedID },
            set: { store.setPresenterCameraID($0, for: angle) }
        )
        let selectedIsMissing = selectedID != nil && !cameras.contains(where: { $0.uniqueID == selectedID })

        return Picker(label, selection: selection) {
            Text("Not set")
                .tag(String?.none)
            if let selectedID, selectedIsMissing {
                Text("Unknown camera")
                    .foregroundStyle(.secondary)
                    .tag(String?.some(selectedID))
            }
            ForEach(cameras) { camera in
                Text(camera.name)
                    .tag(String?.some(camera.uniqueID))
            }
        }
        .pickerStyle(.menu)
        .foregroundStyle(theme.text)
    }

    private func refreshCameras() {
        cameras = CameraDevice.discover()
    }

    private func placeholderRow(_ placeholder: PresenterPlaceholder) -> some View {
        HStack {
            Text(placeholder.name)
                .foregroundStyle(theme.text)
            Spacer()
            if placeholder.source != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.yellow)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedPlaceholderID = placeholder.id
        }
        .background(store.selectedPlaceholderID == placeholder.id ? theme.selected.opacity(0.12) : Color.clear)
    }

    private func placeholderEditor(_ placeholder: PresenterPlaceholder) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Name", text: nameBinding(for: placeholder))
                .textFieldStyle(.roundedBorder)

            Text("Source")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)

            HStack(spacing: 8) {
                Button("Image…") {
                    pickImageForPlaceholder(placeholder)
                }
                Button("Color") {
                    store.updatePresenterPlaceholder(id: placeholder.id) { $0.source = .color(CGColorComponents(r: 0.9, g: 0.2, b: 0.2, a: 1)) }
                }
                Button("Black") {
                    store.updatePresenterPlaceholder(id: placeholder.id) { $0.source = .color(CGColorComponents(r: 0, g: 0, b: 0, a: 1)) }
                }
            }

            if placeholder.source != nil {
                Button("Clear Source", role: .destructive) {
                    store.updatePresenterPlaceholder(id: placeholder.id) { $0.source = nil }
                }
            }
        }
    }

    private func nameBinding(for placeholder: PresenterPlaceholder) -> Binding<String> {
        Binding(
            get: { placeholder.name },
            set: { newName in
                store.updatePresenterPlaceholder(id: placeholder.id) { $0.name = newName }
            }
        )
    }

    private func pickImageForPlaceholder(_ placeholder: PresenterPlaceholder) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            store.updatePresenterPlaceholder(id: placeholder.id) { $0.source = .image(url: url) }
        }
    }

    // MARK: - Transport

    private var transportBar: some View {
        HStack(spacing: 16) {
            Button {
                store.selectPreviousSegment()
            } label: {
                Label("Previous", systemImage: "backward.frame")
            }

            Spacer()

            // Show video controls for the live video if there is one; otherwise
            // let the operator control the preview video while cueing it.
            if let source = liveMediaSource ?? activeMediaSource {
                videoTransportControls(for: source, label: liveMediaSource == nil ? "Preview" : nil)
            }

            Spacer()

            Button {
                if let liveSource = liveMediaSource,
                   MediaSourceRenderer.shared.isPlaying(source: liveSource) {
                    MediaSourceRenderer.shared.pause(source: liveSource)
                } else {
                    store.presenterGo()
                }
            } label: {
                let isLiveVideoPlaying = liveMediaSource.map(MediaSourceRenderer.shared.isPlaying(source:)) ?? false
                Label(isLiveVideoPlaying ? "PAUSE" : "GO", systemImage: isLiveVideoPlaying ? "pause.fill" : "play.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()

            Button {
                store.selectNextSegment()
            } label: {
                Label("Next", systemImage: "forward.frame")
            }
        }
        .padding()
        .background(theme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func videoTransportControls(for source: Source, label: String?) -> some View {
        // Reading the refresh ID forces SwiftUI to re-evaluate the button icon
        // while the timer ticks.
        let _ = playbackRefreshID

        HStack(spacing: 8) {
            if let label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }

            Button {
                MediaSourceRenderer.shared.restart(source: source)
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .help("Restart video")

            Button {
                if MediaSourceRenderer.shared.isPlaying(source: source) {
                    MediaSourceRenderer.shared.pause(source: source)
                } else {
                    MediaSourceRenderer.shared.play(source: source)
                }
            } label: {
                Image(systemName: MediaSourceRenderer.shared.isPlaying(source: source) ? "pause.fill" : "play.fill")
            }
            .help(MediaSourceRenderer.shared.isPlaying(source: source) ? "Pause video" : "Play video")
        }
    }
}
