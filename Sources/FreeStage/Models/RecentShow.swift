//
//  RecentShow.swift
//  FreeStage
//
//  A recently opened FreeStage show package for the project manager dashboard.
//

import Foundation

struct RecentShow: Identifiable, Hashable, Codable, Sendable {
    /// The resolved file-system path of the show package.
    let id: String
    var name: String
    var path: String
    var dateAdded: Date

    init(url: URL) {
        self.id = url.path
        self.name = url.deletingPathExtension().lastPathComponent
        self.path = url.path
        self.dateAdded = Date()
    }

    var resolvedURL: URL? {
        URL(fileURLWithPath: path)
    }
}
