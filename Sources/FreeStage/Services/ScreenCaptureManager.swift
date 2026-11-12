//
//  ScreenCaptureManager.swift
//  FreeStage
//
//  Manages ScreenCaptureKit streams for `.screen` layers. Keeps a dedicated
//  Metal texture per active display so the renderer always samples a valid frame.
//

import Foundation
import ScreenCaptureKit
import CoreVideo
import CoreGraphics
import Metal
import AppKit
import OSLog

/// Thread-safe manager for screen capture streams and their latest frames.
@available(macOS 12.3, *)
final class ScreenCaptureManager: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.woodseedigi.freestage", category: "ScreenCaptureManager")

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let captureQueue = DispatchQueue(label: "com.woodseedigi.freestage.screencapture", qos: .userInteractive)
    private var streams: [CGDirectDisplayID: SCStream] = [:]
    private var delegates: [CGDirectDisplayID: StreamDelegate] = [:]
    private var textures: [CGDirectDisplayID: MTLTexture] = [:]
    private let lock = NSLock()

    /// Optional mixer that receives captured system audio.
    weak var audioMixer: AudioMixer?

    /// When true, exclude the Finder desktop window so wallpaper is captured
    /// but desktop icons/folders are not (matching Ecamm Live behavior).
    var excludeDesktopIcons = false

    init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            fatalError("Metal is not available on this Mac.")
        }
        self.device = device
        self.commandQueue = commandQueue
    }

    /// Start capturing the display with the given ID if not already active.
    func startCapture(displayID: CGDirectDisplayID) {
        let shouldStart = lock.withLock { () -> Bool in
            guard streams[displayID] == nil else { return false }
            return true
        }
        guard shouldStart else { return }

        Task { @MainActor in
            await createStream(displayID: displayID)
        }
    }

    @MainActor
    private func createStream(displayID: CGDirectDisplayID) async {
        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                Self.logger.warning(
                    "Display \(displayID) not found in shareable content (screen recording granted: \(Self.hasScreenRecordingPermission))"
                )
                return
            }

            let excludedWindows = excludeDesktopIcons ? Self.desktopWindows(in: content) : []
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.showsCursor = true
            // Only ask for audio when something is listening. A denied
            // microphone permission must never stop the display stream.
            config.capturesAudio = audioMixer != nil

            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            let delegate = StreamDelegate(manager: self, displayID: displayID)
            try stream.addStreamOutput(delegate, type: SCStreamOutputType.screen, sampleHandlerQueue: captureQueue)
            if config.capturesAudio {
                do {
                    try stream.addStreamOutput(delegate, type: SCStreamOutputType.audio, sampleHandlerQueue: captureQueue)
                } catch {
                    // Video capture is still useful without system audio.
                    Self.logger.error("Screen capture audio unavailable for \(displayID): \(error.localizedDescription)")
                }
            }
            try await stream.startCapture()

            lock.withLock {
                streams[displayID] = stream
                delegates[displayID] = delegate
            }

            Self.logger.info("Started screen capture for display \(displayID)")
        } catch {
            Self.logger.error("Failed to start screen capture for \(displayID): \(error.localizedDescription)")
            if Self.isPermissionError(error) {
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .screenCapturePermissionDenied,
                        object: nil,
                        userInfo: ["displayID": displayID, "error": error]
                    )
                }
            }
        }
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        let description = error.localizedDescription.lowercased()
        return description.contains("declined tcc") || description.contains("user declined")
    }

    /// Reconcile running streams with the set of display IDs that should be active.
    func syncCaptures(requiredIDs: Set<CGDirectDisplayID>) {
        let (toStop, toStart) = lock.withLock { () -> (Set<CGDirectDisplayID>, Set<CGDirectDisplayID>) in
            let currentIDs = Set(streams.keys)
            return (currentIDs.subtracting(requiredIDs), requiredIDs.subtracting(currentIDs))
        }

        for id in toStop {
            stopCapture(displayID: id)
        }
        for id in toStart {
            startCapture(displayID: id)
        }
    }

    /// Stop capturing the display with the given ID.
    func stopCapture(displayID: CGDirectDisplayID) {
        let stream = lock.withLock { () -> SCStream? in
            let stream = streams.removeValue(forKey: displayID)
            delegates.removeValue(forKey: displayID)
            textures.removeValue(forKey: displayID)
            return stream
        }

        Task { @MainActor in
            do {
                try await stream?.stopCapture()
            } catch {
                Self.logger.error("Failed to stop screen capture for \(displayID): \(error.localizedDescription)")
            }
        }
    }

    /// Stop all active screen capture streams.
    func stopAll() {
        let (allStreams, allIDs) = lock.withLock { () -> ([SCStream], [CGDirectDisplayID]) in
            let values = Array(streams.values)
            let keys = Array(streams.keys)
            streams.removeAll()
            delegates.removeAll()
            textures.removeAll()
            return (values, keys)
        }

        Task { @MainActor in
            for stream in allStreams {
                try? await stream.stopCapture()
            }
        }
        Self.logger.info("Stopped all screen captures: \(allIDs.count)")
    }

    /// Copy a new frame into the dedicated texture for this display.
    /// Called from the capture queue.
    func storeFrame(displayID: CGDirectDisplayID, buffer: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)

        let existing = lock.withLock { textures[displayID] }
        let texture: MTLTexture

        if let existing, existing.width == width, existing.height == height {
            texture = existing
        } else {
            let descriptor = MTLTextureDescriptor()
            descriptor.width = width
            descriptor.height = height
            descriptor.pixelFormat = .bgra8Unorm
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .shared
            guard let newTexture = device.makeTexture(descriptor: descriptor) else {
                Self.logger.error("Failed to create screen texture for \(displayID)")
                return
            }
            texture = newTexture
            lock.withLock { textures[displayID] = texture }
            Self.logger.info("Created screen texture \(width)x\(height) for \(displayID)")
        }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            Self.logger.error("Screen buffer has no base address for \(displayID)")
            return
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: baseAddress,
            bytesPerRow: bytesPerRow
        )
    }

    /// Get the latest texture for a display, or nil if no frame has arrived yet.
    func texture(for displayID: CGDirectDisplayID) -> MTLTexture? {
        lock.withLock { textures[displayID] }
    }

    // MARK: - Screen recording permission

    /// True when *this process* is allowed to capture the screen.
    ///
    /// macOS stores Screen Recording grants against the app's code signature.
    /// Ad-hoc signed development builds change their cdhash on every build, so
    /// System Settings can list FreeStage as enabled while this returns `false`.
    /// Call this to detect that stale-grant case and re-register the app.
    static var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Ask macOS to register this app in Screen Recording and prompt the user.
    ///
    /// Returns the current grant state. A grant only takes effect for the next
    /// process launch, so the app still needs relaunching after the user
    /// approves.
    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        ScreenRecordingPermission.request()
    }

    /// Open System Settings on the Screen Recording pane.
    static func openScreenRecordingSettings() {
        ScreenRecordingPermission.openSettings()
    }

    /// Update the desktop-icons exclusion flag and restart active screen streams
    /// so the change takes effect immediately.
    func setExcludeDesktopIcons(_ exclude: Bool) {
        let activeIDs = lock.withLock { Set(streams.keys) }
        guard exclude != excludeDesktopIcons || !activeIDs.isEmpty else {
            excludeDesktopIcons = exclude
            return
        }
        excludeDesktopIcons = exclude
        for id in activeIDs {
            stopCapture(displayID: id)
            startCapture(displayID: id)
        }
    }

    /// Identify Finder desktop windows so they can be excluded from display capture.
    private static func desktopWindows(in content: SCShareableContent) -> [SCWindow] {
        content.windows.filter { window in
            guard let app = window.owningApplication else { return false }
            return app.bundleIdentifier == "com.apple.finder" && window.title?.isEmpty != false
        }
    }
}

