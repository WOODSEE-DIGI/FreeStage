//
//  CameraControlService+Environment.swift
//  FreeStage
//
//  SwiftUI environment key for the shared camera control service.
//

import SwiftUI

private struct CameraControlServiceKey: EnvironmentKey {
    static let defaultValue: CameraControlService? = nil
}

extension EnvironmentValues {
    var cameraControlService: CameraControlService? {
        get { self[CameraControlServiceKey.self] }
        set { self[CameraControlServiceKey.self] = newValue }
    }
}
