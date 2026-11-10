//
//  StreamOutput.swift
//  FreeStage
//
//  Abstract output used by StreamingService to send video/audio to a stream.
//

import Foundation
import AVFoundation
import CoreMedia
import CoreVideo

/// Represents a live stream output (RTMP, SRT, etc.).
protocol StreamOutput: AnyObject, Sendable {
    var isConnected: Bool { get }
    var statusMessage: String { get }

    /// Start the stream to the given URL.
    func start(url: URL) async throws

    /// Stop the stream.
    func stop() async

    /// Append a rendered video frame.
    func appendVideo(pixelBuffer: CVPixelBuffer, presentationTime: CMTime)

    /// Append a mixed audio buffer.
    func appendAudio(buffer: AVAudioPCMBuffer, presentationTime: AVAudioTime)
}

/// Placeholder output used when no streaming backend is linked.
final class NoOpStreamOutput: @unchecked Sendable, StreamOutput {
    private(set) var isConnected = false
    private(set) var statusMessage = "Streaming backend not linked"

    func start(url: URL) async throws {
        throw StreamingError.backendNotAvailable
    }

    func stop() async {}

    func appendVideo(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {}

    func appendAudio(buffer: AVAudioPCMBuffer, presentationTime: AVAudioTime) {}
}

enum StreamingError: Error {
    case backendNotAvailable
    case invalidIngestURL
    case connectionFailed(String)
}
