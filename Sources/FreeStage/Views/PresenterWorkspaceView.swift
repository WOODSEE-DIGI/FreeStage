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
    @State private var isSegmentEditorExpanded = false
    @State private var playbackRefreshID = UUID()
    @State private var selectedCueLayerID: UUID?
    @State private var isPickingCueLayerImage = false
    @State private var isPickingCueLayerVideo = false
    @State private var isPickingCueScreen = false
    @State private var isPickingCueNDI = false
    @State private var isPickingCueSyphon = false
    private let iconStripWidth: CGFloat = 84
    private let playbackTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

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
        var ids = Set<CGDirectDisplayID>()
        ids.formUnion(screenIDs(for: store.presenterActiveScene))
        ids.formUnion(screenIDs(for: store.presenterLiveScene))
        if let globalLayers = store.presenterRundown?.globalLayers {
            ids.formUnion(screenIDs(in: globalLayers))
        }
        return ids
    }

    private func screenIDs(for scene: Scene?) -> Set<CGDirectDisplayID> {
        guard let scene else { return [] }
        return screenIDs(in: scene.layers)
    }

    private func screenIDs(in layers: [Layer]) -> Set<CGDirectDisplayID> {
        Set(layers.compactMap { layer -> CGDirectDisplayID? in
            if case .screen(let displayID) = layer.source { return displayID }
            return nil
        })
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
        .onChange(of: requiredScreenIDs) { _, _ in
            updateScreenCapture()
        }
        .onChange(of: store.activeSegmentID) { _, _ in
            selectedCueLayerID = nil
            updateCameraCapture()
        }
        .task {
            updateCameraCapture()
            updateScreenCapture()
        }
        .onReceive(playbackTimer) { _ in
            playbackRefreshID = UUID()
        }
        .sheet(isPresented: $isPickingCueScreen) {
            ScreenPickerSheet { display in
                addCueLayer(source: .screen(displayID: display.displayID),
                            name: "Screen \(display.displayID)")
                // Register this build with TCC before the stream is attempted.
                // A stale grant (ad-hoc build rebuilt with a new cdhash) fails
                // silently otherwise: black layer, no error.
                if !ScreenRecordingPermission.isGranted {
                    _ = ScreenRecordingPermission.request()
                }
                screenCaptureManager?.startCapture(displayID: display.displayID)
            }
        }
        .sheet(isPresented: $isPickingCueNDI) {
            NDIPickerSheet { source in
                addCueLayer(source: source, name: source.defaultName)
            }
        }
        .sheet(isPresented: $isPickingCueSyphon) {
            SyphonPickerSheet { source in
                addCueLayer(source: source, name: source.defaultName)
            }
        }
        .fileImporter(
            isPresented: $isPickingCueLayerImage,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let url = urls.first else { return }
            addCueLayer(source: .image(url: url))
        }
        .fileImporter(
            isPresented: $isPickingCueLayerVideo,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let url = urls.first else { return }
            addCueLayer(source: .media(url: url))
        }
    }

    private func addCueLayer(source: Source, name: String? = nil) {
        guard let segmentID = store.activeSegmentID else { return }
        selectedCueLayerID = store.addPresenterSegmentLayer(
            segmentID: segmentID,
            source: source,
            name: name
        )
    }

    // MARK: - Capture management

    private func updateCameraCapture() {
        let ids = Array(requiredCameraIDs)
        print("[PresenterWorkspaceView] required camera IDs: \(ids)")
        cameraCaptureManager?.syncCaptures(requiredIDs: requiredCameraIDs)
    }

    private func updateScreenCapture() {
        screenCaptureManager?.syncCaptures(requiredIDs: requiredScreenIDs)
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
    /// the top-right corner. The background is a rounded rectangle behind the
    /// content instead of a clip shape, so wide SF Symbols and badges can not
    /// be sliced off at the right edge.
    private var iconRundown: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(Array((store.presenterRundown?.segments ?? []).enumerated()), id: \.element.id) { index, segment in
                    iconButton(for: segment, index: index)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: iconStripWidth)
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func iconButton(for segment: PresenterSegment, index: Int) -> some View {
        Button {
            store.selectSegment(id: segment.id)
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 2) {
                    Image(systemName: segment.type.iconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .foregroundStyle(iconForeground(for: segment))
                    Text("\(index + 1)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                }
                .frame(width: 64, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(rowBackground(for: segment))
                )

                if segment.id == store.liveSegmentID {
                    badgeIcon("record.circle.fill", color: .red)
                } else if segment.id == store.activeSegmentID {
                    badgeIcon("play.circle.fill", color: theme.selected)
                } else if segment.autoFollow {
                    badgeIcon("arrow.right.circle.fill", color: .green)
                }
            }
        }
        .buttonStyle(.borderless)
        .help("\(index + 1). \(segment.name)")
    }

    private func badgeIcon(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 11))
            .foregroundStyle(color)
            .offset(x: 4, y: -4)
    }

    private func iconForeground(for segment: PresenterSegment) -> Color {
        if segment.id == store.liveSegmentID {
            return .red
        } else if segment.id == store.activeSegmentID {
            return theme.selected
        } else {
            return theme.text
        }
    }

    // MARK: - Segment editor

    /// The editor controls without a header. Wrapped by compact/expanded panels.
    private func segmentEditorBody(_ segment: PresenterSegment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PresenterSegmentEditor(segment: segment)

            cueLayersSection(for: segment)
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

    private func rowBackground(for segment: PresenterSegment) -> Color {
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
            ShowSetupPanel()

            Divider()
                .padding(.horizontal)
                .padding(.bottom, 8)

            AudioMonitorView()
                .padding(.horizontal)
                .padding(.bottom, 12)

            Spacer()
        }
        .background(theme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Cue (per-segment) layers

    /// Layers that belong to this cue only — a screen share, a picture insert,
    /// a one-off graphic. They are composited around the cue content and do not
    /// carry over to other cues.
    private func cueLayersSection(for segment: PresenterSegment) -> some View {
        GroupBox("Cue Layers") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Layers shown only in this cue.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)

                HStack {
                    Text("\(segment.layers.count) layer\(segment.layers.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                    Spacer()
                    Menu {
                        Button("Screen Share…") { isPickingCueScreen = true }
                        Button("Image…") { isPickingCueLayerImage = true }
                        Button("Video…") { isPickingCueLayerVideo = true }
                        Button("NDI…") { isPickingCueNDI = true }
                        Button("Syphon…") { isPickingCueSyphon = true }
                        Divider()
                        Button("Color") {
                            selectedCueLayerID = store.addPresenterSegmentLayer(
                                segmentID: segment.id,
                                source: .color(CGColorComponents(r: 0, g: 0, b: 0, a: 0.6)),
                                name: "Color"
                            )
                        }
                    } label: {
                        Label("Add Layer", systemImage: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Add a layer that only appears in this cue")
                }

                if segment.layers.contains(where: { if case .screen = $0.source { return true } else { return false } }),
                   !ScreenRecordingPermission.isGranted {
                    screenPermissionWarning
                }

                if segment.type == .cameraGraphic {
                    cameraLayerRow(segment: segment)
                }

                if segment.layers.isEmpty {
                    Text("No cue layers yet.")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    ForEach(segment.layers) { layer in
                        cueLayerRow(layer, segment: segment)
                    }
                }

                if let layer = segment.layers.first(where: { $0.id == selectedCueLayerID }) {
                    Divider()
                    LayerEditorControls(layer: Binding(
                        get: { store.presenterSegment(id: segment.id)?
                            .layers.first(where: { $0.id == layer.id }) ?? layer },
                        set: { newValue in
                            store.updatePresenterSegmentLayer(segmentID: segment.id, id: layer.id) { current in
                                current = newValue
                            }
                        }
                    ))
                    .padding(.top, 4)
                    .background(theme.background.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var screenPermissionWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("No screen signal yet", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.bold())
                .foregroundStyle(.orange)
            Text("Screen Recording is not active for this build of FreeStage, so screen layers stay black. If FreeStage already looks enabled in System Settings, remove it with the − button, add it back, then relaunch.")
                .font(.caption2)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Grant Permission…") {
                    _ = ScreenRecordingPermission.request()
                }
                Button("Retry Capture") {
                    updateScreenCapture()
                }
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func cueLayerRow(_ layer: Layer, segment: PresenterSegment) -> some View {
        let isSelected = selectedCueLayerID == layer.id
        return HStack(spacing: 6) {
            Image(systemName: sourceIconName(for: layer.source))
                .foregroundStyle(theme.accent)
                .frame(width: 16)
            Text(layer.name)
                .foregroundStyle(theme.text)
                .lineLimit(1)
            Spacer()
            Text(layer.placement == .background ? "BG" : "FG")
                .font(.caption2.bold())
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(theme.secondaryText.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Button {
                store.updatePresenterSegmentLayer(segmentID: segment.id, id: layer.id) { $0.isVisible.toggle() }
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
            }
            .buttonStyle(.borderless)
            .help(layer.isVisible ? "Hide in this cue" : "Show in this cue")
            Button {
                store.deletePresenterSegmentLayer(segmentID: segment.id, id: layer.id)
                if selectedCueLayerID == layer.id { selectedCueLayerID = nil }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove this layer from the cue")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { selectedCueLayerID = layer.id }
        .background(isSelected ? theme.selected.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func cameraLayerRow(segment: PresenterSegment) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "video.fill")
                .foregroundStyle(theme.accent)
                .frame(width: 16)
            Text(segment.cameraAngle.displayName)
                .foregroundStyle(theme.text)
                .lineLimit(1)
            Spacer()
            Picker("Camera placement", selection: Binding(
                get: { segment.cameraLayerPlacement },
                set: { newPlacement in
                    store.updatePresenterSegment(id: segment.id) { $0.cameraLayerPlacement = newPlacement }
                }
            )) {
                Text("BG").tag(Layer.Placement.background)
                Text("FG").tag(Layer.Placement.foreground)
            }
            .pickerStyle(.segmented)
            .frame(width: 90)
            .help("Background puts screen shares on top of the camera. Foreground puts the camera on top.")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(theme.selected.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 5))
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
