//
//  GoStreamController+Environment.swift
//  FreeStage
//
//  SwiftUI environment key for the shared GoStream switcher controller.
//

import SwiftUI

private struct GoStreamControllerKey: EnvironmentKey {
    static let defaultValue: GoStreamController? = nil
}

extension EnvironmentValues {
    var goStreamController: GoStreamController? {
        get { self[GoStreamControllerKey.self] }
        set { self[GoStreamControllerKey.self] = newValue }
    }
}
