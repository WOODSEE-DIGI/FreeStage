//
//  InspectorView.swift
//  FreeStage
//
//  Bottom inspector for the selected cue and its layers, QLab-style.
//
//  A *Cue* is the playable item in the cue list. Each cue references a *Scene*,
//  and a Scene is made of *Layers*. The "Cue Settings" tab edits the cue itself
//  (number, name, timing, color tag, notes, camera moves). The "Scene Layers"
//  tab edits the layers inside the cue's scene (sources, position, filters like
//  Chroma Key). To key a camera, select its cue, switch to Scene Layers, and
//  click the camera layer.
//

import SwiftUI

struct InspectorView: View {
    @Environment(ShowStore.self) private var store
    @Environment(\.cameraCaptureManager) private var captureManager
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            if store.activeCue != nil {
                Picker("", selection: $selectedTab) {
                    Text("Cue Settings").tag(0)
                    Text("Scene Layers").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: selectedTab) { _, newValue in
                    if newValue == 1 {
                        autoSelectFirstLayer()
                    }
                }

                if selectedTab == 0 {
                    cueInspector
                } else {
                    layerInspector
                }
            } else {
                Text("No cue selected")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func autoSelectFirstLayer() {
        guard store.selectedLayerID == nil else { return }
        if let firstLayer = store.activeScene?.layers.first ?? store.show.globalLayers.first {
            store.selectLayer(id: firstLayer.id)
        }
    }

    // MARK: - Cue Settings tab

    private var cueInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Settings for the selected cue in the list above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let cue = store.activeCue {
                    HStack {
                        TextField("Number", text: Binding(
                            get: { cue.number },
                            set: { newValue in store.updateActiveCue { $0.number = newValue } }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)

                        TextField("Name", text: Binding(
                            get: { cue.name },
                            set: { newValue in store.updateActiveCue { $0.name = newValue } }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: 12) {
                        Toggle("Armed", isOn: Binding(
                            get: { cue.isArmed },
                            set: { _ in store.toggleArmedForActiveCue() }
                        ))
                        .toggleStyle(.checkbox)

                        Toggle("Flagged", isOn: Binding(
                            get: { cue.isFlagged },
                            set: { _ in store.toggleFlaggedForActiveCue() }
                        ))
                        .toggleStyle(.checkbox)

                        Spacer()
                    }

                    Picker("Cue Color", selection: Binding(
                        get: { cue.color },
                        set: { newValue in store.updateActiveCue { $0.color = newValue } }
                    )) {
                        Text("None").tag(nil as CueColor?)
                        ForEach(CueColor.allCases) { color in
                            HStack {
                                Circle()
                                    .fill(color.swiftUIColor)
                                    .frame(width: 12, height: 12)
                                Text(color.rawValue.capitalized)
                            }
                            .tag(color as CueColor?)
                        }
                    }

                    Picker("Transition", selection: Binding(
                        get: { cue.transition },
                        set: { newValue in store.updateActiveCue { $0.transition = newValue } }
                    )) {
                        ForEach(Transition.allCases) { transition in
                            Text(transition.displayName).tag(transition)
                        }
                    }

                    Picker("Continue", selection: Binding(
                        get: { cue.continueMode },
                        set: { newValue in store.updateActiveCue { $0.continueMode = newValue } }
                    )) {
                        ForEach(ContinueMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    HStack {
                        timeField("Pre Wait", value: cue.preWait) { newValue in store.updateActiveCue { $0.preWait = newValue } }
                        timeField("Duration", value: cue.duration) { newValue in store.updateActiveCue { $0.duration = newValue } }
                        timeField("Post Wait", value: cue.postWait) { newValue in store.updateActiveCue { $0.postWait = newValue } }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: Binding(
                            get: { cue.notes },
                            set: { newValue in store.updateActiveCue { $0.notes = newValue } }
                        ))
                        .frame(minHeight: 60)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                    }

                    cameraMoveSection(for: cue)
                }
            }
            .padding()
        }
    }

    private func cameraMoveSection(for cue: Cue) -> some View {
        GroupBox("Camera Move") {
            VStack(alignment: .leading, spacing: 10) {
                let move = cue.cameraMove ?? CameraMove()

                Toggle("Enable A→B Move", isOn: Binding(
                    get: { move.isEnabled },
                    set: { newValue in
                        store.updateActiveCue { cue in
                            var updated = cue.cameraMove ?? CameraMove()
                            updated.isEnabled = newValue
                            cue.cameraMove = updated
                        }
                    }
                ))
                .toggleStyle(.checkbox)

                if move.isEnabled {
                    Picker("Start Preset", selection: Binding(
                        get: { move.startPresetID },
                        set: { newValue in
                            store.updateActiveCue { cue in
                                var updated = cue.cameraMove ?? CameraMove()
                                updated.startPresetID = newValue
                                cue.cameraMove = updated
                            }
                        }
                    )) {
                        Text("Current Position").tag(nil as UUID?)
                        ForEach(store.show.cameraPresets) { preset in
                            Text(preset.name).tag(preset.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("End Preset", selection: Binding(
                        get: { move.endPresetID },
                        set: { newValue in
                            store.updateActiveCue { cue in
                                var updated = cue.cameraMove ?? CameraMove()
                                updated.endPresetID = newValue
                                cue.cameraMove = updated
                            }
                        }
                    )) {
                        Text("Select preset…").tag(nil as UUID?)
                        ForEach(store.show.cameraPresets) { preset in
                            Text(preset.name).tag(preset.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        Text("Duration")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Duration", value: Binding(
                            get: { move.duration },
                            set: { newValue in
                                store.updateActiveCue { cue in
                                    var updated = cue.cameraMove ?? CameraMove()
                                    updated.duration = newValue
                                    cue.cameraMove = updated
                                }
                            }
                        ), formatter: timeFormatter)
                        .textFieldStyle(.roundedBorder)
                    }
                }

                if store.show.cameraPresets.isEmpty {
                    Text("Save camera presets in the Scene Layers tab to use A→B moves.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func timeField(_ label: String, value: TimeInterval, onChange: @escaping (TimeInterval) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(label, value: Binding(
                get: { value },
                set: { onChange($0) }
            ), formatter: timeFormatter)
            .textFieldStyle(.roundedBorder)
            .frame(width: 80)
        }
    }

    private var timeFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }

    // MARK: - Scene Layers tab

    private var layerInspector: some View {
        VStack(spacing: 0) {
            layerList

            if store.selectedLayer != nil {
                ScrollView {
                    VStack(spacing: 0) {
                        if let layer = store.selectedLayer {
                            layerControls(layer: layer)
                        }
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
        }
    }

    private var layerList: some View {
        GroupBox("Layers") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Layers in this cue's scene. Select one to edit it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
                .frame(minHeight: 80, maxHeight: 120)
                .environment(\.defaultMinListRowHeight, 24)
            }
        }
        .padding([.horizontal, .top])
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
