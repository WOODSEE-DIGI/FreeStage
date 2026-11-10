//
//  FacePuppetSourceRenderer.swift
//  FreeStage
//
//  Renders Face Puppet sources: a textured puppet wrap composited over the
//  live camera frame, or a mesh-only wireframe preview for adjusting anchors.
//

import Metal
import CoreVideo
import OSLog
import simd

struct FacePuppetSourceRenderer: SourceRenderer {
    static let logger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "FacePuppet")

    private let captureManager: CameraCaptureManager
    private let imageRenderer = ImageSourceRenderer()
    let tracker: FaceMeshTracker?
    private let resources = FacePuppetRenderResources()
    private let puppetTextureCache = PuppetTextureCache()

    init(
        captureManager: CameraCaptureManager,
        trackingService: FacePuppetTrackingService? = nil
    ) {
        self.captureManager = captureManager
        self.trackingService = trackingService
        self.tracker = FaceMeshTracker()
        self.tracker?.trackingService = trackingService
        if tracker == nil {
            Self.logger.error("Failed to initialize MediaPipe face mesh tracker.")
        }
    }

    private let trackingService: FacePuppetTrackingService?

    func render(
        source: Source,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> MTLTexture? {
        let cameraID: String
        let puppetImageURL: URL?
        let anchorMap: FacePuppetAnchorMap?
        let isMesh: Bool

        switch source {
        case .facePuppet(let id, let url):
            cameraID = id
            puppetImageURL = url
            anchorMap = nil
            isMesh = false
        case .facePuppetAnchored(let id, let url, let map):
            cameraID = id
            puppetImageURL = url
            anchorMap = map
            isMesh = false
        case .facePuppetMesh(let id, let map):
            cameraID = id
            puppetImageURL = nil
            anchorMap = map
            isMesh = true
        default:
            return nil
        }

        captureManager.startCapture(uniqueID: cameraID)

        guard let cameraTexture = captureManager.texture(for: cameraID) else {
            return placeholderTexture(device: device)
        }

        var puppetTexture: MTLTexture?
        if let puppetImageURL {
            puppetTexture = try puppetTextureCache.texture(
                for: puppetImageURL,
                device: device,
                renderer: imageRenderer,
                commandQueue: commandQueue
            )
            if puppetTexture == nil {
                Self.logger.warning("Failed to load puppet image \(puppetImageURL.path)")
            }
        }

        if !isMesh, puppetTexture == nil {
            return cameraTexture
        }

        if let pixelBuffer = captureManager.pixelBuffer(for: cameraID) {
            tracker?.enqueue(pixelBuffer)
        }

        guard let frame = tracker?.latestFrame else {
            Self.logger.debug("No face mesh frame available yet for \(cameraID)")
            return cameraTexture
        }
        guard frame.landmarks.count >= CanonicalFaceMeshData.vertexCount else {
            Self.logger.debug("Face mesh frame has \(frame.landmarks.count) landmarks, need \(CanonicalFaceMeshData.vertexCount)")
            return cameraTexture
        }

        resources.prepare(device: device)

        let meshVertices = buildMeshVertices(from: frame.landmarks, anchorMap: anchorMap)

        let descriptor = MTLTextureDescriptor()
        descriptor.width = cameraTexture.width
        descriptor.height = cameraTexture.height
        descriptor.pixelFormat = .bgra8Unorm
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let outputTexture = device.makeTexture(descriptor: descriptor),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return cameraTexture
        }

        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = outputTexture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            return cameraTexture
        }

        // 1. Full-screen camera background.
        encoder.setRenderPipelineState(resources.backgroundPipeline)
        encoder.setVertexBuffer(resources.backgroundVertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(cameraTexture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: resources.backgroundVertexCount)

        // 2. Puppet mesh or wireframe overlay.
        let vertexBuffer = device.makeBuffer(
            bytes: meshVertices,
            length: MemoryLayout<PuppetVertex>.stride * meshVertices.count,
            options: []
        )!
        var uniforms = PuppetFragmentUniforms(opacity: 0.9)
        let uniformBuffer = device.makeBuffer(
            bytes: &uniforms,
            length: MemoryLayout<PuppetFragmentUniforms>.stride,
            options: []
        )!

        if isMesh {
            encoder.setRenderPipelineState(resources.wireframePipeline)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
            encoder.setTriangleFillMode(.lines)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: CanonicalFaceMeshData.indices.count,
                indexType: .uint16,
                indexBuffer: resources.indexBuffer,
                indexBufferOffset: 0
            )
            encoder.setTriangleFillMode(.fill)
        } else if let puppetTexture {
            encoder.setRenderPipelineState(resources.puppetPipeline)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
            encoder.setFragmentTexture(cameraTexture, index: 0)
            encoder.setFragmentTexture(puppetTexture, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: CanonicalFaceMeshData.indices.count,
                indexType: .uint16,
                indexBuffer: resources.indexBuffer,
                indexBufferOffset: 0
            )
        }

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return outputTexture
    }

    private func buildMeshVertices(
        from landmarks: [FaceMeshLandmark],
        anchorMap: FacePuppetAnchorMap?
    ) -> [PuppetVertex] {
        var vertices: [PuppetVertex] = []
        vertices.reserveCapacity(CanonicalFaceMeshData.vertexCount)
        let uvs = CanonicalFaceMeshData.uvs
        let offsets = anchorMap?.offsets ?? [:]
        for i in 0..<CanonicalFaceMeshData.vertexCount {
            let lm = landmarks[i]
            let offset = offsets[i] ?? .zero
            let x = Float(Double(lm.x) + offset.x)
            let y = Float(Double(lm.y) + offset.y)
            vertices.append(PuppetVertex(position: SIMD2<Float>(x, y), uv: uvs[i]))
        }
        return vertices
    }

    private func placeholderTexture(device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor()
        descriptor.width = 1
        descriptor.height = 1
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        var pixel = SIMD4<UInt8>(255, 0, 255, 255)
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &pixel, bytesPerRow: 4)
        return texture
    }
}

