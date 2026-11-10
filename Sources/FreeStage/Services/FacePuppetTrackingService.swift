//
//  FacePuppetTrackingService.swift
//  FreeStage
//
//  Shared observable state for the latest tracked face mesh frame. The face
//  puppet renderer publishes frames here so the SwiftUI anchor-point overlay
//  can draw handles at the current landmark positions.
//

import Foundation
import SwiftUI

/// Latest face-mesh tracking result, observed by the anchor-point overlay.
@Observable
@MainActor
final class FacePuppetTrackingService {
    var latestFrame: FaceMeshFrame?

    /// Publish a new frame from the inference queue to the main actor.
    nonisolated func publish(frame: FaceMeshFrame) {
        Task { @MainActor in
            latestFrame = frame
        }
    }
}

extension EnvironmentValues {
    var facePuppetTrackingService: FacePuppetTrackingService? {
        get { self[FacePuppetTrackingServiceKey.self] }
        set { self[FacePuppetTrackingServiceKey.self] = newValue }
    }
}

private struct FacePuppetTrackingServiceKey: EnvironmentKey {
    static let defaultValue: FacePuppetTrackingService? = nil
}
