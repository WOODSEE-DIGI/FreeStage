//
//  AppSettings.swift
//  FreeStage
//
//  User-facing application settings persisted to UserDefaults.
//

import Foundation
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// Persistent application-level settings for recording and show behavior.
@Observable
final class AppSettings: @unchecked Sendable {
    private enum Key: String {
        case recordingDirectoryPath
        case recordingFormat
        case recordingWidth
        case recordingHeight
        case recordingFrameRate
        case recordingBitrate
        case recordOnGo
        case autoStopRecordingOnShowEnd
        case startVirtualCameraOnShowMode
        case cueTriggerServerEnabled
        case cueTriggerServerPort
        case cueTriggerServerLocalhostOnly
        case oscCueServerEnabled
        case oscCueServerPort
        case recordingAutoSplitMinutes
        case recordingMinFreeSpaceMB
        case hideDesktopIconsDuringCapture
        case savedLayerDefaults
        case showStyles
        case selectedShowStyleID
        case appThemeID
        case recentShows
    }

    /// Recording container format + codec.
    enum RecordingFormat: String, CaseIterable, Identifiable, Sendable {
        case mp4H264
        case mp4HEVC

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .mp4H264: return "H.264"
            case .mp4HEVC: return "HEVC"
            }
        }

        var fileType: AVFileType {
            switch self {
            case .mp4H264, .mp4HEVC: return .mp4
            }
        }

        var videoCodec: String? {
            switch self {
            case .mp4H264: return AVVideoCodecType.h264.rawValue
            case .mp4HEVC: return AVVideoCodecType.hevc.rawValue
            }
        }

        var fileExtension: String {
            "mp4"
        }

        /// Whether the format needs an explicit bitrate setting.
        var supportsBitrate: Bool { true }
    }

    private let defaults = UserDefaults.standard
    private let defaultDirectory: URL = AppSettings.defaultRecordingDirectory()

    private var recordingDirectoryResolvedURL: URL?

    /// Default recording directory: ~/Movies/FreeStage, created on first use.
    private static func defaultRecordingDirectory() -> URL {
        let fileManager = FileManager.default
        guard let movies = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first else {
            return fileManager.temporaryDirectory
        }
        let directory = movies.appendingPathComponent("FreeStage", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Directory where new recordings are saved. Falls back to ~/Movies/FreeStage.
    var recordingDirectory: URL {
        get {
            if let cached = recordingDirectoryResolvedURL { return cached }
            if let path = defaults.string(forKey: Key.recordingDirectoryPath.rawValue) {
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: url.path) {
                    recordingDirectoryResolvedURL = url
                    return url
                }
            }
            return defaultDirectory
        }
        set {
            recordingDirectoryResolvedURL = newValue
            defaults.set(newValue.path, forKey: Key.recordingDirectoryPath.rawValue)
        }
    }

    var recordingFormat: RecordingFormat {
        get {
            let raw = defaults.string(forKey: Key.recordingFormat.rawValue)
            return raw.flatMap { RecordingFormat(rawValue: $0) } ?? .mp4H264
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.recordingFormat.rawValue)
        }
    }

    var recordingResolution: CGSize {
        get {
            let width = defaults.object(forKey: Key.recordingWidth.rawValue) as? Double
            let height = defaults.object(forKey: Key.recordingHeight.rawValue) as? Double
            if let width, let height {
                return CGSize(width: width, height: height)
            }
            return CGSize(width: 1920, height: 1080)
        }
        set {
            defaults.set(newValue.width, forKey: Key.recordingWidth.rawValue)
            defaults.set(newValue.height, forKey: Key.recordingHeight.rawValue)
        }
    }

    var recordingFrameRate: Int {
        get { defaults.object(forKey: Key.recordingFrameRate.rawValue) as? Int ?? 30 }
        set { defaults.set(newValue, forKey: Key.recordingFrameRate.rawValue) }
    }

    /// Video bitrate in bits per second.
    var recordingBitrate: Int {
        get { defaults.object(forKey: Key.recordingBitrate.rawValue) as? Int ?? 10_000_000 }
        set { defaults.set(newValue, forKey: Key.recordingBitrate.rawValue) }
    }

    /// Automatically start/stop recording from the GO button in Show mode.
    var recordOnGo: Bool {
        get { defaults.object(forKey: Key.recordOnGo.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.recordOnGo.rawValue) }
    }

    /// Stop recording when the show reaches its last cue.
    var autoStopRecordingOnShowEnd: Bool {
        get { defaults.object(forKey: Key.autoStopRecordingOnShowEnd.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoStopRecordingOnShowEnd.rawValue) }
    }

    /// Activate the virtual camera when switching to Show mode.
    var startVirtualCameraOnShowMode: Bool {
        get { defaults.object(forKey: Key.startVirtualCameraOnShowMode.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.startVirtualCameraOnShowMode.rawValue) }
    }

    /// Run the local cue trigger HTTP server on launch.
    var cueTriggerServerEnabled: Bool {
        get { defaults.object(forKey: Key.cueTriggerServerEnabled.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.cueTriggerServerEnabled.rawValue) }
    }

    /// TCP port for the cue trigger server.
    var cueTriggerServerPort: UInt16 {
        get {
            let stored = defaults.object(forKey: Key.cueTriggerServerPort.rawValue) as? Int
            return UInt16(clamping: stored ?? 17352)
        }
        set { defaults.set(Int(newValue), forKey: Key.cueTriggerServerPort.rawValue) }
    }

    /// Bind the HTTP trigger server to localhost only.
    var cueTriggerServerLocalhostOnly: Bool {
        get { defaults.object(forKey: Key.cueTriggerServerLocalhostOnly.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.cueTriggerServerLocalhostOnly.rawValue) }
    }

    /// Run the OSC cue input server on launch.
    var oscCueServerEnabled: Bool {
        get { defaults.object(forKey: Key.oscCueServerEnabled.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.oscCueServerEnabled.rawValue) }
    }

    /// UDP port for the OSC cue server.
    var oscCueServerPort: UInt16 {
        get {
            let stored = defaults.object(forKey: Key.oscCueServerPort.rawValue) as? Int
            return UInt16(clamping: stored ?? 17353)
        }
        set { defaults.set(Int(newValue), forKey: Key.oscCueServerPort.rawValue) }
    }

    /// Automatically start a new recording file after this many minutes. 0 = off.
    var recordingAutoSplitMinutes: Int {
        get { defaults.object(forKey: Key.recordingAutoSplitMinutes.rawValue) as? Int ?? 0 }
        set { defaults.set(newValue, forKey: Key.recordingAutoSplitMinutes.rawValue) }
    }

    /// Minimum free space (in MB) required on the recording volume before starting.
    var recordingMinFreeSpaceMB: Int {
        get { defaults.object(forKey: Key.recordingMinFreeSpaceMB.rawValue) as? Int ?? 1000 }
        set { defaults.set(newValue, forKey: Key.recordingMinFreeSpaceMB.rawValue) }
    }

    /// Hide desktop icons/folders when capturing the full display so the
    /// capture looks clean (matches Ecamm Live behavior).
    var hideDesktopIconsDuringCapture: Bool {
        get { defaults.object(forKey: Key.hideDesktopIconsDuringCapture.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.hideDesktopIconsDuringCapture.rawValue) }
    }

    /// Generate a unique filename inside `recordingDirectory`.
    func nextRecordingURL() -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let name = "FreeStage-\(formatter.string(from: Date())).\(recordingFormat.fileExtension)"
        return recordingDirectory.appendingPathComponent(name)
    }

    /// Layer defaults keyed by `Source.defaultsKey`. These are applied
    /// automatically when a layer with a matching source is added.
    var savedLayerDefaults: [String: LayerDefaults] {
        get {
            guard let data = defaults.data(forKey: Key.savedLayerDefaults.rawValue),
                  let decoded = try? JSONDecoder().decode([String: LayerDefaults].self, from: data) else {
                return [:]
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.savedLayerDefaults.rawValue)
            }
        }
    }

    /// Replace or insert a default for the given source key.
    func setLayerDefault(_ layerDefault: LayerDefaults) {
        var defaults = savedLayerDefaults
        defaults[layerDefault.sourceKey] = layerDefault
        savedLayerDefaults = defaults
    }

    /// Remove a saved default for a source key.
    func removeLayerDefault(for sourceKey: String) {
        var defaults = savedLayerDefaults
        defaults.removeValue(forKey: sourceKey)
        savedLayerDefaults = defaults
    }

    // MARK: - Show styles

    /// Saved show-style presets. New shows can pick one of these as their
    /// default graphic look.
    var showStyles: [ShowStyle] {
        get {
            guard let data = defaults.data(forKey: Key.showStyles.rawValue),
                  let decoded = try? JSONDecoder().decode([ShowStyle].self, from: data) else {
                return ShowStyle.allBuiltIns
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.showStyles.rawValue)
            }
        }
    }

    var selectedShowStyleID: String? {
        get { defaults.string(forKey: Key.selectedShowStyleID.rawValue) }
        set { defaults.set(newValue, forKey: Key.selectedShowStyleID.rawValue) }
    }

    /// The show style that should be used for new shows.
    var defaultShowStyle: ShowStyle {
        guard let idString = selectedShowStyleID,
              let id = UUID(uuidString: idString),
              let style = showStyles.first(where: { $0.id == id }) else {
            return ShowStyle.default
        }
        return style
    }

    // MARK: - App theme

    /// Identifier of the selected FreeStage UI theme.
    var appThemeID: String? {
        get { defaults.string(forKey: Key.appThemeID.rawValue) }
        set { defaults.set(newValue, forKey: Key.appThemeID.rawValue) }
    }

    // MARK: - Recent shows

    /// Recently opened FreeStage show packages for the project manager.
    var recentShows: [RecentShow] {
        get {
            guard let data = defaults.data(forKey: Key.recentShows.rawValue),
                  let decoded = try? JSONDecoder().decode([RecentShow].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.recentShows.rawValue)
            }
        }
    }

    /// Add or move a show to the front of the recent-shows list.
    func addRecentShow(url: URL) {
        let entry = RecentShow(url: url)
        var recents = recentShows.filter { $0.id != entry.id }
        recents.insert(entry, at: 0)
        recentShows = Array(recents.prefix(20))
    }

    /// Remove a recent-show entry.
    func removeRecentShow(id: String) {
        recentShows = recentShows.filter { $0.id != id }
    }
}

