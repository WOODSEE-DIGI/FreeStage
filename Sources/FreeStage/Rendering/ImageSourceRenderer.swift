//
//  ImageSourceRenderer.swift
//  FreeStage
//
//  Loads a still image into a Metal texture using Core Image.
//

import Metal
import CoreImage
import OSLog

struct ImageSourceRenderer: SourceRenderer {
    private static let logger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "ImageSource")

    func render(
        source: Source,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> MTLTexture? {
        guard case .image(let url) = source else { return nil }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            Self.logger.error("CGImageSourceCreateWithURL failed for \(url.path)")
            return nil
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            Self.logger.error("CGImageSourceCreateImageAtIndex failed for \(url.path)")
            return nil
        }

        let descriptor = MTLTextureDescriptor()
        descriptor.width = cgImage.width
        descriptor.height = cgImage.height
        descriptor.pixelFormat = .rgba8Unorm
        // CIContext.render writes into the texture, so it needs shaderWrite
        // (and renderTarget for the Core Image path). shaderRead is for the
        // compute kernel that samples it later.
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            Self.logger.error("makeTexture failed (\(cgImage.width)x\(cgImage.height))")
            return nil
        }

        let ciContext = CIContext(mtlDevice: device)
        let ciImage = CIImage(cgImage: cgImage)

        // Core Image uses a bottom-left origin, but a Metal texture sampled by
        // a compute kernel (gid) has its first row at the top. Rendering the
        // CIImage directly therefore lands vertically flipped. Flip it here so
        // the stored texture is upright for any downstream reader.
        let flipped = ciImage
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .transformed(by: CGAffineTransform(translationX: 0, y: ciImage.extent.height))

        ciContext.render(flipped, to: texture, commandBuffer: nil, bounds: ciImage.extent, colorSpace: CGColorSpaceCreateDeviceRGB())

        Self.logger.info("Loaded image texture \(cgImage.width)x\(cgImage.height) from \(url.lastPathComponent)")
        return texture
    }
}
