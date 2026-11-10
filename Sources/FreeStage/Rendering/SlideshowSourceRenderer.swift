//
//  SlideshowSourceRenderer.swift
//  FreeStage
//
//  Cycles through a folder/album of still images and returns the current
//  slide as a Metal texture.
//

import Metal
import CoreImage
import OSLog

final class SlideshowSourceRenderer: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "SlideshowSource")

    private let lock = NSLock()
    private var timers: [UUID: Timer] = [:]
    private var states: [UUID: SlideshowState] = [:]
    private var cache: [URL: MTLTexture] = [:]

    private struct SlideshowState {
        var imageURLs: [URL]
        var currentIndex: Int
        var interval: TimeInterval
        var transition: SlideTransition
        var lastChange: Date
    }

    func render(
        source: Source,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> MTLTexture? {
        guard case .slideshow(let slideshow) = source else { return nil }

        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let id = slideshow.id

        // Initialize or update state.
        if var state = states[id] {
            let urlsChanged = state.imageURLs != slideshow.imageURLs
            let intervalChanged = state.interval != slideshow.interval
            let transitionChanged = state.transition != slideshow.transition

            if urlsChanged {
                let ordered = slideshow.shuffle ? slideshow.imageURLs.shuffled() : slideshow.imageURLs
                state.imageURLs = ordered
                state.currentIndex = 0
                state.lastChange = now
            }
            if intervalChanged || transitionChanged {
                state.interval = slideshow.interval
                state.transition = slideshow.transition
                restartTimer(id: id, interval: slideshow.interval)
            }
            states[id] = state
        } else {
            let ordered = slideshow.shuffle ? slideshow.imageURLs.shuffled() : slideshow.imageURLs
            states[id] = SlideshowState(
                imageURLs: ordered,
                currentIndex: 0,
                interval: slideshow.interval,
                transition: slideshow.transition,
                lastChange: now
            )
            restartTimer(id: id, interval: slideshow.interval)
        }

        guard let state = states[id], !state.imageURLs.isEmpty else {
            return nil
        }

        let url = state.imageURLs[state.currentIndex]
        if let cached = cache[url] {
            return cached
        }

        guard let texture = loadTexture(url: url, device: device) else { return nil }
        cache[url] = texture
        return texture
    }

    private func restartTimer(id: UUID, interval: TimeInterval) {
        timers[id]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.advanceSlide(id: id)
        }
        timers[id] = timer
    }

    private func advanceSlide(id: UUID) {
        lock.lock()
        defer { lock.unlock() }

        guard var state = states[id], !state.imageURLs.isEmpty else { return }
        state.currentIndex = (state.currentIndex + 1) % state.imageURLs.count
        state.lastChange = Date()
        states[id] = state
    }

    private func loadTexture(url: URL, device: MTLDevice) -> MTLTexture? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            Self.logger.error("Failed to create image source for \(url.path)")
            return nil
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            Self.logger.error("Failed to create CGImage for \(url.path)")
            return nil
        }

        let descriptor = MTLTextureDescriptor()
        descriptor.width = cgImage.width
        descriptor.height = cgImage.height
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            Self.logger.error("makeTexture failed for slideshow image")
            return nil
        }

        let ciContext = CIContext(mtlDevice: device)
        let ciImage = CIImage(cgImage: cgImage)
        let flipped = ciImage
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .transformed(by: CGAffineTransform(translationX: 0, y: ciImage.extent.height))

        ciContext.render(flipped, to: texture, commandBuffer: nil, bounds: ciImage.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
        return texture
    }
}
