//
//  ColorSourceRenderer.swift
//  FreeStage
//
//  Renders a solid color source as a 1×1 Metal texture.
//

import Metal

struct ColorSourceRenderer: SourceRenderer {
    /// Shared cache so we don't allocate a new 1×1 texture every frame for a
    /// static solid-color layer. Keyed by the quantized RGBA bytes.
    private static let cache = ColorTextureCache()

    func render(
        source: Source,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> MTLTexture? {
        guard case .color(let components) = source else { return nil }

        var pixel = SIMD4<UInt8>(
            UInt8(max(0, min(255, components.r * 255))),
            UInt8(max(0, min(255, components.g * 255))),
            UInt8(max(0, min(255, components.b * 255))),
            UInt8(max(0, min(255, components.a * 255)))
        )

        if let cached = Self.cache.texture(for: pixel) {
            return cached
        }

        let descriptor = MTLTextureDescriptor()
        descriptor.width = 1
        descriptor.height = 1
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &pixel,
            bytesPerRow: 4
        )

        Self.cache.store(texture, for: pixel)
        return texture
    }
}

/// Thread-safe cache of 1×1 color textures keyed by RGBA bytes.
private final class ColorTextureCache: @unchecked Sendable {
    private var cache: [SIMD4<UInt8>: MTLTexture] = [:]
    private let lock = NSLock()

    func texture(for pixel: SIMD4<UInt8>) -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        return cache[pixel]
    }

    func store(_ texture: MTLTexture, for pixel: SIMD4<UInt8>) {
        lock.lock()
        defer { lock.unlock() }
        cache[pixel] = texture
    }
}
