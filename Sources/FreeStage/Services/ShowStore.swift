//
//  ShowStore.swift
//  FreeStage
//
//  Observable store for the currently loaded show and playback state.
//

import Foundation
import SwiftUI
import OSLog

@Observable
@MainActor
final class ShowStore: NSObject {
    var show: Show
    /// Package on disk for the current show. `nil` means this show has never
    /// been saved, so Save has to ask for a location before writing.
    var documentURL: URL?
    var activeCueID: UUID?
    var liveCueID: UUID?
    var selectedLayerID: UUID?
    var selectedSceneID: UUID?
    var isPlaying = false

    // MARK: - Presenter mode state

    var activeSegmentID: UUID?
    var liveSegmentID: UUID? {
        didSet { scheduleAutoFollowIfNeeded() }
    }
    var selectedPlaceholderID: UUID?
    private var presenterAutoFollowTimer: Timer?

    // MARK: - Workspace UI state

    var workspaceMode: WorkspaceMode = .edit
    var isEditMode = true
    var mastheadVisible = true
    var sidebarVisible = true
    var inspectorVisible = true
    var panicDuration: TimeInterval = 1.0

    init(show: Show = .default()) {
        self.show = show
        let workspace = show.workspace
        self.activeCueID = workspace.activeCueID ?? show.cues.first?.id
        self.liveCueID = workspace.liveCueID ?? show.cues.first?.id
        self.activeSegmentID = workspace.activeSegmentID ?? show.presenterRundown?.segments.first?.id
        self.liveSegmentID = workspace.liveSegmentID ?? show.presenterRundown?.segments.first?.id
        self.selectedLayerID = workspace.selectedLayerID
        self.selectedSceneID = workspace.selectedSceneID
        self.selectedPlaceholderID = workspace.selectedPlaceholderID
        self.workspaceMode = workspace.workspaceMode
        self.isEditMode = workspace.isEditMode
        self.mastheadVisible = workspace.mastheadVisible
        self.sidebarVisible = workspace.sidebarVisible
        self.inspectorVisible = workspace.inspectorVisible
        self.panicDuration = workspace.panicDuration
    }

    // MARK: - Selected / playhead cue

    var activeCue: Cue? {
        guard let activeCueID else { return nil }
        return show.cues.first { $0.id == activeCueID }
    }

    /// The scene currently being edited. The explicitly selected scene takes
    /// precedence; otherwise it is derived from the active cue.
    var activeScene: Scene? {
        if let selectedSceneID {
            return show.scene(withID: selectedSceneID)
        }
        guard let cue = activeCue else { return nil }
        return show.scene(withID: cue.sceneID)
    }

    // MARK: - Live output

    var liveCue: Cue? {
        guard let liveCueID else { return nil }
        return show.cues.first { $0.id == liveCueID }
    }

    var liveScene: Scene? {
        guard let cue = liveCue else { return nil }
        return show.scene(withID: cue.sceneID)
    }

    func selectCue(id: UUID?) {
        activeCueID = id
        selectedSceneID = nil
    }

    enum GoResult: Sendable {
        case advanced(nextCue: Cue?)
        case atEnd
        case noCue
        case disarmed
    }

    /// Advance the live cue to the active cue, then move the playhead forward.
    /// Returns information about where the show landed.
    @discardableResult
    func go() -> GoResult {
        guard let activeCueID,
              let cue = show.cues.first(where: { $0.id == activeCueID }) else {
            return .noCue
        }
        guard cue.isArmed else { return .disarmed }

        stopCameraMove()
        liveCueID = activeCueID
        selectedLayerID = nil
        selectedSceneID = nil
        startCameraMoveIfNeeded(for: cue)

        guard let index = show.cues.firstIndex(where: { $0.id == activeCueID }),
              index + 1 < show.cues.count else {
            return .atEnd
        }
        self.activeCueID = show.cues[index + 1].id
        return .advanced(nextCue: self.activeCue)
    }

    /// Fire a specific cue by ID, regardless of the current playhead order.
    /// This is used for free-form triggering (e.g., Stream Deck or manual jump).
    func triggerCue(id: UUID) {
        guard let cue = show.cues.first(where: { $0.id == id }) else { return }
        guard cue.isArmed else { return }

        stopCameraMove()
        activeCueID = id
        liveCueID = id
        selectedLayerID = nil
        selectedSceneID = nil
        startCameraMoveIfNeeded(for: cue)
    }

    /// Create a new cue that references the same scene as an existing cue.
    /// This lets the same visual scene be triggered from multiple places.
    @discardableResult
    func duplicateCue(id: UUID) -> UUID? {
        guard let cue = show.cues.first(where: { $0.id == id }) else { return nil }
        let duplicate = Cue(
            name: cue.name + " Copy",
            sceneID: cue.sceneID,
            transition: cue.transition,
            duration: cue.duration,
            preWait: cue.preWait,
            postWait: cue.postWait,
            continueMode: cue.continueMode,
            isArmed: cue.isArmed,
            isFlagged: cue.isFlagged,
            notes: cue.notes,
            targetID: cue.targetID,
            color: cue.color,
            cameraMove: cue.cameraMove
        )
        show.cues.append(duplicate)
        return duplicate.id
    }

    func selectPrevious() {
        guard let activeCueID,
              let index = show.cues.firstIndex(where: { $0.id == activeCueID }),
              index > 0 else { return }
        self.activeCueID = show.cues[index - 1].id
    }

    func selectNext() {
        guard let activeCueID,
              let index = show.cues.firstIndex(where: { $0.id == activeCueID }),
              index + 1 < show.cues.count else { return }
        self.activeCueID = show.cues[index + 1].id
    }

    // MARK: - Playback control

    /// Replace the current show and restore all saved workspace state.
    func load(show: Show, from url: URL? = nil) {
        stopCameraMove()
        self.show = show
        documentURL = url
        let workspace = show.workspace
        activeCueID = workspace.activeCueID ?? show.cues.first?.id
        liveCueID = workspace.liveCueID ?? show.cues.first?.id
        activeSegmentID = workspace.activeSegmentID ?? show.presenterRundown?.segments.first?.id
        liveSegmentID = workspace.liveSegmentID ?? show.presenterRundown?.segments.first?.id
        selectedLayerID = workspace.selectedLayerID
        selectedSceneID = workspace.selectedSceneID
        selectedPlaceholderID = workspace.selectedPlaceholderID
        workspaceMode = workspace.workspaceMode
        isEditMode = workspace.isEditMode
        mastheadVisible = workspace.mastheadVisible
        sidebarVisible = workspace.sidebarVisible
        inspectorVisible = workspace.inspectorVisible
        panicDuration = workspace.panicDuration
        isPlaying = false
    }

