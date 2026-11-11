//
//  LayerDefaults.swift
//  FreeStage
//
//  Saved per-source layer settings that are applied automatically when a new
//  layer with the same source is created. Users can save the current layer's
//  transform, opacity, blend mode, filters, and camera settings as the default
//  starting point for that source.
//

import Foundation

/// A snapshot of layer settings keyed to a specific source. Stored in
/// AppSettings so it persists across shows and launches.
struct LayerDefaults: Identifiable, Hashable, Codable, Sendable {
    /// Stable key for the source this default belongs to (e.g., "camera:<uuid>").
    let sourceKey: String
    var transform: ItemTransform
    var opacity: Double
    var blendMode: BlendMode
    var filters: [Filter]
    var cameraSettings: CameraSettings?

    var id: String { sourceKey }

    init(
        sourceKey: String,
        transform: ItemTransform = .identity,
        opacity: Double = 1.0,
        blendMode: BlendMode = .normal,
        filters: [Filter] = [],
        cameraSettings: CameraSettings? = nil
    ) {
        self.sourceKey = sourceKey
        self.transform = transform
        self.opacity = opacity
        self.blendMode = blendMode
        self.filters = filters
        self.cameraSettings = cameraSettings
    }

    /// Create defaults from an existing layer.
    init(sourceKey: String, layer: Layer) {
        self.sourceKey = sourceKey
        self.transform = layer.transform
        self.opacity = layer.opacity
        self.blendMode = layer.blendMode
        self.filters = layer.filters
        self.cameraSettings = layer.cameraSettings
    }

    /// Apply these defaults to a new layer, preserving the source and name.
    func apply(to layer: inout Layer) {
        layer.transform = transform
        layer.opacity = opacity
        layer.blendMode = blendMode
        layer.filters = filters
        layer.cameraSettings = cameraSettings
    }
}
