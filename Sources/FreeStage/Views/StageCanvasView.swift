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
    @Environment(\.cameraCaptureManager) private var captureManager

    let scene: Scene?
    let title: String
    let isLive: Bool
    let isEditable: Bool
    @StateObject private var fpsCounter = FpsCounter()

    var body: some View {
        VStack(spacing: 0) {
            monitorHeader

            if let captureManager {
                MetalCanvasView(
                    scene: scene,
                    globalLayers: store.show.globalLayers,
                    captureManager: captureManager,
                    fpsCounter: fpsCounter
                )
                .aspectRatio(16 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .overlay(
                    Group {
                        if isEditable {
                            LayerOverlayView()
                        }
                    }
                )
            } else {
                Color.black
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        Text("Camera capture manager not available")
                            .foregroundStyle(.secondary)
                    )
            }

            monitorFooter
        }
    }

    private var monitorHeader: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: isLive ? "record.circle" : "eye")
                    .foregroundStyle(isLive ? .red : .accentColor)
                Text(title)
                    .font(.headline)
            }

            Spacer()

            Text(scene?.name ?? "No Scene")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    private var monitorFooter: some View {
        HStack {
            let visibleCount = (scene?.layers.filter(\.isVisible).count ?? 0)
                + store.show.globalLayers.filter(\.isVisible).count
            Text("\(visibleCount) visible layer(s)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(fpsCounter.fps, specifier: "%.0f") fps")
                .font(.caption.monospacedDigit())
                .foregroundStyle(fpsCounter.fps < 20 ? .red : .secondary)

            if isLive {
                Text("LIVE")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
            } else {
                Text("PREVIEW")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
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
