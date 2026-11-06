//
//  TemplateSourceRenderer.swift
//  FreeStage
//
//  Renders template layer sources (border, lower third, chapter marker,
//  next section, social bug, logo bug, countdown timer) into Metal textures
//  using Core Graphics. Supports in/out animation presets.
//

import Metal
import CoreGraphics
import CoreImage
import AppKit
import OSLog

final class TemplateSourceRenderer: SourceRenderer, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "TemplateSource")

    private struct CacheEntry {
        let sourceID: UUID
        let sourceHash: Int
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
        let sourceID: UUID
        let sourceHash: Int
        switch source {
        case .border(let s):
            sourceID = s.id
            sourceHash = s.hashValue
        case .lowerThird(let s):
            sourceID = s.id
            sourceHash = s.hashValue
        case .chapterMarker(let s):
            sourceID = s.id
            sourceHash = s.hashValue
        case .nextSection(let s):
            sourceID = s.id
            sourceHash = s.hashValue
        case .socialBug(let s):
            sourceID = s.id
            sourceHash = s.hashValue
        case .logoBug(let s):
            sourceID = s.id
            sourceHash = s.hashValue
        case .countdownTimer(let s):
            sourceID = s.id
            // Countdown changes every second, so include the remaining-second
            // floor in the cache key so the texture updates once per second.
            sourceHash = s.hashValue ^ Int(s.remainingSecondFloor(from: Date()))
        default:
            return nil
        }

        cacheLock.lock()
        if let cached = cache[sourceID], cached.sourceHash == sourceHash {
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
                Self.logger.error("Failed to create template texture")
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

            guard let cgImage = renderCGImage(source: source, size: CGSize(width: width, height: height)) else {
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
            cache[sourceID] = CacheEntry(sourceID: sourceID, sourceHash: sourceHash, texture: texture)
            cacheLock.unlock()

            return texture
        }
    }

    private func renderCGImage(source: Source, size: CGSize) -> CGImage? {
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

        context.clear(CGRect(origin: .zero, size: size))

        switch source {
        case .border(let border):
            renderBorder(border, in: context, size: size)
        case .lowerThird(let lowerThird):
            renderLowerThird(lowerThird, in: context, size: size)
        case .chapterMarker(let chapter):
            renderChapterMarker(chapter, in: context, size: size)
        case .nextSection(let next):
            renderNextSection(next, in: context, size: size)
        case .socialBug(let bug):
            renderSocialBug(bug, in: context, size: size)
        case .logoBug(let bug):
            renderLogoBug(bug, in: context, size: size)
        case .countdownTimer(let timer):
            renderCountdownTimer(timer, in: context, size: size)
        default:
            break
        }

        return context.makeImage()
    }

    // MARK: - Animation helpers

    private func applyAnimation(
        _ animation: TemplateAnimation,
        in context: CGContext,
        size: CGSize,
        contentRect: CGRect
    ) {
        let progress = animation.progress
        guard animation.preset != .none, progress < 1 else { return }

        let hidden = 1 - progress
        var transform = CGAffineTransform.identity
        var alpha = 1.0

        switch animation.preset {
        case .slideFromLeft:
            transform = transform.translatedBy(x: -size.width * hidden, y: 0)
        case .slideFromRight:
            transform = transform.translatedBy(x: size.width * hidden, y: 0)
        case .slideFromBottom:
            transform = transform.translatedBy(x: 0, y: -size.height * hidden)
        case .fade:
            alpha = progress
        case .none:
            break
        }

        context.concatenate(transform)
        context.setAlpha(CGFloat(alpha))
    }

    // MARK: - Border

    private func renderBorder(_ source: BorderSource, in context: CGContext, size: CGSize) {
        context.saveGState()
        applyAnimation(source.animation, in: context, size: size, contentRect: CGRect(origin: .zero, size: size))

        let rect = CGRect(origin: .zero, size: size).insetBy(dx: source.thickness / 2, dy: source.thickness / 2)
        let path = CGPath(roundedRect: rect, cornerWidth: source.cornerRadius, cornerHeight: source.cornerRadius, transform: nil)

        if source.fillCenter {
            context.addPath(path)
            context.setFillColor(cgColor(source.fillColor))
            context.fillPath()
        }

        context.addPath(path)
        context.setLineWidth(source.thickness)

        switch source.fillStyle {
        case .solid:
            context.setStrokeColor(cgColor(source.color))
            context.strokePath()
        case .gradient:
            context.saveGState()
            context.addPath(path)
            context.replacePathWithStrokedPath()
            context.clip()
            drawLinearGradient(
                in: context,
                size: size,
                startColor: source.gradientStartColor,
                endColor: source.gradientEndColor,
                angle: source.gradientAngle
            )
            context.restoreGState()
        }

        context.restoreGState()
    }

    // MARK: - Lower Third

    private func renderLowerThird(_ source: LowerThirdSource, in context: CGContext, size: CGSize) {
        let textHeight = CGFloat(source.titleFontSize + source.subtitleFontSize + 12)
        let boxHeight = textHeight + CGFloat(source.verticalPadding * 2)
        let boxRect = CGRect(x: 0, y: 0, width: size.width, height: boxHeight)

        context.saveGState()
        applyAnimation(source.animation, in: context, size: size, contentRect: boxRect)
        drawLowerThirdBackground(source: source, boxRect: boxRect, in: context, size: size)

        let textX: CGFloat
        switch source.alignment {
        case .left:
            textX = CGFloat(source.horizontalPadding)
        case .right:
            let titleSize = attributedSize(for: source.title, fontSize: source.titleFontSize)
            let subtitleSize = attributedSize(for: source.subtitle, fontSize: source.subtitleFontSize)
            let maxWidth = max(titleSize.width, subtitleSize.width)
            textX = size.width - CGFloat(source.horizontalPadding) - maxWidth
        case .center:
            let titleSize = attributedSize(for: source.title, fontSize: source.titleFontSize)
            let subtitleSize = attributedSize(for: source.subtitle, fontSize: source.subtitleFontSize)
            let maxWidth = max(titleSize.width, subtitleSize.width)
            textX = (size.width - maxWidth) / 2
        }

        let titleY = boxHeight - CGFloat(source.verticalPadding) - CGFloat(source.titleFontSize)
        drawText(source.title, at: CGPoint(x: textX, y: titleY), fontSize: source.titleFontSize, color: source.titleColor, in: context)

        let subtitleY = titleY - CGFloat(source.subtitleFontSize) - 6
        drawText(source.subtitle, at: CGPoint(x: textX, y: subtitleY), fontSize: source.subtitleFontSize, color: source.subtitleColor, in: context)
        context.restoreGState()
    }

    // MARK: - Chapter Marker

    private func renderChapterMarker(_ source: ChapterMarkerSource, in context: CGContext, size: CGSize) {
        let margin: CGFloat = 60
        let boxHeight: CGFloat = CGFloat(source.fontSize) + 40
        let boxRect = CGRect(x: margin, y: size.height - boxHeight - margin, width: size.width - margin * 2, height: boxHeight)

        context.saveGState()
        applyAnimation(source.animation, in: context, size: size, contentRect: boxRect)

        let path = CGPath(roundedRect: boxRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(path)
        context.setFillColor(cgColor(source.backgroundColor))
        context.fillPath()

        let accentWidth: CGFloat = 6
        let accentRect = CGRect(x: boxRect.minX, y: boxRect.minY, width: accentWidth, height: boxRect.height)
        context.addRect(accentRect)
        context.setFillColor(cgColor(source.accentColor))
        context.fillPath()

        let numberSize = attributedSize(for: source.chapterNumber, fontSize: source.fontSize)
        let numberX = boxRect.minX + 20
        let numberY = boxRect.midY - numberSize.height / 2
        drawText(source.chapterNumber, at: CGPoint(x: numberX, y: numberY), fontSize: source.fontSize, color: source.accentColor, in: context)

        let titleX = numberX + numberSize.width + 20
        let titleY = boxRect.midY - numberSize.height / 2
        drawText(source.title, at: CGPoint(x: titleX, y: titleY), fontSize: source.fontSize, color: source.textColor, in: context)

        if source.showProgressBar {
            let barHeight: CGFloat = 4
            let barY = boxRect.maxY + 8
            let progressWidth = (size.width - margin * 2) * CGFloat(source.progress)
            context.addRect(CGRect(x: margin, y: barY, width: size.width - margin * 2, height: barHeight))
            context.setFillColor(cgColor(source.backgroundColor))
            context.fillPath()
            context.addRect(CGRect(x: margin, y: barY, width: progressWidth, height: barHeight))
            context.setFillColor(cgColor(source.accentColor))
            context.fillPath()
        }

        context.restoreGState()
    }

    // MARK: - Next Section

    private func renderNextSection(_ source: NextSectionSource, in context: CGContext, size: CGSize) {
        let margin: CGFloat = 60
        let textHeight = CGFloat(source.labelFontSize + source.titleFontSize + source.subtitleFontSize + 20)
        let boxHeight = textHeight + 60
        let boxRect = CGRect(x: margin, y: size.height - boxHeight - margin, width: size.width - margin * 2, height: boxHeight)

        context.saveGState()
        applyAnimation(source.animation, in: context, size: size, contentRect: boxRect)

        switch source.fillStyle {
        case .solid:
            let path = CGPath(roundedRect: boxRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
            context.addPath(path)
            context.setFillColor(cgColor(source.backgroundColor))
            context.fillPath()
        case .gradient:
            context.saveGState()
            let path = CGPath(roundedRect: boxRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
            context.addPath(path)
            context.clip()
            drawLinearGradient(
                in: context,
                size: size,
                startColor: source.gradientStartColor,
                endColor: source.gradientEndColor,
                angle: 0
            )
            context.restoreGState()
        }

        let labelX = boxRect.minX + 30
        let labelY = boxRect.maxY - 30 - CGFloat(source.labelFontSize)
        drawText(source.label, at: CGPoint(x: labelX, y: labelY), fontSize: source.labelFontSize, color: source.labelColor, in: context)

        let titleY = labelY - CGFloat(source.titleFontSize) - 10
        drawText(source.title, at: CGPoint(x: labelX, y: titleY), fontSize: source.titleFontSize, color: source.titleColor, in: context)

        let subtitleY = titleY - CGFloat(source.subtitleFontSize) - 8
        drawText(source.subtitle, at: CGPoint(x: labelX, y: subtitleY), fontSize: source.subtitleFontSize, color: source.subtitleColor, in: context)

        context.restoreGState()
    }

    // MARK: - Social Bug

    private func renderSocialBug(_ source: SocialBugSource, in context: CGContext, size: CGSize) {
        let text = source.handle
        let platformLabel = source.label.isEmpty ? source.platform.displayName : source.label
        let displayText = platformLabel.isEmpty ? text : "\(platformLabel)  \(text)"

        let padding = CGFloat(source.padding)
        let textSize = attributedSize(for: displayText, fontSize: source.fontSize)
        let boxSize = CGSize(width: textSize.width + padding * 2, height: textSize.height + padding * 2)
        let boxRect = rectForBug(size: size, boxSize: boxSize, position: source.position, margin: 40)

        context.saveGState()
        applyAnimation(source.animation, in: context, size: size, contentRect: boxRect)

        let path = CGPath(roundedRect: boxRect, cornerWidth: source.cornerRadius, cornerHeight: source.cornerRadius, transform: nil)
        context.addPath(path)
        context.setFillColor(cgColor(source.backgroundColor))
        context.fillPath()

        drawText(displayText, at: CGPoint(x: boxRect.minX + padding, y: boxRect.minY + padding), fontSize: source.fontSize, color: source.textColor, in: context)

        context.restoreGState()
    }

    // MARK: - Logo Bug

    private func renderLogoBug(_ source: LogoBugSource, in context: CGContext, size: CGSize) {
        let text = source.text
        let padding = CGFloat(source.padding)
        let textSize = attributedSize(for: text, fontSize: source.fontSize)
        let boxSize = CGSize(width: textSize.width + padding * 2, height: textSize.height + padding * 2)
        let boxRect = rectForBug(size: size, boxSize: boxSize, position: source.position, margin: 40)

        context.saveGState()
        applyAnimation(source.animation, in: context, size: size, contentRect: boxRect)

        let path = CGPath(roundedRect: boxRect, cornerWidth: source.cornerRadius, cornerHeight: source.cornerRadius, transform: nil)
        context.addPath(path)
        context.setFillColor(cgColor(source.backgroundColor))
        context.fillPath()

        drawText(text, at: CGPoint(x: boxRect.minX + padding, y: boxRect.minY + padding), fontSize: source.fontSize, color: source.textColor, in: context)

        context.restoreGState()
    }

    // MARK: - Countdown Timer

    private func renderCountdownTimer(_ source: CountdownTimerSource, in context: CGContext, size: CGSize) {
        let label = source.label
        let remaining = source.formattedRemaining(from: Date())

        let timeSize = attributedSize(for: remaining, fontSize: source.fontSize)
        let labelSize = label.isEmpty ? .zero : attributedSize(for: label, fontSize: source.labelFontSize)
        let boxWidth = max(timeSize.width, labelSize.width) + 80
        let boxHeight = timeSize.height + labelSize.height + (labelSize.height > 0 ? 16 : 0) + 40

        let boxRect = CGRect(
            x: (size.width - boxWidth) / 2,
            y: (size.height - boxHeight) / 2,
            width: boxWidth,
            height: boxHeight
        )

        context.saveGState()
        applyAnimation(source.animation, in: context, size: size, contentRect: boxRect)

        let path = CGPath(roundedRect: boxRect, cornerWidth: 16, cornerHeight: 16, transform: nil)
        context.addPath(path)
        context.setFillColor(cgColor(source.backgroundColor))
        context.fillPath()

        let timeX: CGFloat
        let labelX: CGFloat
        switch source.alignment {
        case .left:
            timeX = boxRect.minX + 40
            labelX = boxRect.minX + 40
        case .right:
            timeX = boxRect.maxX - 40 - timeSize.width
            labelX = boxRect.maxX - 40 - labelSize.width
        case .center:
            timeX = boxRect.midX - timeSize.width / 2
            labelX = boxRect.midX - labelSize.width / 2
        }

        let timeY = boxRect.midY - 6
        drawText(remaining, at: CGPoint(x: timeX, y: timeY), fontSize: source.fontSize, color: source.textColor, in: context)

        if !label.isEmpty {
            let labelY = timeY + timeSize.height + 8
            drawText(label, at: CGPoint(x: labelX, y: labelY), fontSize: source.labelFontSize, color: source.textColor, in: context)
        }

        context.restoreGState()
    }

    // MARK: - Helpers

    private func rectForBug(size: CGSize, boxSize: CGSize, position: TemplateBugPosition, margin: CGFloat) -> CGRect {
        let x: CGFloat
        let y: CGFloat
        switch position {
        case .topLeft:
            x = margin
            y = size.height - boxSize.height - margin
        case .topRight:
            x = size.width - boxSize.width - margin
            y = size.height - boxSize.height - margin
        case .bottomLeft:
            x = margin
            y = margin
        case .bottomRight:
            x = size.width - boxSize.width - margin
            y = margin
        }
        return CGRect(x: x, y: y, width: boxSize.width, height: boxSize.height)
    }

    private func drawLowerThirdBackground(source: LowerThirdSource, boxRect: CGRect, in context: CGContext, size: CGSize) {
        switch source.fillStyle {
        case .solid:
            let path = CGPath(roundedRect: boxRect, cornerWidth: 0, cornerHeight: 0, transform: nil)
            context.addPath(path)
            context.setFillColor(cgColor(source.backgroundColor))
            context.fillPath()
        case .gradient:
            context.saveGState()
            let path = CGPath(roundedRect: boxRect, cornerWidth: 0, cornerHeight: 0, transform: nil)
            context.addPath(path)
            context.clip()
            drawLinearGradient(
                in: context,
                size: size,
                startColor: source.gradientStartColor,
                endColor: source.gradientEndColor,
                angle: 0
            )
            context.restoreGState()
        }
    }

    private func drawLinearGradient(
        in context: CGContext,
        size: CGSize,
        startColor: CGColorComponents,
        endColor: CGColorComponents,
        angle: Double
    ) {
        let radians = angle * .pi / 180
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = hypot(size.width, size.height) / 2
        let start = CGPoint(x: center.x - cos(radians) * radius, y: center.y - sin(radians) * radius)
        let end = CGPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)

        let colors = [cgColor(startColor).copy(alpha: 1)!, cgColor(endColor).copy(alpha: 1)!] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private func drawText(_ text: String, at point: CGPoint, fontSize: Double, color: CGColorComponents, in context: CGContext) {
        guard !text.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: CGFloat(fontSize))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(red: color.r, green: color.g, blue: color.b, alpha: color.a)
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        attributed.draw(at: point)
    }

    private func attributedSize(for text: String, fontSize: Double) -> CGSize {
        let font = NSFont.systemFont(ofSize: CGFloat(fontSize))
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return (text as NSString).size(withAttributes: attributes)
    }

    private func cgColor(_ components: CGColorComponents) -> CGColor {
        CGColor(red: components.r, green: components.g, blue: components.b, alpha: components.a)
    }
}

private extension CountdownTimerSource {
    func remainingSecondFloor(from now: Date) -> TimeInterval {
        max(0, targetDate.timeIntervalSince(now))
    }
}