    func resetWorkspace() {
        stopCameraMove()
        // A reset means a brand-new, never-saved document: forget the old file
        // so Save asks for a location instead of overwriting the previous show.
        documentURL = nil
        let firstCueID = show.cues.first?.id
        activeCueID = firstCueID
        liveCueID = firstCueID
        let firstSegmentID = show.presenterRundown?.segments.first?.id
        activeSegmentID = firstSegmentID
        liveSegmentID = firstSegmentID
        selectedLayerID = nil
        selectedSceneID = nil
        selectedPlaceholderID = nil
        isPlaying = false
    }

    /// End the show: stop playback and return to the first cue.
    func stopShow() {
        stopCameraMove()
        isPlaying = false
        let firstCueID = show.cues.first?.id
        activeCueID = firstCueID
        selectedLayerID = nil
        selectedSceneID = nil
    }

    /// The show plus the live workspace selection, ready to write to disk.
    /// Manual saves and autosave both persist this so reopening a show returns
    /// to the same cue, scene, and layout state.
    func documentSnapshot() -> Show {
        var snapshot = show
        snapshot.workspace = WorkspaceState(
            activeCueID: activeCueID,
            liveCueID: liveCueID,
            activeSegmentID: activeSegmentID,
            liveSegmentID: liveSegmentID,
            selectedLayerID: selectedLayerID,
            selectedSceneID: selectedSceneID,
            selectedPlaceholderID: selectedPlaceholderID,
            workspaceMode: workspaceMode,
            isEditMode: isEditMode,
            mastheadVisible: mastheadVisible,
            sidebarVisible: sidebarVisible,
            inspectorVisible: inspectorVisible,
            panicDuration: panicDuration
        )
        return snapshot
    }

    func panic() {
        // Fade and stop all live output.
        stopCameraMove()
        isPlaying = false
    }

    func pauseAll() {
        isPlaying = false
    }

    func resumeAll() {
        isPlaying = true
    }

    // MARK: - Cue mutation

    func updateActiveCue(_ mutation: (inout Cue) -> Void) {
        guard let activeCueID,
              let index = show.cues.firstIndex(where: { $0.id == activeCueID }) else { return }
        mutation(&show.cues[index])
    }

    func toggleArmedForActiveCue() {
        updateActiveCue { $0.isArmed.toggle() }
    }

    func toggleFlaggedForActiveCue() {
        updateActiveCue { $0.isFlagged.toggle() }
    }

    func renumberSelectedCues(start: Double, increment: Double, prefix: String, suffix: String) {
        guard let activeCueID,
              let index = show.cues.firstIndex(where: { $0.id == activeCueID }) else { return }
        var number = start
        for i in index..<show.cues.count {
            var used = prefix + String(format: "%g", number) + suffix
            // Simple uniqueness: append decimals if collision within workspace.
            while show.cues.contains(where: { $0.number == used && $0.id != show.cues[i].id }) {
                number += 0.001
                used = prefix + String(format: "%g", number) + suffix
            }
            show.cues[i].number = used
            number += increment
        }
    }

    // MARK: - Scene creation

    /// Create a standalone scene and return its ID. Does not create a cue.
    @discardableResult
    func createScene(name: String, layers: [Layer] = []) -> UUID {
        let scene = Scene(name: name, layers: layers)
        show.scenes.append(scene)
        return scene.id
    }

    /// Delete a scene and any cues that reference it.
    func deleteScene(id: UUID) {
        show.scenes.removeAll { $0.id == id }
        show.cues.removeAll { $0.sceneID == id }
        if liveCue?.sceneID == id { liveCueID = nil }
        if activeCue?.sceneID == id { activeCueID = show.cues.first?.id }
        if selectedLayer?.id != nil && activeScene?.id == id { selectedLayerID = nil }
    }

    /// Rename a scene.
    func renameScene(id: UUID, to name: String) {
        guard let index = show.scenes.firstIndex(where: { $0.id == id }) else { return }
        show.scenes[index].name = name
    }

    // MARK: - Cue creation

    /// Create a cue that references an existing scene.
    @discardableResult
    func addCue(for sceneID: UUID, name: String? = nil, transition: Transition = .cut) -> UUID {
        guard let scene = show.scene(withID: sceneID) else { return sceneID }
        let cue = Cue(name: name ?? scene.name, sceneID: sceneID, transition: transition)
        show.cues.append(cue)
        return cue.id
    }

    /// Quick-create a scene with a single source layer and a cue that points to it.
    /// Applies any saved layer defaults for the source.
    @discardableResult
    func addCue(source: Source, name: String? = nil) -> UUID {
        var layer = Layer(name: name, source: source)
        if let defaults = appSettings?.savedLayerDefaults[source.defaultsKey] {
            defaults.apply(to: &layer)
        }
        let scene = Scene(name: name ?? source.defaultName, layers: [layer])
        let cue = Cue(name: name ?? source.defaultName, sceneID: scene.id)
        show.scenes.append(scene)
        show.cues.append(cue)
        return cue.id
    }

    @discardableResult
    func addGroupCue() -> UUID {
        let scene = Scene(name: "Group")
        let cue = Cue(name: "Group", sceneID: scene.id)
        show.scenes.append(scene)
        show.cues.append(cue)
        return cue.id
    }

    /// Append a camera layer to the active scene.
    func addCameraLayer(device: CameraDevice) {
        guard let scene = activeScene,
              let sceneIndex = show.scenes.firstIndex(where: { $0.id == scene.id }) else { return }

        let source = Source.camera(deviceID: device.uniqueID)
        var layer = Layer(
            name: device.name,
            source: source,
            transform: ItemTransform(x: 0.5, y: 0.5, scaleX: 1.0, scaleY: 1.0, rotation: 0, crop: .zero)
        )
        if let defaults = appSettings?.savedLayerDefaults[source.defaultsKey] {
            defaults.apply(to: &layer)
        }
        show.scenes[sceneIndex].layers.append(layer)
        selectedLayerID = layer.id
    }

    func addLayer(source: Source) {
        guard let scene = activeScene,
              let sceneIndex = show.scenes.firstIndex(where: { $0.id == scene.id }) else { return }
        var layer = Layer(source: source)
        if let defaults = appSettings?.savedLayerDefaults[source.defaultsKey] {
            defaults.apply(to: &layer)
        }
        show.scenes[sceneIndex].layers.append(layer)
        selectedLayerID = layer.id
    }

    /// Add a layer to whichever container owns the active cue: a theatre scene
    /// or a presenter segment. Used by the Assemble workspace so its tools work
    /// for both show kinds without callers needing to branch.
    @discardableResult
    func addLayerToActiveCue(source: Source, name: String? = nil, transform: ItemTransform = .identity) -> UUID? {
        if show.kind == .presenter {
            guard let segmentID = activeSegmentID else { return nil }
            let layer = Layer(name: name, source: source, transform: transform)
            updatePresenterSegment(id: segmentID) { $0.layers.append(layer) }
            selectedLayerID = layer.id
            return layer.id
        }

        guard let scene = activeScene,
              let sceneIndex = show.scenes.firstIndex(where: { $0.id == scene.id }) else { return nil }
        let layer = Layer(name: name, source: source, transform: transform)
        show.scenes[sceneIndex].layers.append(layer)
        selectedLayerID = layer.id
        return layer.id
    }

