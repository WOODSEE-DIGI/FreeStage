//
//  CueTriggerServer+Environment.swift
//  FreeStage
//
//  Environment key for CueTriggerServer.
//

import SwiftUI

private struct CueTriggerServerKey: EnvironmentKey {
    static let defaultValue: CueTriggerServer? = nil
}

extension EnvironmentValues {
    var cueTriggerServer: CueTriggerServer? {
        get { self[CueTriggerServerKey.self] }
        set { self[CueTriggerServerKey.self] = newValue }
    }
}