// MARK: - Stream delegate

@available(macOS 12.3, *)
private final class StreamDelegate: NSObject, SCStreamOutput {
    private weak var manager: ScreenCaptureManager?
    private let displayID: CGDirectDisplayID

    init(manager: ScreenCaptureManager, displayID: CGDirectDisplayID) {
        self.manager = manager
        self.displayID = displayID
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case SCStreamOutputType.screen:
            guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            manager?.storeFrame(displayID: displayID, buffer: buffer)
        case SCStreamOutputType.audio:
            manager?.audioMixer?.feedSystemAudio(sampleBuffer: sampleBuffer)
        default:
            break
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let screenCapturePermissionDenied = Notification.Name("com.woodseedigi.FreeStage.screenCapturePermissionDenied")
}

// MARK: - Screen recording permission

/// Helpers for the TCC Screen Recording grant, shared by the capture manager
/// and the settings UI. The grant is per-binary: an ad-hoc signed build loses
/// it whenever the cdhash changes, which is exactly what a fresh Xcode build
/// does. `isGranted` is the only reliable way to tell that apart from a real
/// "user never approved this" state.
enum ScreenRecordingPermission {
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Prompt on first use. When the app is already listed (but stale), macOS
    /// does not re-prompt, so fall back to opening the settings pane.
    @discardableResult
    static func request() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        if !granted {
            openSettings()
        }
        return granted
    }

    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenRecording") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Guidance shown when the grant is missing or stale.
    static let guidance = """
        Screen Recording permission is not active for this build of FreeStage. \
        If FreeStage already appears enabled in System Settings → Privacy & Security → \
        Screen & System Audio Recording, remove it with the − button, add it back, \
        then relaunch FreeStage.
        """
}


