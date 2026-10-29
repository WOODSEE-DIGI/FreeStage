//
//  TextSourceRenderer.swift
//  FreeStage
//
//  Renders a TextSource into a Metal texture by rasterising the string with
//  Core Graphics and Core Image. Text is centered on a full-size canvas so it
//  can be positioned and scaled with the layer transform.
//

import Metal
import CoreGraphics
import CoreImage
import AppKit
import OSLog

final class TextSourceRenderer: SourceRenderer, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "TextSource")

    private struct CacheEntry {
        let source: TextSource
        let texture: MTLTexture
    }

    private var cache: [UUID: CacheEntry] = [:]
    private let cacheLock = NSLock()

    private var ciContext: CIContext?
    private let ciContextLock = NSLock()

    func render(
        source: Source,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> MTLTexture? {
        guard case .text(let textSource) = source else { return nil }

        cacheLock.lock()
        if let cached = cache[textSource.id], cached.source == textSource {
            let texture = cached.texture
            cacheLock.unlock()
            return texture
        }
        cacheLock.unlock()

        return autoreleasepool { () -> MTLTexture? in
            let width = Int(freeStageCameraWidth)
            let height = Int(freeStageCameraHeight)

            let descriptor = MTLTextureDescriptor()
            descriptor.width = width
            descriptor.height = height
            descriptor.pixelFormat = .rgba8Unorm
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                Self.logger.error("Failed to create text texture")
                return nil
            }

            ciContextLock.lock()
            if ciContext == nil {
                ciContext = CIContext(mtlDevice: device)
            }
            guard let context = ciContext else {
                ciContextLock.unlock()
                return nil
            }

            guard let cgImage = renderCGImage(textSource: textSource, size: CGSize(width: width, height: height)) else {
                ciContextLock.unlock()
                return nil
            }

            let ciImage = CIImage(cgImage: cgImage)
            let flipped = ciImage
                .transformed(by: CGAffineTransform(scaleX: 1, y: -1))
                .transformed(by: CGAffineTransform(translationX: 0, y: ciImage.extent.height))

            context.render(flipped, to: texture, commandBuffer: nil, bounds: ciImage.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
            ciContextLock.unlock()

            cacheLock.lock()
            cache[textSource.id] = CacheEntry(source: textSource, texture: texture)
            cacheLock.unlock()

            return texture
        }
    }

    private func renderCGImage(textSource: TextSource, size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        // Background fill (clear by default).
        if let backgroundColor = textSource.backgroundColor {
            let bg = backgroundColor
            context.setFillColor(CGColor(red: bg.r, green: bg.g, blue: bg.b, alpha: bg.a))
        } else {
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
        }
        context.fill(CGRect(origin: .zero, size: size))

        let text = textSource.content
        guard !text.isEmpty else { return context.makeImage() }

        let fontSize = max(CGFloat(textSource.fontSize), 8)
        let font: NSFont
        if let fontName = textSource.fontName,
           let customFont = NSFont(name: fontName, size: fontSize) {
            font = customFont
        } else {
            font = NSFont.systemFont(ofSize: fontSize)
        }

        let fg = textSource.color
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(red: fg.r, green: fg.g, blue: fg.b, alpha: fg.a)
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)

        let textSize = attributed.size()
        let location = CGPoint(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2
        )
        attributed.draw(at: location)

        return context.makeImage()
    }
}
