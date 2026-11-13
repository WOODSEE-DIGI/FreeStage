//
//  ShowDocumentSaver+Environment.swift
//  FreeStage
//
//  Environment key for ShowDocumentSaver.
//

import SwiftUI

private struct ShowDocumentSaverKey: EnvironmentKey {
    static let defaultValue: ShowDocumentSaver? = nil
}

extension EnvironmentValues {
    var showDocumentSaver: ShowDocumentSaver? {
        get { self[ShowDocumentSaverKey.self] }
        set { self[ShowDocumentSaverKey.self] = newValue }
    }
}
