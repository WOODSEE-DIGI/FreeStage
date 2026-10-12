//
//  MetalCanvasView.swift
//  FreeStage
//
//  MTKView wrapper that renders a scene (plus optional global layers) through StageRenderer.
//

import SwiftUI
import MetalKit

/// Rolling FPS meter updated by the render loop and observed by the monitor
/// footer. Updates are throttled to ~2 Hz so SwiftUI isn't flooded.
/// `tick` is only called from the MTKView draw callback (one thread) and `fps`
/// is only mutated on the main queue, so the split access is safe in practice.
final class FpsCounter: ObservableObject, @unchecked Sendable {
    @Published var fps: Double = 0
    private var timestamps: [CFTimeInterval] = []
    private var lastPublish: CFTimeInterval = 0
    private let window: CFTimeInterval = 1.0

    func tick(_ now: CFTimeInterval = CACurrentMediaTime()) {
        timestamps.append(now)
        // Keep only samples inside the rolling window (last `window` seconds).
        // NOTE: cutoff must be an absolute time (now - window). Using
        // `last(where:)` here would return the newest sample and collapse the
        // array to a single element, reading a constant 1 fps.
        let cutoff = now - window
        timestamps.removeAll { $0 < cutoff }

        guard now - lastPublish >= 0.5 else { return }
        lastPublish = now
        let count = Double(timestamps.count)
        let span = (timestamps.last ?? now) - (timestamps.first ?? now)
        let value = span > 0 ? count / span : count
        DispatchQueue.main.async { [weak self] in
            self?.fps = value
        }
    }
}

struct MetalCanvasView: NSViewRepresentable {
    var scene: Scene?
    var globalLayers: [Layer]
    var captureManager: CameraCaptureManager
    var fpsCounter: FpsCounter?

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = context.coordinator.device
        mtkView.delegate = context.coordinator
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.scene = scene
        context.coordinator.globalLayers = globalLayers
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(captureManager: captureManager, fpsCounter: fpsCounter)
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        let device: MTLDevice
        private let renderer: StageRenderer
        private let commandQueue: MTLCommandQueue
        private let fpsCounter: FpsCounter?
        var scene: Scene?
        var globalLayers: [Layer] = []

        init(captureManager: CameraCaptureManager, fpsCounter: FpsCounter?) {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let commandQueue = device.makeCommandQueue() else {
                fatalError("Metal is not available on this Mac.")
            }
            self.device = device
            self.commandQueue = commandQueue
            self.renderer = try! StageRenderer(captureManager: captureManager)
            self.fpsCounter = fpsCounter
            super.init()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue.makeCommandBuffer() else { return }

            do {
                if let scene {
                    try renderer.render(
                        scene: scene,
                        globalLayers: globalLayers,
                        into: drawable.texture,
                        commandBuffer: commandBuffer
                    )
                } else {
                    // No scene: clear the drawable so it doesn't show stale content.
                    try renderer.clear(outputTexture: drawable.texture, commandBuffer: commandBuffer)
                }
                commandBuffer.present(drawable)
                commandBuffer.commit()
                fpsCounter?.tick()
            } catch {
                print("Render error: \(error)")
            }
        }
    }
}
