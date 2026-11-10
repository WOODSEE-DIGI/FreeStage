//
//  FacePuppetAnchorMap.swift
//  FreeStage
//
//  Adjustable anchor offsets for the face puppet mesh. Each key is a MediaPipe
//  landmark index; the value is a normalized screen-space offset applied when
//  building the deformed puppet mesh.
//

import Foundation
import CoreGraphics

/// Offsets applied to selected MediaPipe landmarks when warping a puppet
/// texture or drawing the preview mesh.
struct FacePuppetAnchorMap: Hashable, Codable, Sendable {
    var offsets: [Int: CGPoint]

    init(offsets: [Int: CGPoint] = [:]) {
        self.offsets = offsets
    }
}

/// Named facial anchors used to tune the puppet wrap.
enum FacePuppetAnchorName: String, CaseIterable, Identifiable, Sendable {
    case leftEye = "Left Eye"
    case rightEye = "Right Eye"
    case noseTip = "Nose Tip"
    case mouthLeft = "Mouth Left"
    case mouthRight = "Mouth Right"
    case chin = "Chin"

    var id: String { rawValue }

    /// Canonical MediaPipe face-mesh landmark index for this anchor.
    var landmarkIndex: Int {
        switch self {
        case .leftEye: return 33
        case .rightEye: return 263
        case .noseTip: return 1
        case .mouthLeft: return 61
        case .mouthRight: return 291
        case .chin: return 152
        }
    }
}
