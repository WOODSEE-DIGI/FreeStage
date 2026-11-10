//
//  StreamDestination.swift
//  FreeStage
//
//  Model for an RTMP/RTMPS streaming destination.
//

import Foundation

struct StreamDestination: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var platform: StreamingPlatform
    var serverURL: String
    var streamKey: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        platform: StreamingPlatform = .custom,
        serverURL: String,
        streamKey: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.serverURL = serverURL
        self.streamKey = streamKey
        self.isEnabled = isEnabled
    }

    /// The full ingest URL, including the stream key if present.
    var ingestURL: URL? {
        let base = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        let key = streamKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = key.isEmpty ? base : "\(base)/\(key)"
        return URL(string: urlString)
    }
}

enum StreamingPlatform: String, CaseIterable, Codable, Identifiable, Sendable {
    case twitch
    case youtube
    case facebook
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .twitch: return "Twitch"
        case .youtube: return "YouTube"
        case .facebook: return "Facebook Live"
        case .custom: return "Custom RTMP"
        }
    }

    /// Default ingest URL template. Stream key is appended at runtime.
    var defaultServerURL: String {
        switch self {
        case .twitch:
            return "rtmp://live.twitch.tv/live"
        case .youtube:
            return "rtmp://a.rtmp.youtube.com/live2"
        case .facebook:
            return "rtmps://live-api-s.facebook.com:443/rtmp"
        case .custom:
            return ""
        }
    }
}