    // MARK: - Layer selection & mutation

    /// The selected layer, which may live in the active scene or in the global show layers.
    var selectedLayer: Layer? {
        guard let selectedLayerID else { return nil }
        if let scene = activeScene,
           let layer = scene.layers.first(where: { $0.id == selectedLayerID }) {
            return layer
        }
        return show.globalLayers.first { $0.id == selectedLayerID }
    }

    /// Whether the selected layer is a show-level (global) layer.
    var isSelectedLayerGlobal: Bool {
        guard let selectedLayerID else { return false }
        return show.globalLayers.contains { $0.id == selectedLayerID }
    }

    func selectLayer(id: UUID?) {
        selectedLayerID = id
    }

    func updateSelectedLayer(_ transform: ItemTransform) {
        updateSelectedLayer { $0.transform = transform }
    }

    func updateSelectedLayer(_ mutation: (inout Layer) -> Void) {
        guard let selectedLayerID else { return }
        let mutated = mutateLayer(id: selectedLayerID, mutation: mutation)
        if !mutated {
            assertionFailure("Selected layer not found in active scene or global layers")
        }
    }

    @discardableResult
    private func mutateLayer(id: UUID, mutation: (inout Layer) -> Void) -> Bool {
        // Search the active scene first.
        if let scene = activeScene,
           let sceneIndex = show.scenes.firstIndex(where: { $0.id == scene.id }),
           let layerIndex = show.scenes[sceneIndex].layers.firstIndex(where: { $0.id == id }) {
            mutation(&show.scenes[sceneIndex].layers[layerIndex])
            return true
        }
        // Fall back to the global show layers.
        if let index = show.globalLayers.firstIndex(where: { $0.id == id }) {
            mutation(&show.globalLayers[index])
            return true
        }
        return false
    }

    func setLayerSource(id: UUID, source: Source, name: String? = nil) {
        _ = mutateLayer(id: id) { layer in
            layer.source = source
            if let name {
                layer.name = name
            }
        }
    }

    func setLayerVisible(id: UUID, isVisible: Bool) {
        _ = mutateLayer(id: id) { $0.isVisible = isVisible }
    }

    /// Reorder layers within the active scene.
    func moveLayerInActiveScene(from source: IndexSet, to destination: Int) {
        guard let scene = activeScene,
              let sceneIndex = show.scenes.firstIndex(where: { $0.id == scene.id }) else { return }
        show.scenes[sceneIndex].layers.move(fromOffsets: source, toOffset: destination)
    }

    /// Reorder the show-level global layers.
    func moveGlobalLayer(from source: IndexSet, to destination: Int) {
        show.globalLayers.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Filters

    func addFilterToSelectedLayer(_ filter: Filter) {
        updateSelectedLayer { $0.filters.append(filter) }
    }

    func removeFilterFromSelectedLayer(id: String) {
        updateSelectedLayer { $0.filters.removeAll { $0.id == id } }
    }

    func updateColorCorrectionFilter(id: String, mutation: (inout ColorCorrectionFilter) -> Void) {
        updateSelectedLayer { layer in
            guard let index = layer.filters.firstIndex(where: { $0.id == id }),
                  case .colorCorrection(var filter) = layer.filters[index] else { return }
            mutation(&filter)
            layer.filters[index] = .colorCorrection(filter)
        }
    }

    func updateChromaKeyFilter(id: String, mutation: (inout ChromaKeyFilter) -> Void) {
        let logger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "ShowStore")
        let selectedID = selectedLayerID?.uuidString ?? "nil"
        logger.info("updateChromaKeyFilter id=\(id) selectedLayerID=\(selectedID)")
        updateSelectedLayer { layer in
            let layerName = layer.name
            guard let index = layer.filters.firstIndex(where: { $0.id == id }),
                  case .chromaKey(var filter) = layer.filters[index] else {
                logger.warning("Chroma key filter \(id) not found in layer \(layerName)")
                return
            }
            mutation(&filter)
            layer.filters[index] = .chromaKey(filter)
            let bgName = filter.backgroundSource?.defaultName ?? "nil"
            logger.info("Chroma key filter updated, backgroundSource=\(bgName)")
        }
    }

    // MARK: - Chroma key (first-class layer toggle)

    /// The first chroma-key filter on the selected layer, if any.
    var selectedLayerChromaKey: ChromaKeyFilter? {
        guard let layer = selectedLayer else { return nil }
        for filter in layer.filters {
            if case .chromaKey(let f) = filter { return f }
        }
        return nil
    }

    /// Turn the selected layer's chroma key on or off. The filter is kept on
    /// the layer (with `isEnabled` toggled) so the controls stay visible and
    /// settings are preserved when the user disables/enables the effect.
    func setSelectedLayerChromaKeyEnabled(_ enabled: Bool) {
        guard selectedLayer != nil else { return }
        if let existing = selectedLayerChromaKey {
            updateChromaKeyFilter(id: Filter.chromaKey(existing).id) { $0.isEnabled = enabled }
        } else {
            addFilterToSelectedLayer(.chromaKey(ChromaKeyFilter(isEnabled: enabled)))
        }
    }

    /// Ensure the selected camera layer has a chroma-key filter. If one does
    /// not exist, a disabled default filter is added so the inspector controls
    /// can remain visible and editable without immediately keying the source.
    func ensureSelectedLayerChromaKeyFilter() {
        guard let layer = selectedLayer,
              case .camera = layer.source,
              selectedLayerChromaKey == nil else { return }
        addFilterToSelectedLayer(.chromaKey(ChromaKeyFilter(isEnabled: false)))
    }

    /// Mutate the selected layer's chroma-key filter (no-op if none is present).
    func updateSelectedLayerChromaKey(_ mutation: (inout ChromaKeyFilter) -> Void) {
        guard let layer = selectedLayer,
              let existing = layer.filters.first(where: {
                  if case .chromaKey = $0 { return true }
                  return false
              }) else { return }
        updateChromaKeyFilter(id: existing.id, mutation: mutation)
    }

    // MARK: - Camera settings

    /// Hardware control service (gimbal). Injected by the app root.
    var cameraControlService: CameraControlService?

    /// App settings, injected by the app root, used to read/write layer defaults.
    var appSettings: AppSettings?

