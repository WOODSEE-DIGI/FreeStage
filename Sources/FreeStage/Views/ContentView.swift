//
//  ContentView.swift
//  FreeStage
//
//  Main workspace window: cue list and settings on the left, stacked Program
//  and Preview monitors in the centre, and layer editing tools on the right.
//

import SwiftUI

struct ContentView: View {
    @Environment(ShowStore.self) private var store
    @Environment(ThemeStore.self) private var theme
    @Environment(\.cameraCaptureManager) private var captureManager
    @Environment(\.screenCaptureManager) private var screenCaptureManager

    var body: some View {
        guard let captureManager, let screenCaptureManager else {
            return AnyView(
                Text("Capture managers not available")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }

        return AnyView(workspaceBody(manager: captureManager, screenManager: screenCaptureManager))
    }

    private func workspaceBody(manager: CameraCaptureManager, screenManager: ScreenCaptureManager) -> some View {
        // Derive the set of camera uniqueIDs and screen displayIDs that must
        // be capturing. Watching these sets (rather than the whole Scene value)
        // means layer edits don't tear down capture sessions.
        let requiredCameraIDs = activeCameraIDs()
        let requiredScreenIDs = activeScreenIDs()

        return VStack(spacing: 0) {
            if store.mastheadVisible {
                MastheadView()
            }

            HSplitView {
                leftPane
                    .frame(minWidth: 280, idealWidth: 340)

                monitorStack
                    .frame(minWidth: 520, idealWidth: 760)

                rightPane
                    .frame(minWidth: 280, idealWidth: 320)
            }

            FooterView()
        }
        .frame(minWidth: 1400, minHeight: 900)
        .background(theme.background)
        .background(WindowFrameInitializer(minSize: NSSize(width: 1400, height: 900)))
        .onChange(of: requiredCameraIDs) { _, _ in
            updateCameraCapture(manager: manager, requiredIDs: requiredCameraIDs)
        }
        .onChange(of: requiredScreenIDs) { _, _ in
            updateScreenCapture(manager: screenManager, requiredIDs: requiredScreenIDs)
        }
        .task {
            updateCameraCapture(manager: manager, requiredIDs: requiredCameraIDs)
            updateScreenCapture(manager: screenManager, requiredIDs: requiredScreenIDs)
        }
    }

    /// All camera uniqueIDs referenced by the active scene, live scene, and
    /// global layers — the cameras that must have running capture sessions.
    private func activeCameraIDs() -> Set<String> {
        var ids = Set<String>()
        ids.formUnion(cameraIDs(in: store.activeScene))
        ids.formUnion(cameraIDs(in: store.liveScene))
        ids.formUnion(cameraIDs(in: store.show.globalLayers))
        return ids
    }

    private func updateCameraCapture(manager: CameraCaptureManager, requiredIDs: Set<String>) {
        manager.syncCaptures(requiredIDs: requiredIDs)
    }

    private func updateScreenCapture(manager: ScreenCaptureManager, requiredIDs: Set<CGDirectDisplayID>) {
        manager.syncCaptures(requiredIDs: requiredIDs)
    }

    private var leftPane: some View {
        VStack(spacing: 0) {
            SceneLibraryView()
                .frame(minHeight: 140, idealHeight: 200)

            CueListView()
                .frame(minHeight: 160)

            if store.inspectorVisible {
                leftSettingsTabs
            }
        }
    }

    private var leftSettingsTabs: some View {
        TabView {
            CueSettingsView()
                .tabItem { Label("Cue", systemImage: "number") }

            AudioMixerView()
                .tabItem { Label("Audio", systemImage: "waveform") }
        }
    }

    private var rightPane: some View {
        LayerEditorView()
    }

    private var monitorStack: some View {
        VSplitView {
            ProgramMonitorView()
                .frame(minHeight: 200, idealHeight: 360)

            PreviewMonitorView()
                .frame(minHeight: 160, idealHeight: 240)
        }
    }

    private func cameraIDs(in scene: Scene?) -> Set<String> {
        guard let scene else { return [] }
        return cameraIDs(in: scene.layers)
    }

    private func cameraIDs(in layers: [Layer]) -> Set<String> {
        Set(layers.compactMap { layer -> String? in
            if case .camera(let id) = layer.source { return id }
            return nil
        })
    }

    private func activeScreenIDs() -> Set<CGDirectDisplayID> {
        var ids = Set<CGDirectDisplayID>()
        ids.formUnion(screenIDs(in: store.activeScene))
        ids.formUnion(screenIDs(in: store.liveScene))
        ids.formUnion(screenIDs(in: store.show.globalLayers))
        return ids
    }

    private func screenIDs(in scene: Scene?) -> Set<CGDirectDisplayID> {
        guard let scene else { return [] }
        return screenIDs(in: scene.layers)
    }

    private func screenIDs(in layers: [Layer]) -> Set<CGDirectDisplayID> {
        Set(layers.compactMap { layer -> CGDirectDisplayID? in
            if case .screen(let id) = layer.source { return id }
            return nil
        })
    }
}
