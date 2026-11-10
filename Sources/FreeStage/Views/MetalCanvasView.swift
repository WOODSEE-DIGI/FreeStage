//
//  MetalCanvasView.swift
//  FreeStage
//
//  MTKView wrapper that renders a scene (plus optional global layers) through StageRenderer.
//

import SwiftUI
import MetalKit
import CoreVideo
import CoreMedia

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
    var screenCaptureManager: ScreenCaptureManager
    var fpsCounter: FpsCounter?
    var virtualCamera: VirtualCameraOutputService?
    var recordingService: RecordingService?
    var streamingService: StreamingService?
    var trackingService: FacePuppetTrackingService?

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
        context.coordinator.virtualCamera = virtualCamera
        context.coordinator.recordingService = recordingService
        context.coordinator.streamingService = streamingService
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            captureManager: captureManager,
            screenCaptureManager: screenCaptureManager,
            fpsCounter: fpsCounter,
            virtualCamera: virtualCamera,
            recordingService: recordingService,
            streamingService: streamingService,
            trackingService: trackingService
        )
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        let device: MTLDevice
        private let renderer: StageRenderer
        private let commandQueue: MTLCommandQueue
        private let fpsCounter: FpsCounter?
        private let syphon: SyphonOutputService?
        var virtualCamera: VirtualCameraOutputService?
        var recordingService: RecordingService?
        var streamingService: StreamingService?
        private let textureCache: CVMetalTextureCache
        private let programPixelBufferPool: CVPixelBufferPool
        private let programPixelBufferAuxAttributes: NSDictionary
        private var recordingPixelBufferPool: CVPixelBufferPool?
        private var recordingPoolSize: CGSize = .zero
        var scene: Scene?
        var globalLayers: [Layer] = []

        init(
            captureManager: CameraCaptureManager,
            screenCaptureManager: ScreenCaptureManager,
            fpsCounter: FpsCounter?,
            virtualCamera: VirtualCameraOutputService?,
            recordingService: RecordingService?,
            streamingService: StreamingService?,
            trackingService: FacePuppetTrackingService?
        ) {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let commandQueue = device.makeCommandQueue() else {
                fatalError("Metal is not available on this Mac.")
            }
            self.device = device
            self.commandQueue = commandQueue
            self.renderer = try! StageRenderer(
                captureManager: captureManager,
                screenCaptureManager: screenCaptureManager,
                trackingService: trackingService
            )
            self.syphon = SyphonOutputService(device: device)
            self.virtualCamera = virtualCamera
            self.recordingService = recordingService
            self.streamingService = streamingService
            self.fpsCounter = fpsCounter

            var cache: CVMetalTextureCache?
            CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
            guard let textureCache = cache else {
                fatalError("Failed to create CVMetalTextureCache")
            }
            self.textureCache = textureCache

            let programPixelBufferAttributes: NSDictionary = [
                kCVPixelBufferWidthKey: freeStageCameraWidth,
                kCVPixelBufferHeightKey: freeStageCameraHeight,
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferMetalCompatibilityKey: true,
                kCVPixelBufferIOSurfacePropertiesKey: [:]
            ]
            var programPool: CVPixelBufferPool?
            let programErr = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, programPixelBufferAttributes, &programPool)
            guard programErr == noErr, let programPool else {
                fatalError("Failed to create CVPixelBufferPool: \(programErr)")
            }
            self.programPixelBufferPool = programPool
            self.programPixelBufferAuxAttributes = [kCVPixelBufferPoolAllocationThresholdKey: 5]

            super.init()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue.makeCommandBuffer() else { return }

            do {
                // Always render the program output to a fixed-size pixel buffer
                // so the virtual camera and recording get a stable resolution.
                guard let programPixelBuffer = createPixelBuffer() else {
                    throw MetalCanvasError.pixelBufferTextureCreationFailed
                }
                guard let programTexture = texture(from: programPixelBuffer) else {
                    throw MetalCanvasError.pixelBufferTextureCreationFailed
                }

                if let scene {
                    try renderer.render(
                        scene: scene,
                        globalLayers: globalLayers,
                        into: programTexture,
                        commandBuffer: commandBuffer
                    )
                } else {
                    try renderer.clear(outputTexture: programTexture, commandBuffer: commandBuffer)
                }

                // Present the program output on the on-screen drawable.
                try renderer.blit(sourceTexture: programTexture, destinationTexture: drawable.texture, commandBuffer: commandBuffer)

                syphon?.publish(programTexture, commandBuffer: commandBuffer)
                commandBuffer.present(drawable)
                commandBuffer.commit()

                // Hand the program frame to outputs after the GPU is done.
                commandBuffer.waitUntilCompleted()
                let timestamp = CMClockGetTime(CMClockGetHostTimeClock())
                DispatchQueue.main.async { [weak self] in
                    self?.virtualCamera?.enqueue(programPixelBuffer)
                    self?.recordingService?.appendVideo(pixelBuffer: programPixelBuffer, presentationTime: timestamp)
                    self?.streamingService?.appendVideo(pixelBuffer: programPixelBuffer, presentationTime: timestamp)
                }

                // If recording is active, produce a separately scaled buffer at the recording resolution.
                if let recordingService = recordingService, recordingService.isRecording {
                    scaleAndAppendRecording(programPixelBuffer: programPixelBuffer, at: timestamp)
                }

                fpsCounter?.tick()
            } catch {
                print("Render error: \(error)")
            }
        }

        private func scaleAndAppendRecording(programPixelBuffer: CVPixelBuffer, at timestamp: CMTime) {
            guard let recordingService = recordingService else { return }
            let size = recordingService.recordingSize
            guard size.width > 0, size.height > 0 else { return }

            guard let pool = ensureRecordingPool(size: size) else { return }

            var scaledPixelBuffer: CVPixelBuffer?
            let auxAttributes: NSDictionary = [kCVPixelBufferPoolAllocationThresholdKey: 3]
            let createErr = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
                kCFAllocatorDefault,
                pool,
                auxAttributes,
                &scaledPixelBuffer
            )
            guard createErr == noErr, let scaledPixelBuffer else { return }

            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let programTexture = texture(from: programPixelBuffer),
                  let scaledTexture = texture(from: scaledPixelBuffer) else { return }

            do {
                try renderer.blit(sourceTexture: programTexture, destinationTexture: scaledTexture, commandBuffer: commandBuffer)
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                recordingService.appendVideo(pixelBuffer: scaledPixelBuffer, presentationTime: timestamp)
            } catch {
                print("Recording scale error: \(error)")
            }
        }

        private func createPixelBuffer() -> CVPixelBuffer? {
            var pixelBuffer: CVPixelBuffer?
            let err = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
                kCFAllocatorDefault,
                programPixelBufferPool,
                programPixelBufferAuxAttributes,
                &pixelBuffer
            )
            guard err == noErr else { return nil }
            return pixelBuffer
        }

        private func ensureRecordingPool(size: CGSize) -> CVPixelBufferPool? {
            if recordingPoolSize == size, let pool = recordingPixelBufferPool {
                return pool
            }
            recordingPixelBufferPool = nil
            recordingPoolSize = .zero

            let attributes: NSDictionary = [
                kCVPixelBufferWidthKey: Int(size.width),
                kCVPixelBufferHeightKey: Int(size.height),
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferMetalCompatibilityKey: true,
                kCVPixelBufferIOSurfacePropertiesKey: [:]
            ]
            var pool: CVPixelBufferPool?
            let err = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes, &pool)
            guard err == noErr, let pool else { return nil }
            recordingPixelBufferPool = pool
            recordingPoolSize = size
            return pool
        }

        private func texture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
            var cvTexture: CVMetalTexture?
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let status = CVMetalTextureCacheCreateTextureFromImage(
                nil,
                textureCache,
                pixelBuffer,
                nil,
                .bgra8Unorm,
                width,
                height,
                0,
                &cvTexture
            )
            guard status == kCVReturnSuccess, let cvTexture else { return nil }
            return CVMetalTextureGetTexture(cvTexture)
        }
    }
}

enum MetalCanvasError: Error {
    case pixelBufferTextureCreationFailed
}
