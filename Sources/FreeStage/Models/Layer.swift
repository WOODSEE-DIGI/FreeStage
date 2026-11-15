//
//  Layer.swift
//  FreeStage
//
//  A layer is one instance of a source inside a scene, with transform,
//  filters, camera controls, and blending settings.
//

import Foundation

/// A solid-color border drawn around a layer's bounds.
struct LayerBorder: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var isEnabled: Bool
    var color: CGColorComponents
    var width: Double
    var cornerRadius: Double

    init(
        id: UUID = UUID(),
        isEnabled: Bool = false,
        color: CGColorComponents = CGColorComponents(r: 1, g: 1, b: 1, a: 1),
        width: Double = 8,
        cornerRadius: Double = 0
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.color = color
        self.width = width
        self.cornerRadius = cornerRadius
    }
}

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
    /// Optional border drawn around the layer's on-screen bounds.
    var border: LayerBorder

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
        placement: Placement = .foreground,
        border: LayerBorder = LayerBorder()
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
        self.border = border
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
