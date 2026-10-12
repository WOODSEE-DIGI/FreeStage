//
//  ContentView.swift
//  FreeStage
//
//  Main workspace window: masthead, cue list + inspector on the left,
//  stacked Program and Preview monitors on the right, footer bottom.
//

import SwiftUI

struct ContentView: View {
    @Environment(ShowStore.self) private var store
    @Environment(\.cameraCaptureManager) private var captureManager

    var body: some View {
        guard let captureManager else {
            return AnyView(
                Text("Camera capture manager not available")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }

        return AnyView(workspaceBody(manager: captureManager))
    }

    private func workspaceBody(manager: CameraCaptureManager) -> some View {
        // Derive the set of camera uniqueIDs that must be capturing. Watching
        // this set (rather than the whole Scene value) means layer edits —
        // transform, color, gimbal pose — no longer tear down and restart
        // every capture session; only adding/removing/retargeting a camera
        // layer triggers a change.
        let requiredCameraIDs = activeCameraIDs()

        return VStack(spacing: 0) {
            if store.mastheadVisible {
                MastheadView()
            }

            HSplitView {
                leftPane
                    .frame(minWidth: 280, idealWidth: 360)

                monitorStack
                    .frame(minWidth: 480, idealWidth: 800)

                if store.sidebarVisible {
                    SidebarView()
                }
            }

            FooterView()
        }
        .onChange(of: requiredCameraIDs) { _, _ in
            updateCameraCapture(manager: manager, requiredIDs: requiredCameraIDs)
        }
        .task {
            updateCameraCapture(manager: manager, requiredIDs: requiredCameraIDs)
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

    private var leftPane: some View {
        VStack(spacing: 0) {
            CueListView()
                .frame(minHeight: 160)

            if store.inspectorVisible {
                InspectorView()
                    .frame(minHeight: 200)
            }
        }
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
}
