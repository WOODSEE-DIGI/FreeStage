//
//  RecentShow.swift
//  FreeStage
//
//  A recently opened FreeStage show package for the project manager
//  dashboard. Bookmarks are kept so sandboxed file access survives relaunches.
//

import Foundation

struct RecentShow: Identifiable, Hashable, Codable, Sendable {
    /// The resolved file-system path of the show package.
    let id: String
    var name: String
    var path: String
    var bookmarkData: Data?
    var dateAdded: Date

    init(url: URL, bookmarkData: Data? = nil) {
        self.id = url.path
        self.name = url.deletingPathExtension().lastPathComponent
        self.path = url.path
        self.bookmarkData = bookmarkData
        self.dateAdded = Date()
    }

    /// Resolve the bookmark, if any, back to a file URL. Falls back to the
    /// stored path for non-sandboxed or legacy entries.
    var resolvedURL: URL? {
        if let bookmarkData,
           let url = SecurityScopedBookmark.resolve(bookmarkData) {
            return url
        }
        return URL(fileURLWithPath: path)
    }
}
