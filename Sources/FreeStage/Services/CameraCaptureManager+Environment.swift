//
//  CameraCaptureManager+Environment.swift
//  FreeStage
//
//  Environment key for passing the camera capture manager through the view
//  hierarchy without requiring Observable conformance.
//

import SwiftUI

private struct CameraCaptureManagerKey: EnvironmentKey {
    static let defaultValue: CameraCaptureManager? = nil
}

extension EnvironmentValues {
    var cameraCaptureManager: CameraCaptureManager? {
        get { self[CameraCaptureManagerKey.self] }
        set { self[CameraCaptureManagerKey.self] = newValue }
    }
}
