//
//  RecordingService.swift
//  FreeStage
//
//  Records the program video and mixed audio to a local movie file using
//  AVAssetWriter.
//

import Foundation
import AVFoundation
@preconcurrency import AVFAudio
import CoreVideo
import CoreMedia
import Observation
import OSLog

private let recordingLogger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "Recording")

/// Records the program output to disk.
@Observable
final class RecordingService: @unchecked Sendable {
    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var lastRecordingURL: URL?
    private(set) var recordingDuration: TimeInterval = 0
    private(set) var recordedFileSize: Int64 = 0

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var startTime: CMTime?
    private var settings: AppSettings?
    private let defaultWidth: Int
    private let defaultHeight: Int
    private var audioMixer: AudioMixer?
    private let lock = NSLock()
    private var recordingStartDate: Date?
    private var statusTimer: Timer?
    private var splitTask: Task<Void, Never>?


    init(width: Int = Int(freeStageCameraWidth), height: Int = Int(freeStageCameraHeight)) {
        self.defaultWidth = width
        self.defaultHeight = height
    }

    /// Wire the mixer so recording can capture mixed audio.
    func setAudioMixer(_ mixer: AudioMixer?) {
        self.audioMixer = mixer
    }

    /// Wire user settings so recordings use the chosen directory and codec.
    func configure(with settings: AppSettings) {
        self.settings = settings
    }

    /// The resolution the recorded video should be encoded at.
    var recordingSize: CGSize {
        CGSize(
            width: settings?.recordingResolution.width ?? CGFloat(defaultWidth),
            height: settings?.recordingResolution.height ?? CGFloat(defaultHeight)
        )
    }

    /// The frame rate the recorded video should be encoded at.
    var recordingFrameRate: Int {
        settings?.recordingFrameRate ?? 30
    }

    /// Start recording to a new file. Returns the destination URL.
    @discardableResult
    func startRecording() throws -> URL {
        let url = settings?.nextRecordingURL()
            ?? defaultRecordingURL()

        let requiredMB = settings?.recordingMinFreeSpaceMB ?? 1000
        if let freeSpace = freeSpaceMB(at: url), freeSpace < Int64(requiredMB) {
            throw RecordingError.insufficientDiskSpace(needed: requiredMB, available: Int(freeSpace))
        }

        let format = settings?.recordingFormat ?? .mp4H264
        let width = Int(settings?.recordingResolution.width ?? CGFloat(defaultWidth))
        let height = Int(settings?.recordingResolution.height ?? CGFloat(defaultHeight))
        let frameRate = settings?.recordingFrameRate ?? 30

        let writer = try AVAssetWriter(url: url, fileType: format.fileType)

        // Video input.
        var videoSettings: [String: Any] = [
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        if let codec = format.videoCodec {
            videoSettings[AVVideoCodecKey] = codec
        }
        if format.supportsBitrate, let bitrate = settings?.recordingBitrate {
            videoSettings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: bitrate
            ]
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else {
            throw RecordingError.cannotAddVideoInput
        }
        writer.add(videoInput)

        // Audio input: 48 kHz stereo AAC.
        let audioSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: settings?.audioBitrate ?? 384_000
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(audioInput) else {
            throw RecordingError.cannotAddAudioInput
        }
        writer.add(audioInput)

        guard writer.startWriting() else {
            throw writer.error ?? RecordingError.startWritingFailed
        }

        lock.withLock {
            self.assetWriter = writer
            self.videoInput = videoInput
            self.audioInput = audioInput
            self.startTime = nil
        }
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = true
            self?.lastRecordingURL = url
            self?.isPaused = false
            self?.recordingDuration = 0
            self?.recordedFileSize = 0
            self?.recordingStartDate = Date()
        }

        installAudioTap()
        startStatusUpdates()

        recordingLogger.info("Started recording to \(url.path) at \(width)×\(height)@\(frameRate)fps")
        return url
    }

    private func defaultRecordingURL() -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let name = "FreeStage-\(formatter.string(from: Date())).mp4"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    /// Stop the current recording and finalize the file.
    func stopRecording() async throws -> URL? {
        let (writer, url) = lock.withLock { () -> (AVAssetWriter?, URL?) in
            (self.assetWriter, self.lastRecordingURL)
        }
        guard let writer, let url else { return nil }

        removeAudioTap()

        lock.withLock {
            videoInput?.markAsFinished()
            audioInput?.markAsFinished()
        }

        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }

