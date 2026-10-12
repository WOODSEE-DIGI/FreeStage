//
//  Layer.swift
//  FreeStage
//
//  A layer is one instance of a source inside a scene, with transform,
//  filters, camera controls, and blending settings.
//

import Foundation

struct Layer: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var source: Source
    var transform: ItemTransform
    var filters: [Filter]
    var blendMode: BlendMode
    var opacity: Double
    var isVisible: Bool
    var isLocked: Bool
    /// Per-layer camera controls. Only used when `source` is a camera.
    var cameraSettings: CameraSettings?

    init(
        id: UUID = UUID(),
        name: String? = nil,
        source: Source,
        transform: ItemTransform = .identity,
        filters: [Filter] = [],
        blendMode: BlendMode = .normal,
        opacity: Double = 1.0,
        isVisible: Bool = true,
        isLocked: Bool = false,
        cameraSettings: CameraSettings? = nil
    ) {
        self.id = id
        self.name = name ?? source.defaultName
        self.source = source
        self.transform = transform
        self.filters = filters
        self.blendMode = blendMode
        self.opacity = opacity
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.cameraSettings = cameraSettings
    }
}
