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
        // No frame yet: return a no-signal pattern so the layer bounds are
        // visible while the camera warms up, but it no longer looks like a
        // chroma-key artefact.
        return CameraSourceRenderer.placeholderTexture(device: device)
    }

    private static func placeholderTexture(device: MTLDevice) -> MTLTexture? {
        let size = 64
        let descriptor = MTLTextureDescriptor()
        descriptor.width = size
        descriptor.height = size
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        // Diagonal no-signal stripes: dark grey / safety orange.
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let stripe = 8
        for y in 0..<size {
            for x in 0..<size {
                let band = (x + y) / stripe
                let signal = band % 2 == 0
                let r: UInt8 = signal ? 200 : 30
                let g: UInt8 = signal ? 120 : 30
                let b: UInt8 = signal ? 0 : 30
                let base = (y * size + x) * 4
                pixels[base] = r
                pixels[base + 1] = g
                pixels[base + 2] = b
                pixels[base + 3] = 255
            }
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: size * 4
        )
        return texture
    }
}
