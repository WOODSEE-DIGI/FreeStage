//
//  CameraSourceRenderer.swift
//  FreeStage
//
//  Renders a live camera source by sampling the latest frame from the
//  CameraCaptureManager.
//

import Metal

struct CameraSourceRenderer: SourceRenderer {
    private let captureManager: CameraCaptureManager

    init(captureManager: CameraCaptureManager) {
        self.captureManager = captureManager
    }

    func render(
        source: Source,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> MTLTexture? {
        guard case .camera(let uniqueID) = source else { return nil }
        if let texture = captureManager.texture(for: uniqueID) {
            return texture
        }
        // No frame yet: return a bright magenta 1x1 placeholder so the layer
        // bounds are visible while the camera warms up.
        return CameraSourceRenderer.placeholderTexture(device: device)
    }

    private static func placeholderTexture(device: MTLDevice) -> MTLTexture? {
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
