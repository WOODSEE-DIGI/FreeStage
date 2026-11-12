//
//  ProxyGenerator.swift
//  FreeStage
//
//  Generates lower-resolution proxy files and trimmed subclips for Presenter
//  mode video packages. Uses AVAssetExportSession so it works inside the
//  sandbox without bundling external transcoders.
//

import AVFoundation
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.woodseedigi.freestage", category: "ProxyGenerator")

/// Errors thrown by the proxy/subclip generator.
enum ProxyGeneratorError: Error {
    case invalidURL
    case exportFailed(Error?)
    case exportCancelled
    case invalidTimeRange
}

/// Generates proxy media and subclips for presenter video packages.
actor ProxyGenerator {
    static let shared = ProxyGenerator()

    private init() {}

    /// Directory used for derived media. Lives inside the app container so it
    /// does not need security-scoped bookmarks.
    private var derivedMediaDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("com.woodseedigi.FreeStage/DerivedMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Create a lower-resolution proxy of `sourceURL` suitable for fast
    /// scrubbing in the clip editor. Returns the proxy URL.
    func generateProxy(for sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)

        let outputURL = derivedMediaDirectory
            .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent + "_proxy")
            .appendingPathExtension("mp4")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            return outputURL
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw ProxyGeneratorError.exportFailed(nil)
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        try? FileManager.default.removeItem(at: outputURL)
        await exportSession.export()

        if let error = exportSession.error as? NSError, error.domain == AVFoundationErrorDomain, error.code == -11819 {
            // Export cancelled.
            throw ProxyGeneratorError.exportCancelled
        }
        guard exportSession.status == .completed else {
            throw ProxyGeneratorError.exportFailed(exportSession.error)
        }
        logger.info("Generated proxy: \(outputURL.path)")
        return outputURL
    }

    /// Export a new video file containing only the `inPoint`...`outPoint`
    /// range of `sourceURL`. Returns the subclip URL.
    func generateSubclip(for sourceURL: URL, inPoint: TimeInterval, outPoint: TimeInterval?) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let start = CMTime(seconds: max(0, inPoint), preferredTimescale: 600)
        let end: CMTime
        if let outPoint {
            end = CMTime(seconds: min(outPoint, duration.seconds), preferredTimescale: 600)
        } else {
            end = duration
        }
        guard CMTimeCompare(end, start) > 0 else {
            throw ProxyGeneratorError.invalidTimeRange
        }

        let outputURL = derivedMediaDirectory
            .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent + "_subclip")
            .appendingPathExtension("mp4")

        try? FileManager.default.removeItem(at: outputURL)

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProxyGeneratorError.exportFailed(nil)
        }
        try videoTrack.insertTimeRange(CMTimeRange(start: start, end: end), of: sourceVideoTrack, at: .zero)

        if let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try audioTrack.insertTimeRange(CMTimeRange(start: start, end: end), of: sourceAudioTrack, at: .zero)
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ProxyGeneratorError.exportFailed(nil)
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        await exportSession.export()

        if let error = exportSession.error as? NSError, error.domain == AVFoundationErrorDomain, error.code == -11819 {
            throw ProxyGeneratorError.exportCancelled
        }
        guard exportSession.status == .completed else {
            throw ProxyGeneratorError.exportFailed(exportSession.error)
        }
        logger.info("Generated subclip: \(outputURL.path) (\(inPoint)s - \(end.seconds)s)")
        return outputURL
    }
}
