//
//  AppSettings+Environment.swift
//  FreeStage
//
//  Environment key for AppSettings.
//

import SwiftUI

private struct AppSettingsKey: EnvironmentKey {
    static let defaultValue: AppSettings? = nil
}

extension EnvironmentValues {
    var appSettings: AppSettings? {
        get { self[AppSettingsKey.self] }
        set { self[AppSettingsKey.self] = newValue }
    }
}
