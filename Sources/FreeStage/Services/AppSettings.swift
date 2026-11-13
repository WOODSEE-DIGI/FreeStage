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
import OSLog

/// Persistent application-level settings for recording and show behavior.
@Observable
final class AppSettings: @unchecked Sendable {
    private enum Key: String {
        case libraryRootPath
        case librarySetupCompleted
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
        case defaultInputDeviceID
        case defaultOutputDeviceID
        case defaultMicrophoneVolume
        case defaultSystemVolume
        case defaultMasterVolume
        case defaultOutputMuted
        case audioBitrate
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

    private static let logger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "AppSettings")

    /// Show-library root, resolved once at launch so SwiftUI observes a stored value.
    private var libraryRootURL: URL

    /// Explicit recording-directory override picked in Settings, if any.
    private var recordingDirectoryOverrideURL: URL?

    /// Outcome of the most recent library preparation, so Settings can report problems.
    private(set) var lastLibraryPreparation: ShowLibrary.PreparationResult?

    init() {
        let root = defaults.string(forKey: Key.libraryRootPath.rawValue)
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? ShowLibrary.defaultRoot()
        let library = ShowLibrary(root: root)
        libraryRootURL = library.root

        // Drop a stored override that predates the show library (the old default
        // was the library root itself) or that no longer exists, so recordings
        // follow the library's Output/Recordings folder.
        if let stored = defaults.string(forKey: Key.recordingDirectoryPath.rawValue) {
            let candidate = URL(fileURLWithPath: stored, isDirectory: true).standardizedFileURL
            let isStale = candidate == library.root || !FileManager.default.fileExists(atPath: candidate.path)
            if !isStale {
                recordingDirectoryOverrideURL = candidate
            } else {
                defaults.removeObject(forKey: Key.recordingDirectoryPath.rawValue)
            }
        }
    }

    // MARK: - Show library

    /// Root of the FreeStage show library (global assets, shows and output).
    var libraryRoot: URL {
        get { libraryRootURL }
        set {
            let previous = libraryRootURL
            let resolved = newValue.standardizedFileURL
            guard resolved != previous else { return }

            libraryRootURL = resolved
            defaults.set(resolved.path, forKey: Key.libraryRootPath.rawValue)
            adoptRecordingsIntoNewRoot(from: previous)
            prepareLibrary()
        }
    }

    /// The library rooted at `libraryRoot`.
    var library: ShowLibrary { ShowLibrary(root: libraryRootURL) }

    /// Whether first-run library setup has been completed.
    var hasCompletedLibrarySetup: Bool {
        get { defaults.bool(forKey: Key.librarySetupCompleted.rawValue) }
        set { defaults.set(newValue, forKey: Key.librarySetupCompleted.rawValue) }
    }

    /// Persist the chosen root, create the folder template and mark setup as done.
    @discardableResult
    func completeLibrarySetup(root: URL) -> ShowLibrary.PreparationResult {
        libraryRoot = root
        let result = prepareLibrary()
        hasCompletedLibrarySetup = true
        return result
    }

    /// Create any missing folders in the current library. Safe to call on launch.
    @discardableResult
    func prepareLibrary() -> ShowLibrary.PreparationResult {
        let result = library.prepare()
        lastLibraryPreparation = result
        return result
    }

    /// Point recordings at `<root>/Output/Recordings` if the user's custom
    /// location lived inside the previous library.
    private func adoptRecordingsIntoNewRoot(from previous: URL) {
        guard let override = recordingDirectoryOverrideURL else { return }
        guard Self.isDescendant(override, of: previous) else { return }
        recordingDirectoryOverrideURL = nil
        defaults.removeObject(forKey: Key.recordingDirectoryPath.rawValue)
    }

    private static func isDescendant(_ url: URL, of parent: URL) -> Bool {
        let childPath = url.standardizedFileURL.resolvingSymlinksInPath().path
        let parentPath = parent.standardizedFileURL.resolvingSymlinksInPath().path
        guard parentPath != "/" else { return true }
        return childPath == parentPath || childPath.hasPrefix(parentPath + "/")
    }

