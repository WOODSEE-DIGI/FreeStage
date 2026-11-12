//
//  VideoClip.swift
//  FreeStage
//
//  A trimmed video section for Presenter-mode Video Package segments.
//  Stores the original source, in/out points, an optional lower-resolution
//  proxy for scrubbing, and an optional exported subclip for instant
//  final playback.
//

import Foundation

struct VideoClip: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    /// The original video file selected by the user.
    var sourceURL: URL
    /// Cached duration of the original source, in seconds.
    var sourceDuration: TimeInterval?
    /// Start time of the playable section.
    var inPoint: TimeInterval
    /// End time of the playable section. nil means play to the end of the file.
    var outPoint: TimeInterval?
    /// Lower-resolution proxy used for fast scrubbing in the clip editor.
    var proxyURL: URL?
    /// Exported subclip containing only inPoint...outPoint for instant playback.
    var subclipURL: URL?

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        sourceDuration: TimeInterval? = nil,
        inPoint: TimeInterval = 0,
        outPoint: TimeInterval? = nil,
        proxyURL: URL? = nil,
        subclipURL: URL? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.sourceDuration = sourceDuration
        self.inPoint = inPoint
        self.outPoint = outPoint
        self.proxyURL = proxyURL
        self.subclipURL = subclipURL
    }

    /// The URL that should be used for final playback: subclip if available,
    /// otherwise the original source.
    var playbackURL: URL {
        subclipURL ?? sourceURL
    }

    /// Effective duration of the trimmed section, falling back to the full
    /// source duration when no out point is set.
    var trimmedDuration: TimeInterval? {
        guard let sourceDuration else { return nil }
        let end = outPoint ?? sourceDuration
        return max(0, end - inPoint)
    }
}
