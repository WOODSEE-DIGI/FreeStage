//
//  LayerEditorView.swift
//  FreeStage
//
//  Right-side layer editing panel: scene layers list, transform controls,
//  source-specific editors, filters, and camera controls.
//

import SwiftUI
import UniformTypeIdentifiers

struct LayerEditorView: View {
    @Environment(ShowStore.self) private var store
    @Environment(\.cameraCaptureManager) private var captureManager
    @Environment(\.screenCaptureManager) private var screenCaptureManager
    @State private var isAddingCamera = false
    @State private var isAddingScreen = false
    @State private var isAddingSlideshow = false
    @State private var isAddingImage = false
    @State private var isAddingVideo = false

    var body: some View {
        VStack(spacing: 0) {
            if store.activeCue != nil {
                layerList

                if let layer = store.selectedLayer {
                    ScrollView {
                        VStack(spacing: 0) {
                            layerControls(layer: layer)

                            if store.selectedLayerSlideshow != nil {
                                SlideshowControlsView()
                            }
                            if store.selectedLayerDrawing != nil {
                                DrawingControlsView()
                            }
                            if store.selectedLayerText != nil {
                                TextControlsView()
                            }
                            if store.selectedLayerBorder != nil {
                                BorderControlsView()
                            }
                            if store.selectedLayerLowerThird != nil {
                                LowerThirdControlsView()
                            }
                            if store.selectedLayerChapterMarker != nil {
                                ChapterMarkerControlsView()
                            }
                            if store.selectedLayerNextSection != nil {
                                NextSectionControlsView()
                            }
                            if store.selectedLayerSocialBug != nil {
                                SocialBugControlsView()
                            }
                            if store.selectedLayerLogoBug != nil {
                                LogoBugControlsView()
                            }
                            if store.selectedLayerCountdownTimer != nil {
                                CountdownTimerControlsView()
                            }
                            if store.selectedLayerImageLogoBug != nil {
                                ImageLogoBugControlsView()
                            }
                            if store.selectedLayerTicker != nil {
                                TickerControlsView()
                            }
                            if store.selectedLayerPlaylist != nil {
                                PlaylistControlsView()
                            }
                            if isFacePuppetSource(store.selectedLayer?.source) {
                                FacePuppetControlsView()
                            }
                            if store.selectedLayerImage != nil {
                                ImageControlsView()
                            }
                            if store.selectedLayerMedia != nil {
                                VideoControlsView()
                            }

                            FilterEditorView()
                            CameraControlsView()
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.up")
                            .foregroundStyle(.secondary)
                        Text("Select a layer above to edit its source, position, and filters such as Chroma Key.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Text("No cue selected")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $isAddingCamera) {
            CameraPickerSheet { device in
                addLayer(source: .camera(deviceID: device.uniqueID), name: device.name)
                captureManager?.startCapture(uniqueID: device.uniqueID)
            }
        }
        .sheet(isPresented: $isAddingScreen) {
            if let screenCaptureManager {
                ScreenPickerSheet { display in
                    addLayer(source: .screen(displayID: display.displayID), name: "Screen \(display.displayID)")
                    screenCaptureManager.startCapture(displayID: display.displayID)
                }
            }
        }
        .sheet(isPresented: $isAddingSlideshow) {
            SlideshowPickerSheet { slideshow in
                addLayer(source: .slideshow(slideshow), name: "Slideshow")
            }
        }
        .fileImporter(
            isPresented: $isAddingImage,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                addLayer(source: .image(url: url), name: url.deletingPathExtension().lastPathComponent)
            case .failure:
                break
            }
        }
        .fileImporter(
            isPresented: $isAddingVideo,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                addLayer(source: .media(url: url), name: url.deletingPathExtension().lastPathComponent)
            case .failure:
                break
            }
        }
    }

    private var layerList: some View {
        GroupBox("Layers") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Layers in this scene. Select one to edit it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    addLayerMenu
                }

                List(selection: Binding(
                    get: { store.selectedLayerID },
                    set: { store.selectLayer(id: $0) }
                )) {
                    if !store.show.globalLayers.isEmpty {
                        Section("Show Layers") {
                            ForEach(store.show.globalLayers) { layer in
                                layerRow(layer: layer, isGlobal: true)
                            }
                            .onMove(perform: store.moveGlobalLayer)
                        }
                    }

                    if let scene = store.activeScene {
                        Section("Cue Layers") {
                            ForEach(scene.layers) { layer in
                                layerRow(layer: layer, isGlobal: false)
                            }
                            .onMove(perform: store.moveLayerInActiveScene)
                        }
                    }
                }
                .frame(minHeight: 100, maxHeight: 160)
                .environment(\.defaultMinListRowHeight, 26)
            }
        }
        .padding([.horizontal, .top])
    }