    /// Save the selected layer's transform, opacity, blend mode, filters, and
    /// camera settings as the default starting point for its source.
    func saveSelectedLayerAsDefault() {
        guard let layer = selectedLayer else { return }
        let defaults = LayerDefaults(sourceKey: layer.source.defaultsKey, layer: layer)
        appSettings?.setLayerDefault(defaults)
    }

    /// Apply saved defaults for `source` to the layer with `id`, if any exist.
    func applyLayerDefaults(to id: UUID, source: Source) {
        guard let defaults = appSettings?.savedLayerDefaults[source.defaultsKey] else { return }
        _ = mutateLayer(id: id) { layer in
            defaults.apply(to: &layer)
        }
    }

    /// Whether a default has been saved for this source.
    func hasLayerDefault(for source: Source) -> Bool {
        appSettings?.savedLayerDefaults[source.defaultsKey] != nil
    }

    /// A snapshot of the selected layer's camera-relevant adjustments.
    func selectedLayerCameraSettings() -> CameraSettings {
        guard let layer = selectedLayer else { return CameraSettings() }
        let cc = selectedLayerColorCorrection ?? ColorCorrectionFilter()
        let stored = layer.cameraSettings
        return CameraSettings(
            zoom: layer.transform.scaleX,
            panX: layer.transform.x,
            panY: layer.transform.y,
            exposure: cc.exposure,
            temperature: cc.temperature,
            tint: cc.tint,
            gimbalPan: stored?.gimbalPan ?? 0,
            gimbalTilt: stored?.gimbalTilt ?? 0,
            gimbalActive: stored?.gimbalActive ?? false
        )
    }

    /// Apply a full camera adjustment snapshot to the selected layer.
    func applyCameraSettingsToSelectedLayer(_ settings: CameraSettings) {
        updateSelectedLayer { layer in
            layer.transform.scaleX = settings.zoom
            layer.transform.scaleY = settings.zoom
            layer.transform.x = settings.panX
            layer.transform.y = settings.panY
            layer.cameraSettings = settings
        }
        let id = ensureSelectedLayerColorCorrection()
        updateColorCorrectionFilter(id: id) { filter in
            filter.exposure = settings.exposure
            filter.temperature = settings.temperature
            filter.tint = settings.tint
        }
    }

    // MARK: - Color-correction shortcuts for camera adjustments

    /// The first color-correction filter on the selected layer, if any.
    var selectedLayerColorCorrection: ColorCorrectionFilter? {
        guard let layer = selectedLayer else { return nil }
        for filter in layer.filters {
            if case .colorCorrection(let cc) = filter { return cc }
        }
        return nil
    }

    /// The slideshow configuration if the selected layer is a slideshow source.
    var selectedLayerSlideshow: SlideshowSource? {
        guard let layer = selectedLayer,
              case .slideshow(let slideshow) = layer.source else { return nil }
        return slideshow
    }

    /// The drawing configuration if the selected layer is a drawing source.
    var selectedLayerDrawing: DrawingSource? {
        guard let layer = selectedLayer,
              case .drawing(let drawing) = layer.source else { return nil }
        return drawing
    }

    /// The text configuration if the selected layer is a text source.
    var selectedLayerText: TextSource? {
        guard let layer = selectedLayer,
              case .text(let textSource) = layer.source else { return nil }
        return textSource
    }

    /// The border configuration if the selected layer is a border source.
    var selectedLayerBorder: BorderSource? {
        guard let layer = selectedLayer,
              case .border(let border) = layer.source else { return nil }
        return border
    }

    /// The lower-third configuration if the selected layer is a lower-third source.
    var selectedLayerLowerThird: LowerThirdSource? {
        guard let layer = selectedLayer,
              case .lowerThird(let lowerThird) = layer.source else { return nil }
        return lowerThird
    }

    /// The chapter-marker configuration if the selected layer is a chapter-marker source.
    var selectedLayerChapterMarker: ChapterMarkerSource? {
        guard let layer = selectedLayer,
              case .chapterMarker(let chapter) = layer.source else { return nil }
        return chapter
    }

    /// The next-section configuration if the selected layer is a next-section source.
    var selectedLayerNextSection: NextSectionSource? {
        guard let layer = selectedLayer,
              case .nextSection(let next) = layer.source else { return nil }
        return next
    }

    /// The social-bug configuration if the selected layer is a social-bug source.
    var selectedLayerSocialBug: SocialBugSource? {
        guard let layer = selectedLayer,
              case .socialBug(let bug) = layer.source else { return nil }
        return bug
    }

    /// The logo-bug configuration if the selected layer is a logo-bug source.
    var selectedLayerLogoBug: LogoBugSource? {
        guard let layer = selectedLayer,
              case .logoBug(let bug) = layer.source else { return nil }
        return bug
    }

    /// The countdown-timer configuration if the selected layer is a countdown-timer source.
    var selectedLayerCountdownTimer: CountdownTimerSource? {
        guard let layer = selectedLayer,
              case .countdownTimer(let timer) = layer.source else { return nil }
        return timer
    }

    /// The image-logo-bug configuration if the selected layer is an image-logo-bug source.
    var selectedLayerImageLogoBug: ImageLogoBugSource? {
        guard let layer = selectedLayer,
              case .imageLogoBug(let bug) = layer.source else { return nil }
        return bug
    }

    /// The ticker configuration if the selected layer is a ticker source.
    var selectedLayerTicker: TickerSource? {
        guard let layer = selectedLayer,
              case .ticker(let ticker) = layer.source else { return nil }
        return ticker
    }

    /// The playlist configuration if the selected layer is a playlist source.
    var selectedLayerPlaylist: PlaylistSource? {
        guard let layer = selectedLayer,
              case .playlist(let playlist) = layer.source else { return nil }
        return playlist
    }

    /// The image URL if the selected layer is a static image source.
    var selectedLayerImage: URL? {
        guard let layer = selectedLayer,
              case .image(let url) = layer.source else { return nil }
        return url
    }

    /// The video URL if the selected layer is a media source.
    var selectedLayerMedia: URL? {
        guard let layer = selectedLayer else { return nil }
        switch layer.source {
        case .media(let url), .mediaClip(let url, _, _):
            return url
        default:
            return nil
        }
    }

    /// Update the animation state of any selected animatable template layer.
    func updateSelectedLayerAnimation(_ mutation: (inout TemplateAnimation) -> Void) {
        updateSelectedLayer { layer in
            switch layer.source {
            case .border(var source):
                mutation(&source.animation)
                layer.source = .border(source)
            case .lowerThird(var source):
                mutation(&source.animation)
                layer.source = .lowerThird(source)
            case .chapterMarker(var source):
                mutation(&source.animation)
                layer.source = .chapterMarker(source)
            case .nextSection(var source):
                mutation(&source.animation)
                layer.source = .nextSection(source)
            case .socialBug(var source):
                mutation(&source.animation)
                layer.source = .socialBug(source)
            case .logoBug(var source):
                mutation(&source.animation)
                layer.source = .logoBug(source)
            case .countdownTimer(var source):
                mutation(&source.animation)
                layer.source = .countdownTimer(source)
            case .imageLogoBug(var source):
                mutation(&source.animation)
                layer.source = .imageLogoBug(source)
            case .ticker(var source):
                mutation(&source.animation)
                layer.source = .ticker(source)
            case .playlist(var source):
                mutation(&source.animation)
                layer.source = .playlist(source)
            default:
                break
            }
        }
    }

