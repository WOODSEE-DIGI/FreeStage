//
//  OSCCueServer+Environment.swift
//  FreeStage
//
//  Environment key for OSCCueServer.
//

import SwiftUI

private struct OSCCueServerKey: EnvironmentKey {
    static let defaultValue: OSCCueServer? = nil
}

extension EnvironmentValues {
    var oscCueServer: OSCCueServer? {
        get { self[OSCCueServerKey.self] }
        set { self[OSCCueServerKey.self] = newValue }
    }
}
