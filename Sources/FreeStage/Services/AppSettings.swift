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
        case recordingDirectoryBookmark
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
            if let data = defaults.data(forKey: Key.recordingDirectoryBookmark.rawValue) {
                var isStale = false
                if let bookmark = try? URL(
                    resolvingBookmarkData: data,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ), !isStale {
                    let accessible = bookmark.startAccessingSecurityScopedResource()
                    if accessible && FileManager.default.fileExists(atPath: bookmark.path) {
                        recordingDirectoryResolvedURL = bookmark
                        return bookmark
                    }
                }
            }
            return defaultDirectory
        }
        set {
            recordingDirectoryResolvedURL = newValue
            if let data = try? newValue.bookmarkData(options: .withSecurityScope) {
                defaults.set(data, forKey: Key.recordingDirectoryBookmark.rawValue)
            }
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
}

