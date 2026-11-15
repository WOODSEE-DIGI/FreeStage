//
//  MicrophoneCapture.swift
//  FreeStage
//
//  Captures microphone audio via AVCaptureSession and writes interleaved
//  Float32 samples to a ring buffer for the AudioMixer.
//

import Foundation
import AVFoundation
import OSLog

private let micLogger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "MicrophoneCapture")

/// Captures an audio input device and feeds it to a ring buffer.
final class MicrophoneCapture: @unchecked Sendable {
    private let captureQueue = DispatchQueue(label: "com.woodseedigi.freestage.microphone", qos: .userInteractive)
    private var session: AVCaptureSession?
    private var delegate: CaptureDelegate?
    private let ring: AudioRingBuffer
    private var selectedDeviceID: String?

    init(ring: AudioRingBuffer, deviceID: String? = nil) {
        self.ring = ring
        self.selectedDeviceID = deviceID
    }

    var deviceID: String? {
        get { captureQueue.sync { selectedDeviceID } }
        set {
            captureQueue.sync { selectedDeviceID = newValue }
            let wasRunning = session?.isRunning == true
            stop()
            if wasRunning {
                start()
            }
        }
    }

    func start() {
        captureQueue.async { [weak self] in
            self?.startSession()
        }
    }

    func stop() {
        captureQueue.async { [weak self] in
            self?.session?.stopRunning()
            self?.session = nil
            self?.delegate = nil
        }
    }

    private func startSession() {
        let device: AVCaptureDevice?
        if let selectedDeviceID {
            device = AVCaptureDevice(uniqueID: selectedDeviceID)
        } else {
            device = AVCaptureDevice.default(for: .audio)
        }

        guard let device else {
            micLogger.warning("No audio input device found")
            return
        }

        let session = AVCaptureSession()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                micLogger.warning("Cannot add microphone input")
                return
            }
            session.addInput(input)

            let output = AVCaptureAudioDataOutput()
            let delegate = CaptureDelegate(ring: ring)
            output.setSampleBufferDelegate(delegate, queue: captureQueue)
            guard session.canAddOutput(output) else {
                micLogger.warning("Cannot add microphone output")
                return
            }
            session.addOutput(output)

            self.session = session
            self.delegate = delegate
            session.startRunning()
            micLogger.info("Started microphone capture: \(device.localizedName, privacy: .public)")
        } catch {
            micLogger.error("Failed to start microphone capture: \(error.localizedDescription)")
        }
    }
}

private final class CaptureDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let ring: AudioRingBuffer

    init(ring: AudioRingBuffer) {
        self.ring = ring
        super.init()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
        else { return }

        let channels = Int(asbd.pointee.mChannelsPerFrame)
        let interleaved = asbd.pointee.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        let isFloat = asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let bytesPerSample = Int(asbd.pointee.mBitsPerChannel / 8)
        let frameLength = CMSampleBufferGetNumSamples(sampleBuffer)

        guard channels > 0, frameLength > 0 else { return }

        // Query the required AudioBufferList size; a non-interleaved format
        // needs one buffer per channel, which does not fit in a single
        // AudioBufferList value. Passing an undersized buffer caused the
        // general-path loop to read past the allocated memory.
        var bufferListSize = 0
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: nil
        )
        guard status == noErr, bufferListSize > 0 else {
            micLogger.error("Failed to get audio buffer list size: \(status)")
            return
        }

        let bufferListMemory = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListMemory.deallocate() }
        let bufferListOut = bufferListMemory.assumingMemoryBound(to: AudioBufferList.self)

        var blockBuffer: CMBlockBuffer?
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: bufferListOut,
            bufferListSize: bufferListSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else {
            micLogger.error("Failed to get audio buffer list: \(status)")
            return
        }

        if interleaved, isFloat, bytesPerSample == MemoryLayout<Float>.size, channels == 2 {
            // Fast path: already interleaved stereo Float32.
            let audioBuffer = bufferListOut.pointee.mBuffers
            guard let data = audioBuffer.mData else { return }
            let samples = data.assumingMemoryBound(to: Float.self)
            let count = frameLength * channels
            _ = ring.write(samples, count: count)
            return
        }

        // General path: convert to interleaved stereo Float32.
        let sourceABL = UnsafeMutableAudioBufferListPointer(bufferListOut)
        let availableBuffers = sourceABL.count
        guard availableBuffers > 0 else { return }

        var outputSamples = [Float](repeating: 0, count: frameLength * 2)

        for frame in 0..<frameLength {
            var left: Float = 0
            var right: Float = 0

            for channel in 0..<min(channels, 2, availableBuffers) {
                let buffer = sourceABL[channel]
                guard let data = buffer.mData else { continue }
                let sample: Float
                if isFloat {
                    let ptr = data.assumingMemoryBound(to: Float.self)
                    sample = interleaved ? ptr[frame * channels + channel] : ptr[frame]
                } else {
                    let ptr = data.assumingMemoryBound(to: Int16.self)
                    let raw = interleaved ? ptr[frame * channels + channel] : ptr[frame]
                    sample = Float(raw) / Float(Int16.max)
                }
                if channel == 0 { left = sample }
                else { right = sample }
            }

            outputSamples[frame * 2] = left
            outputSamples[frame * 2 + 1] = right
        }

        outputSamples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            _ = ring.write(base, count: outputSamples.count)
        }
    }
}
