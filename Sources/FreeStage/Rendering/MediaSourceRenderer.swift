//
//  MediaSourceRenderer.swift
//  FreeStage
//
//  Renders a video file source into a Metal texture using AVPlayer.
//  Supports full-file `.media` sources and trimmed `.mediaClip` sources
//  (In/Out points) so presenter Video Package segments play only the
//  selected range without requiring an exported subclip.
//

@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Metal
import Foundation

/// Unique key for a media rendering session. The same URL with different
/// In/Out trim ranges needs separate sessions so each layer plays its own
/// section.
private struct MediaSessionKey: Hashable {
    let url: URL
    let inPoint: TimeInterval
    let outPoint: TimeInterval?

    init(url: URL, inPoint: TimeInterval = 0, outPoint: TimeInterval? = nil) {
        self.url = url
        self.inPoint = inPoint
        self.outPoint = outPoint
    }
}

final class MediaSourceRenderer: @unchecked Sendable {
    private final class Session: @unchecked Sendable {
        let url: URL
        let inPoint: TimeInterval
        let outPoint: TimeInterval?
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

        init?(url: URL, inPoint: TimeInterval = 0, outPoint: TimeInterval? = nil, device: MTLDevice) {
            self.url = url
            self.inPoint = inPoint
            self.outPoint = outPoint
            self.securityScopedAccessing = url.startAccessingSecurityScopedResource()
            let item = AVPlayerItem(url: url)
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ])
            item.add(output)

            if let outPoint, outPoint > 0 {
                item.forwardPlaybackEndTime = CMTime(seconds: outPoint, preferredTimescale: 600)
            } else {
                item.forwardPlaybackEndTime = CMTime.invalid
            }

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
                let start = CMTime(seconds: self.inPoint, preferredTimescale: 600)
                self.player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    self.player.play()
                }
            }

            // Start at the In point so the first frame is already trimmed.
            if inPoint > 0 {
                let start = CMTime(seconds: inPoint, preferredTimescale: 600)
                player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero)
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

    private var sessions: [MediaSessionKey: Session] = [:]
    private let lock = NSLock()

    func render(
        source: Source,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> MTLTexture? {
        let (url, inPoint, outPoint): (URL, TimeInterval, TimeInterval?)
        switch source {
        case .media(let mediaURL):
            (url, inPoint, outPoint) = (mediaURL, 0, nil)
        case .mediaClip(let mediaURL, let clipIn, let clipOut):
            (url, inPoint, outPoint) = (mediaURL, clipIn, clipOut)
        default:
            return nil
        }

        let key = MediaSessionKey(url: url, inPoint: inPoint, outPoint: outPoint)

        lock.lock()
        defer { lock.unlock() }

        if sessions[key] == nil {
            sessions[key] = Session(url: url, inPoint: inPoint, outPoint: outPoint, device: device)
        }
        guard let session = sessions[key] else { return nil }
        session.start()
        return session.currentFrame()
    }
}
