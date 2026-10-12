//
//  CameraLimitZone.swift
//  FreeStage
//
//  A software "keep-out" rectangle for one camera's gimbal, expressed in the
//  user frame (pan + = right, tilt + = up, degrees). When enabled, every gimbal
//  command is clamped to the zone before it reaches hardware, so the camera
//  cannot frame outside the allowed area — even via cue moves or presets.
//
//  This is a FreeStage-side clamp: neither the OBSBOT OSC API nor the vendor
//  protocol exposes a hardware limit-zone (the SDK's "zone" APIs are AI-tracking
//  aim presets, not safety boundaries).
//

import Foundation

struct CameraLimitZone: Hashable, Codable, Sendable {
    /// Master switch. When false the zone is stored but not enforced.
    var isEnabled: Bool

    /// Allowed pan range in degrees (user frame, + = right).
    var panMin: Double
    var panMax: Double

    /// Allowed tilt range in degrees (user frame, + = up).
    var tiltMin: Double
    var tiltMax: Double

    init(
        isEnabled: Bool = true,
        panMin: Double = -45,
        panMax: Double = 45,
        tiltMin: Double = -20,
        tiltMax: Double = 20
    ) {
        self.isEnabled = isEnabled
        // Normalize so min is never above max regardless of input order.
        self.panMin = min(panMin, panMax)
        self.panMax = max(panMin, panMax)
        self.tiltMin = min(tiltMin, tiltMax)
        self.tiltMax = max(tiltMin, tiltMax)
    }

    /// Clamp a pose (user frame degrees) into the zone. No-op when disabled.
    func clamp(pan: Double, tilt: Double) -> (pan: Double, tilt: Double) {
        guard isEnabled else { return (pan, tilt) }
        return (
            min(max(pan, panMin), panMax),
            min(max(tilt, tiltMin), tiltMax)
        )
    }

    /// The full hardware-range zone (used when resetting).
    static let unrestricted = CameraLimitZone(isEnabled: false, panMin: -130, panMax: 130, tiltMin: -32, tiltMax: 60)
}
