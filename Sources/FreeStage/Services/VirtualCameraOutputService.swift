//
//  VirtualCameraOutputService.swift
//  FreeStage
//
//  Finds the FreeStage virtual camera's sink stream and enqueues rendered
//  frames so the system extension can publish them as a camera device.
//

import Foundation
import CoreMediaIO
import CoreMedia
import CoreVideo
import SystemExtensions
import os.log

private let virtualCameraLogger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "VirtualCamera")

/// Manages activation of the FreeStage virtual camera system extension and
/// feeds it CMSampleBuffers.
@MainActor
final class VirtualCameraOutputService: NSObject, ObservableObject {
    @Published var isExtensionActive = false
    @Published var statusMessage = "Virtual camera inactive"

    private var extensionBundle: Bundle {
        let extensionsURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/SystemExtensions")
        let urls = (try? FileManager.default.contentsOfDirectory(at: extensionsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        guard let url = urls.first else {
            fatalError("FreeStageCameraExtension.systemextension not found in app bundle")
        }
        return Bundle(url: url)!
    }

    private var deviceObjectID: CMIOObjectID?
    private var sinkStreamID: CMIOStreamID?
    private var sourceStreamID: CMIOStreamID?
    private var sinkQueue: CMSimpleQueue?
    private var videoDescription: CMFormatDescription?
    private var bufferPool: CVPixelBufferPool?
    private var bufferAuxAttributes: NSDictionary?
    private var readyToEnqueue = false
    private var enqueued = false

    private let width = Int32(freeStageCameraWidth)
    private let height = Int32(freeStageCameraHeight)
    private let frameDuration = CMTime(value: 1, timescale: freeStageCameraFrameRate)

    override init() {
        super.init()
        makeDevicesVisible()
        discoverCamera()
    }

    // MARK: - Activation

    func activate() {
        guard let identifier = extensionBundle.bundleIdentifier else { return }
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: identifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func deactivate() {
        guard let identifier = extensionBundle.bundleIdentifier else { return }
        let request = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: identifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    // MARK: - Discovery

    private func makeDevicesVisible() {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &allow
        )
    }

    func discoverCamera() {
        performDiscovery()
    }

    private func performDiscovery() {
        guard let deviceID = findCMIODevice(named: freeStageCameraName) else {
            DispatchQueue.main.async { [weak self] in
                self?.statusMessage = "Virtual camera not found"
            }
            return
        }
        deviceObjectID = deviceID
        let streams = streamsForDevice(deviceID)
        guard streams.count >= 2 else {
            DispatchQueue.main.async { [weak self] in
                self?.statusMessage = "Virtual camera streams not ready"
            }
            return
        }
        sourceStreamID = streams[0]
        sinkStreamID = streams[1]

        DispatchQueue.main.async { [weak self] in
            self?.isExtensionActive = true
            self?.statusMessage = "Virtual camera ready"
        }

        initSink()
    }

    private func findCMIODevice(named name: String) -> CMIOObjectID? {
        var size: UInt32 = 0
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: .global,
            mElement: .main
        )
        let systemObject = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else { return nil }

        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(systemObject, &address, 0, nil, size, &used, &devices) == noErr else { return nil }

        for deviceID in devices {
            var nameAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID),
                mScope: .global,
                mElement: .main
            )
            var nameSize: UInt32 = 0
            guard CMIOObjectGetPropertyDataSize(deviceID, &nameAddress, 0, nil, &nameSize) == noErr else { continue }
            var uid: CFString = "" as CFString
            var nameUsed: UInt32 = 0
            let uidErr = withUnsafeMutablePointer(to: &uid) { uidPtr in
                CMIOObjectGetPropertyData(deviceID, &nameAddress, 0, nil, nameSize, &nameUsed, UnsafeMutableRawPointer(uidPtr))
            }
            guard uidErr == noErr else { continue }
            let uidString = uid as String
            if uidString.contains(name) || deviceNameForObject(deviceID) == name {
                return deviceID
            }
        }
        return nil
    }

