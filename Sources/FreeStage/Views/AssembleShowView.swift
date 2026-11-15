//
//  AssembleShowView.swift
//  FreeStage
//
//  Dedicated content-creation workspace for building cue cards/scenes.
//  Layout: cue-card grid + cue editor on the left, visual canvas + playback
//  controls + layer stack in the centre, Photoshop-style tools on the right.
//

import SwiftUI

struct AssembleShowView: View {
    @Environment(ShowStore.self) private var store
    @Environment(ThemeStore.self) private var theme
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.cameraCaptureManager) private var cameraCaptureManager
    @Environment(\.screenCaptureManager) private var screenCaptureManager
    @State private var selectedLayerID: UUID?
    @State private var rightPanelTab: RightPanelTab = .tools
    @State private var isAddingCamera = false
    @State private var isAddingScreen = false
    @State private var isAddingImage = false
    @State private var isAddingVideo = false
    @State private var isAddingNDI = false
    @State private var isAddingSyphon = false

    // MARK: - Panel widths

    private let cueGridHeightFraction: CGFloat = 0.45

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()

            AssembleSplitView(
                leftContent: AnyView(leftColumn),
                centreContent: AnyView(centreColumn),
                rightContent: AnyView(rightColumn)
            )
        }
        .onChange(of: requiredCameraIDs) { _, _ in
            updateCameraCapture()
        }
        .onChange(of: requiredScreenIDs) { _, _ in
            updateScreenCapture()
        }
        .onChange(of: store.activeSegmentID) { _, _ in
            updateCameraCapture()
        }
        .task {
            updateCameraCapture()
            updateScreenCapture()
        }
        .sheet(isPresented: $isAddingCamera) {
            CameraPickerSheet { device in
                addCameraLayer(device: device)
            }
            .frame(minWidth: 360, minHeight: 320)
        }
        .sheet(isPresented: $isAddingScreen) {
            ScreenPickerSheet { display in
                addScreenLayer(display: display)
            }
            .frame(minWidth: 400, minHeight: 360)
        }
        .sheet(isPresented: $isAddingNDI) {
            NDIPickerSheet { source in
                if let id = store.addLayerToActiveCue(source: source, name: source.defaultName) {
                    selectedLayerID = id
                }
            }
            .frame(minWidth: 400, minHeight: 360)
        }
        .sheet(isPresented: $isAddingSyphon) {
            SyphonPickerSheet { source in
                if let id = store.addLayerToActiveCue(source: source, name: source.defaultName) {
                    selectedLayerID = id
                }
            }
            .frame(minWidth: 400, minHeight: 360)
        }
        .fileImporter(
            isPresented: $isAddingImage,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let url = urls.first else { return }
            addMediaLayer(url: url, isImage: true)
        }
        .fileImporter(
            isPresented: $isAddingVideo,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let url = urls.first else { return }
            addMediaLayer(url: url, isImage: false)
        }
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(spacing: 0) {
            cueCardGrid

            Divider()

            cueCardEditor
        }
    }

    private var cueCardGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(store.show.kind == .presenter ? "Rundown" : "Cue List")
                    .font(.headline)
                    .foregroundStyle(theme.text)
                Spacer()
                Button {
                    addCueOrSegment()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding([.top, .horizontal], 12)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80, maximum: 120), spacing: 8)], spacing: 8) {
                    ForEach(cueItems) { item in
                        CueCardCell(item: item, isSelected: isSelected(item: item)) {
                            select(item: item)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .frame(maxHeight: .infinity)
        .background(theme.panelBackground)
    }

    private var cueCardEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CueCard Editor")
                .font(.headline)
                .foregroundStyle(theme.text)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            ScrollView {
                cueEditorContent
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.panelBackground)
    }

    @ViewBuilder
    private var cueEditorContent: some View {
        if let cue = store.activeCue {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Cue Name", text: Binding(
                    get: { cue.name },
                    set: { newValue in
                        if let index = store.show.cues.firstIndex(where: { $0.id == cue.id }) {
                            store.show.cues[index].name = newValue
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)

                Text("Scene: \(store.show.scene(withID: cue.sceneID)?.name ?? "Untitled")")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)

                HStack {
                    Text("Number")
                    Spacer()
                    TextField("Number", text: Binding(
                        get: { cue.number },
                        set: { newValue in
                            if let index = store.show.cues.firstIndex(where: { $0.id == cue.id }) {
                                store.show.cues[index].number = newValue
                            }
                        }
                    ))
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("Duration")
                    Spacer()
                    TextField("Seconds", value: Binding(
                        get: { cue.duration },
                        set: { newValue in
                            if let index = store.show.cues.firstIndex(where: { $0.id == cue.id }) {
                                store.show.cues[index].duration = newValue
                            }
                        }
                    ), format: .number)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                }
            }
        } else if let segment = store.activeSegment {
            PresenterSegmentEditor(segment: segment)
        } else {
            Text("Select a cue or segment to edit its properties.")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }

    // MARK: - Centre column

    private var centreColumn: some View {
        VStack(spacing: 0) {
            canvasArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            playbackControls
                .frame(height: 80)

            Divider()

            layerStackPanel
                .frame(height: 220)
        }
        .background(theme.background)
    }

    private var canvasArea: some View {
        ZStack {
            theme.background

            if activeSceneForCanvas != nil {
                StageMonitorView(
                    scene: activeSceneForCanvas,
                    title: "Canvas",
                    isLive: false,
                    isEditable: false
                )

                AssembleCanvasOverlay(
                    selectedLayerID: $selectedLayerID,
                    layers: activeLayersBinding
                )
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(theme.secondaryText)
                    Text("Select a cue to start assembling")
                        .foregroundStyle(theme.secondaryText)
                }
            }
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 16) {
            Button {
                store.selectPrevious()
            } label: {
                Image(systemName: "backward.fill")
            }

            Button {
                _ = store.go()
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderedProminent)

            Button {
                store.selectNext()
            } label: {
                Image(systemName: "forward.fill")
            }

            Spacer()

            Text("Trim controls (In / Out) planned for v2")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.horizontal, 16)
        .background(theme.panelBackground)
    }

    private var layerStackPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Layers")
                    .font(.headline)
                    .foregroundStyle(theme.text)
                Spacer()
            }
            .padding(12)

            if store.show.kind == .presenter {
                HStack(spacing: 0) {
                    localLayersColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    globalLayersColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                LayerStackView(
                    layers: activeLayersBinding,
                    selectedLayerID: $selectedLayerID
                )
            }
        }
        .background(theme.panelBackground)
    }

    private var localLayersColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Cue Layers")
                    .font(.subheadline.bold())
                    .foregroundStyle(theme.text)
                Spacer()
                addLayerMenu
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if let segment = store.activeSegment, segment.type == .cameraGraphic {
                cameraLayerRow(segment: segment)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            LayerStackView(
                layers: activeLayersBinding,
                selectedLayerID: $selectedLayerID
            )
        }
    }

    private func cameraLayerRow(segment: PresenterSegment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "video.fill")
                .foregroundStyle(theme.accent)
                .frame(width: 16)

            Text(segment.cameraAngle.displayName)
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

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
            .help("Background puts cue layers on top of the camera. Foreground puts the camera on top.")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(theme.selected.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var globalLayersColumn: some View {
        GlobalLayersPanel()
            .padding(.top, 8)
    }

    private var addLayerMenu: some View {
        Menu {
            Button("Camera…") { isAddingCamera = true }
            Button("Screen…") { isAddingScreen = true }
            Divider()
            Button("Image…") { isAddingImage = true }
            Button("Video…") { isAddingVideo = true }
            Divider()
            Button("Color") { addColorLayer() }
            Button("Text") { addTextLayer() }
            Divider()
            Button("NDI…") { isAddingNDI = true }
            Button("Syphon…") { isAddingSyphon = true }
        } label: {
            Image(systemName: "plus")
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Right column

    private var rightColumn: some View {
        VStack(spacing: 0) {
            rightColumnHeader
                .padding(12)

            rightColumnContent

            Spacer()
        }
        .background(theme.panelBackground)
    }

    @ViewBuilder
    private var rightColumnHeader: some View {
        if store.show.kind == .presenter {
            Picker("Panel", selection: $rightPanelTab) {
                ForEach(RightPanelTab.allCases) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
        } else {
            Text("Tools")
                .font(.headline)
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var rightColumnContent: some View {
        switch rightPanelTab {
        case .tools:
            AssembleToolsSidebar(
                selectedLayerID: $selectedLayerID,
                layers: activeLayersBinding
            ) { addedID in
                selectedLayerID = addedID
            }
            .padding(.horizontal, 12)
        case .setup:
            ShowSetupPanel(showGlobalLayers: false)
        }
    }

    // MARK: - Capture lifecycle

    private var requiredCameraIDs: Set<String> {
        guard store.show.kind == .presenter else { return [] }
        var ids = Set<String>()
        ids.formUnion(cameraIDs(for: store.presenterLiveScene))
        ids.formUnion(cameraIDs(for: store.presenterActiveScene))
        if let primaryID = store.presenterCameraID(for: .primary) {
            ids.insert(primaryID)
        }
        if let secondaryID = store.presenterCameraID(for: .secondary) {
            ids.insert(secondaryID)
        }
        return ids
    }

    private var requiredScreenIDs: Set<CGDirectDisplayID> {
        guard store.show.kind == .presenter else { return [] }
        var ids = Set<CGDirectDisplayID>()
        ids.formUnion(screenIDs(for: store.presenterActiveScene))
        ids.formUnion(screenIDs(for: store.presenterLiveScene))
        if let globalLayers = store.presenterRundown?.globalLayers {
            ids.formUnion(screenIDs(in: globalLayers))
        }
        return ids
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

    private func updateCameraCapture() {
        cameraCaptureManager?.syncCaptures(requiredIDs: requiredCameraIDs)
    }

    private func updateScreenCapture() {
        screenCaptureManager?.syncCaptures(requiredIDs: requiredScreenIDs)
    }

    // MARK: - Helpers

    private var activeSceneForCanvas: Scene? {
        if store.show.kind == .presenter {
            guard let segment = store.activeSegment else { return nil }
            return store.scene(for: segment)
        }
        return store.activeScene
    }

    private var activeLayersBinding: Binding<[Layer]> {
        if store.show.kind == .presenter {
            guard let segment = store.activeSegment else {
                return .constant([])
            }
            return Binding(
                get: { segment.layers },
                set: { newLayers in
                    store.updatePresenterSegment(id: segment.id) { $0.layers = newLayers }
                }
            )
        }

        guard let scene = store.activeScene,
              let sceneIndex = store.show.scenes.firstIndex(where: { $0.id == scene.id }) else {
            return .constant([])
        }
        return Binding(
            get: { store.show.scenes[sceneIndex].layers },
            set: { store.show.scenes[sceneIndex].layers = $0 }
        )
    }

    private func addCueOrSegment() {
        if store.show.kind == .presenter {
            store.addPresenterSegment(after: store.activeSegmentID)
        } else if let scene = store.activeScene {
            store.addCue(for: scene.id)
        } else if let firstScene = store.show.scenes.first {
            store.addCue(for: firstScene.id)
        } else {
            let sceneID = store.createScene(name: "Scene 1")
            store.addCue(for: sceneID)
        }
    }

    // MARK: - Layer creation helpers

    private func addColorLayer() {
        let style = appSettings.defaultShowStyle
        let source = Source.color(style.primaryColor)
        if let id = store.addLayerToActiveCue(source: source, name: "Color") {
            selectedLayerID = id
        }
    }

    private func addTextLayer() {
        let textSource = TextSource(content: "New Text")
        let source = Source.text(textSource)
        if let id = store.addLayerToActiveCue(source: source, name: "Text") {
            selectedLayerID = id
        }
    }

    private func addMediaLayer(url: URL, isImage: Bool) {
        let source: Source = isImage ? .image(url: url) : .media(url: url)
        let name = url.deletingPathExtension().lastPathComponent
        if let id = store.addLayerToActiveCue(source: source, name: name) {
            selectedLayerID = id
        }
    }

    private func addCameraLayer(device: CameraDevice) {
        let source = Source.camera(deviceID: device.uniqueID)
        if let id = store.addLayerToActiveCue(source: source, name: device.name) {
            selectedLayerID = id
        }
        cameraCaptureManager?.startCapture(uniqueID: device.uniqueID)
    }

    private func addScreenLayer(display: ScreenCaptureDisplay) {
        let source = Source.screen(displayID: display.displayID)
        if let id = store.addLayerToActiveCue(source: source, name: "Screen \(display.displayID)") {
            selectedLayerID = id
        }
        if !ScreenRecordingPermission.isGranted {
            _ = ScreenRecordingPermission.request()
        }
        screenCaptureManager?.startCapture(displayID: display.displayID)
    }
}

// MARK: - Cue list item

private struct AssembleCueItem: Identifiable {
    let id: UUID
    let name: String
    let subtitle: String
    let isArmed: Bool
}

extension AssembleShowView {
    private var cueItems: [AssembleCueItem] {
        if store.show.kind == .presenter,
           let rundown = store.presenterRundown {
            return rundown.segments.map { segment in
                AssembleCueItem(
                    id: segment.id,
                    name: segment.name,
                    subtitle: segment.type.displayName,
                    isArmed: true
                )
            }
        }
        return store.show.cues.map { cue in
            AssembleCueItem(
                id: cue.id,
                name: cue.name,
                subtitle: store.show.scene(withID: cue.sceneID)?.name ?? "",
                isArmed: cue.isArmed
            )
        }
    }

    private func isSelected(item: AssembleCueItem) -> Bool {
        if store.show.kind == .presenter {
            return store.activeSegmentID == item.id
        }
        return store.activeCueID == item.id
    }

    private func select(item: AssembleCueItem) {
        if store.show.kind == .presenter {
            store.selectSegment(id: item.id)
        } else {
            store.selectCue(id: item.id)
        }
    }
}

// MARK: - Cue card cell

private struct CueCardCell: View {
    let item: AssembleCueItem
    let isSelected: Bool
    let action: () -> Void
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? theme.selected : theme.accent.opacity(0.6))
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(
                        Text(item.name.prefix(1).uppercased())
                            .font(.title.bold())
                            .foregroundStyle(.white)
                    )

                Text(item.name)
                    .font(.caption.bold())
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Layer stack

struct LayerStackView: View {
    @Binding var layers: [Layer]
    @Binding var selectedLayerID: UUID?
    @Environment(ThemeStore.self) private var theme
    @State private var editingLayerID: UUID?
    @State private var editingName: String = ""

    var body: some View {
        List {
            // Display layers front-to-back: the topmost rendered layer appears
            // at the top of the list. The underlying model still stores layers
            // back-to-front, so we map moves/deletes through the reversed view.
            ForEach(Array(layers.reversed())) { layer in
                layerRow(layer: layer)
                    .padding(.vertical, 4)
                    .background(isSelected(layer: layer) ? theme.selected.opacity(0.2) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if editingLayerID != layer.id {
                            selectedLayerID = layer.id
                        }
                    }
                    .contextMenu {
                        Button("Rename") {
                            startRenaming(layer: layer)
                        }
                        Button("Duplicate") {
                            duplicate(layer: layer)
                        }
                        Button(layer.isLocked ? "Unlock" : "Lock") {
                            toggleLock(layer: layer)
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            delete(layer: layer)
                        }
                    }
            }
            .onMove(perform: move)
            .onDelete(perform: deleteAtOffsets)
        }
    }

    private func layerRow(layer: Layer) -> some View {
        HStack(spacing: 10) {
            Button {
                toggleVisibility(layer: layer)
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(theme.secondaryText)
            }
            .buttonStyle(.borderless)
            .disabled(layer.isLocked)

            if editingLayerID == layer.id {
                TextField("Name", text: $editingName)
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity)
                    .onSubmit {
                        finishRenaming()
                    }
            } else {
                Text(layer.name)
                    .foregroundStyle(layer.isLocked ? theme.secondaryText : theme.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if layer.isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }

            Slider(value: opacityBinding(for: layer), in: 0...1)
                .frame(width: 80)
                .disabled(layer.isLocked)
        }
    }

    private func isSelected(layer: Layer) -> Bool {
        selectedLayerID == layer.id
    }

    private func opacityBinding(for layer: Layer) -> Binding<Double> {
        Binding(
            get: { layer.opacity },
            set: { newValue in
                if let index = layers.firstIndex(where: { $0.id == layer.id }) {
                    layers[index].opacity = newValue
                }
            }
        )
    }

    private func toggleVisibility(layer: Layer) {
        guard !layer.isLocked else { return }
        if let index = layers.firstIndex(where: { $0.id == layer.id }) {
            layers[index].isVisible.toggle()
        }
    }

    private func toggleLock(layer: Layer) {
        if let index = layers.firstIndex(where: { $0.id == layer.id }) {
            layers[index].isLocked.toggle()
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var display = Array(layers.reversed())
        display.move(fromOffsets: source, toOffset: destination)
        layers = display.reversed()
    }

    private func deleteAtOffsets(_ offsets: IndexSet) {
        var display = Array(layers.reversed())
        let idsToDelete = offsets.compactMap { display[$0].id }
        display.remove(atOffsets: offsets)
        layers = display.reversed()
        if selectedLayerID.map(idsToDelete.contains) == true {
            selectedLayerID = nil
        }
    }

    private func delete(layer: Layer) {
        if let index = layers.firstIndex(where: { $0.id == layer.id }) {
            layers.remove(at: index)
        }
        if selectedLayerID == layer.id {
            selectedLayerID = nil
        }
    }

    private func duplicate(layer: Layer) {
        let copy = Layer(
            name: layer.name + " Copy",
            source: layer.source,
            transform: layer.transform,
            filters: layer.filters,
            blendMode: layer.blendMode,
            opacity: layer.opacity,
            isVisible: layer.isVisible,
            isLocked: false,
            cameraSettings: layer.cameraSettings,
            placement: layer.placement
        )
        if let index = layers.firstIndex(where: { $0.id == layer.id }) {
            layers.insert(copy, at: index + 1)
        } else {
            layers.append(copy)
        }
        selectedLayerID = copy.id
    }

    private func startRenaming(layer: Layer) {
        editingLayerID = layer.id
        editingName = layer.name
    }

    private func finishRenaming() {
        guard let editingLayerID else { return }
        if let index = layers.firstIndex(where: { $0.id == editingLayerID }) {
            layers[index].name = editingName.isEmpty ? layers[index].name : editingName
        }
        self.editingLayerID = nil
    }
}

// MARK: - Tools sidebar

struct AssembleToolsSidebar: View {
    @Environment(ShowStore.self) private var store
    @Environment(ThemeStore.self) private var theme
    @Environment(AppSettings.self) private var appSettings
    @Binding var selectedLayerID: UUID?
    @Binding var layers: [Layer]
    @State private var selectedTool: AssembleTool = .select
    @State private var shapeOptions = ShapeToolOptions()
    @State private var isAspectRatioLocked = false
    @State private var lockedAspectRatio: Double = 1.0
    var onLayerAdded: ((UUID) -> Void)?

    /// Index of any selected cue layer, regardless of source type.
    private var selectedLayerIndex: Int? {
        guard let selectedLayerID else { return nil }
        return layers.firstIndex(where: { $0.id == selectedLayerID })
    }

    /// True when the selected layer is a single-stroke drawing shape that can
    /// be edited with the same controls used for tool options.
    private var selectedShapeIndex: Int? {
        guard let layerIndex = selectedLayerIndex,
              case .drawing(let drawing) = layers[layerIndex].source,
              drawing.strokes.first != nil else { return nil }
        return layerIndex
    }

    private var selectedShapeTool: AssembleTool? {
        guard let layerIndex = selectedShapeIndex,
              case .drawing(let drawing) = layers[layerIndex].source,
              let stroke = drawing.strokes.first,
              let tool = AssembleTool(drawingTool: stroke.tool) else { return nil }
        return tool
    }

    private var panelTitle: String {
        if let layerIndex = selectedLayerIndex {
            if let tool = selectedShapeTool {
                return "\(tool.displayName) Properties"
            }
            return layers[layerIndex].name
        }
        return "\(selectedTool.displayName) Options"
    }

    private var effectiveTool: AssembleTool {
        selectedShapeTool ?? selectedTool
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                ForEach(AssembleTool.allCases) { tool in
                    ToolButton(tool: tool, isSelected: effectiveTool == tool) {
                        select(tool: tool)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if selectedLayerIndex != nil || selectedTool.hasOptions {
                Divider()
                    .padding(.vertical, 12)

                toolOptionsPanel
                    .padding(.horizontal, 12)
            }

            Spacer()
        }
    }

    private var toolOptionsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(panelTitle)
                .font(.subheadline.bold())
                .foregroundStyle(theme.text)
                .lineLimit(1)

            if selectedLayerIndex != nil {
                transformOptions
            }

            if selectedShapeTool?.supportsFill == true {
                fillOptions
            }

            if selectedShapeTool != nil {
                strokeOptions
            }

            if selectedShapeTool == .rectangle {
                cornerRadiusOptions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transformOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transform")
                .font(.caption.bold())
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text("X")
                    .lineLimit(1)
                    .frame(width: 16, alignment: .leading)
                Slider(value: positionXBinding, in: 0...1)
                Text("\(Int(positionXBinding.wrappedValue * 100))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Text("Y")
                    .lineLimit(1)
                    .frame(width: 16, alignment: .leading)
                Slider(value: positionYBinding, in: 0...1)
                Text("\(Int(positionYBinding.wrappedValue * 100))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Text("S")
                    .lineLimit(1)
                    .frame(width: 16, alignment: .leading)
                Slider(value: uniformScaleBinding, in: 0.05...3.0)
                Text("\(Int(uniformScaleBinding.wrappedValue * 100))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Text("W")
                    .lineLimit(1)
                    .frame(width: 16, alignment: .leading)
                Slider(value: scaleXBinding, in: 0.05...3.0)
                Text("\(Int(scaleXBinding.wrappedValue * 100))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Text("H")
                    .lineLimit(1)
                    .frame(width: 16, alignment: .leading)
                Slider(value: scaleYBinding, in: 0.05...3.0)
                Text("\(Int(scaleYBinding.wrappedValue * 100))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
                    .lineLimit(1)
            }

            if selectedShapeTool != nil {
                HStack(spacing: 8) {
                    Button {
                        toggleAspectRatioLock()
                    } label: {
                        Image(systemName: isAspectRatioLocked ? "lock.fill" : "lock.open")
                            .foregroundStyle(isAspectRatioLocked ? theme.accent : theme.secondaryText)
                    }
                    .buttonStyle(.borderless)
                    .help(isAspectRatioLocked ? "Unlock aspect ratio" : "Lock aspect ratio")

                    Text(isAspectRatioLocked ? "Locked" : "Unlocked")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 4) {
                        ForEach(AspectRatioPreset.allCases) { preset in
                            Button {
                                applyAspectRatioPreset(preset)
                            } label: {
                                Text(preset.displayName)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .foregroundStyle(theme.text)
                                    .background(theme.secondaryText.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Text("R")
                    .lineLimit(1)
                    .frame(width: 16, alignment: .leading)
                Slider(value: rotationBinding, in: 0...360, step: 1)
                Text("\(Int(rotationBinding.wrappedValue))°")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
                    .lineLimit(1)
            }
        }
    }

    private var fillOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fill")
                .font(.caption.bold())
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)

            Picker("Fill Style", selection: fillStyleBinding) {
                ForEach(ShapeFillStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch fillStyleBinding.wrappedValue {
            case .solid:
                colorRow("Color", color: fillColorBinding)
            case .gradient:
                colorRow("Start", color: gradientStartColorBinding)
                colorRow("End", color: gradientEndColorBinding)
                HStack(spacing: 8) {
                    Text("Angle")
                        .lineLimit(1)
                    Slider(value: gradientAngleBinding, in: 0...360, step: 1)
                    Text("\(Int(gradientAngleBinding.wrappedValue))°")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                        .lineLimit(1)
                }
            case .none:
                EmptyView()
            }
        }
    }

    private var strokeOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(effectiveTool == .line || effectiveTool == .arrow ? "Line" : "Border")
                .font(.caption.bold())
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)

            Toggle("Enabled", isOn: strokeEnabledBinding)
                .foregroundStyle(theme.text)
                .disabled(!effectiveTool.canDisableStroke)

            if strokeEnabledBinding.wrappedValue {
                Picker("Stroke Style", selection: strokeStyleBinding) {
                    ForEach(ShapeFillStyle.allCases.filter { $0 != .none }) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch strokeStyleBinding.wrappedValue {
                case .solid:
                    colorRow("Color", color: strokeColorBinding)
                case .gradient:
                    colorRow("Start", color: strokeGradientStartColorBinding)
                    colorRow("End", color: strokeGradientEndColorBinding)
                    HStack(spacing: 8) {
                        Text("Angle")
                            .lineLimit(1)
                        Slider(value: strokeGradientAngleBinding, in: 0...360, step: 1)
                        Text("\(Int(strokeGradientAngleBinding.wrappedValue))°")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                            .lineLimit(1)
                    }
                case .none:
                    EmptyView()
                }

                HStack(spacing: 8) {
                    Text("Width")
                        .lineLimit(1)
                    Slider(value: strokeWidthBinding, in: 1...32, step: 1)
                    Text("\(Int(strokeWidthBinding.wrappedValue))")
                        .monospacedDigit()
                        .frame(width: 24, alignment: .trailing)
                        .lineLimit(1)
                }
            }
        }
    }

    private var cornerRadiusOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Corners")
                .font(.caption.bold())
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text("Radius")
                    .lineLimit(1)
                Slider(value: cornerRadiusBinding, in: 0...0.25, step: 0.01)
                Text("\(Int(cornerRadiusBinding.wrappedValue * 100))%")
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
                    .lineLimit(1)
            }
        }
    }

    private func colorRow(_ label: String, color: Binding<CGColorComponents>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(theme.text)
                .lineLimit(1)
            Spacer()
            ColorPicker("", selection: Binding(
                get: {
                    Color(rgb: RGBColor(r: color.wrappedValue.r, g: color.wrappedValue.g, b: color.wrappedValue.b))
                },
                set: { newValue in
                    let rgb = RGBColor(color: newValue)
                    color.wrappedValue = CGColorComponents(r: rgb.r, g: rgb.g, b: rgb.b, a: 1.0)
                }
            ))
            .labelsHidden()
            .frame(width: 44, height: 28)
        }
    }

    // MARK: - Bindings

    private var fillStyleBinding: Binding<ShapeFillStyle> {
        makeBinding(
            get: { $0.fillStyle },
            set: { $0.fillStyle = $1 }
        )
    }

    private var fillColorBinding: Binding<CGColorComponents> {
        makeBinding(
            get: { $0.fillColor },
            set: { $0.fillColor = $1 }
        )
    }

    private var gradientStartColorBinding: Binding<CGColorComponents> {
        makeBinding(
            get: { $0.gradientStartColor },
            set: { $0.gradientStartColor = $1 }
        )
    }

    private var gradientEndColorBinding: Binding<CGColorComponents> {
        makeBinding(
            get: { $0.gradientEndColor },
            set: { $0.gradientEndColor = $1 }
        )
    }

    private var gradientAngleBinding: Binding<Double> {
        makeBinding(
            get: { $0.gradientAngle },
            set: { $0.gradientAngle = $1 }
        )
    }

    private var strokeEnabledBinding: Binding<Bool> {
        makeBinding(
            get: { $0.strokeEnabled },
            set: { $0.strokeEnabled = $1 }
        )
    }

    private var strokeStyleBinding: Binding<ShapeFillStyle> {
        makeBinding(
            get: { $0.strokeStyle },
            set: { $0.strokeStyle = $1 }
        )
    }

    private var strokeColorBinding: Binding<CGColorComponents> {
        makeBinding(
            get: { $0.strokeColor },
            set: { $0.strokeColor = $1 }
        )
    }

    private var strokeGradientStartColorBinding: Binding<CGColorComponents> {
        makeBinding(
            get: { $0.strokeGradientStartColor },
            set: { $0.strokeGradientStartColor = $1 }
        )
    }

    private var strokeGradientEndColorBinding: Binding<CGColorComponents> {
        makeBinding(
            get: { $0.strokeGradientEndColor },
            set: { $0.strokeGradientEndColor = $1 }
        )
    }

    private var strokeGradientAngleBinding: Binding<Double> {
        makeBinding(
            get: { $0.strokeGradientAngle },
            set: { $0.strokeGradientAngle = $1 }
        )
    }

    private var strokeWidthBinding: Binding<Double> {
        makeBinding(
            get: { $0.strokeWidth },
            set: { $0.strokeWidth = $1 }
        )
    }

    private var cornerRadiusBinding: Binding<Double> {
        makeBinding(
            get: { $0.cornerRadius },
            set: { $0.cornerRadius = $1 }
        )
    }

    private var positionXBinding: Binding<Double> {
        makeTransformBinding(
            get: { $0.x },
            set: { $0.x = $1 }
        )
    }

    private var positionYBinding: Binding<Double> {
        makeTransformBinding(
            get: { $0.y },
            set: { $0.y = $1 }
        )
    }

    private var scaleXBinding: Binding<Double> {
        Binding(
            get: {
                guard let layerIndex = selectedLayerIndex else { return 1.0 }
                return layers[layerIndex].transform.scaleX
            },
            set: { newValue in
                guard let layerIndex = selectedLayerIndex else { return }
                var transform = layers[layerIndex].transform
                transform.scaleX = newValue
                if isAspectRatioLocked, selectedShapeTool != nil, transform.scaleY > 0 {
                    transform.scaleY = newValue / lockedAspectRatio
                }
                layers[layerIndex].transform = transform
            }
        )
    }

    private var scaleYBinding: Binding<Double> {
        Binding(
            get: {
                guard let layerIndex = selectedLayerIndex else { return 1.0 }
                return layers[layerIndex].transform.scaleY
            },
            set: { newValue in
                guard let layerIndex = selectedLayerIndex else { return }
                var transform = layers[layerIndex].transform
                transform.scaleY = newValue
                if isAspectRatioLocked, selectedShapeTool != nil, transform.scaleY > 0 {
                    transform.scaleX = newValue * lockedAspectRatio
                }
                layers[layerIndex].transform = transform
            }
        )
    }

    private var rotationBinding: Binding<Double> {
        makeTransformBinding(
            get: { $0.rotation },
            set: { $0.rotation = $1 }
        )
    }

    private var uniformScaleBinding: Binding<Double> {
        Binding(
            get: {
                guard let layerIndex = selectedLayerIndex else { return 1.0 }
                let transform = layers[layerIndex].transform
                return (transform.scaleX + transform.scaleY) / 2
            },
            set: { newValue in
                guard let layerIndex = selectedLayerIndex else { return }
                var transform = layers[layerIndex].transform
                let currentScale = (transform.scaleX + transform.scaleY) / 2
                guard currentScale > 0 else { return }
                let ratio = newValue / currentScale
                transform.scaleX *= ratio
                transform.scaleY *= ratio
                layers[layerIndex].transform = transform
            }
        )
    }

    private func makeTransformBinding<Value>(
        get: @escaping (ItemTransform) -> Value,
        set: @escaping (inout ItemTransform, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: {
                guard let layerIndex = selectedLayerIndex else { return get(.identity) }
                return get(layers[layerIndex].transform)
            },
            set: { newValue in
                guard let layerIndex = selectedLayerIndex else { return }
                var transform = layers[layerIndex].transform
                set(&transform, newValue)
                layers[layerIndex].transform = transform
            }
        )
    }

    private func makeBinding<Value>(
        get: @escaping (ShapeToolOptions) -> Value,
        set: @escaping (inout ShapeToolOptions, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: {
                if let options = selectedShapeOptions {
                    return get(options)
                }
                return get(shapeOptions)
            },
            set: { newValue in
                if let layerIndex = selectedShapeIndex {
                    var options = selectedShapeOptions ?? ShapeToolOptions()
                    set(&options, newValue)
                    updateShapeStroke(at: layerIndex, with: options)
                } else {
                    set(&shapeOptions, newValue)
                }
            }
        )
    }

    private var selectedShapeOptions: ShapeToolOptions? {
        guard let layerIndex = selectedShapeIndex,
              case .drawing(let drawing) = layers[layerIndex].source,
              let stroke = drawing.strokes.first else { return nil }
        return ShapeToolOptions(from: stroke)
    }

    private func updateShapeStroke(at layerIndex: Int, with options: ShapeToolOptions) {
        guard case .drawing(var drawing) = layers[layerIndex].source,
              drawing.strokes.indices.contains(0) else { return }
        let tool = drawing.strokes[0].tool
        drawing.strokes[0] = options.stroke(tool: tool)
        layers[layerIndex].source = .drawing(drawing)
    }

    private func toggleAspectRatioLock() {
        isAspectRatioLocked.toggle()
        if isAspectRatioLocked, let layerIndex = selectedShapeIndex {
            let transform = layers[layerIndex].transform
            lockedAspectRatio = transform.scaleY > 0 ? transform.scaleX / transform.scaleY : 1.0
        }
    }

    private func applyAspectRatioPreset(_ preset: AspectRatioPreset) {
        guard let layerIndex = selectedShapeIndex else { return }
        let desiredRatio = preset.ratio
        let internalRatio = aspectRatioOfSelectedLayer(at: layerIndex)
        guard internalRatio > 0 else { return }

        // finalRatio = internalRatio * (scaleX / scaleY)
        // desired scale ratio = desiredRatio / internalRatio
        let scaleRatio = desiredRatio / internalRatio
        let currentTransform = layers[layerIndex].transform
        let currentArea = max(currentTransform.scaleX * currentTransform.scaleY, 0.0001)
        let newScaleY = sqrt(currentArea / scaleRatio)
        let newScaleX = newScaleY * scaleRatio

        var transform = currentTransform
        transform.scaleX = newScaleX
        transform.scaleY = newScaleY
        layers[layerIndex].transform = transform

        if isAspectRatioLocked {
            lockedAspectRatio = scaleRatio
        }
    }

    private func aspectRatioOfSelectedLayer(at layerIndex: Int) -> Double {
        guard case .drawing(let drawing) = layers[layerIndex].source,
              let stroke = drawing.strokes.first,
              stroke.points.count >= 2 else { return 1.0 }

        let p1 = stroke.points[0]
        let p2 = stroke.points[1]
        let canvas = drawing.canvasSize
        let width = abs(p2.x - p1.x) * canvas.width
        let height = abs(p2.y - p1.y) * canvas.height
        guard height > 0 else { return 1.0 }
        return width / height
    }

    // MARK: - Actions

    private func select(tool: AssembleTool) {
        selectedTool = tool

        switch tool {
        case .select:
            break
        case .rectangle:
            addShapeLayer(tool: .rectangle, name: "Rectangle")
        case .ellipse:
            addShapeLayer(tool: .ellipse, name: "Ellipse")
        case .line:
            addShapeLayer(tool: .line, name: "Line")
        case .arrow:
            addShapeLayer(tool: .arrow, name: "Arrow")
        case .text:
            addTextLayer()
        }
    }

    private func addShapeLayer(tool: DrawingTool, name: String) {
        let stroke = shapeOptions.stroke(tool: tool)
        let source = Source.drawing(DrawingSource(
            strokes: [stroke],
            tool: tool,
            color: shapeOptions.strokeColor,
            brushWidth: shapeOptions.strokeEnabled ? shapeOptions.strokeWidth : 4
        ))
        let transform = ItemTransform(
            x: 0.5, y: 0.5,
            scaleX: 1.0, scaleY: 1.0,
            rotation: 0,
            crop: .zero
        )
        if let id = store.addLayerToActiveCue(source: source, name: name, transform: transform) {
            onLayerAdded?(id)
        }
    }

    private func addTextLayer() {
        let textSource = TextSource(content: "New Text")
        let source = Source.text(textSource)
        if let id = store.addLayerToActiveCue(source: source, name: "Text") {
            onLayerAdded?(id)
        }
    }
}

/// Common aspect-ratio presets for the transform panel.
enum AspectRatioPreset: String, CaseIterable, Identifiable {
    case square
    case fourThree
    case sixteenNine
    case nineSixteen
    case twentyOneNine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .square: return "1:1"
        case .fourThree: return "4:3"
        case .sixteenNine: return "16:9"
        case .nineSixteen: return "9:16"
        case .twentyOneNine: return "21:9"
        }
    }

    var ratio: Double {
        switch self {
        case .square: return 1.0
        case .fourThree: return 4.0 / 3.0
        case .sixteenNine: return 16.0 / 9.0
        case .nineSixteen: return 9.0 / 16.0
        case .twentyOneNine: return 21.0 / 9.0
        }
    }
}

/// Tool-level options for shape tools in the Assemble workspace.
struct ShapeToolOptions {
    var fillStyle: ShapeFillStyle = .solid
    var fillColor: CGColorComponents = CGColorComponents(r: 1, g: 0, b: 0, a: 1)
    var gradientStartColor: CGColorComponents = CGColorComponents(r: 1, g: 1, b: 1, a: 1)
    var gradientEndColor: CGColorComponents = CGColorComponents(r: 0, g: 0, b: 0, a: 1)
    var gradientAngle: Double = 0
    var strokeEnabled: Bool = true
    var strokeStyle: ShapeFillStyle = .solid
    var strokeColor: CGColorComponents = CGColorComponents(r: 1, g: 1, b: 1, a: 1)
    var strokeGradientStartColor: CGColorComponents = CGColorComponents(r: 1, g: 1, b: 1, a: 1)
    var strokeGradientEndColor: CGColorComponents = CGColorComponents(r: 0, g: 0, b: 0, a: 1)
    var strokeGradientAngle: Double = 0
    var strokeWidth: Double = 4
    var cornerRadius: Double = 0

    init() {}

    init(from stroke: DrawingStroke) {
        self.fillStyle = stroke.fillStyle
        self.fillColor = stroke.fillColor
        self.gradientStartColor = stroke.gradientStartColor
        self.gradientEndColor = stroke.gradientEndColor
        self.gradientAngle = stroke.gradientAngle
        self.strokeEnabled = stroke.strokeStyle != .none
        self.strokeStyle = stroke.strokeStyle == .none ? .solid : stroke.strokeStyle
        self.strokeColor = stroke.color
        self.strokeGradientStartColor = stroke.strokeGradientStartColor
        self.strokeGradientEndColor = stroke.strokeGradientEndColor
        self.strokeGradientAngle = stroke.strokeGradientAngle
        self.strokeWidth = stroke.width
        self.cornerRadius = stroke.cornerRadius
    }

    func stroke(tool: DrawingTool) -> DrawingStroke {
        DrawingStroke(
            points: defaultShapePoints(for: tool),
            color: strokeEnabled ? strokeColor : fillColor,
            width: strokeEnabled ? strokeWidth : 0,
            tool: tool,
            fillStyle: fillStyle,
            fillColor: fillColor,
            gradientStartColor: gradientStartColor,
            gradientEndColor: gradientEndColor,
            gradientAngle: gradientAngle,
            strokeStyle: strokeEnabled ? strokeStyle : .none,
            strokeGradientStartColor: strokeGradientStartColor,
            strokeGradientEndColor: strokeGradientEndColor,
            strokeGradientAngle: strokeGradientAngle,
            cornerRadius: cornerRadius
        )
    }

    private func defaultShapePoints(for tool: DrawingTool) -> [DrawingPoint] {
        switch tool {
        case .rectangle, .ellipse:
            return [
                DrawingPoint(x: 0.35, y: 0.40),
                DrawingPoint(x: 0.65, y: 0.60)
            ]
        case .line, .arrow:
            return [
                DrawingPoint(x: 0.30, y: 0.50),
                DrawingPoint(x: 0.70, y: 0.50)
            ]
        default:
            return []
        }
    }
}

enum AssembleTool: String, CaseIterable, Identifiable {
    case select
    case rectangle
    case ellipse
    case line
    case arrow
    case text

    init?(drawingTool: DrawingTool) {
        switch drawingTool {
        case .rectangle: self = .rectangle
        case .ellipse: self = .ellipse
        case .line: self = .line
        case .arrow: self = .arrow
        default: return nil
        }
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .select: return "Select"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .text: return "Text"
        }
    }

    var systemImage: String {
        switch self {
        case .select: return "arrow.up.left.and.arrow.down.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
        case .line: return "minus"
        case .arrow: return "arrow.right"
        case .text: return "textformat"
        }
    }

    var hasOptions: Bool {
        switch self {
        case .select, .text: return false
        case .rectangle, .ellipse, .line, .arrow: return true
        }
    }

    var supportsFill: Bool {
        switch self {
        case .rectangle, .ellipse: return true
        case .select, .line, .arrow, .text: return false
        }
    }

    var canDisableStroke: Bool {
        switch self {
        case .rectangle, .ellipse: return true
        case .select, .line, .arrow, .text: return false
        }
    }
}

private enum RightPanelTab: String, CaseIterable, Identifiable {
    case tools
    case setup

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tools: return "Tools"
        case .setup: return "Setup"
        }
    }
}

private struct ToolButton: View {
    let tool: AssembleTool
    let isSelected: Bool
    let action: () -> Void
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tool.systemImage)
                    .frame(width: 20)
                Text(tool.displayName)
                Spacer()
            }
            .padding(8)
            .background(isSelected ? theme.selected.opacity(0.3) : Color.clear)
            .foregroundStyle(isSelected ? theme.selected : theme.text)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Canvas overlay

/// On-canvas selection, move, and resize for the Assemble workspace.
/// Operates on the local layer binding so it works for both theatre scenes
/// and presenter segments without relying on store.selectedLayer semantics.
private struct AssembleCanvasOverlay: View {
    @Binding var selectedLayerID: UUID?
    @Binding var layers: [Layer]
    @State private var lastMoveTranslation: CGSize = .zero
    @State private var lastResizeTranslation: CGSize = .zero

    private var selectedLayer: Layer? {
        guard let selectedLayerID else { return nil }
        return layers.first { $0.id == selectedLayerID }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent hit areas so clicking any layer on the canvas
                // selects it. Rendered first so the selected-layer controls
                // sit on top and take precedence for drag/resize.
                ForEach(layers) { layer in
                    let size = geometry.size
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .frame(
                            width: max(0, layer.transform.scaleX * size.width),
                            height: max(0, layer.transform.scaleY * size.height)
                        )
                        .position(
                            x: layer.transform.x * size.width,
                            y: layer.transform.y * size.height
                        )
                        .onTapGesture {
                            selectedLayerID = layer.id
                        }
                }

                if let layer = selectedLayer {
                    let frame = frame(for: layer, in: geometry.size)
                    boundingBox(frame: frame, layer: layer, size: geometry.size)
                    resizeHandle(frame: frame, layer: layer, size: geometry.size)
                }
            }
        }
    }

    private func frame(for layer: Layer, in size: CGSize) -> CGRect {
        let width = size.width
        let height = size.height
        let origin = CGPoint(
            x: (layer.transform.x - layer.transform.scaleX / 2) * width,
            y: (layer.transform.y - layer.transform.scaleY / 2) * height
        )
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: layer.transform.scaleX * width,
            height: layer.transform.scaleY * height
        )
    }

    private func boundingBox(frame: CGRect, layer: Layer, size: CGSize) -> some View {
        Rectangle()
            .strokeBorder(Color.yellow, lineWidth: 2)
            .frame(width: max(0, frame.width), height: max(0, frame.height))
            .position(x: frame.midX, y: frame.midY)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .local)
                    .onChanged { value in
                        let delta = CGSize(
                            width: value.translation.width - lastMoveTranslation.width,
                            height: value.translation.height - lastMoveTranslation.height
                        )
                        move(layer: layer, by: delta, in: size)
                        lastMoveTranslation = value.translation
                    }
                    .onEnded { _ in
                        lastMoveTranslation = .zero
                    }
            )
            .onTapGesture(count: 2) {
                update(layer: layer, transform: .identity)
            }
    }

    private func move(layer: Layer, by translation: CGSize, in size: CGSize) {
        let dx = Double(translation.width / size.width)
        let dy = Double(translation.height / size.height)
        var transform = layer.transform
        transform.x = (layer.transform.x + dx).clamped(to: 0...1)
        transform.y = (layer.transform.y + dy).clamped(to: 0...1)
        update(layer: layer, transform: transform)
    }

    private func resizeHandle(frame: CGRect, layer: Layer, size: CGSize) -> some View {
        Circle()
            .fill(Color.yellow)
            .frame(width: 14, height: 14)
            .position(x: frame.maxX, y: frame.maxY)
            .gesture(
                DragGesture(coordinateSpace: .local)
                    .onChanged { value in
                        let delta = CGSize(
                            width: value.translation.width - lastResizeTranslation.width,
                            height: value.translation.height - lastResizeTranslation.height
                        )
                        resize(layer: layer, from: frame, by: delta, in: size)
                        lastResizeTranslation = value.translation
                    }
                    .onEnded { _ in
                        lastResizeTranslation = .zero
                    }
            )
    }

    private func resize(layer: Layer, from frame: CGRect, by translation: CGSize, in size: CGSize) {
        let newMaxX = frame.maxX + translation.width
        let newMaxY = frame.maxY + translation.height
        let newWidth = max(20, newMaxX - frame.minX)
        let newHeight = max(20, newMaxY - frame.minY)

        let scaleX = Double(newWidth / size.width)
        let scaleY = Double(newHeight / size.height)

        let newCenterX = frame.minX / size.width + scaleX / 2
        let newCenterY = frame.minY / size.height + scaleY / 2

        var transform = layer.transform
        transform.scaleX = scaleX.clamped(to: 0.01...2.0)
        transform.scaleY = scaleY.clamped(to: 0.01...2.0)
        transform.x = newCenterX.clamped(to: 0...1)
        transform.y = newCenterY.clamped(to: 0...1)
        update(layer: layer, transform: transform)
    }

    private func update(layer: Layer, transform: ItemTransform) {
        guard let index = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        layers[index].transform = transform
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    let settings = AppSettings()
    let store = ShowStore(show: .presenterDefault(style: settings.defaultShowStyle))
    store.workspaceMode = .assemble
    return AssembleShowView()
        .environment(store)
        .environment(ThemeStore(settings: settings))
}
