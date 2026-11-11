//
//  SecurityScopedBookmark.swift
//  FreeStage
//
//  Helpers for creating and resolving App Sandbox security-scoped bookmarks,
//  and for wrapping file access with start/stop calls. Required so show files
//  can reload image, video, and slideshow sources after the app restarts.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.woodseedigi.freestage", category: "SecurityScopedBookmark")

enum SecurityScopedBookmark {
    /// Create a security-scoped bookmark for a file URL. Returns nil for
    /// non-file URLs or if bookmark creation fails (e.g., the file is outside
    /// the sandbox and the user has not granted access via a picker).
    static func create(for url: URL) -> Data? {
        guard url.isFileURL else { return nil }
        do {
            return try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            logger.warning("Failed to create bookmark for \(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    /// Resolve bookmark data back into a file URL. Returns nil if the bookmark
    /// is stale or cannot be resolved.
    static func resolve(_ data: Data) -> URL? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                logger.warning("Stale security-scoped bookmark for \(url.path)")
                return nil
            }
            return url
        } catch {
            logger.warning("Failed to resolve bookmark: \(error.localizedDescription)")
            return nil
        }
    }
}

/// Execute `body` while accessing a security-scoped URL. For non-scoped URLs
/// this is a no-op aside from the closure call. Always pairs start/stop.
func accessSecurityScopedResource<T>(url: URL, _ body: () throws -> T) rethrows -> T {
    let didStart = url.startAccessingSecurityScopedResource()
    defer {
        if didStart {
            url.stopAccessingSecurityScopedResource()
        }
    }
    return try body()
}