        lock.withLock {
            assetWriter = nil
            videoInput = nil
            audioInput = nil
            startTime = nil
        }
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
            self?.isPaused = false
            self?.recordingStartDate = nil
        }
        stopStatusUpdates()

        recordingLogger.info("Finished recording: \(url.path)")
        return url
    }

    /// Pause the current recording. The file is finalized; resume starts a new file.
    func pauseRecording() async {
        guard isRecording else { return }
        _ = try? await stopRecording()
        DispatchQueue.main.async { [weak self] in
            self?.isPaused = true
        }
    }

    /// Resume recording after a pause, creating a new file.
    @discardableResult
    func resumeRecording() throws -> URL? {
        guard isPaused else { return nil }
        return try startRecording()
    }

    /// Stop the current file and immediately start a new one. Used for manual
    /// splits and auto-segmentation.
    @discardableResult
    func splitRecording() async throws -> URL? {
        guard isRecording else { return nil }
        _ = try? await stopRecording()
        return try startRecording()
    }

    /// Append a rendered video frame to the recording.
    func appendVideo(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        let sampleBuffer = createVideoSampleBuffer(pixelBuffer: pixelBuffer, presentationTime: presentationTime)
        guard let sampleBuffer else { return }

        lock.withLock {
            guard let videoInput, videoInput.isReadyForMoreMediaData else { return }

            if startTime == nil {
                startTime = presentationTime
                assetWriter?.startSession(atSourceTime: presentationTime)
            }

            videoInput.append(sampleBuffer)
        }
    }

    private var frameRate: Int {
        settings?.recordingFrameRate ?? 30
    }

    private func createVideoSampleBuffer(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) -> CMSampleBuffer? {
        var videoInfo: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &videoInfo
        )
        guard let videoInfo else { return nil }

        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(frameRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: videoInfo,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }

    private func installAudioTap() {
        guard let audioMixer else { return }
        audioMixer.installRecordingTap { [weak self] buffer, time in
            guard let self,
                  let sampleBuffer = buffer.makeCMSampleBuffer(audioTime: time)
            else { return }
            self.lock.withLock {
                guard self.isRecording,
                      let audioInput = self.audioInput,
                      audioInput.isReadyForMoreMediaData,
                      let assetWriter = self.assetWriter,
                      assetWriter.status == .writing
                else { return }
                audioInput.append(sampleBuffer)
            }
        }
    }

    private func removeAudioTap() {
        audioMixer?.removeRecordingTap()
    }

    // MARK: - Status updates

    private func startStatusUpdates() {
        stopStatusUpdates()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
        updateStatus()
    }

    private func stopStatusUpdates() {
        statusTimer?.invalidate()
        statusTimer = nil
        splitTask?.cancel()
        splitTask = nil
    }

    private func updateStatus() {
        guard isRecording else { return }
        if let startDate = recordingStartDate {
            recordingDuration = Date().timeIntervalSince(startDate)
        }
        if let url = lastRecordingURL {
            recordedFileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }
        scheduleAutoSplitIfNeeded()
    }

    private func scheduleAutoSplitIfNeeded() {
        guard splitTask == nil,
              let minutes = settings?.recordingAutoSplitMinutes,
              minutes > 0 else { return }
        let interval = TimeInterval(minutes * 60)
        guard recordingDuration >= interval else { return }

        splitTask = Task { [weak self] in
            _ = try? await self?.splitRecording()
        }
    }

    private func freeSpaceMB(at url: URL) -> Int64? {
        let path = url.path as NSString
        let directory = path.deletingLastPathComponent
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: directory),
              let freeSize = attrs[.systemFreeSize] as? NSNumber else { return nil }
        return freeSize.int64Value / (1024 * 1024)
    }
}

extension AVAudioPCMBuffer {
    /// Convert this PCM buffer to a CMSampleBuffer using the audio time stamp.
    func makeCMSampleBuffer(audioTime: AVAudioTime) -> CMSampleBuffer? {
        let asbd = format.streamDescription
        var formatDesc: CMFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )
        guard let formatDesc else { return nil }

        let sampleRate = format.sampleRate
        let pts = CMTime(
            value: CMTimeValue(audioTime.audioTimeStamp.mSampleTime),
            timescale: CMTimeScale(sampleRate)
        )
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            formatDescription: formatDesc,
            sampleCount: CMItemCount(frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else { return nil }

        let setStatus = CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: audioBufferList
        )
        return setStatus == noErr ? sampleBuffer : nil
    }
}

enum RecordingError: Error {
    case cannotAddVideoInput
    case cannotAddAudioInput
    case startWritingFailed
    case insufficientDiskSpace(needed: Int, available: Int)
}

extension RecordingError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .cannotAddVideoInput:
            return "Cannot add video input to the recording."
        case .cannotAddAudioInput:
            return "Cannot add audio input to the recording."
        case .startWritingFailed:
            return "Failed to start writing the recording file."
        case .insufficientDiskSpace(let needed, let available):
            return "Insufficient disk space: \(needed) MB required, \(available) MB available."
        }
    }
}
