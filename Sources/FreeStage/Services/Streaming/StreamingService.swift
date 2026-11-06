//
//  StreamingService.swift
//  FreeStage
//
//  Manages live streaming to one or more RTMP destinations.
//

import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import Observation
import OSLog

private let streamingLogger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "Streaming")

/// Manages live streaming output.
@Observable
final class StreamingService: @unchecked Sendable {
    private(set) var isStreaming = false
    private(set) var activeDestinationID: UUID?
    private(set) var statusMessage = "Not streaming"
    private(set) var streamDuration: TimeInterval = 0
    private(set) var reconnectAttempts = 0

    var destinations: [StreamDestination] = [] {
        didSet { saveDestinations() }
    }

    var autoReconnect: Bool = true
    var maxReconnectAttempts: Int = 5

    private var output: StreamOutput?
    private var audioMixer: AudioMixer?
    private var startDate: Date?
    private var statusTimer: Timer?
    private var reconnectTask: Task<Void, Never>?
    private let lock = NSLock()

    init() {
        self.destinations = loadDestinations()
        #if canImport(HaishinKit)
        self.output = HaishinKitStreamOutput()
        #else
        self.output = NoOpStreamOutput()
        #endif
    }

    func setAudioMixer(_ mixer: AudioMixer?) {
        self.audioMixer = mixer
    }

    // MARK: - Destination management

    func addDestination(_ destination: StreamDestination) {
        destinations.append(destination)
    }

    func removeDestination(id: UUID) {
        destinations.removeAll { $0.id == id }
    }

    func updateDestination(_ destination: StreamDestination) {
        if let index = destinations.firstIndex(where: { $0.id == destination.id }) {
            destinations[index] = destination
        }
    }

    // MARK: - Stream control

    func startStreaming(to destinationID: UUID) async {
        guard let destination = destinations.first(where: { $0.id == destinationID && $0.isEnabled }),
              let url = destination.ingestURL else {
            statusMessage = "Invalid stream destination"
            return
        }

        stopStreaming()
        reconnectAttempts = 0

        do {
            try await output?.start(url: url)
            DispatchQueue.main.async { [weak self] in
                self?.isStreaming = true
                self?.activeDestinationID = destinationID
                self?.startDate = Date()
                self?.statusMessage = "Streaming to \(destination.name)"
            }
            startStatusUpdates()
            installAudioTap()
            streamingLogger.info("Started streaming to \(destination.name)")
        } catch {
            statusMessage = "Failed: \(error.localizedDescription)"
            streamingLogger.error("Failed to start stream: \(error.localizedDescription)")
            if autoReconnect {
                scheduleReconnect(to: destinationID)
            }
        }
    }

    func stopStreaming() {
        reconnectTask?.cancel()
        reconnectTask = nil
        stopStatusUpdates()
        removeAudioTap()

        Task { [weak self] in
            await self?.output?.stop()
            await MainActor.run {
                self?.isStreaming = false
                self?.activeDestinationID = nil
                self?.startDate = nil
                self?.streamDuration = 0
                self?.statusMessage = "Not streaming"
            }
        }
    }

    // MARK: - Feeds

    func appendVideo(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard isStreaming else { return }
        output?.appendVideo(pixelBuffer: pixelBuffer, presentationTime: presentationTime)
    }

    private func installAudioTap() {
        guard let audioMixer else { return }
        audioMixer.installRecordingTap { [weak self] buffer, time in
            guard let self, self.isStreaming else { return }
            self.output?.appendAudio(buffer: buffer, presentationTime: time)
        }
    }

    private func removeAudioTap() {
        audioMixer?.removeRecordingTap()
    }

    // MARK: - Status & reconnect

    private func startStatusUpdates() {
        stopStatusUpdates()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }

    private func stopStatusUpdates() {
        statusTimer?.invalidate()
        statusTimer = nil
    }

    private func updateStatus() {
        guard isStreaming, let startDate else { return }
        streamDuration = Date().timeIntervalSince(startDate)
        if output?.isConnected == false {
            statusMessage = "Connection lost"
            if autoReconnect, let destinationID = activeDestinationID {
                scheduleReconnect(to: destinationID)
            }
        }
    }

    private func scheduleReconnect(to destinationID: UUID) {
        guard reconnectTask == nil,
              reconnectAttempts < maxReconnectAttempts,
              destinations.first(where: { $0.id == destinationID }) != nil else { return }

        reconnectAttempts += 1
        statusMessage = "Reconnecting \(reconnectAttempts)/\(maxReconnectAttempts)..."
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.startStreaming(to: destinationID)
        }
    }

    // MARK: - Persistence

    private func loadDestinations() -> [StreamDestination] {
        guard let data = UserDefaults.standard.data(forKey: "streamDestinations"),
              let destinations = try? JSONDecoder().decode([StreamDestination].self, from: data) else {
            return []
        }
        return destinations
    }

    private func saveDestinations() {
        if let data = try? JSONEncoder().encode(destinations) {
            UserDefaults.standard.set(data, forKey: "streamDestinations")
        }
    }
}
