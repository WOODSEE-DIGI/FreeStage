//
//  ShowSetupPanel.swift
//  FreeStage
//
//  Reusable show-setup panel shared by the Presenter workspace and the Assemble
//  workspace: camera source selection, global background, placeholders, and
//  global layers. This view only mutates the ShowStore; its parent is
//  responsible for keeping camera/screen captures alive.
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct ShowSetupPanel: View {
    @Environment(ShowStore.self) private var store
    @Environment(ThemeStore.self) private var theme
    @State private var cameras: [CameraDevice] = []
    @State private var cameraAccessStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isPickingGlobalBackground = false
    @State private var isPickingGlobalLayerImage = false
    @State private var isPickingGlobalLayerVideo = false
    @State private var selectedGlobalLayerID: UUID?

    var body: some View {
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

            placeholdersSection
                .padding(.horizontal)

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
        .task { checkCameraAccess() }
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

    // MARK: - Cameras

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

            if cameraAccessStatus == .denied || cameraAccessStatus == .restricted {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Camera access is disabled. Enable it in System Settings to use cameras.")
                        .font(.caption)
                        .foregroundStyle(theme.text)
                    Spacer()
                    Button("Open Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.caption)
                }
                .padding(.top, 4)
            }
        }
    }

    private func cameraPicker(angle: PresenterCameraAngle, label: String) -> some View {
        let selectedID = store.presenterCameraID(for: angle)
        let selection = Binding<String?>(
            get: { selectedID },
            set: { newID in
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                if status == .authorized {
                    store.setPresenterCameraID(newID, for: angle)
                } else if status == .notDetermined {
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        Task { @MainActor in
                            self.cameraAccessStatus = AVCaptureDevice.authorizationStatus(for: .video)
                            if granted {
                                store.setPresenterCameraID(newID, for: angle)
                            }
                        }
                    }
                } else {
                    self.cameraAccessStatus = status
                }
            }
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

    // MARK: - Background

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

    // MARK: - Placeholders

    private var placeholdersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            Text("Named reusable source slots. A cue of type Title Card or Camera + Graphic shows the placeholder you pick in its editor — swap the placeholder's source here and every cue using it updates at once.")
                .font(.caption2)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let placeholders = store.presenterRundown?.placeholders, !placeholders.isEmpty {
                List {
                    ForEach(placeholders) { placeholder in
                        PlaceholderRow(placeholder: placeholder)
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
                PlaceholderSourceEditor(placeholder: placeholder)
                    .padding()
                    .background(theme.background.opacity(0.5))
            }
        }
    }

    // MARK: - Global layers

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
                        GlobalLayerRow(
                            layer: layer,
                            isSelected: selectedGlobalLayerID == layer.id
                        ) {
                            selectedGlobalLayerID = layer.id
                        } toggleVisibility: {
                            store.updatePresenterGlobalLayer(id: layer.id) { $0.isVisible.toggle() }
                        }
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
                    LayerEditorControls(layer: Binding(
                        get: { store.presenterRundown?.globalLayers.first(where: { $0.id == layer.id }) ?? layer },
                        set: { newValue in
                            store.updatePresenterGlobalLayer(id: layer.id) { current in
                                current = newValue
                            }
                        }
                    ))
                }
            } else {
                ContentUnavailableView("No Global Layers", systemImage: "square.3.layers.3d")
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }

    // MARK: - Helpers

    private func refreshCameras() {
        cameras = CameraDevice.discover()
    }

    private func checkCameraAccess() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraAccessStatus = status
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    self.cameraAccessStatus = AVCaptureDevice.authorizationStatus(for: .video)
                }
            }
        }
    }
}

// MARK: - Placeholder row

private struct PlaceholderRow: View {
    let placeholder: PresenterPlaceholder
    @Environment(ShowStore.self) private var store
    @Environment(ThemeStore.self) private var theme

    var body: some View {
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
}

// MARK: - Placeholder source editor

private struct PlaceholderSourceEditor: View {
    let placeholder: PresenterPlaceholder
    @Environment(ShowStore.self) private var store
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Name", text: nameBinding)
                .textFieldStyle(.roundedBorder)

            Text("Source")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)

            HStack(spacing: 8) {
                Button("Image…") {
                    pickImage()
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

    private var nameBinding: Binding<String> {
        Binding(
            get: { placeholder.name },
            set: { newName in
                store.updatePresenterPlaceholder(id: placeholder.id) { $0.name = newName }
            }
        )
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            store.updatePresenterPlaceholder(id: placeholder.id) { $0.source = .image(url: url) }
        }
    }
}

// MARK: - Global layer row

private struct GlobalLayerRow: View {
    let layer: Layer
    let isSelected: Bool
    let select: () -> Void
    let toggleVisibility: () -> Void
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        HStack {
            Image(systemName: sourceIconName(for: layer.source))
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
            Button(action: toggleVisibility) {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .background(isSelected ? theme.selected.opacity(0.12) : Color.clear)
    }
}

// MARK: - Layer editor controls

/// Shared transform/placement/opacity controls used by global and cue layers.
struct LayerEditorControls: View {
    @Binding var layer: Layer
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $layer.name)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            Picker("Placement", selection: $layer.placement) {
                Text("Background").tag(Layer.Placement.background)
                Text("Foreground").tag(Layer.Placement.foreground)
            }
            .pickerStyle(.segmented)
            .font(.caption)
            .help("Background renders behind the cue content, foreground on top of it.")

            HStack {
                Text("X")
                    .frame(width: 16)
                Slider(value: $layer.transform.x, in: 0...1)
            }
            HStack {
                Text("Y")
                    .frame(width: 16)
                Slider(value: $layer.transform.y, in: 0...1)
            }
            HStack {
                Text("Size")
                    .frame(width: 28)
                Slider(value: Binding(
                    get: { layer.transform.scaleX },
                    set: { newValue in
                        layer.transform.scaleX = newValue
                        layer.transform.scaleY = newValue
                    }
                ), in: 0.1...3)
            }
            HStack {
                Text("Opacity")
                    .frame(width: 44)
                Slider(value: $layer.opacity, in: 0...1)
            }
        }
    }
}

// MARK: - Source icon helper

func sourceIconName(for source: Source) -> String {
    switch source {
    case .image: return "photo"
    case .media, .mediaClip: return "film"
    case .color: return "paintpalette"
    case .screen: return "display"
    case .camera: return "video"
    case .ndi: return "network"
    case .syphon: return "app.connected.to.app.below.fill"
    case .browser: return "safari"
    case .slideshow: return "rectangle.stack"
    case .text: return "textformat"
    default: return "square.dashed"
    }
}