    private func ensureSelectedLayerColorCorrection() -> String {
        if let layer = selectedLayer,
           let filter = layer.filters.first(where: {
               if case .colorCorrection = $0 { return true }
               return false
           }) {
            return filter.id
        }
        let cc = ColorCorrectionFilter()
        addFilterToSelectedLayer(.colorCorrection(cc))
        return "colorCorrection:\(cc.id)"
    }

    func setSelectedLayerExposure(_ value: Double) {
        let id = ensureSelectedLayerColorCorrection()
        updateColorCorrectionFilter(id: id) { $0.exposure = value }
    }

    func setSelectedLayerColorTemperature(_ value: Double) {
        let id = ensureSelectedLayerColorCorrection()
        updateColorCorrectionFilter(id: id) { $0.temperature = value }
    }

    func setSelectedLayerColorTint(_ value: Double) {
        let id = ensureSelectedLayerColorCorrection()
        updateColorCorrectionFilter(id: id) { $0.tint = value }
    }

    // MARK: - Gimbal (hardware PTZ)

    /// The uniqueID of the selected camera layer's capture device, if any.
    var selectedCameraUniqueID: String? {
        guard let layer = selectedLayer, case .camera(let deviceID) = layer.source else { return nil }
        return deviceID
    }

    /// Update the selected layer's gimbal pose (user frame degrees) and push
    /// to hardware immediately if connected. Marks the snapshot gimbal-active.
    func updateSelectedLayerGimbal(pan: Double? = nil, tilt: Double? = nil) {
        updateSelectedLayer { layer in
            var settings = layer.cameraSettings ?? CameraSettings()
            if let pan { settings.gimbalPan = pan }
            if let tilt { settings.gimbalTilt = tilt }
            settings.gimbalActive = true
            layer.cameraSettings = settings
        }
        pushGimbalToHardware()
    }

    /// Send the selected layer's gimbal pose to hardware (if connected),
    /// clamped by the camera's limit zone.
    func pushGimbalToHardware() {
        guard let service = cameraControlService,
              let uniqueID = selectedCameraUniqueID,
              let settings = selectedLayer?.cameraSettings,
              settings.gimbalActive
        else { return }
        let zone = show.cameraLimitZones[uniqueID]
        service.apply(settings: settings, to: uniqueID, limitZone: zone)
    }

    // MARK: - Gimbal limit zones

    /// The limit zone for the selected camera (defaults to unrestricted).
    func limitZoneForSelectedCamera() -> CameraLimitZone? {
        guard let uniqueID = selectedCameraUniqueID else { return nil }
        return show.cameraLimitZones[uniqueID] ?? .unrestricted
    }

    /// Set (or clear, with nil) the limit zone for the selected camera.
    func setLimitZoneForSelectedCamera(_ zone: CameraLimitZone?) {
        guard let uniqueID = selectedCameraUniqueID else { return }
        if let zone {
            show.cameraLimitZones[uniqueID] = zone
        } else {
            show.cameraLimitZones.removeValue(forKey: uniqueID)
        }
    }

    // MARK: - Camera presets

    func addCameraPreset(name: String) {
        let snapshot = selectedLayerCameraSettings()
        show.cameraPresets.append(CameraPreset(name: name, settings: snapshot))
    }

    func deleteCameraPreset(id: UUID) {
        show.cameraPresets.removeAll { $0.id == id }
    }

    func applyCameraPresetToSelectedLayer(_ preset: CameraPreset) {
        applyCameraSettingsToSelectedLayer(preset.settings)
    }

    func deleteSelectedLayer() {
        guard let selectedLayerID else { return }
        if let scene = activeScene,
           let sceneIndex = show.scenes.firstIndex(where: { $0.id == scene.id }),
           let layerIndex = show.scenes[sceneIndex].layers.firstIndex(where: { $0.id == selectedLayerID }) {
            show.scenes[sceneIndex].layers.remove(at: layerIndex)
        } else if let index = show.globalLayers.firstIndex(where: { $0.id == selectedLayerID }) {
            show.globalLayers.remove(at: index)
        }
        self.selectedLayerID = nil
    }

    // MARK: - Layer scope (cue vs show)

    /// Move the selected cue-local layer into the show-level global layers.
    func moveSelectedLayerToGlobal() {
        guard let selectedLayerID,
              let scene = activeScene,
              let sceneIndex = show.scenes.firstIndex(where: { $0.id == scene.id }),
              let layerIndex = show.scenes[sceneIndex].layers.firstIndex(where: { $0.id == selectedLayerID })
        else { return }

        let layer = show.scenes[sceneIndex].layers.remove(at: layerIndex)
        show.globalLayers.append(layer)
    }

    /// Move the selected show-level global layer into the active scene.
    func moveSelectedLayerToCue() {
        guard let selectedLayerID,
              let scene = activeScene,
              let sceneIndex = show.scenes.firstIndex(where: { $0.id == scene.id }),
              let index = show.globalLayers.firstIndex(where: { $0.id == selectedLayerID })
        else { return }

        let layer = show.globalLayers.remove(at: index)
        show.scenes[sceneIndex].layers.append(layer)
    }

    func toggleSelectedLayerScope() {
        if isSelectedLayerGlobal {
            moveSelectedLayerToCue()
        } else {
            moveSelectedLayerToGlobal()
        }
    }

    // MARK: - A→B camera moves

    private var cameraMoveTimer: Timer?
    private var cameraMoveState: CameraMoveState?

    private struct CameraMoveState {
        let layerID: UUID
        let startSettings: CameraSettings
        let endSettings: CameraSettings
        let startTime: Date
        let duration: TimeInterval
    }

