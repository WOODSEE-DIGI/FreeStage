//
//  StreamingService+Environment.swift
//  FreeStage
//
//  Environment key for StreamingService.
//

import SwiftUI

private struct StreamingServiceKey: EnvironmentKey {
    static let defaultValue: StreamingService? = nil
}

extension EnvironmentValues {
    var streamingService: StreamingService? {
        get { self[StreamingServiceKey.self] }
        set { self[StreamingServiceKey.self] = newValue }
    }
}