    private var addLayerMenu: some View {
        Menu {
            Button("Camera…") { isAddingCamera = true }
            Button("Screen…") { isAddingScreen = true }
            Button("Face Puppet…") { beginAddingFacePuppet() }
            Button("Face Puppet Mesh…") { beginAddingFacePuppetMesh() }
            Button("Image…") { isAddingImage = true }
            Button("Video…") { isAddingVideo = true }
            Button("Color") { addLayer(source: .color(.green), name: "Color") }
            Button("Text") { addLayer(source: .text(TextSource()), name: "Text") }
            Button("Slideshow…") { isAddingSlideshow = true }
            Button("Draw") { addLayer(source: .drawing(DrawingSource()), name: "Drawing") }
            Divider()
            Button("Border") { addLayer(source: .border(BorderSource()), name: "Border") }
            Button("Lower Third") { addLayer(source: .lowerThird(LowerThirdSource()), name: "Lower Third") }
            Button("Chapter Marker") { addLayer(source: .chapterMarker(ChapterMarkerSource()), name: "Chapter Marker") }
            Button("Next Section") { addLayer(source: .nextSection(NextSectionSource()), name: "Next Section") }
            Button("Social Bug") { addLayer(source: .socialBug(SocialBugSource()), name: "Social Bug") }
            Button("Logo Bug") { addLayer(source: .logoBug(LogoBugSource()), name: "Logo Bug") }
            Button("Countdown") { addLayer(source: .countdownTimer(CountdownTimerSource()), name: "Countdown") }
            Button("Image Logo Bug") { addLayer(source: .imageLogoBug(ImageLogoBugSource()), name: "Image Logo Bug") }
            Button("Ticker") { addLayer(source: .ticker(TickerSource()), name: "Ticker") }
            Button("Playlist") { addLayer(source: .playlist(PlaylistSource()), name: "Playlist") }
        } label: {
            Label("Add Layer", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .disabled(store.activeScene == nil)
    }

    private func addLayer(source: Source, name: String) {
        guard let scene = store.activeScene,
              let sceneIndex = store.show.scenes.firstIndex(where: { $0.id == scene.id }) else { return }
        let layer = Layer(name: name, source: source)
        store.show.scenes[sceneIndex].layers.append(layer)
        store.selectLayer(id: layer.id)
    }

    private func beginAddingFacePuppet() {
        let devices = CameraDevice.discover()
        guard let first = devices.first else { return }
        guard let defaultURL = Bundle.main.url(forResource: "default_puppet", withExtension: "png"),
              let localURL = copyPuppetImageToAppSupport(from: defaultURL) else { return }
        captureManager?.startCapture(uniqueID: first.uniqueID)
        addLayer(
            source: .facePuppetAnchored(
                cameraID: first.uniqueID,
                puppetImageURL: localURL,
                anchorMap: nil
            ),
            name: "Face Puppet"
        )
    }

    private func beginAddingFacePuppetMesh() {
        let devices = CameraDevice.discover()
        guard let first = devices.first else { return }
        captureManager?.startCapture(uniqueID: first.uniqueID)
        addLayer(
            source: .facePuppetMesh(cameraID: first.uniqueID, anchorMap: nil),
            name: "Face Puppet Mesh"
        )
    }

    private func copyPuppetImageToAppSupport(from url: URL) -> URL? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return nil
            }
            let directory = support.appendingPathComponent("PuppetImages", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private func isFacePuppetSource(_ source: Source?) -> Bool {
        switch source {
        case .facePuppet, .facePuppetAnchored, .facePuppetMesh:
            return true
        default:
            return false
        }
    }

    private func layerRow(layer: Layer, isGlobal: Bool) -> some View {
        HStack {
            Button {
                store.setLayerVisible(id: layer.id, isVisible: !layer.isVisible)
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(layer.isVisible ? "Hide layer" : "Show layer")

            Text(layer.name)
                .lineLimit(1)
            if isGlobal {
                Image(systemName: "globe")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
        }
        .tag(layer.id)
    }

    private func layerControls(layer: Layer) -> some View {
        GroupBox("Layer") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(layer.name)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        Text(layer.source.defaultName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("Visible", isOn: Binding(
                        get: { layer.isVisible },
                        set: { _ in store.updateSelectedLayer { $0.isVisible.toggle() } }
                    ))
                    .toggleStyle(.checkbox)
                }

                AdjustmentSlider("X", value: layer.transform.x, range: 0...1, defaultValue: 0.5) { newValue in store.updateSelectedLayer { $0.transform.x = newValue } }
                AdjustmentSlider("Y", value: layer.transform.y, range: 0...1, defaultValue: 0.5) { newValue in store.updateSelectedLayer { $0.transform.y = newValue } }
                AdjustmentSlider("Width", value: layer.transform.scaleX, range: 0.01...2.0, defaultValue: 1.0) { newValue in store.updateSelectedLayer { $0.transform.scaleX = newValue } }
                AdjustmentSlider("Height", value: layer.transform.scaleY, range: 0.01...2.0, defaultValue: 1.0) { newValue in store.updateSelectedLayer { $0.transform.scaleY = newValue } }
                AdjustmentSlider("Opacity", value: layer.opacity, range: 0...1, defaultValue: 1.0) { newValue in store.updateSelectedLayer { $0.opacity = newValue } }

                if case .camera = layer.source {
                    cameraPicker(layer: layer)
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Toggle("Chroma Key", isOn: Binding(
                            get: { store.selectedLayerChromaKey?.isEnabled ?? false },
                            set: { store.setSelectedLayerChromaKeyEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        Spacer()
                    }

                    Text("Removes a solid color background from this layer (e.g., a green-screen camera).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                ChromaKeyControlsView()
                    .padding(.top, 4)

                Divider()

                HStack {
                    Button {
                        store.updateSelectedLayer {
                            $0.transform.x = 0.5
                            $0.transform.y = 0.5
                            $0.transform.scaleX = 1.0
                            $0.transform.scaleY = 1.0
                        }
                    } label: {
                        Label("Fit to Canvas", systemImage: "aspectratio")
                    }

                    Button {
                        store.toggleSelectedLayerScope()
                    } label: {
                        Label(
                            store.isSelectedLayerGlobal ? "Make Cue Layer" : "Make Show Layer",
                            systemImage: store.isSelectedLayerGlobal ? "doc" : "globe"
                        )
                    }

                    Spacer()

                    Button {
                        if case .camera(let id) = layer.source {
                            captureManager?.stopCapture(uniqueID: id)
                        }
                        store.deleteSelectedLayer()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .padding()
    }

    private func cameraPicker(layer: Layer) -> some View {
        let devices = CameraDevice.discover()
        return Picker("Camera", selection: Binding(
            get: {
                if case .camera(let id) = layer.source {
                    return id
                }
                return ""
            },
            set: { newID in
                guard case .camera(let oldID) = layer.source else { return }
                guard newID != oldID else { return }
                guard let device = devices.first(where: { $0.uniqueID == newID }) else { return }
                captureManager?.stopCapture(uniqueID: oldID)
                store.setLayerSource(id: layer.id, source: .camera(deviceID: device.uniqueID), name: device.name)
                captureManager?.startCapture(uniqueID: device.uniqueID)
            }
        )) {
            ForEach(devices) { device in
                Text(device.name).tag(device.uniqueID)
            }
        }
        .pickerStyle(.menu)
    }
}
