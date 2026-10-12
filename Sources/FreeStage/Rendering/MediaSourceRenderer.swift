//
//  MediaSourceRenderer.swift
//  FreeStage
//
//  Renders a video file source into a Metal texture using AVPlayer.
//  The video loops automatically and is suitable for backgrounds
//  behind a chroma-keyed layer.
//

@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Metal
import Foundation

final class MediaSourceRenderer: @unchecked Sendable {
    private final class Session: @unchecked Sendable {
        let url: URL
        let player: AVPlayer
        let output: AVPlayerItemVideoOutput
        let item: AVPlayerItem
        let textureCache: CVMetalTextureCache
        var lastFrame: Frame?
        private var loopObserver: NSObjectProtocol?
        private let securityScopedAccessing: Bool

        struct Frame {
            let cvTexture: CVMetalTexture
            let texture: MTLTexture
        }

        init?(url: URL, device: MTLDevice) {
            self.url = url
            self.securityScopedAccessing = url.startAccessingSecurityScopedResource()
            let item = AVPlayerItem(url: url)
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ])
            item.add(output)
            item.forwardPlaybackEndTime = CMTime.invalid
            self.item = item
            self.output = output
            self.player = AVPlayer(playerItem: item)
            self.player.actionAtItemEnd = .none
            // This renderer only consumes pixels via AVPlayerItemVideoOutput; the
            // media's audio track is incidental and must not reach system output.
            // Left unmuted, the item's loop plus stacked media layers sum into an
            // audible, growing looping growl. Background videos are silent by design.
            self.player.isMuted = true

            var cache: CVMetalTextureCache?
            let status = CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
            guard status == kCVReturnSuccess, let cache else { return nil }
            self.textureCache = cache

            self.loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    self.player.play()
                }
            }
        }

        deinit {
            if let loopObserver {
                NotificationCenter.default.removeObserver(loopObserver)
            }
            if securityScopedAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        func start() {
            player.play()
        }

        func currentFrame() -> MTLTexture? {
            let hostTime = CACurrentMediaTime()
            let time = output.itemTime(forHostTime: hostTime)
            guard output.hasNewPixelBuffer(forItemTime: time),
                  let pixelBuffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else {
                return lastFrame?.texture
            }

            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            var cvTexture: CVMetalTexture?
            let status = CVMetalTextureCacheCreateTextureFromImage(
                nil,
                textureCache,
                pixelBuffer,
                nil,
                .bgra8Unorm,
                width,
                height,
                0,
                &cvTexture
            )
            guard status == kCVReturnSuccess,
                  let cvTexture,
                  let texture = CVMetalTextureGetTexture(cvTexture) else {
                return lastFrame?.texture
            }
            lastFrame = Frame(cvTexture: cvTexture, texture: texture)
            return texture
        }
    }

    private var sessions: [URL: Session] = [:]
    private let lock = NSLock()

    func render(
        source: Source,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> MTLTexture? {
        guard case .media(let url) = source else { return nil }

        lock.lock()
        defer { lock.unlock() }

        if sessions[url] == nil {
            sessions[url] = Session(url: url, device: device)
        }
        guard let session = sessions[url] else { return nil }
        session.start()
        return session.currentFrame()
    }
}