    /// Where recordings go when they have not been overridden in Settings.
    var libraryRecordingDirectory: URL { library.recordings }

    /// Directory where new recordings are saved. Defaults to
    /// `<libraryRoot>/Output/Recordings`.
    var recordingDirectory: URL {
        get { recordingDirectoryOverrideURL ?? libraryRecordingDirectory }
        set {
            let resolved = newValue.standardizedFileURL
            if resolved == libraryRecordingDirectory.standardizedFileURL {
                resetRecordingDirectory()
            } else {
                recordingDirectoryOverrideURL = resolved
                defaults.set(resolved.path, forKey: Key.recordingDirectoryPath.rawValue)
            }
        }
    }

    /// True when recordings are written somewhere other than the library default.
    var hasCustomRecordingDirectory: Bool { recordingDirectoryOverrideURL != nil }

    /// Send new recordings back to the library's `Output/Recordings` folder.
    func resetRecordingDirectory() {
        recordingDirectoryOverrideURL = nil
        defaults.removeObject(forKey: Key.recordingDirectoryPath.rawValue)
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

    // MARK: - Audio defaults

    /// Last-selected audio input device unique ID. nil means "System Default".
    var defaultInputDeviceID: String? {
        get { defaults.string(forKey: Key.defaultInputDeviceID.rawValue) }
        set { defaults.set(newValue, forKey: Key.defaultInputDeviceID.rawValue) }
    }

    /// Last-selected audio output device ID. nil means "System Default".
    var defaultOutputDeviceID: UInt32? {
        get {
            let value = defaults.object(forKey: Key.defaultOutputDeviceID.rawValue) as? Int
            return value.map { UInt32($0) }
        }
        set {
            if let newValue {
                defaults.set(Int(newValue), forKey: Key.defaultOutputDeviceID.rawValue)
            } else {
                defaults.removeObject(forKey: Key.defaultOutputDeviceID.rawValue)
            }
        }
    }

    /// Default microphone channel volume (0...2).
    var defaultMicrophoneVolume: Double {
        get { defaults.object(forKey: Key.defaultMicrophoneVolume.rawValue) as? Double ?? 1.0 }
        set { defaults.set(newValue, forKey: Key.defaultMicrophoneVolume.rawValue) }
    }

    /// Default system-audio channel volume (0...2).
    var defaultSystemVolume: Double {
        get { defaults.object(forKey: Key.defaultSystemVolume.rawValue) as? Double ?? 1.0 }
        set { defaults.set(newValue, forKey: Key.defaultSystemVolume.rawValue) }
    }

    /// Default master output volume (0...2).
    var defaultMasterVolume: Double {
        get { defaults.object(forKey: Key.defaultMasterVolume.rawValue) as? Double ?? 1.0 }
        set { defaults.set(newValue, forKey: Key.defaultMasterVolume.rawValue) }
    }

    /// Whether output is muted by default.
    var defaultOutputMuted: Bool {
        get { defaults.object(forKey: Key.defaultOutputMuted.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.defaultOutputMuted.rawValue) }
    }

    /// Audio bitrate for recordings. 384 kbps is YouTube's recommended stereo
    /// bitrate for high-quality uploads.
    var audioBitrate: Int {
        get { defaults.object(forKey: Key.audioBitrate.rawValue) as? Int ?? 384_000 }
        set { defaults.set(newValue, forKey: Key.audioBitrate.rawValue) }
    }

    /// Generate a unique filename inside `recordingDirectory`, creating the
    /// folder first if needed.
    func nextRecordingURL() -> URL {
        let directory = recordingDirectory
        if !library.ensureDirectory(directory) {
            Self.logger.error("Recording directory unavailable: \(directory.path, privacy: .public)")
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let name = "FreeStage-\(formatter.string(from: Date())).\(recordingFormat.fileExtension)"
        return directory.appendingPathComponent(name)
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

