//
//  CameraMove.swift
//  FreeStage
//
//  Describes an A→B camera move that runs when a cue is fired.
//  The move interpolates a camera layer between two saved presets
//  over a fixed duration.
//

import Foundation

struct CameraMove: Hashable, Codable, Sendable {
    var isEnabled: Bool
    /// Preset that defines the camera position at the start of the move.
    /// If nil, the move starts from the layer's current settings.
    var startPresetID: UUID?
    /// Preset that defines the camera position at the end of the move.
    var endPresetID: UUID?
    /// Duration of the move in seconds.
    var duration: TimeInterval
    /// The layer that will be animated. If nil, the first camera layer in
    /// the cue's scene is used.
    var targetLayerID: UUID?

    init(
        isEnabled: Bool = false,
        startPresetID: UUID? = nil,
        endPresetID: UUID? = nil,
        duration: TimeInterval = 2.0,
        targetLayerID: UUID? = nil
    ) {
        self.isEnabled = isEnabled
        self.startPresetID = startPresetID
        self.endPresetID = endPresetID
        self.duration = duration
        self.targetLayerID = targetLayerID
    }
}
