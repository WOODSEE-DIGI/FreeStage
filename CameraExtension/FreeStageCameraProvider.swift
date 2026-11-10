//
//  FreeStageCameraProvider.swift
//  FreeStageCameraExtension
//
//  CoreMediaIO provider that exposes "FreeStage Virtual Camera" as a source.
//

import Foundation
import CoreMediaIO
import IOKit.audio
import os.log

final class FreeStageCameraProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private let deviceSource: FreeStageCameraDeviceSource

    override init() {
        self.deviceSource = FreeStageCameraDeviceSource(localizedName: freeStageCameraName)
        super.init()
        let queue = DispatchQueue(label: "com.woodseedigi.FreeStage.CameraExtension.client", qos: .userInteractive)
        self.provider = CMIOExtensionProvider(source: self, clientQueue: queue)

        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            fatalError("Failed to add virtual camera device: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}
    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let props = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            props.manufacturer = "Woodsee Digital"
        }
        return props
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}

final class FreeStageCameraDeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private var streamSource: FreeStageCameraStreamSource!
    private var streamSink: FreeStageCameraStreamSink!
    private var videoDescription: CMFormatDescription!
    private var bufferPool: CVPixelBufferPool!
    private var bufferAuxAttributes: NSDictionary!
    private var streamingCounter: UInt32 = 0
    private var sinkStarted = false
    private var sinkClient: CMIOExtensionClient?

    init(localizedName: String) {
        super.init()

        let deviceID = UUID()
        self.device = CMIOExtensionDevice(
            localizedName: localizedName,
            deviceID: deviceID,
            legacyDeviceID: deviceID.uuidString,
            source: self
        )

        let dims = CMVideoDimensions(width: freeStageCameraWidth, height: freeStageCameraHeight)
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: dims.width,
            height: dims.height,
            extensions: nil,
            formatDescriptionOut: &videoDescription
        )

        let pixelBufferAttributes: NSDictionary = [
            kCVPixelBufferWidthKey: dims.width,
            kCVPixelBufferHeightKey: dims.height,
            kCVPixelBufferPixelFormatTypeKey: videoDescription.mediaSubType,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, pixelBufferAttributes, &bufferPool)
        bufferAuxAttributes = [kCVPixelBufferPoolAllocationThresholdKey: 5]

        let frameDuration = CMTime(value: 1, timescale: freeStageCameraFrameRate)
        let streamFormat = CMIOExtensionStreamFormat(
            formatDescription: videoDescription,
            maxFrameDuration: frameDuration,
            minFrameDuration: frameDuration,
            validFrameDurations: nil
        )

        let sourceID = UUID()
        streamSource = FreeStageCameraStreamSource(
            localizedName: "\(localizedName).Video",
            streamID: sourceID,
            streamFormat: streamFormat,
            device: device
        )

        let sinkID = UUID()
        streamSink = FreeStageCameraStreamSink(
            localizedName: "\(localizedName).Sink",
            streamID: sinkID,
            streamFormat: streamFormat,
            device: device
        )

        do {
            try device.addStream(streamSource.stream)
            try device.addStream(streamSink.stream)
        } catch {
            fatalError("Failed to add streams: \(error.localizedDescription)")
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let props = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            props.transportType = kIOAudioDeviceTransportTypeVirtual
        }
        if properties.contains(.deviceModel) {
            props.model = "FreeStage Virtual Camera"
        }
        return props
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    func startStreaming() {
        guard bufferPool != nil else { return }
        streamingCounter += 1
    }

    func stopStreaming() {
        if streamingCounter > 1 {
            streamingCounter -= 1
        } else {
            streamingCounter = 0
        }
    }

    func startStreamingSink(client: CMIOExtensionClient) {
        sinkClient = client
        sinkStarted = true
        consumeBuffer(client)
    }

    func stopStreamingSink() {
        sinkStarted = false
        sinkClient = nil
    }

    private func consumeBuffer(_ client: CMIOExtensionClient) {
        guard sinkStarted else { return }
        streamSink.stream.consumeSampleBuffer(from: client) { [weak self] sampleBuffer, sequence, discontinuity, hasMore, error in
            guard let self else { return }
            if let sampleBuffer {
                let now = CMClockGetTime(CMClockGetHostTimeClock())
                let output = CMIOExtensionScheduledOutput(
                    sequenceNumber: sequence,
                    hostTimeInNanoseconds: UInt64(now.seconds * Double(NSEC_PER_SEC))
                )
                if streamingCounter > 0 {
                    streamSource.stream.send(
                        sampleBuffer,
                        discontinuity: [],
                        hostTimeInNanoseconds: UInt64(sampleBuffer.presentationTimeStamp.seconds * Double(NSEC_PER_SEC))
                    )
                }
                streamSink.stream.notifyScheduledOutputChanged(output)
            }
            self.consumeBuffer(client)
        }
    }
}

