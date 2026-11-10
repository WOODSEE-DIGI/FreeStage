//
//  FacePuppetRendererTests.swift
//  FreeStageTests
//
//  Smoke test for the Face Puppet 3D mesh render pipeline.
//

import Testing
import CoreVideo
import Metal
import AppKit
@testable import FreeStage

struct FacePuppetRendererTests {

    @Test("Face puppet renderer produces a deforming mesh output texture")
    func rendersWithSyntheticFace() throws {
        let captureManager = CameraCaptureManager()
        let renderer = FacePuppetSourceRenderer(captureManager: captureManager)

        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            Issue.record("Metal not available")
            return
        }

        let pixelBuffer = try #require(createBGRAPixelBuffer(width: 320, height: 240))
        captureManager.storeFrame(uniqueID: "test", buffer: pixelBuffer)

        let puppetURL = try #require(createTestPuppetImage())
        let source = Source.facePuppet(cameraID: "test", puppetImageURL: puppetURL)

        let syntheticFrame = FaceMeshFrame(
            landmarks: syntheticFaceLandmarks(),
            geometry: nil,
            blendshapes: nil,
            score: 0.9,
            imageSize: CGSize(width: 320, height: 240)
        )
        renderer.tracker?.injectLatestFrame(syntheticFrame)

        let texture = try renderer.render(source: source, device: device, commandQueue: commandQueue)
        #expect(texture != nil)
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

    private func createTestPuppetImage() -> URL? {
        let size = CGSize(width: 256, height: 256)
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fillEllipse(in: CGRect(x: 64, y: 64, width: 128, height: 128))

        guard let cgImage = context.makeImage() else { return nil }
        let image = NSImage(cgImage: cgImage, size: size)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_puppet.png")
        try? png.write(to: url)
        return url
    }

    private func syntheticFaceLandmarks() -> [FaceMeshLandmark] {
        // Produce a neutral-ish face in normalized 0..1 coordinates.
        var landmarks: [FaceMeshLandmark] = []
        let center = SIMD2<Float>(0.5, 0.5)
        for i in 0..<CanonicalFaceMeshData.vertexCount {
            let uv = CanonicalFaceMeshData.uvs[i]
            // Map canonical UVs to a region centered on the canvas.
            let x = center.x + (uv.x - 0.5) * 0.6
            let y = center.y + (uv.y - 0.5) * 0.8
            landmarks.append(FaceMeshLandmark(x: x, y: y, z: 0))
        }
        return landmarks
    }
}
