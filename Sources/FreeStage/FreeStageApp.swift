//
//  FreeStageApp.swift
//  FreeStage
//
//  App entry point for the live production switcher.
//

import SwiftUI

@main
struct FreeStageApp: App {
    @State private var store = ShowStore()
    @State private var captureManager = CameraCaptureManager()
    @State private var cameraControlService = CameraControlService()

    init() {
        captureManager.cameraControlService = cameraControlService
        store.cameraControlService = cameraControlService
    }

    var body: some SwiftUI.Scene {
        WindowGroup("FreeStage") {
            ContentView()
                .environment(store)
                .environment(\.cameraCaptureManager, captureManager)
                .environment(\.cameraControlService, cameraControlService)
        }
        .defaultSize(width: 1400, height: 900)
        .windowResizability(.contentSize)
    }
}
