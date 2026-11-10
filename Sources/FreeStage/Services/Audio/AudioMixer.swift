//
//  AudioMixer.swift
//  FreeStage
//
//  Mixes microphone and system audio with per-channel gain and EQ, monitors
//  the result to the selected output device, and supplies mixed audio to a
//  recording tap.
//

import Foundation
import AVFoundation
@preconcurrency import AVFAudio
import Observation
import OSLog

private let audioMixerLogger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "AudioMixer")

/// Live audio mixer for FreeStage.
@Observable
final class AudioMixer: @unchecked Sendable {
    private(set) var isRunning = false

    // MARK: - Volumes

    var microphoneVolume: Double = 1.0 {
        didSet { updateVolumes() }
    }
    var systemVolume: Double = 1.0 {
        didSet { updateVolumes() }
    }
    var masterVolume: Double = 1.0 {
        didSet { updateVolumes() }
    }
    var isOutputMuted: Bool = false {
        didSet { updateVolumes() }
    }

    // MARK: - Microphone EQ

    var microphoneLowGain: Double = 0.0 {
        didSet { updateEQ() }
    }
    var microphoneMidGain: Double = 0.0 {
        didSet { updateEQ() }
    }
    var microphoneHighGain: Double = 0.0 {
        didSet { updateEQ() }
    }

    // MARK: - System audio EQ

    var systemLowGain: Double = 0.0 {
        didSet { updateEQ() }
    }
    var systemMidGain: Double = 0.0 {
        didSet { updateEQ() }
    }
    var systemHighGain: Double = 0.0 {
        didSet { updateEQ() }
    }

    // MARK: - Input/output devices

    var selectedInputDeviceID: String? {
        didSet {
            guard oldValue != self.selectedInputDeviceID else { return }
            self.microphoneCapture?.deviceID = self.selectedInputDeviceID
            audioMixerLogger.info("Selected input device: \(self.selectedInputDeviceID ?? "default", privacy: .public)")
        }
    }

    var selectedOutputDeviceID: AudioDeviceID? {
        didSet {
            guard let selectedOutputDeviceID,
                  selectedOutputDeviceID != oldValue else { return }
            AudioDeviceManager.setDefaultOutputDevice(selectedOutputDeviceID)
        }
    }

    var availableInputDevices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    var availableOutputDevices: [AudioDevice] {
        AudioDeviceManager.outputDevices()
    }

    // MARK: - Engine nodes

    private let engine = AVAudioEngine()
    private let microphoneRing = AudioRingBuffer(capacity: 48000 * 2 * 2)
    private let systemRing = AudioRingBuffer(capacity: 48000 * 2 * 2)
    private var microphoneSourceNode: AVAudioSourceNode?
    private var systemSourceNode: AVAudioSourceNode?
    @ObservationIgnored private var microphoneEQNode: AVAudioUnitEQ?
    @ObservationIgnored private var systemEQNode: AVAudioUnitEQ?
    private let mixerFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    private var microphoneCapture: MicrophoneCapture?

    init() {
        microphoneCapture = MicrophoneCapture(ring: microphoneRing)
        setupEngine()
    }

    // MARK: - Engine setup

    private func setupEngine() {
        let mixer = engine.mainMixerNode
        let output = engine.outputNode

        // Microphone source node.
        let micSource = makeSourceNode(ring: microphoneRing, volumeProvider: { [weak self] in Float(self?.microphoneVolume ?? 1.0) })
        self.microphoneSourceNode = micSource
        engine.attach(micSource)

        // Microphone EQ.
        let micEQ = makeEQNode()
        self.microphoneEQNode = micEQ
        engine.attach(micEQ)
        engine.connect(micSource, to: micEQ, format: mixerFormat)
        engine.connect(micEQ, to: mixer, format: mixerFormat)

        // System audio source node.
        let sysSource = makeSourceNode(ring: systemRing, volumeProvider: { [weak self] in Float(self?.systemVolume ?? 1.0) })
        self.systemSourceNode = sysSource
        engine.attach(sysSource)

        // System audio EQ.
        let sysEQ = makeEQNode()
        self.systemEQNode = sysEQ
        engine.attach(sysEQ)
        engine.connect(sysSource, to: sysEQ, format: mixerFormat)
        engine.connect(sysEQ, to: mixer, format: mixerFormat)

        // Mixer -> output.
        engine.connect(mixer, to: output, format: mixerFormat)

        updateVolumes()
        updateEQ()
    }

    private func makeSourceNode(ring: AudioRingBuffer, volumeProvider: @escaping () -> Float) -> AVAudioSourceNode {
        AVAudioSourceNode { isSilence, timestamp, frameCount, audioBufferList -> OSStatus in
            let channels = 2
            let requested = Int(frameCount) * channels
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let data = abl[0].mData else { return noErr }

            var temp = [Float](repeating: 0, count: requested)
            let read = ring.read(into: &temp, count: requested)
            let gain = volumeProvider()
            for i in 0..<read {
                temp[i] *= gain
            }

            let floatData = data.assumingMemoryBound(to: Float.self)
            let buf = UnsafeMutableBufferPointer(start: floatData, count: Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size)
            for i in 0..<min(requested, buf.count) {
                buf[i] = temp[i]
            }

            isSilence.pointee = false
            return noErr
        }
    }