    private func startCameraMoveIfNeeded(for cue: Cue) {
        guard let move = cue.cameraMove, move.isEnabled,
              let endPresetID = move.endPresetID,
              let endPreset = show.cameraPresets.first(where: { $0.id == endPresetID }),
              let scene = show.scene(withID: cue.sceneID) else { return }

        let layerID = move.targetLayerID ?? scene.layers.first(where: { layer in
            if case .camera = layer.source { return true }
            return false
        })?.id

        guard let layerID else { return }

        let startSettings: CameraSettings
        if let startPresetID = move.startPresetID,
           let preset = show.cameraPresets.first(where: { $0.id == startPresetID }) {
            startSettings = preset.settings
            applyCameraSettings(startSettings, to: layerID)
        } else {
            startSettings = cameraSettings(for: layerID)
        }

        let duration = max(move.duration, 0.01)
        cameraMoveState = CameraMoveState(
            layerID: layerID,
            startSettings: startSettings,
            endSettings: endPreset.settings,
            startTime: Date(),
            duration: duration
        )

        cameraMoveTimer?.invalidate()
        cameraMoveTimer = Timer.scheduledTimer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(tickCameraMove),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func tickCameraMove() {
        guard let state = cameraMoveState else {
            stopCameraMove()
            return
        }
        let elapsed = Date().timeIntervalSince(state.startTime)
        let progress = min(elapsed / state.duration, 1.0)
        let settings = state.startSettings.interpolated(to: state.endSettings, progress: progress)
        applyCameraSettings(settings, to: state.layerID)
        if progress >= 1.0 {
            stopCameraMove()
        }
    }

    private func stopCameraMove() {
        cameraMoveTimer?.invalidate()
        cameraMoveTimer = nil
        cameraMoveState = nil
    }

    /// Find a layer by ID in the active scene or global layers.
    private func layerForID(_ layerID: UUID) -> Layer? {
        if let scene = activeScene, let found = scene.layers.first(where: { $0.id == layerID }) {
            return found
        }
        return show.globalLayers.first(where: { $0.id == layerID })
    }

    /// Snapshot the camera-relevant settings for a specific layer.
    private func cameraSettings(for layerID: UUID) -> CameraSettings {
        let layer: Layer?
        if let scene = activeScene,
           let found = scene.layers.first(where: { $0.id == layerID }) {
            layer = found
        } else {
            layer = show.globalLayers.first(where: { $0.id == layerID })
        }
        guard let layer else { return CameraSettings() }

        let cc: ColorCorrectionFilter
        if let filter = layer.filters.first(where: {
            if case .colorCorrection = $0 { return true }
            return false
        }), case .colorCorrection(let existing) = filter {
            cc = existing
        } else {
            cc = ColorCorrectionFilter()
        }

        let stored = layer.cameraSettings
        return CameraSettings(
            zoom: layer.transform.scaleX,
            panX: layer.transform.x,
            panY: layer.transform.y,
            exposure: cc.exposure,
            temperature: cc.temperature,
            tint: cc.tint,
            gimbalPan: stored?.gimbalPan ?? 0,
            gimbalTilt: stored?.gimbalTilt ?? 0,
            gimbalActive: stored?.gimbalActive ?? false
        )
    }

    /// Apply camera settings to a specific layer by ID.
    private func applyCameraSettings(_ settings: CameraSettings, to layerID: UUID) {
        // If this layer is a camera and the snapshot is gimbal-active, drive
        // the physical gimbal too (A→B moves interpolate gimbalPan/Tilt).
        if let service = cameraControlService,
           settings.gimbalActive,
           let layer = layerForID(layerID),
           case .camera(let deviceID) = layer.source {
            let zone = show.cameraLimitZones[deviceID]
            service.apply(settings: settings, to: deviceID, limitZone: zone)
        }

        _ = mutateLayer(id: layerID) { layer in
            layer.transform.scaleX = settings.zoom
            layer.transform.scaleY = settings.zoom
            layer.transform.x = settings.panX
            layer.transform.y = settings.panY
            layer.cameraSettings = settings

            if let index = layer.filters.firstIndex(where: {
                if case .colorCorrection = $0 { return true }
                return false
            }), case .colorCorrection(var filter) = layer.filters[index] {
                filter.exposure = settings.exposure
                filter.temperature = settings.temperature
                filter.tint = settings.tint
                layer.filters[index] = .colorCorrection(filter)
            } else {
                let filter = ColorCorrectionFilter(
                    exposure: settings.exposure,
                    temperature: settings.temperature,
                    tint: settings.tint
                )
                layer.filters.append(.colorCorrection(filter))
            }
        }
    }

    // MARK: - Presenter mode

    private func scheduleAutoFollowIfNeeded() {
        presenterAutoFollowTimer?.invalidate()
        presenterAutoFollowTimer = nil
        guard show.kind == .presenter,
              let segment = liveSegment,
              segment.autoFollow,
              segment.type == .videoPackage,
              let duration = segment.duration, duration > 0 else { return }
        presenterAutoFollowTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.presenterGo()
            }
        }
    }

    var presenterRundown: PresenterRundown? {
        show.presenterRundown
    }

    var activeSegment: PresenterSegment? {
        guard let activeSegmentID,
              let rundown = show.presenterRundown else { return nil }
        return rundown.segments.first { $0.id == activeSegmentID }
    }

    var liveSegment: PresenterSegment? {
        guard let liveSegmentID,
              let rundown = show.presenterRundown else { return nil }
        return rundown.segments.first { $0.id == liveSegmentID }
    }

    /// The scene that represents the live presenter segment, if any.
    var presenterLiveScene: Scene? {
        guard let segment = liveSegment else { return nil }
        return scene(for: segment)
    }

    /// The scene that represents the active (preview) presenter segment, if any.
    var presenterActiveScene: Scene? {
        guard let segment = activeSegment else { return nil }
        return scene(for: segment)
    }

    func selectSegment(id: UUID?) {
        activeSegmentID = id
        selectedPlaceholderID = nil
    }

    @discardableResult
    func presenterGo() -> GoResult {
        guard let activeSegmentID,
              let rundown = show.presenterRundown,
              rundown.segments.contains(where: { $0.id == activeSegmentID }) else {
            return .noCue
        }
        stopCameraMove()
        liveSegmentID = activeSegmentID
        applyPresenterGimbalIfNeeded(for: liveSegment)

        guard let index = rundown.segments.firstIndex(where: { $0.id == activeSegmentID }),
              index + 1 < rundown.segments.count else {
            return .atEnd
        }
        self.activeSegmentID = rundown.segments[index + 1].id
        let nextSegment = activeSegment
        return .advanced(nextCue: nextSegment.map { Cue(name: $0.name, sceneID: UUID()) })
    }

    func triggerSegment(id: UUID) {
        guard let rundown = show.presenterRundown,
              rundown.segments.contains(where: { $0.id == id }) else { return }
        stopCameraMove()
        activeSegmentID = id
        liveSegmentID = id
        applyPresenterGimbalIfNeeded(for: liveSegment)
    }

    /// When a presenter segment goes live and it has gimbal-active camera
    /// settings, send the pose to the physical gimbal for that camera angle.
    private func applyPresenterGimbalIfNeeded(for segment: PresenterSegment?) {
        guard let segment,
              segment.type == .cameraGraphic,
              let settings = segment.cameraSettings,
              settings.gimbalActive,
              let service = cameraControlService,
              let deviceID = presenterCameraID(for: segment.cameraAngle) else { return }
        let zone = show.cameraLimitZones[deviceID]
        service.apply(settings: settings, to: deviceID, limitZone: zone)
    }

    func selectPreviousSegment() {
        guard let activeSegmentID,
              let rundown = show.presenterRundown,
              let index = rundown.segments.firstIndex(where: { $0.id == activeSegmentID }),
              index > 0 else { return }
        self.activeSegmentID = rundown.segments[index - 1].id
    }

    func selectNextSegment() {
        guard let activeSegmentID,
              let rundown = show.presenterRundown,
              let index = rundown.segments.firstIndex(where: { $0.id == activeSegmentID }),
              index + 1 < rundown.segments.count else { return }
        self.activeSegmentID = rundown.segments[index + 1].id
    }

    // MARK: - Presenter segment mutation

    @discardableResult
    func addPresenterSegment(type: PresenterSegmentType = .cameraGraphic, after id: UUID? = nil) -> UUID {
        guard var rundown = show.presenterRundown else { return UUID() }
        let segment = PresenterSegment(name: "New \(type.displayName)", type: type)
        if let id,
           let index = rundown.segments.firstIndex(where: { $0.id == id }) {
            rundown.segments.insert(segment, at: index + 1)
        } else {
            rundown.segments.append(segment)
        }
        show.presenterRundown = rundown
        activeSegmentID = segment.id
        return segment.id
    }

    func duplicatePresenterSegment(id: UUID) {
        guard var rundown = show.presenterRundown,
              let segment = rundown.segments.first(where: { $0.id == id }),
              let index = rundown.segments.firstIndex(where: { $0.id == id }) else { return }
        let copy = PresenterSegment(
            name: segment.name + " Copy",
            type: segment.type,
            placeholderID: segment.placeholderID,
            videoClip: segment.videoClip,
            cameraAngle: segment.cameraAngle,
            autoFollow: segment.autoFollow,
            notes: segment.notes
        )
        rundown.segments.insert(copy, at: index + 1)
        show.presenterRundown = rundown
    }

    func deletePresenterSegment(id: UUID) {
        guard var rundown = show.presenterRundown else { return }
        rundown.segments.removeAll { $0.id == id }
        show.presenterRundown = rundown
        if activeSegmentID == id { activeSegmentID = rundown.segments.first?.id }
        if liveSegmentID == id { liveSegmentID = rundown.segments.first?.id }
    }

    func movePresenterSegment(from source: IndexSet, to destination: Int) {
        guard var rundown = show.presenterRundown else { return }
        rundown.segments.move(fromOffsets: source, toOffset: destination)
        show.presenterRundown = rundown
    }

    func updatePresenterSegment(id: UUID, mutation: (inout PresenterSegment) -> Void) {
        guard var rundown = show.presenterRundown,
              let index = rundown.segments.firstIndex(where: { $0.id == id }) else { return }
        mutation(&rundown.segments[index])
        show.presenterRundown = rundown
    }

    // MARK: - Presenter placeholders

    @discardableResult
    func addPresenterPlaceholder(name: String = "Placeholder") -> UUID {
        guard var rundown = show.presenterRundown else { return UUID() }
        let placeholder = PresenterPlaceholder(name: name)
        rundown.placeholders.append(placeholder)
        show.presenterRundown = rundown
        selectedPlaceholderID = placeholder.id
        return placeholder.id
    }

    func deletePresenterPlaceholder(id: UUID) {
        guard var rundown = show.presenterRundown else { return }
        rundown.placeholders.removeAll { $0.id == id }
        for index in rundown.segments.indices where rundown.segments[index].placeholderID == id {
            rundown.segments[index].placeholderID = nil
        }
        show.presenterRundown = rundown
        if selectedPlaceholderID == id { selectedPlaceholderID = nil }
    }

    func updatePresenterPlaceholder(id: UUID, mutation: (inout PresenterPlaceholder) -> Void) {
        guard var rundown = show.presenterRundown,
              let index = rundown.placeholders.firstIndex(where: { $0.id == id }) else { return }
        mutation(&rundown.placeholders[index])
        show.presenterRundown = rundown
    }

    func placeholder(id: UUID?) -> PresenterPlaceholder? {
        guard let id,
              let rundown = show.presenterRundown else { return nil }
        return rundown.placeholders.first { $0.id == id }
    }

    // MARK: - Presenter global layers

    @discardableResult
    func addPresenterGlobalLayer(source: Source, name: String? = nil) -> UUID {
        guard var rundown = show.presenterRundown else { return UUID() }
        let layer = Layer(
            name: name ?? source.defaultName,
            source: source,
            transform: .identity
        )
        rundown.globalLayers.append(layer)
        show.presenterRundown = rundown
        return layer.id
    }

    func deletePresenterGlobalLayer(id: UUID) {
        guard var rundown = show.presenterRundown else { return }
        rundown.globalLayers.removeAll { $0.id == id }
        show.presenterRundown = rundown
    }

    func updatePresenterGlobalLayer(id: UUID, mutation: (inout Layer) -> Void) {
        guard var rundown = show.presenterRundown,
              let index = rundown.globalLayers.firstIndex(where: { $0.id == id }) else { return }
        mutation(&rundown.globalLayers[index])
        show.presenterRundown = rundown
    }

    // MARK: - Presenter cue (segment) layers

    @discardableResult
    func addPresenterSegmentLayer(segmentID: UUID, source: Source, name: String? = nil) -> UUID {
        let layer = Layer(
            name: name ?? source.defaultName,
            source: source,
            transform: .identity
        )
        updatePresenterSegment(id: segmentID) { $0.layers.append(layer) }
        return layer.id
    }

    func deletePresenterSegmentLayer(segmentID: UUID, id: UUID) {
        updatePresenterSegment(id: segmentID) { segment in
            segment.layers.removeAll { $0.id == id }
        }
    }

    func updatePresenterSegmentLayer(segmentID: UUID, id: UUID, mutation: (inout Layer) -> Void) {
        updatePresenterSegment(id: segmentID) { segment in
            guard let index = segment.layers.firstIndex(where: { $0.id == id }) else { return }
            mutation(&segment.layers[index])
        }
    }

    /// Move a cue layer through the render stack. `+1` brings it forward,
    /// `-1` sends it back.
    func movePresenterSegmentLayer(segmentID: UUID, id: UUID, by offset: Int) {
        updatePresenterSegment(id: segmentID) { segment in
            guard let index = segment.layers.firstIndex(where: { $0.id == id }) else { return }
            let target = index + offset
            guard segment.layers.indices.contains(target) else { return }
            let layer = segment.layers.remove(at: index)
            segment.layers.insert(layer, at: target)
        }
    }

    /// Copy a cue layer to another segment, e.g. reusing a screen share across
    /// a run of cues.
    func copyPresenterSegmentLayer(from sourceSegmentID: UUID, layerID: UUID, to targetSegmentID: UUID) {
        guard let layer = presenterSegment(id: sourceSegmentID)?
            .layers.first(where: { $0.id == layerID }) else { return }
        let copy = Layer(
            name: layer.name,
            source: layer.source,
            transform: layer.transform,
            filters: layer.filters,
            blendMode: layer.blendMode,
            opacity: layer.opacity,
            isVisible: layer.isVisible,
            isLocked: layer.isLocked,
            cameraSettings: layer.cameraSettings,
            placement: layer.placement
        )
        updatePresenterSegment(id: targetSegmentID) { $0.layers.append(copy) }
    }

    func presenterSegment(id: UUID) -> PresenterSegment? {
        show.presenterRundown?.segments.first { $0.id == id }
    }

    func setPresenterCameraID(_ deviceID: String?, for angle: PresenterCameraAngle) {
        guard var rundown = show.presenterRundown else { return }
        switch angle {
        case .primary: rundown.primaryCameraID = deviceID
        case .secondary: rundown.secondaryCameraID = deviceID
        }
        show.presenterRundown = rundown
    }

    func presenterCameraID(for angle: PresenterCameraAngle) -> String? {
        guard let rundown = show.presenterRundown else { return nil }
        switch angle {
        case .primary: return rundown.primaryCameraID
        case .secondary: return rundown.secondaryCameraID
        }
    }

    private func cameraTransform(from settings: CameraSettings?) -> ItemTransform {
        guard let settings else { return .identity }
        return ItemTransform(
            x: settings.panX,
            y: settings.panY,
            scaleX: settings.zoom,
            scaleY: settings.zoom,
            rotation: 0,
            crop: .zero
        )
    }

    // MARK: - Presenter segment → scene mapping

    /// Convert a presenter segment into a renderable Scene so the shared
    /// StageRenderer can composite it without knowing about segments.
    func scene(for segment: PresenterSegment) -> Scene {
        var layers: [Layer] = []

        // Global presenter background (virtual set), rendered behind the
        // segment content so it stays full-frame regardless of camera framing.
        if let backgroundSource = show.presenterRundown?.backgroundSource {
            layers.append(Layer(
                name: "Background",
                source: backgroundSource,
                transform: show.presenterRundown?.backgroundTransform ?? .identity
            ))
        }

        // Global layers marked as background are composited behind segment
        // content. This lets a looping video fill the frame while the
        // presenter/screenshare sit on top.
        if let backgroundLayers = show.presenterRundown?.globalLayers
            .filter({ $0.placement == .background && $0.isVisible }) {
            layers.append(contentsOf: backgroundLayers)
        }

        // Cue-owned layers placed behind the cue content (e.g. a backdrop that
        // only exists in this cue).
        layers.append(contentsOf: segment.layers
            .filter { $0.placement == .background && $0.isVisible })

        // For cameraGraphic segments, the camera can either sit behind cue
        // layers (default) or in front of them. The placeholder graphic always
        // follows the camera so it stays anchored to the shot.
        let cameraIsBackground = segment.type == .cameraGraphic && segment.cameraLayerPlacement == .background

        if cameraIsBackground {
            appendCameraAndPlaceholder(to: &layers, segment: segment)
        }

        switch segment.type {
        case .cameraGraphic:
            // Camera/placeholder handled above or below depending on placement.
            break

        case .videoPackage:
            if let clip = segment.videoClip {
                let source: Source
                if let subclipURL = clip.subclipURL {
                    // Pre-exported subclip takes priority for performance.
                    source = .media(url: subclipURL)
                } else {
                    // Play the trimmed range directly from the original file.
                    source = .mediaClip(url: clip.sourceURL, inPoint: clip.inPoint, outPoint: clip.outPoint)
                }
                layers.append(Layer(
                    name: segment.name,
                    source: source,
                    transform: .identity
                ))
            } else {
                layers.append(Layer(
                    name: "No Video",
                    source: .color(CGColorComponents(r: 0, g: 0, b: 0, a: 1)),
                    transform: .identity
                ))
            }

        case .titleCard:
            if let placeholder = placeholder(id: segment.placeholderID),
               let source = placeholder.source {
                layers.append(Layer(
                    name: placeholder.name,
                    source: source,
                    transform: .identity
                ))
            }
            // When no placeholder is set, render nothing so the global
            // background layer remains visible instead of being covered by
            // an opaque fallback card.

        case .stationBreak:
            layers.append(Layer(
                name: "Break",
                source: .color(CGColorComponents(r: 0, g: 0, b: 0, a: 1)),
                transform: .identity
            ))
        }

        // Cue-owned layers in front of the cue content — screen shares,
        // picture inserts, one-off graphics.
        layers.append(contentsOf: segment.layers
            .filter { $0.placement == .foreground && $0.isVisible })

        // When the camera is in the foreground it must sit above the cue
        // foreground layers so the presenter is not hidden by a screen share.
        if !cameraIsBackground && segment.type == .cameraGraphic {
            appendCameraAndPlaceholder(to: &layers, segment: segment)
        }

        // Global overlays (logo bugs, lower-thirds, etc.) appear on top of
        // every presenter segment.
        if let foregroundLayers = show.presenterRundown?.globalLayers
            .filter({ $0.placement == .foreground && $0.isVisible }) {
            layers.append(contentsOf: foregroundLayers)
        }

        return Scene(name: segment.name, layers: layers, outputSize: CGSize(width: 1920, height: 1080))
    }

    private func appendCameraAndPlaceholder(to layers: inout [Layer], segment: PresenterSegment) {
        guard segment.type == .cameraGraphic else { return }
        if let cameraID = presenterCameraID(for: segment.cameraAngle) {
            var cameraLayer = Layer(
                name: segment.cameraAngle.displayName,
                source: .camera(deviceID: cameraID),
                transform: cameraTransform(from: segment.cameraSettings)
            )
            cameraLayer.cameraSettings = segment.cameraSettings
            if let chromaKey = segment.chromaKeyFilter {
                cameraLayer.filters.append(.chromaKey(chromaKey))
            }
            layers.append(cameraLayer)
        } else {
            layers.append(Layer(
                name: "No Camera",
                source: .color(CGColorComponents(r: 0, g: 0, b: 0, a: 1)),
                transform: .identity
            ))
        }
        if let placeholder = placeholder(id: segment.placeholderID),
           let source = placeholder.source {
            layers.append(Layer(
                name: placeholder.name,
                source: source,
                transform: ItemTransform(
                    x: 0.5, y: 0.85,
                    scaleX: 0.4, scaleY: 0.15,
                    rotation: 0, crop: .zero
                )
            ))
        }
    }

}
