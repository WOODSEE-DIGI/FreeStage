//
//  ScreenCaptureManager+Environment.swift
//  FreeStage
//
//  Environment key for ScreenCaptureManager.
//

import SwiftUI

private struct ScreenCaptureManagerKey: EnvironmentKey {
    static let defaultValue: ScreenCaptureManager? = nil
}

extension EnvironmentValues {
    var screenCaptureManager: ScreenCaptureManager? {
        get { self[ScreenCaptureManagerKey.self] }
        set { self[ScreenCaptureManagerKey.self] = newValue }
    }
}
