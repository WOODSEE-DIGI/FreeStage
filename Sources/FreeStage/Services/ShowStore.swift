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
    var activeCueID: UUID?
    var liveCueID: UUID?
    var selectedLayerID: UUID?
    var isPlaying = false

    // MARK: - Workspace UI state

    var isEditMode = true
    var mastheadVisible = true
    var sidebarVisible = false
    var inspectorVisible = true
    var panicDuration: TimeInterval = 1.0

    init(show: Show = .default()) {
        self.show = show
        let firstCueID = show.cues.first?.id
        self.activeCueID = firstCueID
        self.liveCueID = firstCueID
    }

    // MARK: - Selected / playhead cue

    var activeCue: Cue? {
        guard let activeCueID else { return nil }
        return show.cues.first { $0.id == activeCueID }
    }

    var activeScene: Scene? {
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
    }

    func go() {
        guard let activeCueID,
              let cue = show.cues.first(where: { $0.id == activeCueID }),
              cue.isArmed else { return }

        stopCameraMove()
        liveCueID = activeCueID
        selectedLayerID = nil
        startCameraMoveIfNeeded(for: cue)

        guard let index = show.cues.firstIndex(where: { $0.id == activeCueID }),
              index + 1 < show.cues.count else { return }
        self.activeCueID = show.cues[index + 1].id
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

    func resetWorkspace() {
        stopCameraMove()
        let firstCueID = show.cues.first?.id
        activeCueID = firstCueID
        liveCueID = firstCueID
        selectedLayerID = nil
        isPlaying = false
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

    // MARK: - Cue / scene creation

    @discardableResult
    func addCue(source: Source, name: String? = nil) -> UUID {
        let layer = Layer(name: name, source: source)
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

        let layer = Layer(
            name: device.name,
            source: .camera(deviceID: device.uniqueID),
            transform: ItemTransform(x: 0.5, y: 0.5, scaleX: 1.0, scaleY: 1.0, rotation: 0, crop: .zero)
        )
        show.scenes[sceneIndex].layers.append(layer)
        selectedLayerID = layer.id
    }

    func addLayer(source: Source) {
        guard let scene = activeScene,
              let sceneIndex = show.scenes.firstIndex(where: { $0.id == scene.id }) else { return }
        let layer = Layer(source: source)
        show.scenes[sceneIndex].layers.append(layer)
        selectedLayerID = layer.id
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

    /// Turn the selected layer's chroma key on or off. When turning on, a
    /// default chroma-key filter is added if the layer doesn't already have one.
    func setSelectedLayerChromaKeyEnabled(_ enabled: Bool) {
        guard let layer = selectedLayer else { return }
        if enabled {
            guard selectedLayerChromaKey == nil else { return }
            addFilterToSelectedLayer(.chromaKey(ChromaKeyFilter()))
        } else if let existing = layer.filters.first(where: {
            if case .chromaKey = $0 { return true }
            return false
        }) {
            removeFilterFromSelectedLayer(id: existing.id)
        }
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
}
