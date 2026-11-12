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

struct PresenterWorkspaceView: View {
    @Environment(ShowStore.self) private var store
    @Environment(ThemeStore.self) private var theme
    @State private var cameras: [CameraDevice] = []

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()

            VStack(spacing: 12) {
                headerBar
                    .padding(.horizontal)

                HStack(spacing: 16) {
                    segmentRundown
                        .frame(minWidth: 260, idealWidth: 300)

                    VStack(spacing: 12) {
                        liveMonitor
                        previewMonitor
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    placeholderPanel
                        .frame(minWidth: 260, idealWidth: 300)
                }
                .padding(.horizontal)

                transportBar
                    .padding(.horizontal)
                    .padding(.bottom)
            }
            .padding(.vertical, 8)
        }
    }

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

    // MARK: - Rundown

    private var segmentRundown: some View {
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

                if let segment = store.activeSegment {
                    Divider()
                        .padding(.horizontal)
                    segmentEditor(segment)
                        .padding()
                }
            } else {
                ContentUnavailableView("No Segments", systemImage: "list.bullet.rectangle")
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .background(theme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Segment editor

    private func segmentEditor(_ segment: PresenterSegment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selected Segment")
                .font(.subheadline.bold())
                .foregroundStyle(theme.text)

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
                    // Sheet presented via .sheet on the workspace view.
                }
                .disabled(true)
                .help("Clip editor coming in the next build")
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
        let isSelected = segment.id == store.activeSegmentID
        let isLive = segment.id == store.liveSegmentID
        return (isLive ? theme.selected.opacity(0.25) : (isSelected ? theme.selected.opacity(0.12) : Color.clear))
    }

    // MARK: - Monitors

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

    private func cameraPicker(angle: PresenterCameraAngle, label: String) -> some View {
        let selection = Binding<String?>(
            get: { store.presenterCameraID(for: angle) },
            set: { store.setPresenterCameraID($0, for: angle) }
        )

        return Picker(label, selection: selection) {
            Text("Not set")
                .tag(String?.none)
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

            Button {
                store.presenterGo()
            } label: {
                Label("GO", systemImage: "play.fill")
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
}
