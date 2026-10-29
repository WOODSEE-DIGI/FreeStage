//
//  LayerEditorView.swift
//  FreeStage
//
//  Right-side layer editing panel: scene layers list, transform controls,
//  source-specific editors, filters, and camera controls.
//

import SwiftUI

struct LayerEditorView: View {
    @Environment(ShowStore.self) private var store
    @Environment(\.cameraCaptureManager) private var captureManager
    @Environment(\.screenCaptureManager) private var screenCaptureManager
    @State private var isAddingCamera = false
    @State private var isAddingScreen = false
    @State private var isAddingSlideshow = false

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
                        }
                    }

                    if let scene = store.activeScene {
                        Section("Cue Layers") {
                            ForEach(scene.layers) { layer in
                                layerRow(layer: layer, isGlobal: false)
                            }
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
            Button("Color") { addLayer(source: .color(.green), name: "Color") }
            Button("Text") { addLayer(source: .text(TextSource()), name: "Text") }
            Button("Slideshow…") { isAddingSlideshow = true }
            Button("Draw") { addLayer(source: .drawing(DrawingSource()), name: "Drawing") }
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

    private func layerRow(layer: Layer, isGlobal: Bool) -> some View {
        HStack {
            Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                .foregroundStyle(.secondary)
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
