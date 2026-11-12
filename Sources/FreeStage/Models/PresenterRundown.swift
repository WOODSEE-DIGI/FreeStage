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
    /// For videoPackage segments: the trimmed video clip.
    var videoClip: VideoClip?
    /// For cameraGraphic segments: which camera angle to use.
    var cameraAngle: PresenterCameraAngle
    /// Optional chroma-key filter applied to the camera layer.
    var chromaKeyFilter: ChromaKeyFilter?
    /// Optional camera settings (gimbal pose, zoom, etc.) applied to the camera layer.
    var cameraSettings: CameraSettings?
    /// If true, automatically advance to the next segment when this one ends.
    /// Primarily used for video packages.
    var autoFollow: Bool
    var notes: String

    /// Backward-compatible accessor for the original video URL.
    var mediaURL: URL? {
        videoClip?.sourceURL
    }

    /// Backward-compatible accessor for the effective trimmed duration.
    var duration: TimeInterval? {
        videoClip?.trimmedDuration ?? videoClip?.sourceDuration
    }

    init(
        id: UUID = UUID(),
        name: String = "New Segment",
        type: PresenterSegmentType = .cameraGraphic,
        placeholderID: UUID? = nil,
        videoClip: VideoClip? = nil,
        cameraAngle: PresenterCameraAngle = .primary,
        chromaKeyFilter: ChromaKeyFilter? = nil,
        cameraSettings: CameraSettings? = nil,
        autoFollow: Bool = false,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.placeholderID = placeholderID
        self.videoClip = videoClip
        self.cameraAngle = cameraAngle
        self.chromaKeyFilter = chromaKeyFilter
        self.cameraSettings = cameraSettings
        self.autoFollow = autoFollow
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, type, placeholderID, videoClip, cameraAngle
        case chromaKeyFilter, cameraSettings, autoFollow, notes
        case mediaURL, duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(PresenterSegmentType.self, forKey: .type)
        placeholderID = try container.decodeIfPresent(UUID.self, forKey: .placeholderID)
        cameraAngle = try container.decodeIfPresent(PresenterCameraAngle.self, forKey: .cameraAngle) ?? .primary
        chromaKeyFilter = try container.decodeIfPresent(ChromaKeyFilter.self, forKey: .chromaKeyFilter)
        cameraSettings = try container.decodeIfPresent(CameraSettings.self, forKey: .cameraSettings)
        autoFollow = try container.decodeIfPresent(Bool.self, forKey: .autoFollow) ?? false
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""

        if let clip = try container.decodeIfPresent(VideoClip.self, forKey: .videoClip) {
            videoClip = clip
        } else if let url = try container.decodeIfPresent(URL.self, forKey: .mediaURL) {
            // Migrate old mediaURL/duration fields into a VideoClip.
            let duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
            videoClip = VideoClip(sourceURL: url, sourceDuration: duration)
        } else {
            videoClip = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(placeholderID, forKey: .placeholderID)
        try container.encodeIfPresent(videoClip, forKey: .videoClip)
        try container.encode(cameraAngle, forKey: .cameraAngle)
        try container.encodeIfPresent(chromaKeyFilter, forKey: .chromaKeyFilter)
        try container.encodeIfPresent(cameraSettings, forKey: .cameraSettings)
        try container.encode(autoFollow, forKey: .autoFollow)
        try container.encode(notes, forKey: .notes)
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
