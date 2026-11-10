//
//  RecordingService+Environment.swift
//  FreeStage
//
//  Environment key for RecordingService.
//

import SwiftUI

private struct RecordingServiceKey: EnvironmentKey {
    static let defaultValue: RecordingService? = nil
}

extension EnvironmentValues {
    var recordingService: RecordingService? {
        get { self[RecordingServiceKey.self] }
        set { self[RecordingServiceKey.self] = newValue }
    }
}
