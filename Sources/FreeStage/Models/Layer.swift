//
//  Layer.swift
//  FreeStage
//
//  A layer is one instance of a source inside a scene, with transform,
//  filters, camera controls, and blending settings.
//

import Foundation

struct Layer: Identifiable, Hashable, Codable, Sendable {
    /// Where the layer sits relative to the segment content.
    enum Placement: String, Codable, Sendable, CaseIterable {
        case background
        case foreground
    }

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
    /// For presenter global layers: render behind segment content
    /// (`.background`) or on top of it (`.foreground`).
    var placement: Placement

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
        cameraSettings: CameraSettings? = nil,
        placement: Placement = .foreground
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
        self.placement = placement
    }

    /// Resolve security-scoped bookmarks for this layer's source and filters.
    mutating func resolveBookmarks(using bookmarks: [String: Data]) {
        source = source.resolvingBookmarks(using: bookmarks)
        for filterIndex in filters.indices {
            filters[filterIndex].resolveBookmarks(using: bookmarks)
        }
    }

    /// Transform every file URL in this layer's source and filters.
    mutating func withFileURLs(_ map: (URL) -> URL) {
        source = source.withFileURLs(map)
        for filterIndex in filters.indices {
            filters[filterIndex].withFileURLs(map)
        }
    }
}