final class FreeStageCameraStreamSource: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    let device: CMIOExtensionDevice
    private let streamFormat: CMIOExtensionStreamFormat

    init(localizedName: String, streamID: UUID, streamFormat: CMIOExtensionStreamFormat, device: CMIOExtensionDevice) {
        self.device = device
        self.streamFormat = streamFormat
        super.init()
        self.stream = CMIOExtensionStream(
            localizedName: localizedName,
            streamID: streamID,
            direction: .source,
            clockType: .hostTime,
            source: self
        )
    }

    var formats: [CMIOExtensionStreamFormat] { [streamFormat] }
    var activeFormatIndex: Int = 0

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let props = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            props.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            props.frameDuration = CMTime(value: 1, timescale: freeStageCameraFrameRate)
        }
        return props
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let index = streamProperties.activeFormatIndex {
            activeFormatIndex = index
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool { true }

    func startStream() throws {
        guard let source = device.source as? FreeStageCameraDeviceSource else {
            fatalError("Unexpected device source")
        }
        source.startStreaming()
    }

    func stopStream() throws {
        guard let source = device.source as? FreeStageCameraDeviceSource else {
            fatalError("Unexpected device source")
        }
        source.stopStreaming()
    }
}

final class FreeStageCameraStreamSink: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    let device: CMIOExtensionDevice
    private let streamFormat: CMIOExtensionStreamFormat
    var client: CMIOExtensionClient?

    init(localizedName: String, streamID: UUID, streamFormat: CMIOExtensionStreamFormat, device: CMIOExtensionDevice) {
        self.device = device
        self.streamFormat = streamFormat
        super.init()
        self.stream = CMIOExtensionStream(
            localizedName: localizedName,
            streamID: streamID,
            direction: .sink,
            clockType: .hostTime,
            source: self
        )
    }

    var formats: [CMIOExtensionStreamFormat] { [streamFormat] }
    var activeFormatIndex: Int = 0

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration, .streamSinkBufferQueueSize, .streamSinkBuffersRequiredForStartup]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let props = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            props.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            props.frameDuration = CMTime(value: 1, timescale: freeStageCameraFrameRate)
        }
        if properties.contains(.streamSinkBufferQueueSize) {
            props.sinkBufferQueueSize = 1
        }
        if properties.contains(.streamSinkBuffersRequiredForStartup) {
            props.sinkBuffersRequiredForStartup = 1
        }
        return props
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let index = streamProperties.activeFormatIndex {
            activeFormatIndex = index
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        self.client = client
        return true
    }

    func startStream() throws {
        guard let source = device.source as? FreeStageCameraDeviceSource,
              let client else {
            fatalError("Unexpected device source or missing client")
        }
        source.startStreamingSink(client: client)
    }

    func stopStream() throws {
        guard let source = device.source as? FreeStageCameraDeviceSource else {
            fatalError("Unexpected device source")
        }
        source.stopStreamingSink()
    }
}
