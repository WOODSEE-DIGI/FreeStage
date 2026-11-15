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
    @State private var selectedLayerID: UUID?

    // MARK: - Panel widths

    private let leftColumnWidth: CGFloat = 320
    private let rightColumnWidth: CGFloat = 220
    private let cueGridHeightFraction: CGFloat = 0.45

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()

            HStack(spacing: 0) {
                leftColumn
                    .frame(width: leftColumnWidth)

                Divider()

                centreColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                rightColumn
                    .frame(width: rightColumnWidth)
            }
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
                .padding(12)

            ScrollView {
                cueEditorContent
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
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
            VStack(alignment: .leading, spacing: 10) {
                TextField("Segment Name", text: Binding(
                    get: { segment.name },
                    set: { newValue in
                        store.updatePresenterSegment(id: segment.id) { $0.name = newValue }
                    }
                ))
                .textFieldStyle(.roundedBorder)

                Text("Type: \(segment.type.displayName)")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)

                Picker("Camera Angle", selection: Binding(
                    get: { segment.cameraAngle },
                    set: { newValue in
                        store.updatePresenterSegment(id: segment.id) { $0.cameraAngle = newValue }
                    }
                )) {
                    ForEach(PresenterCameraAngle.allCases) { angle in
                        Text(angle.displayName).tag(angle)
                    }
                }
                .pickerStyle(.menu)
            }
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
                Button {
                    // TODO: Add layer menu
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(12)

            LayerStackView(
                layers: activeLayersBinding,
                selectedLayerID: $selectedLayerID
            )
        }
        .background(theme.panelBackground)
    }

    // MARK: - Right column

    private var rightColumn: some View {
        VStack(spacing: 0) {
            Text("Tools")
                .font(.headline)
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)

            AssembleToolsSidebar { addedID in
                selectedLayerID = addedID
            }

            Spacer()
        }
        .background(theme.panelBackground)
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

    var body: some View {
        List {
            ForEach(layers) { layer in
                HStack(spacing: 10) {
                    Button {
                        toggleVisibility(layer: layer)
                    } label: {
                        Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                            .foregroundStyle(theme.secondaryText)
                    }
                    .buttonStyle(.borderless)

                    Text(layer.name)
                        .foregroundStyle(theme.text)

                    Spacer()

                    Slider(value: opacityBinding(for: layer), in: 0...1)
                        .frame(width: 80)
                }
                .padding(.vertical, 4)
                .background(isSelected(layer: layer) ? theme.selected.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedLayerID = layer.id
                }
            }
            .onMove(perform: move)
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
        if let index = layers.firstIndex(where: { $0.id == layer.id }) {
            layers[index].isVisible.toggle()
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        layers.move(fromOffsets: source, toOffset: destination)
    }
}

// MARK: - Tools sidebar

struct AssembleToolsSidebar: View {
    @Environment(ShowStore.self) private var store
    @Environment(ThemeStore.self) private var theme
    @Environment(AppSettings.self) private var appSettings
    @State private var selectedTool: AssembleTool = .select
    var onLayerAdded: ((UUID) -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(AssembleTool.allCases) { tool in
                ToolButton(tool: tool, isSelected: selectedTool == tool) {
                    select(tool: tool)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
    }

    private func select(tool: AssembleTool) {
        selectedTool = tool

        switch tool {
        case .select:
            break
        case .rectangle:
            addRectangleLayer()
        case .text:
            addTextLayer()
        }
    }

    private func addRectangleLayer() {
        let style = appSettings.defaultShowStyle
        let source = Source.color(style.primaryColor)
        let transform = ItemTransform(
            x: 0.5, y: 0.5,
            scaleX: 0.3, scaleY: 0.3,
            rotation: 0,
            crop: .zero
        )
        if let id = store.addLayerToActiveCue(source: source, name: "Rectangle", transform: transform) {
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

enum AssembleTool: String, CaseIterable, Identifiable {
    case select
    case rectangle
    case text

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .select: return "Select"
        case .rectangle: return "Rectangle"
        case .text: return "Text"
        }
    }

    var systemImage: String {
        switch self {
        case .select: return "arrow.up.left.and.arrow.down.right"
        case .rectangle: return "rectangle"
        case .text: return "textformat"
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
