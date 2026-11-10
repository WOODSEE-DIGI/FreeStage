//
//  StageRenderer.swift
//  FreeStage
//
//  Metal-based scene renderer. Composites all visible layers (scene-local plus
//  optional global show layers) and writes the program output texture.
//

import Metal
import OSLog

final class StageRenderer: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "StageRenderer")

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let layerRenderer: LayerRenderer
    private let clearPipelineState: MTLComputePipelineState
    private let blitPipelineState: MTLComputePipelineState
    private let sourceRegistry: SourceRendererRegistry
    /// Cache of already-decoded image textures keyed by source, so still
    /// images used as backgrounds (or layers) aren't re-decoded every frame.
    private let imageCache = ImageTextureCache()

    init(
        captureManager: CameraCaptureManager,
        screenCaptureManager: ScreenCaptureManager,
        trackingService: FacePuppetTrackingService? = nil
    ) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw StageRendererError.noDevice
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw StageRendererError.noCommandQueue
        }
        self.device = device
        self.commandQueue = commandQueue
        self.layerRenderer = try LayerRenderer(device: device)
        self.sourceRegistry = SourceRendererRegistry(
            captureManager: captureManager,
            screenCaptureManager: screenCaptureManager,
            trackingService: trackingService
        )

        // Compile the clear pipeline once; recompiling it per frame is very costly.
        let library = try device.makeDefaultLibrary(bundle: Bundle(for: BundleFinder.self))
        guard let clearFunction = library.makeFunction(name: "clearOutput") else {
            throw StageRendererError.kernelNotFound
        }
        self.clearPipelineState = try device.makeComputePipelineState(function: clearFunction)

        guard let blitFunction = library.makeFunction(name: "blitScaled") else {
            throw StageRendererError.kernelNotFound
        }
        self.blitPipelineState = try device.makeComputePipelineState(function: blitFunction)
    }

    /// Encode the scene composite into the *provided* command buffer. The caller
    /// owns commit/present, so the GPU runs clear → layers → present in order on
    /// a single buffer without a CPU-side wait.
    func render(
        scene: Scene,
        globalLayers: [Layer] = [],
        into outputTexture: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) throws {
        // Clear the output to transparent black.
        try clear(outputTexture: outputTexture, commandBuffer: commandBuffer)

        // Composite each visible layer back-to-front: scene layers first, then globals.
        let allLayers = scene.layers + globalLayers
        for layer in allLayers where layer.isVisible {
            guard let sourceTexture = try sourceRegistry.render(
                source: layer.source,
                device: device,
                commandQueue: commandQueue
            ) else { continue }

            let backgroundTexture = try backgroundTexture(for: layer)

            try layerRenderer.render(
                layer: layer,
                sourceTexture: sourceTexture,
                backgroundTexture: backgroundTexture,
                outputTexture: outputTexture,
                commandBuffer: commandBuffer
            )
        }
    }

    private func backgroundTexture(for layer: Layer) throws -> MTLTexture? {
        for filter in layer.filters {
            if case .chromaKey(let keyFilter) = filter,
               let backgroundSource = keyFilter.backgroundSource {
                switch backgroundSource.kind {
                case .image:
                    if let cached = imageCache.texture(for: backgroundSource) {
                        return cached
                    }
                    let texture = try sourceRegistry.render(
                        source: backgroundSource,
                        device: device,
                        commandQueue: commandQueue
                    )
                    if let texture {
                        imageCache.store(texture, for: backgroundSource)
                    } else {
                        Self.logger.warning("Background image failed to load: \(backgroundSource.defaultName)")
                    }
                    return texture
                default:
                    return try sourceRegistry.render(
                        source: backgroundSource,
                        device: device,
                        commandQueue: commandQueue
                    )
                }
            }
        }
        return nil
    }

    /// Blit a source texture into a destination texture of a different size.
    /// Used to present the program output onto the on-screen drawable.
    func blit(sourceTexture: MTLTexture, destinationTexture: MTLTexture, commandBuffer: MTLCommandBuffer) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw StageRendererError.encodeFailed
        }
        encoder.setComputePipelineState(blitPipelineState)
        encoder.setTexture(sourceTexture, index: 0)
        encoder.setTexture(destinationTexture, index: 1)
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (destinationTexture.width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (destinationTexture.height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
    }

    /// Clear the output texture to transparent black. Also used by the view
    /// when there is no active scene to present.
    func clear(outputTexture: MTLTexture, commandBuffer: MTLCommandBuffer) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw StageRendererError.encodeFailed
        }
        encoder.setComputePipelineState(clearPipelineState)
        encoder.setTexture(outputTexture, index: 0)
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (outputTexture.width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (outputTexture.height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
    }
}

enum StageRendererError: Error {
    case noDevice
    case noCommandQueue
    case encodeFailed
    case kernelNotFound
    case metalError(String)
}

/// Simple thread-safe cache for decoded image textures keyed by `Source`.
/// Avoids re-decoding the same still image on every frame.
private final class ImageTextureCache: @unchecked Sendable {
    private var cache: [Source: MTLTexture] = [:]
    private let lock = NSLock()

    func texture(for source: Source) -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        return cache[source]
    }

    func store(_ texture: MTLTexture, for source: Source) {
        lock.lock()
        defer { lock.unlock() }
        cache[source] = texture
    }
}

private final class BundleFinder {}
