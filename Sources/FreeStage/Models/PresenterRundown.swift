//
//  PresenterRundown.swift
//  FreeStage
//
//  Data model for the presenter-to-camera show system: a linear rundown of
//  segments, each with a camera angle, an optional graphic placeholder, and
//  optional auto-follow behaviour. Placeholders are named slots so the same
//  rundown can be reused with different graphics.
//

import Foundation

/// The presenter-mode document: an ordered list of segments plus a library of
/// named placeholders that segments reference by ID.
struct PresenterRundown: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var segments: [PresenterSegment]
    var placeholders: [PresenterPlaceholder]
    /// Device uniqueID for the primary presenter camera.
    var primaryCameraID: String?
    /// Device uniqueID for the secondary/alt angle camera.
    var secondaryCameraID: String?

    init(
        id: UUID = UUID(),
        segments: [PresenterSegment] = [],
        placeholders: [PresenterPlaceholder] = [],
        primaryCameraID: String? = nil,
        secondaryCameraID: String? = nil
    ) {
        self.id = id
        self.segments = segments
        self.placeholders = placeholders
        self.primaryCameraID = primaryCameraID
        self.secondaryCameraID = secondaryCameraID
    }

    /// A default starter rundown with one of each segment type.
    static func `default`() -> PresenterRundown {
        var rundown = PresenterRundown()
        rundown.segments = [
            PresenterSegment(name: "Intro", type: .titleCard, autoFollow: false),
            PresenterSegment(name: "Opening Monologue", type: .cameraGraphic, cameraAngle: .primary, autoFollow: false),
            PresenterSegment(name: "Story Package", type: .videoPackage, autoFollow: true),
            PresenterSegment(name: "Closing", type: .cameraGraphic, cameraAngle: .primary, autoFollow: false),
            PresenterSegment(name: "Outro", type: .titleCard, autoFollow: false),
            PresenterSegment(name: "Break", type: .stationBreak, autoFollow: false)
        ]
        return rundown
    }
}

/// A single item in a presenter rundown.
struct PresenterSegment: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var type: PresenterSegmentType
    /// For cameraGraphic / titleCard segments: the placeholder to display.
    var placeholderID: UUID?
    /// For videoPackage segments: the video file URL.
    var mediaURL: URL?
    /// Cached duration of the selected video, in seconds.
    var duration: TimeInterval?
    /// For cameraGraphic segments: which camera angle to use.
    var cameraAngle: PresenterCameraAngle
    /// If true, automatically advance to the next segment when this one ends.
    /// Primarily used for video packages.
    var autoFollow: Bool
    var notes: String

    init(
        id: UUID = UUID(),
        name: String = "New Segment",
        type: PresenterSegmentType = .cameraGraphic,
        placeholderID: UUID? = nil,
        mediaURL: URL? = nil,
        duration: TimeInterval? = nil,
        cameraAngle: PresenterCameraAngle = .primary,
        autoFollow: Bool = false,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.placeholderID = placeholderID
        self.mediaURL = mediaURL
        self.duration = duration
        self.cameraAngle = cameraAngle
        self.autoFollow = autoFollow
        self.notes = notes
    }
}

enum PresenterSegmentType: String, Codable, CaseIterable, Identifiable, Sendable {
    case cameraGraphic
    case videoPackage
    case titleCard
    case stationBreak

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cameraGraphic: return "Camera + Graphic"
        case .videoPackage: return "Video Package"
        case .titleCard: return "Title Card"
        case .stationBreak: return "Break"
        }
    }

    var iconName: String {
        switch self {
        case .cameraGraphic: return "video.fill.badge.plus"
        case .videoPackage: return "film"
        case .titleCard: return "text.bubble"
        case .stationBreak: return "moon.fill"
        }
    }
}

enum PresenterCameraAngle: String, Codable, CaseIterable, Identifiable, Sendable {
    case primary
    case secondary

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .primary: return "Primary Camera"
        case .secondary: return "Secondary Camera"
        }
    }
}

/// A named slot that a segment can reference. The source can be swapped
/// without changing the rundown, making shows reusable.
struct PresenterPlaceholder: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    /// The actual pixel source assigned to this slot. Nil means the slot is
    /// empty and will render as transparent/black depending on the segment.
    var source: Source?

    init(
        id: UUID = UUID(),
        name: String = "Placeholder",
        source: Source? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
    }
}
