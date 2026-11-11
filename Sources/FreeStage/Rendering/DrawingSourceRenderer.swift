//
//  DrawingSourceRenderer.swift
//  FreeStage
//
//  Renders a DrawingSource into a Metal texture by rasterising strokes, shapes,
//  and text with Core Graphics. Strokes are stored in normalized coordinates and
//  scaled to the source's canvas size.
//
//  The renderer is a class so it can cache the rendered texture per source ID
//  and only re-render when the drawing actually changes. This avoids repeating
//  expensive Core Graphics / Core Image work every frame and removes the
//  previous risk of concurrent access during continuous edits.
//

import Metal
import CoreGraphics
import CoreImage
import AppKit
import OSLog

final class DrawingSourceRenderer: SourceRenderer, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "DrawingSource")

    private struct CacheEntry {
        let source: DrawingSource
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
        guard case .drawing(let drawing) = source else { return nil }

        // Cached? Return the existing texture.
        cacheLock.lock()
        if let cached = cache[drawing.id], cached.source == drawing {
            let texture = cached.texture
            cacheLock.unlock()
            return texture
        }
        cacheLock.unlock()

        return autoreleasepool { () -> MTLTexture? in
            let size = drawing.canvasSize
            let width = Int(size.width)
            let height = Int(size.height)
            guard width > 0, height > 0 else { return nil }

            let descriptor = MTLTextureDescriptor()
            descriptor.width = width
            descriptor.height = height
            descriptor.pixelFormat = .rgba8Unorm
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                Self.logger.error("Failed to create drawing texture")
                return nil
            }

            // Lazily create and reuse a single CIContext.
            ciContextLock.lock()
            if ciContext == nil {
                ciContext = CIContext(mtlDevice: device)
            }
            guard let context = ciContext else {
                ciContextLock.unlock()
                return nil
            }

            guard let cgImage = renderCGImage(drawing: drawing, size: CGSize(width: width, height: height)) else {
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
            cache[drawing.id] = CacheEntry(source: drawing, texture: texture)
            cacheLock.unlock()

            return texture
        }
    }

    private func renderCGImage(drawing: DrawingSource, size: CGSize) -> CGImage? {
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

        // Clear/background.
        let bg = drawing.backgroundColor
        context.setFillColor(CGColor(red: bg.r, green: bg.g, blue: bg.b, alpha: bg.a))
        context.fill(CGRect(origin: .zero, size: size))

        for stroke in drawing.strokes {
            drawStroke(stroke, in: context, size: size)
        }

        return context.makeImage()
    }

    private func drawStroke(_ stroke: DrawingStroke, in context: CGContext, size: CGSize) {
        switch stroke.tool {
        case .pen, .eraser:
            drawFreehandStroke(stroke, in: context, size: size)
        case .rectangle:
            drawRectangle(stroke, in: context, size: size)
        case .ellipse:
            drawEllipse(stroke, in: context, size: size)
        case .line, .arrow:
            drawLineOrArrow(stroke, in: context, size: size)
        case .text:
            drawText(stroke, in: context, size: size)
        }
    }

    private func drawFreehandStroke(_ stroke: DrawingStroke, in context: CGContext, size: CGSize) {
        guard stroke.points.count > 1 else { return }
        let path = CGMutablePath()
        let first = stroke.points[0]
        path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
        for point in stroke.points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
        }

        context.setLineWidth(CGFloat(stroke.width))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch stroke.tool {
        case .pen:
            let c = stroke.color
            context.setStrokeColor(CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a))
            context.setBlendMode(.normal)
        case .eraser:
            context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
            context.setBlendMode(.clear)
        default:
            return
        }

        context.addPath(path)
        context.strokePath()
    }

    private func drawRectangle(_ stroke: DrawingStroke, in context: CGContext, size: CGSize) {
        guard stroke.points.count >= 2 else { return }
        let start = CGPoint(x: stroke.points[0].x * size.width, y: stroke.points[0].y * size.height)
        let end = CGPoint(x: stroke.points[1].x * size.width, y: stroke.points[1].y * size.height)
        let rect = CGRect(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y)).standardized

        let c = stroke.color
        context.setStrokeColor(CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a))
        context.setLineWidth(CGFloat(stroke.width))
        context.setLineJoin(.round)
        context.setBlendMode(.normal)
        context.stroke(rect)
    }

    private func drawEllipse(_ stroke: DrawingStroke, in context: CGContext, size: CGSize) {
        guard stroke.points.count >= 2 else { return }
        let start = CGPoint(x: stroke.points[0].x * size.width, y: stroke.points[0].y * size.height)
        let end = CGPoint(x: stroke.points[1].x * size.width, y: stroke.points[1].y * size.height)
        let rect = CGRect(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y)).standardized

        let c = stroke.color
        context.setStrokeColor(CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a))
        context.setLineWidth(CGFloat(stroke.width))
        context.setBlendMode(.normal)
        context.strokeEllipse(in: rect)
    }

    private func drawLineOrArrow(_ stroke: DrawingStroke, in context: CGContext, size: CGSize) {
        guard stroke.points.count >= 2 else { return }
        let start = CGPoint(x: stroke.points[0].x * size.width, y: stroke.points[0].y * size.height)
        let end = CGPoint(x: stroke.points[1].x * size.width, y: stroke.points[1].y * size.height)

        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)

        let c = stroke.color
        context.setStrokeColor(CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a))
        context.setLineWidth(CGFloat(stroke.width))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setBlendMode(.normal)
        context.addPath(path)
        context.strokePath()

        if stroke.tool == .arrow {
            drawArrowhead(at: end, from: start, in: context, color: c, width: stroke.width)
        }
    }

    private func drawArrowhead(at tip: CGPoint, from start: CGPoint, in context: CGContext, color: CGColorComponents, width: Double) {
        let angle = atan2(tip.y - start.y, tip.x - start.x)
        let headLength = CGFloat(max(width * 3, 12))
        let headAngle: CGFloat = .pi / 6

        let left = CGPoint(
            x: tip.x - headLength * cos(angle - headAngle),
            y: tip.y - headLength * sin(angle - headAngle)
        )
        let right = CGPoint(
            x: tip.x - headLength * cos(angle + headAngle),
            y: tip.y - headLength * sin(angle + headAngle)
        )

        let path = CGMutablePath()
        path.move(to: tip)
        path.addLine(to: left)
        path.move(to: tip)
        path.addLine(to: right)

        context.setStrokeColor(CGColor(red: color.r, green: color.g, blue: color.b, alpha: color.a))
        context.setLineWidth(CGFloat(width))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()
    }

    private func drawText(_ stroke: DrawingStroke, in context: CGContext, size: CGSize) {
        guard stroke.points.count >= 1,
              let text = stroke.text, !text.isEmpty else { return }
        let point = stroke.points[0]
        let location = CGPoint(x: point.x * size.width, y: point.y * size.height)
        let c = stroke.color

        let fontSize = max(CGFloat(stroke.width), 12)
        let font = CTFontCreateWithName("SFPro-Regular" as CFString, fontSize, nil)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font as Any,
            .foregroundColor: NSColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)

        // NSAttributedString.draw(at:) requires an NSGraphicsContext to be
        // current when drawing into a manually created CGContext.
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        attributed.draw(at: location)
        NSGraphicsContext.restoreGraphicsState()
    }
}
