//
//  CameraDevice.swift
//  FreeStage
//
//  Model representing an available AVCaptureDevice.
//

import Foundation
import AVFoundation

struct CameraDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let uniqueID: String
    let isOBSBOT: Bool

    init(device: AVCaptureDevice) {
        self.name = device.localizedName
        self.uniqueID = device.uniqueID
        self.id = device.uniqueID
        self.isOBSBOT = device.localizedName.lowercased().contains("obsbot")
    }
}

extension CameraDevice {
    static func discover() -> [CameraDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .external,
                .continuityCamera,
            ],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.map(CameraDevice.init)
    }
}
