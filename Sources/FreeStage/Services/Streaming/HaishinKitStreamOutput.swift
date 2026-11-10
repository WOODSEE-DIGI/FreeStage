//
//  HaishinKitStreamOutput.swift
//  FreeStage
//
//  RTMP/RTMPS stream output using HaishinKit.
//  Add HaishinKit via Swift Package Manager to enable this backend.
//

import Foundation
import AVFoundation
import CoreMedia
import CoreVideo

#if canImport(HaishinKit)
import HaishinKit
import Logboard

/// RTMP stream output powered by HaishinKit.
final class HaishinKitStreamOutput: StreamOutput {
    private(set) var isConnected = false
    private(set) var statusMessage = "Ready"

    private var connection: RTMPConnection?
    private var stream: RTMPStream?
    private let audioEngine = AVAudioEngine()

    func start(url: URL) async throws {
        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)
        stream.sessionPreset = .hd1920x1080
        stream.videoSettings.videoSize = .init(width: 1920, height: 1080)
        stream.videoSettings.bitRate = 6000 * 1000
        stream.audioSettings.bitRate = 192 * 1000

        self.connection = connection
        self.stream = stream

        try await connection.connect(url.absoluteString)
        try await stream.publish("live")

        isConnected = true
        statusMessage = "Streaming"
    }

    func stop() async {
        if let stream {
            try? await stream.close()
        }
        if let connection {
            try? await connection.close()
        }
        stream = nil
        connection = nil
        isConnected = false
        statusMessage = "Stopped"
    }

    func appendVideo(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard let stream else { return }
        // HaishinKit accepts CMSampleBuffer for video append.
        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDesc
        )
        guard let formatDesc else { return }

        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        guard let sampleBuffer else { return }
        stream.append(sampleBuffer)
    }

    func appendAudio(buffer: AVAudioPCMBuffer, presentationTime: AVAudioTime) {
        guard let sampleBuffer = buffer.makeCMSampleBuffer(audioTime: presentationTime),
              let stream else { return }
        stream.append(sampleBuffer)
    }
}

#endif