    private func deviceNameForObject(_ objectID: CMIOObjectID) -> String? {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOObjectPropertyName),
            mScope: .global,
            mElement: .main
        )
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(objectID, &address, 0, nil, &size) == noErr else { return nil }
        var name: CFString = "" as CFString
        var used: UInt32 = 0
        let nameErr = withUnsafeMutablePointer(to: &name) { namePtr in
            CMIOObjectGetPropertyData(objectID, &address, 0, nil, size, &used, UnsafeMutableRawPointer(namePtr))
        }
        guard nameErr == noErr else { return nil }
        return name as String
    }

    private func streamsForDevice(_ deviceID: CMIOObjectID) -> [CMIOStreamID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyStreams),
            mScope: .global,
            mElement: .main
        )
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<CMIOStreamID>.size
        var streams = [CMIOStreamID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(deviceID, &address, 0, nil, size, &used, &streams) == noErr else { return [] }
        return streams
    }

    private func initSink() {
        guard let sinkStreamID, let deviceObjectID else { return }

        let dims = CMVideoDimensions(width: width, height: height)
        var desc: CMFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: dims.width,
            height: dims.height,
            extensions: nil,
            formatDescriptionOut: &desc
        )
        videoDescription = desc

        let attrs: NSDictionary = [
            kCVPixelBufferWidthKey: dims.width,
            kCVPixelBufferHeightKey: dims.height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs, &bufferPool)
        bufferAuxAttributes = [kCVPixelBufferPoolAllocationThresholdKey: 5]

        let pointerQueue = UnsafeMutablePointer<Unmanaged<CMSimpleQueue>?>.allocate(capacity: 1)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let result = CMIOStreamCopyBufferQueue(sinkStreamID, { sinkStream, _, ref in
            guard let ref else { return }
            let service = Unmanaged<VirtualCameraOutputService>.fromOpaque(ref).takeUnretainedValue()
            Task { @MainActor in
                service.readyToEnqueue = true
            }
        }, refcon, pointerQueue)

        guard result == noErr, let queue = pointerQueue.pointee else {
            virtualCameraLogger.error("Failed to copy sink buffer queue")
            return
        }
        sinkQueue = queue.takeUnretainedValue()
        CMIODeviceStartStream(deviceObjectID, sinkStreamID)
    }

    // MARK: - Frame submission

    /// Submit a rendered pixel buffer to the virtual camera sink.
    func enqueue(_ pixelBuffer: CVPixelBuffer) {
        guard isExtensionActive,
              let sinkQueue,
              let videoDescription,
              CMSimpleQueueGetCount(sinkQueue) < CMSimpleQueueGetCapacity(sinkQueue)
        else { return }

        guard enqueued == false || readyToEnqueue else { return }
        enqueued = true
        readyToEnqueue = false

        var timingInfo = CMSampleTimingInfo(
            duration: frameDuration,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let err = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: videoDescription,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        guard err == noErr, let sampleBuffer else {
            virtualCameraLogger.error("Failed to create sample buffer for virtual camera")
            return
        }

        let retained = Unmanaged.passRetained(sampleBuffer)
        CMSimpleQueueEnqueue(sinkQueue, element: retained.toOpaque())
    }
}

extension VirtualCameraOutputService: OSSystemExtensionRequestDelegate {
    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in
            statusMessage = "Approve FreeStage Virtual Camera in System Settings"
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Task { @MainActor in
            if result == .completed {
                isExtensionActive = true
                statusMessage = "Virtual camera active"
                discoverCamera()
            } else {
                statusMessage = "Virtual camera pending; restart may be required"
            }
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        Task { @MainActor in
            isExtensionActive = false
            statusMessage = "Virtual camera activation failed: \(error.localizedDescription)"
        }
    }
}

public extension CMIOObjectPropertyAddress {
    init(_ selector: CMIOObjectPropertySelector,
         _ scope: CMIOObjectPropertyScope = .anyScope,
         _ element: CMIOObjectPropertyElement = .anyElement) {
        self.init(mSelector: selector, mScope: scope, mElement: element)
    }
}

public extension CMIOObjectPropertyScope {
    static let global = CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal)
    static let anyScope = CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard)
}

public extension CMIOObjectPropertyElement {
    static let main = CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    static let anyElement = CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
}
