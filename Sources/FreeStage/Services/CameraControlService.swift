//
//  CameraControlService.swift
//  FreeStage
//
//  Manages CameraSettings for physical cameras and drives hardware control
//  (OBSBOT gimbal) when available. The UI and ShowStore only touch this
//  service; AVFoundation and USB details stay here.
//
//  Standard AVCaptureDevice video controls (zoom, focus, exposure, white
//  balance) are not available on macOS, so those settings are applied at the
//  layer/filter level by ShowStore. Gimbal pan/tilt, however, is real hardware
//  motion and is sent to the camera through ObsbotPTZController.
//

import Foundation
import OSLog

/// Manages `CameraSettings` for physical cameras and the OBSBOT gimbal.
@MainActor
@Observable
final class CameraControlService {
    private static let logger = Logger(subsystem: "com.woodseedigi.freestage", category: "CameraControlService")

    /// Gimbal backend. Exposed read-only for UI (connection state, ranges).
    let ptz = ObsbotPTZController()

    /// Desired settings per camera uniqueID (kept for reconnect / presets).
    private var pendingSettings: [String: CameraSettings] = [:]

    /// Whether the user has explicitly connected the gimbal this session.
    /// Hardware commands are only sent while connected.
    var isGimbalConnected: Bool { ptz.isConnected }

    // MARK: - Settings store

    /// Store the desired settings for a camera uniqueID and apply them.
    func setSettings(_ settings: CameraSettings?, for uniqueID: String) {
        pendingSettings[uniqueID] = settings
        if let settings {
            apply(settings: settings, to: uniqueID)
        }
    }

    /// Retrieve the pending settings for a camera, if any.
    func settings(for uniqueID: String) -> CameraSettings? {
        pendingSettings[uniqueID]
    }

    // MARK: - Gimbal connection

    func connectGimbal(transport: ObsbotPTZController.Transport, captureUniqueID: String?) {
        NSLog("[CameraControlService] connectGimbal transport=%@ captureUniqueID=%@", transport.rawValue, captureUniqueID ?? "nil")
        GimbalLog.log("connectGimbal transport=\(transport.rawValue) captureUniqueID=\(captureUniqueID ?? "nil")")
        ptz.connect(transport: transport, captureUniqueID: captureUniqueID)
        NSLog("[CameraControlService] connectGimbal result: isConnected=%d", ptz.isConnected ? 1 : 0)
        GimbalLog.log("connectGimbal result: isConnected=\(ptz.isConnected) name=\(ptz.deviceName ?? "nil") error=\(ptz.lastError ?? "nil")")
        Self.logger.info("Gimbal connect (\(transport.rawValue, privacy: .public)): \(self.ptz.isConnected ? "connected" : "failed", privacy: .public)")
    }

    func disconnectGimbal() {
        NSLog("[CameraControlService] disconnectGimbal")
        ptz.disconnect()
    }

    // MARK: - Applying settings to hardware

    /// Apply settings to the physical device.
    ///
    /// Gimbal pan/tilt is sent (clamped to the camera's limit zone) when the
    /// snapshot is gimbal-active and the gimbal is connected. All other fields
    /// are layer-side and handled by ShowStore.
    ///
    /// - Parameters:
    ///   - settings: The desired snapshot.
    ///   - uniqueID: AVCaptureDevice.uniqueID of the target camera.
    ///   - limitZone: Optional keep-out zone; when provided and enabled, the
    ///     gimbal target is clamped into it before sending.
    func apply(settings: CameraSettings, to uniqueID: String, limitZone: CameraLimitZone? = nil) {
        guard settings.gimbalActive else {
            NSLog("[CameraControlService] apply skipped: gimbalActive=false (id=%@)", uniqueID)
            GimbalLog.log("apply skipped: gimbalActive=false (id=\(uniqueID))")
            return
        }
        guard ptz.isConnected else {
            NSLog("[CameraControlService] apply skipped: gimbal not connected (id=%@)", uniqueID)
            GimbalLog.log("apply skipped: gimbal not connected (id=\(uniqueID)) — slider moved but nothing sent to hardware")
            return
        }

        var pan = settings.gimbalPan
        var tilt = settings.gimbalTilt
        if let limitZone, limitZone.isEnabled {
            let clamped = limitZone.clamp(pan: pan, tilt: tilt)
            pan = clamped.pan
            tilt = clamped.tilt
        }

        ptz.moveTo(pan: pan, tilt: tilt)
        Self.logger.debug("Gimbal move \(pan, privacy: .public)°/\(tilt, privacy: .public)° (zone: \(limitZone?.isEnabled ?? false, privacy: .public))")
        GimbalLog.log("apply→moveTo pan=\(pan) tilt=\(tilt) zoneEnabled=\(limitZone?.isEnabled ?? false)")
    }
}
