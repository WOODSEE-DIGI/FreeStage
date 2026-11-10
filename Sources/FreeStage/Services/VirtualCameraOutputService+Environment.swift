//
//  VirtualCameraOutputService+Environment.swift
//  FreeStage
//
//  Injects the virtual camera service into the SwiftUI environment.
//

import SwiftUI

private struct VirtualCameraOutputServiceKey: EnvironmentKey {
    static let defaultValue: VirtualCameraOutputService? = nil
}

extension EnvironmentValues {
    var virtualCameraOutputService: VirtualCameraOutputService? {
        get { self[VirtualCameraOutputServiceKey.self] }
        set { self[VirtualCameraOutputServiceKey.self] = newValue }
    }
}
