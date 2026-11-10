//
//  ScreenSourceRenderer.swift
//  FreeStage
//
//  Renders a `.screen` source by fetching the latest frame from
//  ScreenCaptureManager.
//

import Metal
import CoreGraphics

@available(macOS 12.3, *)
struct ScreenSourceRenderer: SourceRenderer {
    private let manager: ScreenCaptureManager

    init(manager: ScreenCaptureManager) {
        self.manager = manager
    }

    func render(
        source: Source,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> MTLTexture? {
        guard case .screen(let displayID) = source else { return nil }
        return manager.texture(for: displayID)
    }
}
