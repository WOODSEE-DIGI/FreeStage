//
//  FaceMeshTracker.swift
//  FreeStage
//
//  Native MediaPipe face-mesh tracker using the cornpip C API. Runs face
//  detection + 478-point 3D face mesh inference on a dedicated queue and
//  exposes the latest tracking frame for rendering.
//

import Foundation
import CoreVideo
import OSLog

/// A single tracked face frame.
struct FaceMeshFrame {
    let landmarks: [FaceMeshLandmark]
    let geometry: FaceMeshGeometry?
    let blendshapes: [String: Float]?
    let score: Float
    let imageSize: CGSize
}

struct FaceMeshLandmark {
    let x: Float  // normalized 0..1
    let y: Float
    let z: Float  // relative depth, same scale as x
}

struct FaceMeshGeometry {
    let metricLandmarks: [FaceMeshLandmark]
    let poseMatrix: [Float] // row-major 4x4
    let yawDegrees: Float
    let pitchDegrees: Float
    let rollDegrees: Float
    let scale: Float
}

/// CVPixelBuffer is not Sendable, but we only pass it to a single serial
/// inference queue and never mutate it concurrently. This unchecked wrapper
/// lets us move the buffer across the queue boundary without a global unsafe
/// conformance.
private final class PixelBufferBox: @unchecked Sendable {
    let buffer: CVPixelBuffer
    init(_ buffer: CVPixelBuffer) { self.buffer = buffer }
}

