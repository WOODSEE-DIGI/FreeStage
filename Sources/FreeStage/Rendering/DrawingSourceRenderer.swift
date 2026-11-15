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
            let logicalSize = drawing.canvasSize
            guard logicalSize.width > 0, logicalSize.height > 0 else { return nil }

            // Render at 2× logical resolution so shapes stay sharp on Retina
            // displays and when scaled by layer transforms.
            let renderScale: CGFloat = 2
            let textureSize = CGSize(
                width: logicalSize.width * renderScale,
                height: logicalSize.height * renderScale
            )
            let width = Int(textureSize.width)
            let height = Int(textureSize.height)

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

            guard let cgImage = renderCGImage(
                drawing: drawing,
                logicalSize: logicalSize,
                renderScale: renderScale
            ) else {
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

    private func renderCGImage(
        drawing: DrawingSource,
        logicalSize: CGSize,
        renderScale: CGFloat
    ) -> CGImage? {
        let textureSize = CGSize(
            width: logicalSize.width * renderScale,
            height: logicalSize.height * renderScale
        )
        let width = Int(textureSize.width)
        let height = Int(textureSize.height)
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

        // Scale so that logical coordinates fill the high-resolution texture.
        context.scaleBy(x: renderScale, y: renderScale)

        // Clear/background.
        let bg = drawing.backgroundColor
        context.setFillColor(CGColor(red: bg.r, green: bg.g, blue: bg.b, alpha: bg.a))
        context.fill(CGRect(origin: .zero, size: logicalSize))

        // Enable smooth antialiasing for shape edges.
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)

        for stroke in drawing.strokes {
            drawStroke(stroke, in: context, size: logicalSize)
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

        let cornerRadius = CGFloat(min(stroke.cornerRadius * min(size.width, size.height), min(rect.width, rect.height) / 2))
        let roundedPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        fillShape(rect: rect, stroke: stroke, in: context, path: { ctx, _ in ctx.addPath(roundedPath) })
        strokePath(roundedPath, stroke: stroke, in: context, rect: rect)
    }

    private func drawEllipse(_ stroke: DrawingStroke, in context: CGContext, size: CGSize) {
        guard stroke.points.count >= 2 else { return }
        let start = CGPoint(x: stroke.points[0].x * size.width, y: stroke.points[0].y * size.height)
        let end = CGPoint(x: stroke.points[1].x * size.width, y: stroke.points[1].y * size.height)
        let rect = CGRect(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y)).standardized

        let ellipsePath = CGPath(ellipseIn: rect, transform: nil)
        fillShape(rect: rect, stroke: stroke, in: context, path: { ctx, _ in ctx.addPath(ellipsePath) })
        strokePath(ellipsePath, stroke: stroke, in: context, rect: rect)
    }

    private func strokePath(_ path: CGPath, stroke: DrawingStroke, in context: CGContext, rect: CGRect) {
        context.saveGState()
        context.addPath(path)
        context.setLineWidth(CGFloat(stroke.width))
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.setBlendMode(.normal)

        switch stroke.strokeStyle {
        case .solid:
            let c = stroke.color
            context.setStrokeColor(CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a))
            context.strokePath()
        case .gradient:
            context.replacePathWithStrokedPath()
            context.clip()
            drawLinearGradient(
                in: context,
                rect: rect,
                startColor: stroke.strokeGradientStartColor,
                endColor: stroke.strokeGradientEndColor,
                angle: stroke.strokeGradientAngle
            )
        case .none:
            break
        }

        context.restoreGState()
    }

    private func fillShape(
        rect: CGRect,
        stroke: DrawingStroke,
        in context: CGContext,
        path: ((CGContext, CGRect) -> Void)? = nil
    ) {
        switch stroke.fillStyle {
        case .none:
            return
        case .solid:
            let c = stroke.fillColor
            context.setFillColor(CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a))
            if let path {
                path(context, rect)
                context.fillPath()
            } else {
                context.fill(rect)
            }
        case .gradient:
            drawLinearGradient(
                in: context,
                rect: rect,
                startColor: stroke.gradientStartColor,
                endColor: stroke.gradientEndColor,
                angle: stroke.gradientAngle,
                path: path
            )
        }
    }

    private func drawLinearGradient(
        in context: CGContext,
        rect: CGRect,
        startColor: CGColorComponents,
        endColor: CGColorComponents,
        angle: Double,
        path: ((CGContext, CGRect) -> Void)? = nil
    ) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(red: startColor.r, green: startColor.g, blue: startColor.b, alpha: startColor.a),
                CGColor(red: endColor.r, green: endColor.g, blue: endColor.b, alpha: endColor.a)
            ] as CFArray,
            locations: [0, 1]
        ) else { return }

        let radians = CGFloat(angle * .pi / 180)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let halfDiagonal = CGFloat(sqrt(rect.width * rect.width + rect.height * rect.height) / 2)
        let start = CGPoint(
            x: center.x - halfDiagonal * cos(radians),
            y: center.y - halfDiagonal * sin(radians)
        )
        let end = CGPoint(
            x: center.x + halfDiagonal * cos(radians),
            y: center.y + halfDiagonal * sin(radians)
        )

        if let path {
            context.saveGState()
            path(context, rect)
            context.clip()
            context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            context.restoreGState()
        } else {
            context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }

    private func drawLineOrArrow(_ stroke: DrawingStroke, in context: CGContext, size: CGSize) {
        guard stroke.points.count >= 2 else { return }
        let start = CGPoint(x: stroke.points[0].x * size.width, y: stroke.points[0].y * size.height)
        let end = CGPoint(x: stroke.points[1].x * size.width, y: stroke.points[1].y * size.height)

        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)

        let lineRect = CGRect(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y)).standardized

        if stroke.strokeStyle == .gradient {
            context.saveGState()
            context.addPath(path)
            context.setLineWidth(CGFloat(stroke.width))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.replacePathWithStrokedPath()
            context.clip()
            drawLinearGradient(
                in: context,
                rect: lineRect,
                startColor: stroke.strokeGradientStartColor,
                endColor: stroke.strokeGradientEndColor,
                angle: stroke.strokeGradientAngle
            )
            context.restoreGState()
        } else if stroke.strokeStyle == .solid {
            let c = stroke.color
            context.setStrokeColor(CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a))
            context.setLineWidth(CGFloat(stroke.width))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setBlendMode(.normal)
            context.addPath(path)
            context.strokePath()
        }

        if stroke.tool == .arrow {
            drawArrowhead(at: end, from: start, in: context, stroke: stroke)
        }
    }

    private func drawArrowhead(at tip: CGPoint, from start: CGPoint, in context: CGContext, stroke: DrawingStroke) {
        let angle = atan2(tip.y - start.y, tip.x - start.x)
        let headLength = CGFloat(max(stroke.width * 3, 12))
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

        if stroke.strokeStyle == .gradient {
            context.saveGState()
            context.addPath(path)
            context.setLineWidth(CGFloat(stroke.width))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.replacePathWithStrokedPath()
            context.clip()
            let headRect = CGRect(origin: tip, size: .zero).insetBy(dx: -headLength * 2, dy: -headLength * 2)
            drawLinearGradient(
                in: context,
                rect: headRect,
                startColor: stroke.strokeGradientStartColor,
                endColor: stroke.strokeGradientEndColor,
                angle: stroke.strokeGradientAngle
            )
            context.restoreGState()
        } else {
            let c = stroke.color
            context.setStrokeColor(CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a))
            context.setLineWidth(CGFloat(stroke.width))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(path)
            context.strokePath()
        }
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
