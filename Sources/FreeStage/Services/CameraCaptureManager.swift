//
//  CameraCaptureManager.swift
//  FreeStage
//
//  Manages AVCaptureSessions for camera sources used in scenes. Keeps a
//  dedicated Metal texture per active camera and copies each new frame into
//  it so the renderer always samples a valid texture.
//

import Foundation
import AVFoundation
import CoreVideo
import Metal
import OSLog

/// Thread-safe manager for camera capture sessions and their latest frames.
final class CameraCaptureManager: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.woodseedigi.freestage", category: "CameraCaptureManager")

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let captureQueue = DispatchQueue(label: "com.woodseedigi.freestage.camera", qos: .userInteractive)
    private var sessions: [String: AVCaptureSession] = [:]
    private var textures: [String: MTLTexture] = [:]
    private var delegates: [String: CaptureDelegate] = [:]
    private let lock = NSLock()

    /// Optional service used to apply per-camera settings when capture starts.
    var cameraControlService: CameraControlService?

    init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            fatalError("Metal is not available on this Mac.")
        }
        self.device = device
        self.commandQueue = commandQueue
    }

    /// Start capturing from the camera with the given uniqueID if not already active.
    func startCapture(uniqueID: String) {
        lock.lock()
        guard sessions[uniqueID] == nil else {
            lock.unlock()
            return
        }
        lock.unlock()

        guard let avDevice = AVCaptureDevice(uniqueID: uniqueID) else {
            Self.logger.warning("Camera device not found: \(uniqueID, privacy: .public)")
            return
        }

        let session = AVCaptureSession()

        do {
            session.beginConfiguration()

            let input = try AVCaptureDeviceInput(device: avDevice)
            guard session.canAddInput(input) else {
                Self.logger.warning("Cannot add input for \(avDevice.localizedName, privacy: .public)")
                session.commitConfiguration()
                return
            }
            session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            // Use plain 32BGRA buffers. We copy frames into our own Metal texture,
            // so Metal-compatibility is unnecessary and can break some virtual cameras.
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.alwaysDiscardsLateVideoFrames = true

            let delegate = CaptureDelegate(manager: self, uniqueID: uniqueID)
            output.setSampleBufferDelegate(delegate, queue: captureQueue)

            guard session.canAddOutput(output) else {
                Self.logger.warning("Cannot add output for \(avDevice.localizedName, privacy: .public)")
                session.commitConfiguration()
                return
            }
            session.addOutput(output)
            session.commitConfiguration()

            lock.lock()
            sessions[uniqueID] = session
            delegates[uniqueID] = delegate
            lock.unlock()

            session.startRunning()

            // Apply any pending camera settings now that the device is live.
            // CameraControlService is MainActor-isolated; hop over.
            if let service = self.cameraControlService {
                Task { @MainActor in
                    if let settings = service.settings(for: uniqueID) {
                        service.apply(settings: settings, to: uniqueID)
                    }
                }
            }

            print("[FreeStage] Started camera session: \(avDevice.localizedName) running=\(session.isRunning)")
            Self.logger.info("Started camera: \(avDevice.localizedName, privacy: .public)")
        } catch {
            Self.logger.error("Failed to start camera \(avDevice.localizedName, privacy: .public): \(error.localizedDescription)")
        }
    }

    /// Reconcile running capture sessions with the set of camera uniqueIDs
    /// that should be active. Starts only missing sessions and stops only
    /// sessions no longer required — existing sessions keep running, so
    /// unrelated edits (layer transform, color, gimbal) never interrupt video.
    func syncCaptures(requiredIDs: Set<String>) {
        lock.lock()
        let currentIDs = Set(sessions.keys)
        let toStop = currentIDs.subtracting(requiredIDs)
        let toStart = requiredIDs.subtracting(currentIDs)
        lock.unlock()

        for id in toStop {
            stopCapture(uniqueID: id)
        }
        for id in toStart {
            startCapture(uniqueID: id)
        }
    }

    /// Stop capturing from the camera with the given uniqueID.
    func stopCapture(uniqueID: String) {
        lock.lock()
        let session = sessions.removeValue(forKey: uniqueID)
        textures.removeValue(forKey: uniqueID)
        delegates.removeValue(forKey: uniqueID)
        lock.unlock()
        session?.stopRunning()
        Self.logger.info("Stopped camera: \(uniqueID, privacy: .public)")
    }

    /// Stop all active capture sessions.
    func stopAll() {
        lock.lock()
        let allSessions = sessions.values
        let allIDs = Array(sessions.keys)
        sessions.removeAll()
        textures.removeAll()
        delegates.removeAll()
        lock.unlock()
        for session in allSessions {
            session.stopRunning()
        }
        Self.logger.info("Stopped all cameras: \(allIDs.count)")
    }

    /// Copy a new frame into the dedicated texture for this camera.
    /// Called from the capture queue.
    func storeFrame(uniqueID: String, buffer: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)

        lock.lock()
        var texture = textures[uniqueID]
        let hadTexture = texture != nil
        lock.unlock()

        if texture == nil || texture!.width != width || texture!.height != height {
            let descriptor = MTLTextureDescriptor()
            descriptor.width = width
            descriptor.height = height
            descriptor.pixelFormat = .bgra8Unorm
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .shared
            guard let newTexture = device.makeTexture(descriptor: descriptor) else {
                Self.logger.error("Failed to create camera texture for \(uniqueID, privacy: .public)")
                return
            }
            texture = newTexture
            lock.lock()
            textures[uniqueID] = texture
            lock.unlock()
            Self.logger.info("Created camera texture \(width)x\(height) for \(uniqueID, privacy: .public)")
        }

        guard let texture else { return }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            Self.logger.error("Camera buffer has no base address for \(uniqueID, privacy: .public)")
            return
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: baseAddress,
            bytesPerRow: bytesPerRow
        )

        if !hadTexture {
            print("[FreeStage] First frame copied for \(uniqueID) \(width)x\(height)")
            Self.logger.info("First frame copied for \(uniqueID, privacy: .public)")
        }
    }

    /// Get the latest texture for a camera, or nil if no frame has arrived yet.
    func texture(for uniqueID: String) -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        return textures[uniqueID]
    }
}

// MARK: - Delegate

private final class CaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private weak var manager: CameraCaptureManager?
    private let uniqueID: String

    init(manager: CameraCaptureManager, uniqueID: String) {
        self.manager = manager
        self.uniqueID = uniqueID
        super.init()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("[FreeStage] Capture delegate got sample buffer without image buffer")
            return
        }
        print("[FreeStage] Capture delegate frame arrived \(uniqueID) \(CVPixelBufferGetWidth(buffer))x\(CVPixelBufferGetHeight(buffer))")
        manager?.storeFrame(uniqueID: uniqueID, buffer: buffer)
    }
}
