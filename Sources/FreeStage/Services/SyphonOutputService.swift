//
//  SyphonOutputService.swift
//  FreeStage
//
//  Publishes the rendered program output as a Syphon server so other macOS
//  apps (e.g. Ecamm Live, OBS, Resolume) can receive it.
//

import Foundation
import Metal
import Syphon

/// Thin wrapper around SyphonMetalServer. Lives on the render side and is
/// called once per frame with the output texture.
///
/// Note: Syphon uses CFMessagePort and NSDistributedNotificationCenter, which
/// are blocked by the App Sandbox. Initializing a server inside a sandboxed
/// process raises an exception, so this service returns nil and disables Syphon
/// output when sandboxed.
final class SyphonOutputService: @unchecked Sendable {
    private let server: SyphonMetalServer?

    init?(device: MTLDevice, name: String = "FreeStage") {
        guard !isAppSandboxed() else {
            self.server = nil
            return
        }
        self.server = SyphonMetalServer(name: name, device: device, options: nil)
    }

    /// Publish a new frame. Must be called on the same serial queue that
    /// produced the texture (the MTKView draw callback).
    func publish(_ texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard let server else { return }
        let region = NSRect(
            x: 0,
            y: 0,
            width: Double(texture.width),
            height: Double(texture.height)
        )
        server.publishFrameTexture(
            texture,
            on: commandBuffer,
            imageRegion: region,
            flipped: false
        )
    }
}
