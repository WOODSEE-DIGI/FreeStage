//
//  FaceMeshTrackerTests.swift
//  FreeStageTests
//
//  Smoke tests for the native MediaPipe face-mesh tracker integration.
//

import Testing
import CoreVideo
@testable import FreeStage

struct FaceMeshTrackerTests {

    @Test("FaceMeshTracker initializes with bundled models")
    func initializes() {
        let tracker = FaceMeshTracker()
        #expect(tracker != nil)
    }

    @Test("FaceMeshTracker processes a BGRA buffer without crashing")
    func processesBufferWithoutCrashing() async throws {
        let tracker = try #require(FaceMeshTracker())
        let buffer = try #require(createBGRAPixelBuffer(width: 320, height: 240))

        tracker.enqueue(buffer)

        // Give inference a moment to complete (or drop the frame).
        try await Task.sleep(for: .milliseconds(500))

        // A blank buffer contains no face, so the latest frame should be nil.
        #expect(tracker.latestFrame == nil)
    }

    private func createBGRAPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        defer { CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0)) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        memset(baseAddress, 0x7F, bytesPerRow * height)
        return buffer
    }
}
