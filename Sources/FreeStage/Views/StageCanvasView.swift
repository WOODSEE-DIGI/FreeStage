//
//  StageCanvasView.swift
//  FreeStage
//
//  Program (live) and Preview (next/selected cue) monitors. Each renders a
//  scene plus the show's persistent global layers. Preview is editable.
//

import SwiftUI

struct StageMonitorView: View {
    @Environment(ShowStore.self) private var store
    @Environment(ThemeStore.self) private var theme
    @Environment(\.cameraCaptureManager) private var captureManager
    @Environment(\.screenCaptureManager) private var screenCaptureManager
    @Environment(\.virtualCameraOutputService) private var virtualCamera
    @Environment(\.recordingService) private var recordingService
    @Environment(\.streamingService) private var streamingService
    @Environment(\.facePuppetTrackingService) private var trackingService

    let scene: Scene?
    let title: String
    let isLive: Bool
    let isEditable: Bool
    @StateObject private var fpsCounter = FpsCounter()

    var body: some View {
        VStack(spacing: 0) {
            monitorHeader

            if let captureManager, let screenCaptureManager {
                MetalCanvasView(
                    scene: scene,
                    globalLayers: store.show.globalLayers,
                    captureManager: captureManager,
                    screenCaptureManager: screenCaptureManager,
                    fpsCounter: fpsCounter,
                    virtualCamera: isLive ? virtualCamera : nil,
                    recordingService: isLive ? recordingService : nil,
                    streamingService: isLive ? streamingService : nil,
                    trackingService: trackingService
                )
                .aspectRatio(16 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.monitorBackground)
                .overlay(
                    Group {
                        if isEditable {
                            LayerOverlayView()
                        }
                    }
                )
            } else {
                theme.monitorBackground
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        Text("Capture managers not available")
                            .foregroundStyle(theme.secondaryText)
                    )
            }

            monitorFooter
        }
    }

    private var monitorHeader: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: isLive ? "record.circle" : "eye")
                    .foregroundStyle(isLive ? .red : theme.accent)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(theme.text)
            }

            Spacer()

            Text(scene?.name ?? "No Scene")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(theme.panelBackground)
    }

    private var monitorFooter: some View {
        HStack {
            let visibleCount = (scene?.layers.filter(\.isVisible).count ?? 0)
                + store.show.globalLayers.filter(\.isVisible).count
            Text("\(visibleCount) visible layer(s)")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)

            Spacer()

            Text("\(fpsCounter.fps, specifier: "%.0f") fps")
                .font(.caption.monospacedDigit())
                .foregroundStyle(fpsCounter.fps < 20 ? .red : theme.secondaryText)

            if isLive {
                Text("LIVE")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
            } else {
                Text("PREVIEW")
                    .font(.caption.bold())
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(theme.panelBackground)
    }
}

struct ProgramMonitorView: View {
    @Environment(ShowStore.self) private var store

    var body: some View {
        StageMonitorView(
            scene: store.liveScene,
            title: "Program",
            isLive: true,
            isEditable: false
        )
    }
}

struct PreviewMonitorView: View {
    @Environment(ShowStore.self) private var store

    var body: some View {
        StageMonitorView(
            scene: store.activeScene,
            title: "Preview",
            isLive: false,
            isEditable: true
        )
    }
}