    private func makeEQNode() -> AVAudioUnitEQ {
        let eq = AVAudioUnitEQ(numberOfBands: 3)
        eq.globalGain = 0
        let bands = eq.bands
        // Low shelf ~100 Hz
        bands[0].filterType = .lowShelf
        bands[0].frequency = 100
        bands[0].bandwidth = 1.0
        bands[0].gain = 0
        bands[0].bypass = false

        // Mid parametric ~1 kHz
        bands[1].filterType = .parametric
        bands[1].frequency = 1000
        bands[1].bandwidth = 1.0
        bands[1].gain = 0
        bands[1].bypass = false

        // High shelf ~8 kHz
        bands[2].filterType = .highShelf
        bands[2].frequency = 8000
        bands[2].bandwidth = 1.0
        bands[2].gain = 0
        bands[2].bypass = false
        return eq
    }

    // MARK: - Transport

    func start() throws {
        guard !engine.isRunning else { return }
        try engine.start()
        microphoneCapture?.start()
        DispatchQueue.main.async { [weak self] in
            self?.isRunning = true
        }
        audioMixerLogger.info("Audio engine started")
    }

    func stop() {
        engine.stop()
        microphoneCapture?.stop()
        DispatchQueue.main.async { [weak self] in
            self?.isRunning = false
        }
        audioMixerLogger.info("Audio engine stopped")
    }

    // MARK: - Feeds

    /// Feed interleaved 48 kHz stereo Float32 system-audio samples.
    func feedSystemAudio(samples: UnsafePointer<Float>, count: Int) {
        _ = systemRing.write(samples, count: count)
    }

    /// Feed a CoreMedia audio sample buffer from ScreenCaptureKit or AVCapture.
    @discardableResult
    func feedSystemAudio(sampleBuffer: CMSampleBuffer) -> Bool {
        guard let bufferList = CMSampleBufferGetDataBuffer(sampleBuffer),
              CMBlockBufferGetDataLength(bufferList) > 0 else { return false }

        let format = mixerFormat
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return false }

        var abl = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &abl,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
        else { return false }

        if asbd.pointee.mSampleRate == format.sampleRate,
           asbd.pointee.mChannelsPerFrame == format.channelCount,
           asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            let audioBuffer = abl.mBuffers
            guard let data = audioBuffer.mData else { return false }
            let samples = data.assumingMemoryBound(to: Float.self)
            let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
            _ = systemRing.write(samples, count: count)
            return true
        }

        guard let sourceFormat = AVAudioFormat(streamDescription: asbd),
              let converter = AVAudioConverter(from: sourceFormat, to: format) else { return false }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(frameCount)) else { return false }
        pcmBuffer.frameLength = pcmBuffer.frameCapacity

        let sourceABL = UnsafeMutableAudioBufferListPointer(&abl)
        for (index, buffer) in sourceABL.enumerated() {
            guard index < Int(pcmBuffer.audioBufferList.pointee.mNumberBuffers) else { break }
            let destBuffer = pcmBuffer.audioBufferList.pointee.mBuffers
            guard let src = buffer.mData, let dst = destBuffer.mData else { continue }
            memcpy(dst, src, Int(min(buffer.mDataByteSize, destBuffer.mDataByteSize)))
        }

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return false }
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return pcmBuffer
        }
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error {
            audioMixerLogger.error("Audio conversion failed: \(error.localizedDescription)")
            return false
        }

        if let channelData = outputBuffer.floatChannelData {
            let count = Int(outputBuffer.frameLength) * Int(format.channelCount)
            _ = systemRing.write(channelData[0], count: count)
            return true
        }
        return false
    }

    // MARK: - Recording tap

    func installRecordingTap(_ block: @escaping AVAudioNodeTapBlock) {
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil, block: block)
    }

    func removeRecordingTap() {
        engine.mainMixerNode.removeTap(onBus: 0)
    }

    // MARK: - Private updates

    private func updateVolumes() {
        engine.mainMixerNode.volume = isOutputMuted ? 0 : Float(masterVolume)
    }

    private func updateEQ() {
        if let micEQ = microphoneEQNode {
            micEQ.bands[0].gain = Float(microphoneLowGain)
            micEQ.bands[1].gain = Float(microphoneMidGain)
            micEQ.bands[2].gain = Float(microphoneHighGain)
        }
        if let sysEQ = systemEQNode {
            sysEQ.bands[0].gain = Float(systemLowGain)
            sysEQ.bands[1].gain = Float(systemMidGain)
            sysEQ.bands[2].gain = Float(systemHighGain)
        }
    }
}