private struct PuppetVertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
}

private struct PuppetFragmentUniforms {
    var opacity: Float
}

// MARK: - Cached render resources

private final class FacePuppetRenderResources: @unchecked Sendable {
    private let lock = NSLock()
    private var isPrepared = false

    private(set) var backgroundPipeline: MTLRenderPipelineState!
    private(set) var puppetPipeline: MTLRenderPipelineState!
    private(set) var wireframePipeline: MTLRenderPipelineState!
    private(set) var backgroundVertexBuffer: MTLBuffer!
    private(set) var indexBuffer: MTLBuffer!
    let backgroundVertexCount: Int = 6

    func prepare(device: MTLDevice) {
        lock.lock()
        defer { lock.unlock() }
        guard !isPrepared else { return }

        do {
            let library = try device.makeDefaultLibrary(bundle: Bundle(for: BundleFinder.self))

            let vertexDescriptor = MTLVertexDescriptor()
            vertexDescriptor.attributes[0].format = .float2
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            vertexDescriptor.attributes[1].format = .float2
            vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
            vertexDescriptor.attributes[1].bufferIndex = 0
            vertexDescriptor.layouts[0].stride = MemoryLayout<PuppetVertex>.stride

            let backgroundDescriptor = MTLRenderPipelineDescriptor()
            backgroundDescriptor.vertexFunction = library.makeFunction(name: "puppetVertex")
            backgroundDescriptor.fragmentFunction = library.makeFunction(name: "copyCameraFragment")
            backgroundDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            backgroundDescriptor.vertexDescriptor = vertexDescriptor
            backgroundPipeline = try device.makeRenderPipelineState(descriptor: backgroundDescriptor)

            let puppetDescriptor = MTLRenderPipelineDescriptor()
            puppetDescriptor.vertexFunction = library.makeFunction(name: "puppetVertex")
            puppetDescriptor.fragmentFunction = library.makeFunction(name: "puppetFragment")
            puppetDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            puppetDescriptor.vertexDescriptor = vertexDescriptor
            puppetPipeline = try device.makeRenderPipelineState(descriptor: puppetDescriptor)

            let wireframeDescriptor = MTLRenderPipelineDescriptor()
            wireframeDescriptor.vertexFunction = library.makeFunction(name: "puppetVertex")
            wireframeDescriptor.fragmentFunction = library.makeFunction(name: "wireframeFragment")
            wireframeDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            wireframeDescriptor.vertexDescriptor = vertexDescriptor
            wireframePipeline = try device.makeRenderPipelineState(descriptor: wireframeDescriptor)

            let backgroundVertices: [PuppetVertex] = [
                PuppetVertex(position: SIMD2<Float>(0, 0), uv: SIMD2<Float>(0, 0)),
                PuppetVertex(position: SIMD2<Float>(1, 0), uv: SIMD2<Float>(1, 0)),
                PuppetVertex(position: SIMD2<Float>(0, 1), uv: SIMD2<Float>(0, 1)),
                PuppetVertex(position: SIMD2<Float>(1, 0), uv: SIMD2<Float>(1, 0)),
                PuppetVertex(position: SIMD2<Float>(1, 1), uv: SIMD2<Float>(1, 1)),
                PuppetVertex(position: SIMD2<Float>(0, 1), uv: SIMD2<Float>(0, 1)),
            ]
            backgroundVertexBuffer = device.makeBuffer(
                bytes: backgroundVertices,
                length: MemoryLayout<PuppetVertex>.stride * backgroundVertices.count,
                options: []
            )

            indexBuffer = device.makeBuffer(
                bytes: CanonicalFaceMeshData.indices,
                length: MemoryLayout<UInt16>.stride * CanonicalFaceMeshData.indices.count,
                options: []
            )

            isPrepared = true
        } catch {
            FacePuppetSourceRenderer.logger.error("Failed to prepare render resources: \(error.localizedDescription)")
        }
    }
}

/// Caches the decoded puppet texture so the image is not re-loaded from disk
/// on every frame. The cache key includes the file modification date so
/// replacing an image with the same filename still invalidates the old copy.
private final class PuppetTextureCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedKey: String?
    private var cachedTexture: MTLTexture?

    func texture(
        for url: URL,
        device: MTLDevice,
        renderer: ImageSourceRenderer,
        commandQueue: MTLCommandQueue
    ) throws -> MTLTexture? {
        let key = cacheKey(for: url)

        lock.lock()
        if key == cachedKey, let cachedTexture {
            lock.unlock()
            return cachedTexture
        }
        lock.unlock()

        guard let texture = try renderer.render(
            source: .image(url: url),
            device: device,
            commandQueue: commandQueue
        ) else {
            return nil
        }

        lock.lock()
        cachedKey = key
        cachedTexture = texture
        lock.unlock()
        return texture
    }

    private func cacheKey(for url: URL) -> String {
        let modification = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
            .flatMap { "\($0.timeIntervalSince1970)" } ?? "none"
        return "\(url.path)--\(modification)"
    }
}

private final class BundleFinder {}
