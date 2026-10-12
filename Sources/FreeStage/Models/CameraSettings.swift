//
//  CameraSettings.swift
//  FreeStage
//
//  A snapshot of camera adjustments for a layer. Software-framing fields
//  (zoom / panX / panY) map to the layer's transform and color fields to a
//  Color Correction filter; gimbal fields drive the physical OBSBOT gimbal
//  via CameraControlService when the camera supports it.
//

import Foundation

struct CameraSettings: Hashable, Codable, Sendable {
    /// Zoom multiplier; maps to layer scale.
    var zoom: Double
    /// Normalized layer center X; maps to layer transform x.
    var panX: Double
    /// Normalized layer center Y; maps to layer transform y.
    var panY: Double
    /// Exposure value in EV; maps to color-correction filter exposure.
    var exposure: Double
    /// Color temperature offset; maps to color-correction filter temperature.
    var temperature: Double
    /// Tint offset; maps to color-correction filter tint.
    var tint: Double

    /// Gimbal pan in degrees (user frame: positive = camera pans RIGHT).
    /// Only sent to hardware when `gimbalActive` is true, so color-only
    /// snapshots and old presets never nudge the gimbal.
    var gimbalPan: Double
    /// Gimbal tilt in degrees (user frame: positive = camera tilts UP).
    var gimbalTilt: Double
    /// Whether this snapshot includes an intentional gimbal pose.
    var gimbalActive: Bool

    init(
        zoom: Double = 1.0,
        panX: Double = 0.5,
        panY: Double = 0.5,
        exposure: Double = 0.0,
        temperature: Double = 0.0,
        tint: Double = 0.0,
        gimbalPan: Double = 0.0,
        gimbalTilt: Double = 0.0,
        gimbalActive: Bool = false
    ) {
        self.zoom = zoom
        self.panX = panX
        self.panY = panY
        self.exposure = exposure
        self.temperature = temperature
        self.tint = tint
        self.gimbalPan = gimbalPan
        self.gimbalTilt = gimbalTilt
        self.gimbalActive = gimbalActive
    }

    // MARK: - Codable (back-compat with shows saved before gimbal fields)

    private enum CodingKeys: String, CodingKey {
        case zoom, panX, panY, exposure, temperature, tint
        case gimbalPan, gimbalTilt, gimbalActive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zoom = try container.decode(Double.self, forKey: .zoom)
        panX = try container.decode(Double.self, forKey: .panX)
        panY = try container.decode(Double.self, forKey: .panY)
        exposure = try container.decode(Double.self, forKey: .exposure)
        temperature = try container.decode(Double.self, forKey: .temperature)
        tint = try container.decode(Double.self, forKey: .tint)
        gimbalPan = try container.decodeIfPresent(Double.self, forKey: .gimbalPan) ?? 0
        gimbalTilt = try container.decodeIfPresent(Double.self, forKey: .gimbalTilt) ?? 0
        gimbalActive = try container.decodeIfPresent(Bool.self, forKey: .gimbalActive) ?? false
    }

    // MARK: - Interpolation (A→B camera moves)

    func interpolated(to other: CameraSettings, progress: Double) -> CameraSettings {
        let t = max(0, min(1, progress))
        return CameraSettings(
            zoom: zoom + (other.zoom - zoom) * t,
            panX: panX + (other.panX - panX) * t,
            panY: panY + (other.panY - panY) * t,
            exposure: exposure + (other.exposure - exposure) * t,
            temperature: temperature + (other.temperature - temperature) * t,
            tint: tint + (other.tint - tint) * t,
            gimbalPan: gimbalPan + (other.gimbalPan - gimbalPan) * t,
            gimbalTilt: gimbalTilt + (other.gimbalTilt - gimbalTilt) * t,
            gimbalActive: gimbalActive || other.gimbalActive
        )
    }
}

struct CameraPreset: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var settings: CameraSettings

    init(id: UUID = UUID(), name: String, settings: CameraSettings) {
        self.id = id
        self.name = name
        self.settings = settings
    }
}
