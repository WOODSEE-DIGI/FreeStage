//
//  ItemTransform.swift
//  FreeStage
//
//  Position, scale, rotation, and crop for a layer within a scene.
//  All values are normalized to the scene output size unless noted.
//

import Foundation

struct ItemTransform: Hashable, Codable, Sendable {
    /// Normalized X position of the layer center, 0 = left edge, 1 = right edge.
    var x: Double
    /// Normalized Y position of the layer center, 0 = top edge, 1 = bottom edge.
    var y: Double
    /// Normalized width, 1.0 = full output width.
    var scaleX: Double
    /// Normalized height, 1.0 = full output height.
    var scaleY: Double
    /// Rotation in degrees.
    var rotation: Double
    /// Normalized crop inset from each edge.
    var crop: CropInsets

    static let identity = ItemTransform(x: 0.5, y: 0.5, scaleX: 1.0, scaleY: 1.0, rotation: 0, crop: .zero)
}

struct CropInsets: Hashable, Codable, Sendable {
    var top: Double
    var left: Double
    var bottom: Double
    var right: Double

    static let zero = CropInsets(top: 0, left: 0, bottom: 0, right: 0)
}