/// Tracks a face in a video stream using MediaPipe Face Mesh.
///
/// Thread-safe: enqueue frames from any queue; read the latest result from
/// any queue. Inference runs serially on a private background queue.
final class FaceMeshTracker: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "FaceMeshTracker")

    private let inferenceQueue = DispatchQueue(label: "com.woodseedigi.FreeStage.faceMesh", qos: .userInitiated)
    private let lock = NSLock()
    private let processingLock = NSLock()
    private var _isProcessing = false
    private var _latestFrame: FaceMeshFrame?

    weak var trackingService: FacePuppetTrackingService?

    private let detectorContext: OpaquePointer
    private let meshContext: OpaquePointer
    private let blendshapesContext: OpaquePointer?

    /// Initialize with model paths from the app bundle.
    init?() {
        guard let detectorURL = Bundle.main.url(forResource: "face_detection_short_range", withExtension: "tflite"),
              let meshURL = Bundle.main.url(forResource: "face_landmark_with_attention", withExtension: "tflite"),
              let blendshapesURL = Bundle.main.url(forResource: "face_blendshapes", withExtension: "tflite") else {
            Self.logger.error("Failed to locate MediaPipe model files in bundle.")
            return nil
        }

        var detectorOptions = MpFaceDetectorCreateOptions(
            threads: 2,
            min_detection_confidence: 0.5,
            min_suppression_threshold: 0.3,
            max_results: 1,
            delegate: MP_DELEGATE_CPU,
            disable_delegate_fallback: 0
        )

        guard let detector = detectorURL.path.withCString({ path in
            mp_face_detector_create(path, &detectorOptions)
        }) else {
            let error = String(cString: mp_face_detector_last_global_error())
            Self.logger.error("Failed to create face detector: \(error)")
            return nil
        }

        var meshOptions = MpFaceMeshCreateOptions(
            iris_model_path: nil,
            threads: 2,
            min_detection_confidence: 0.5,
            min_tracking_confidence: 0.5,
            min_face_presence_confidence: 0.5,
            delegate: MP_DELEGATE_CPU,
            enable_roi_tracking: 1,
            enable_iris: 0,
            enable_attention_mesh: 1,
            disable_delegate_fallback: 0
        )

        guard let mesh = meshURL.path.withCString({ path in
            mp_face_mesh_create(path, &meshOptions)
        }) else {
            let error = String(cString: mp_face_mesh_last_global_error())
            Self.logger.error("Failed to create face mesh: \(error)")
            mp_face_detector_destroy(detector)
            return nil
        }

        var blendshapesOptions = MpBlendshapesCreateOptions(
            threads: 2,
            delegate: MP_DELEGATE_CPU,
            disable_delegate_fallback: 0
        )
        let blendshapes = blendshapesURL.path.withCString { path in
            mp_blendshapes_create(path, &blendshapesOptions)
        }
        if blendshapes == nil {
            let error = String(cString: mp_blendshapes_last_global_error())
            Self.logger.warning("Failed to create blendshapes model: \(error). Blendshapes disabled.")
        }

        self.detectorContext = detector
        self.meshContext = mesh
        self.blendshapesContext = blendshapes
    }

    deinit {
        mp_face_mesh_destroy(meshContext)
        mp_face_detector_destroy(detectorContext)
        if let blendshapesContext {
            mp_blendshapes_destroy(blendshapesContext)
        }
    }

    /// The most recently processed frame, or nil if no face has been tracked yet.
    var latestFrame: FaceMeshFrame? {
        lock.lock()
        defer { lock.unlock() }
        return _latestFrame
    }

    /// Test hook: inject a synthetic frame without running inference.
    func injectLatestFrame(_ frame: FaceMeshFrame) {
        lock.lock()
        defer { lock.unlock() }
        _latestFrame = frame
    }

    /// Submit a pixel buffer for asynchronous face tracking.
    ///
    /// The buffer must be in a 32-bit BGRA format (`kCVPixelFormatType_32BGRA`).
    /// Frames are dropped while a previous inference is still running so the
    /// tracker stays locked to the camera's present time.
    func enqueue(_ pixelBuffer: CVPixelBuffer) {
        processingLock.lock()
        guard !_isProcessing else {
            processingLock.unlock()
            return
        }
        _isProcessing = true
        processingLock.unlock()

        let box = PixelBufferBox(pixelBuffer)
        inferenceQueue.async { [weak self] in
            defer {
                self?.processingLock.lock()
                self?._isProcessing = false
                self?.processingLock.unlock()
            }
            guard let self else { return }
            if let frame = self.process(box.buffer) {
                self.lock.lock()
                self._latestFrame = frame
                self.lock.unlock()
                self.trackingService?.publish(frame: frame)
            }
        }
    }

    private func process(_ pixelBuffer: CVPixelBuffer) -> FaceMeshFrame? {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard format == kCVPixelFormatType_32BGRA else {
            Self.logger.warning("Unsupported pixel buffer format: \(format)")
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = Int32(CVPixelBufferGetWidth(pixelBuffer))
        let height = Int32(CVPixelBufferGetHeight(pixelBuffer))
        let bytesPerRow = Int32(CVPixelBufferGetBytesPerRow(pixelBuffer))

        var image = MpImage(
            data: baseAddress.assumingMemoryBound(to: UInt8.self),
            width: width,
            height: height,
            bytes_per_row: bytesPerRow,
            format: MP_PIXEL_FORMAT_BGRA
        )

        // Run detector to seed/refresh the mesh ROI.
        let detectionRect: MpNormalizedRect? = runDetector(image: &image)

        // Run face mesh.
        let meshResult: UnsafeMutablePointer<MpFaceMeshResult>?
        if let rect = detectionRect {
            meshResult = withUnsafePointer(to: &image) { imagePtr in
                withUnsafePointer(to: rect) { rectPtr in
                    mp_face_mesh_process(meshContext, imagePtr, rectPtr, 0, 0)
                }
            }
        } else {
            meshResult = withUnsafePointer(to: &image) { imagePtr in
                mp_face_mesh_process(meshContext, imagePtr, nil, 0, 0)
            }
        }

        guard let meshResult else {
            if let error = mp_face_mesh_last_error(meshContext) {
                Self.logger.error("Face mesh inference failed: \(String(cString: error))")
            }
            return nil
        }
        defer { mp_face_mesh_release_result(meshResult) }

        let result = meshResult.pointee
        guard result.landmarks_count > 0 else {
            Self.logger.debug("Face mesh produced no landmarks for this frame.")
            return nil
        }

        let landmarkCount = Int(result.landmarks_count)
        let landmarks = (0..<landmarkCount).map { i in
            let lm = result.landmarks[i]
            return FaceMeshLandmark(x: lm.x, y: lm.y, z: lm.z)
        }

        let geometry = estimateGeometry(
            landmarks: result.landmarks,
            count: landmarkCount,
            imageWidth: Int(result.image_width),
            imageHeight: Int(result.image_height)
        )

        let blendshapes = estimateBlendshapes(
            landmarks: result.landmarks,
            count: landmarkCount,
            imageWidth: Int(result.image_width),
            imageHeight: Int(result.image_height)
        )

        return FaceMeshFrame(
            landmarks: landmarks,
            geometry: geometry,
            blendshapes: blendshapes,
            score: result.score,
            imageSize: CGSize(width: Int(result.image_width), height: Int(result.image_height))
        )
    }

    private func runDetector(image: inout MpImage) -> MpNormalizedRect? {
        guard let detectionResult: UnsafeMutablePointer<MpFaceDetectorResult> = mp_face_detector_process(detectorContext, &image, nil, 0, 0, nil) else {
            Self.logger.debug("Face detector returned no result.")
            return nil
        }
        defer { mp_face_detector_release_result(detectionResult) }

        guard detectionResult.pointee.detections_count > 0 else {
            Self.logger.debug("Face detector found no faces.")
            return nil
        }
        return detectionResult.pointee.detections.pointee.expanded_face_rect
    }

    private func estimateGeometry(
        landmarks: UnsafeMutablePointer<MpLandmark>,
        count: Int,
        imageWidth: Int,
        imageHeight: Int
    ) -> FaceMeshGeometry? {
        var options = MpFaceGeometryOptions(
            vertical_fov_degrees: 63,
            near_plane: 1,
            far_plane: 1000,
            origin_top_left: 1
        )
        guard let geometry: UnsafeMutablePointer<MpFaceGeometryResult> = mp_face_geometry_estimate(
            landmarks,
            Int32(count),
            Int32(imageWidth),
            Int32(imageHeight),
            &options
        ) else { return nil }
        defer { mp_face_geometry_release_result(geometry) }

        let metricCount = Int(geometry.pointee.metric_landmarks_count)
        let metricLandmarks = (0..<metricCount).map { i in
            let lm = geometry.pointee.metric_landmarks[i]
            return FaceMeshLandmark(x: lm.x, y: lm.y, z: lm.z)
        }
        let matrix = poseMatrixArray(from: geometry.pointee.pose_transform_matrix)

        return FaceMeshGeometry(
            metricLandmarks: metricLandmarks,
            poseMatrix: matrix,
            yawDegrees: geometry.pointee.yaw_degrees,
            pitchDegrees: geometry.pointee.pitch_degrees,
            rollDegrees: geometry.pointee.roll_degrees,
            scale: geometry.pointee.scale
        )
    }

    private func poseMatrixArray(from tuple: (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float)) -> [Float] {
        [tuple.0, tuple.1, tuple.2, tuple.3,
         tuple.4, tuple.5, tuple.6, tuple.7,
         tuple.8, tuple.9, tuple.10, tuple.11,
         tuple.12, tuple.13, tuple.14, tuple.15]
    }

    private func estimateBlendshapes(
        landmarks: UnsafeMutablePointer<MpLandmark>,
        count: Int,
        imageWidth: Int,
        imageHeight: Int
    ) -> [String: Float]? {
        guard let blendshapesContext else { return nil }
        guard let result: UnsafeMutablePointer<MpBlendshapesResult> = mp_blendshapes_process(
            blendshapesContext,
            landmarks,
            Int32(count),
            Int32(imageWidth),
            Int32(imageHeight)
        ) else { return nil }
        defer { mp_blendshapes_release_result(result) }

        guard result.pointee.scores_count == 52 else { return nil }
        let names = FaceMeshTracker.blendshapeNames
        var map: [String: Float] = [:]
        for i in 0..<52 {
            map[names[i]] = result.pointee.scores[i]
        }
        return map
    }

    private static let blendshapeNames: [String] = [
        "_neutral", "browDownLeft", "browDownRight", "browInnerUp",
        "browOuterUpLeft", "browOuterUpRight", "cheekPuff", "cheekSquintLeft",
        "cheekSquintRight", "eyeBlinkLeft", "eyeBlinkRight", "eyeLookDownLeft",
        "eyeLookDownRight", "eyeLookInLeft", "eyeLookInRight", "eyeLookOutLeft",
        "eyeLookOutRight", "eyeLookUpLeft", "eyeLookUpRight", "eyeSquintLeft",
        "eyeSquintRight", "eyeWideLeft", "eyeWideRight", "jawForward",
        "jawLeft", "jawOpen", "jawRight", "mouthClose", "mouthDimpleLeft",
        "mouthDimpleRight", "mouthFrownLeft", "mouthFrownRight", "mouthFunnel",
        "mouthLeft", "mouthLowerDownLeft", "mouthLowerDownRight", "mouthPressLeft",
        "mouthPressRight", "mouthPucker", "mouthRight", "mouthRollLower",
        "mouthRollUpper", "mouthShrugLower", "mouthShrugUpper", "mouthSmileLeft",
        "mouthSmileRight", "mouthStretchLeft", "mouthStretchRight", "mouthUpperUpLeft",
        "mouthUpperUpRight", "noseSneerLeft", "noseSneerRight"
    ]
}
