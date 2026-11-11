//
//  ThemeStore+Environment.swift
//  FreeStage
//
//  Environment key for the shared ThemeStore.
//

import SwiftUI

private struct ThemeStoreKey: EnvironmentKey {
    static let defaultValue: ThemeStore? = nil
}

extension EnvironmentValues {
    var themeStore: ThemeStore? {
        get { self[ThemeStoreKey.self] }
        set { self[ThemeStoreKey.self] = newValue }
    }
}