// MARK: - Display discovery

@available(macOS 12.3, *)
struct ScreenCaptureDisplay: Identifiable, Hashable, Sendable {
    let displayID: CGDirectDisplayID
    let width: Int
    let height: Int

    var id: CGDirectDisplayID { displayID }

    var name: String {
        if let screenName = Self.screenName(for: displayID) {
            return "\(screenName) (\(width)×\(height))"
        }
        return "Display \(displayID) (\(width)×\(height))"
    }

    private static func screenName(for displayID: CGDirectDisplayID) -> String? {
        guard let matched = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return number.uint32Value == displayID
        }) else { return nil }

        let localized = matched.localizedName
        let trimmed = localized.trimmingCharacters(in: CharacterSet.whitespaces)
        return trimmed.isEmpty ? nil : localized
    }

    static func discover() async -> [ScreenCaptureDisplay] {
        do {
            let content = try await SCShareableContent.current
            let displays = content.displays.map {
                ScreenCaptureDisplay(displayID: $0.displayID, width: $0.width, height: $0.height)
            }
            if !displays.isEmpty {
                return displays
            }
        } catch {
            Logger(subsystem: "com.woodseedigi.freestage", category: "ScreenCaptureManager")
                .error("Failed to discover displays via ScreenCaptureKit: \(error.localizedDescription)")
        }
        // Fall back to CoreGraphics so the user can still pick a display when
        // ScreenCaptureKit permission has not yet been granted.
        return discoverCoreGraphics()
    }

    private static func discoverCoreGraphics() -> [ScreenCaptureDisplay] {
        let maxDisplays: UInt32 = 32
        var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(maxDisplays, &onlineDisplays, &displayCount) == .success else {
            Logger(subsystem: "com.woodseedigi.freestage", category: "ScreenCaptureManager")
                .error("CoreGraphics display discovery failed")
            return []
        }
        return onlineDisplays.prefix(Int(displayCount)).compactMap { id in
            guard id != 0 else { return nil }
            return ScreenCaptureDisplay(
                displayID: id,
                width: CGDisplayPixelsWide(id),
                height: CGDisplayPixelsHigh(id)
            )
        }
    }
}
