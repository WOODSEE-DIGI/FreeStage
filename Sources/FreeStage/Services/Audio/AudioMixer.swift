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
import os

private let audioMixerLogger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "AudioMixer")

/// Live audio mixer for FreeStage.
@Observable
final class AudioMixer: @unchecked Sendable {
    private(set) var isRunning = false
    private weak var settings: AppSettings?

    // MARK: - Volumes

    /// Per-input channel volumes. Three independent hardware inputs.
    var inputVolumes: [Double] = [1.0, 0.0, 0.0] {
        didSet {
            updateVolumes()
            persistInputDefaults()
        }
    }
    /// Per-input channel mute. When true the channel is silent but its fader
    /// position is preserved.
    var inputMuted: [Bool] = [false, false, false] {
        didSet {
            updateVolumes()
            persistInputDefaults()
        }
    }
    var systemVolume: Double = 1.0 {
        didSet {
            updateVolumes()
            settings?.defaultSystemVolume = systemVolume
        }
    }
    var systemMuted: Bool = false {
        didSet {
            updateVolumes()
            settings?.defaultSystemMuted = systemMuted
        }
    }
    var masterVolume: Double = 1.0 {
        didSet {
            updateVolumes()
            settings?.defaultMasterVolume = masterVolume
        }
    }
    var isOutputMuted: Bool = false {
        didSet {
            updateVolumes()
            settings?.defaultOutputMuted = isOutputMuted
        }
    }

    // MARK: - Live levels (for the retro audio monitor)

    /// Aggregate input level used by the retro monitor (max of all channels).
    var microphoneLevel: Float = 0
    var systemLevel: Float = 0
    var outputLevel: Float = 0

    private let levelLock = OSAllocatedUnfairLock<(inputs: [Float], system: Float)>(initialState: (inputs: [0, 0, 0], system: 0))
    private var levelTimer: Timer?

    // MARK: - Input EQ

    var inputLowGains: [Double] = [0.0, 0.0, 0.0] {
        didSet { updateEQ() }
    }
    var inputMidGains: [Double] = [0.0, 0.0, 0.0] {
        didSet { updateEQ() }
    }
    var inputHighGains: [Double] = [0.0, 0.0, 0.0] {
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

    var selectedInputDeviceIDs: [String?] = [nil, nil, nil]

    var selectedOutputDeviceID: AudioDeviceID? {
        didSet {
            guard let selectedOutputDeviceID,
                  selectedOutputDeviceID != oldValue else { return }
            AudioDeviceManager.setDefaultOutputDevice(selectedOutputDeviceID)
            settings?.defaultOutputDeviceID = selectedOutputDeviceID
        }
    }

    // MARK: - Input channel accessors

    /// Number of independent hardware input channels supported by the mixer.
    static let inputChannelCount = 3

    func inputDeviceID(at index: Int) -> String? {
        guard (0..<Self.inputChannelCount).contains(index) else { return nil }
        return selectedInputDeviceIDs[index]
    }

    func setInputDeviceID(_ deviceID: String?, at index: Int) {
        guard (0..<Self.inputChannelCount).contains(index) else { return }
        guard selectedInputDeviceIDs[index] != deviceID else { return }
        selectedInputDeviceIDs[index] = deviceID
        microphoneCaptures[index].deviceID = deviceID
        persistInputDefaults()
        audioMixerLogger.info("Input \(index + 1) device: \(deviceID ?? "default", privacy: .public)")
    }

    func inputVolume(at index: Int) -> Double {
        guard (0..<Self.inputChannelCount).contains(index) else { return 0 }
        return inputVolumes[index]
    }

    func setInputVolume(_ volume: Double, at index: Int) {
        guard (0..<Self.inputChannelCount).contains(index) else { return }
        inputVolumes[index] = volume
        persistInputDefaults()
    }

    func inputLowGain(at index: Int) -> Double {
        guard (0..<Self.inputChannelCount).contains(index) else { return 0 }
        return inputLowGains[index]
    }

    func setInputLowGain(_ gain: Double, at index: Int) {
        guard (0..<Self.inputChannelCount).contains(index) else { return }
        inputLowGains[index] = gain
        persistInputDefaults()
    }

    func inputMidGain(at index: Int) -> Double {
        guard (0..<Self.inputChannelCount).contains(index) else { return 0 }
        return inputMidGains[index]
    }

    func setInputMidGain(_ gain: Double, at index: Int) {
        guard (0..<Self.inputChannelCount).contains(index) else { return }
        inputMidGains[index] = gain
        persistInputDefaults()
    }

    func inputHighGain(at index: Int) -> Double {
        guard (0..<Self.inputChannelCount).contains(index) else { return 0 }
        return inputHighGains[index]
    }

    func setInputHighGain(_ gain: Double, at index: Int) {
        guard (0..<Self.inputChannelCount).contains(index) else { return }
        inputHighGains[index] = gain
        persistInputDefaults()
    }

    /// Raw input level (0...1) for the channel before volume and mute.
    func inputLevel(at index: Int) -> Float {
        guard (0..<Self.inputChannelCount).contains(index) else { return 0 }
        return levelLock.withLock { state in
            guard index < state.inputs.count else { return 0 }
            return state.inputs[index]
        }
    }

    func inputMuted(at index: Int) -> Bool {
        guard (0..<Self.inputChannelCount).contains(index) else { return false }
        return inputMuted[index]
    }

    func setInputMuted(_ muted: Bool, at index: Int) {
        guard (0..<Self.inputChannelCount).contains(index) else { return }
        inputMuted[index] = muted
        persistInputDefaults()
    }

    private func persistInputDefaults() {
        guard let settings else { return }
        var channels = settings.inputChannels
        for index in 0..<Self.inputChannelCount {
            channels[index] = AppSettings.InputChannelSettings(
                deviceID: selectedInputDeviceIDs[index],
                volume: inputVolumes[index],
                isMuted: inputMuted[index],
                lowGain: inputLowGains[index],
                midGain: inputMidGains[index],
                highGain: inputHighGains[index]
            )
        }
        settings.inputChannels = channels
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
    private let systemRing = AudioRingBuffer(capacity: 48000 * 2 * 2)
    private var inputRings: [AudioRingBuffer] = []
    private var inputSourceNodes: [AVAudioSourceNode] = []
    private var systemSourceNode: AVAudioSourceNode?
    @ObservationIgnored private var inputEQNodes: [AVAudioUnitEQ] = []
    @ObservationIgnored private var systemEQNode: AVAudioUnitEQ?
    private let mixerFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    private var microphoneCaptures: [MicrophoneCapture] = []

    init(settings: AppSettings? = nil) {
        self.settings = settings
        inputRings = (0..<Self.inputChannelCount).map { _ in AudioRingBuffer(capacity: 48000 * 2 * 2) }
        microphoneCaptures = inputRings.map { MicrophoneCapture(ring: $0) }
        loadDefaults()
        setupEngine()
    }

    deinit {
        levelTimer?.invalidate()
    }

    private func loadDefaults() {
        guard let settings else { return }
        let channels = settings.inputChannels
        for index in 0..<Self.inputChannelCount {
            selectedInputDeviceIDs[index] = channels[index].deviceID
            microphoneCaptures[index].deviceID = channels[index].deviceID
            inputVolumes[index] = channels[index].volume
            inputMuted[index] = channels[index].isMuted
            inputLowGains[index] = channels[index].lowGain
            inputMidGains[index] = channels[index].midGain
            inputHighGains[index] = channels[index].highGain
        }
        systemVolume = settings.defaultSystemVolume
        systemMuted = settings.defaultSystemMuted
        masterVolume = settings.defaultMasterVolume
        isOutputMuted = settings.defaultOutputMuted
        selectedOutputDeviceID = settings.defaultOutputDeviceID
    }

    // MARK: - Engine setup

    private func setupEngine() {
        let mixer = engine.mainMixerNode
        let output = engine.outputNode

        // Input source nodes + EQ (one per hardware input channel).
        for index in 0..<Self.inputChannelCount {
            let ring = inputRings[index]
            let source = makeSourceNode(ring: ring, volumeProvider: { [weak self] in
                guard let self, !self.inputMuted[index] else { return 0 }
                return Float(self.inputVolumes[index])
            })
            inputSourceNodes.append(source)
            engine.attach(source)

            let eq = makeEQNode()
            inputEQNodes.append(eq)
            engine.attach(eq)
            engine.connect(source, to: eq, format: mixerFormat)
            engine.connect(eq, to: mixer, format: mixerFormat)
            installLevelTap(on: eq) { [weak self] level in
                self?.levelLock.withLock { state in
                    guard index < state.inputs.count else { return }
                    state.inputs[index] = level
                }
            }
        }

        // System audio source node.
        let sysSource = makeSourceNode(ring: systemRing, volumeProvider: { [weak self] in
            guard let self, !self.systemMuted else { return 0 }
            return Float(self.systemVolume)
        })
        self.systemSourceNode = sysSource
        engine.attach(sysSource)

        // System audio EQ.
        let sysEQ = makeEQNode()
        self.systemEQNode = sysEQ
        engine.attach(sysEQ)
        engine.connect(sysSource, to: sysEQ, format: mixerFormat)
        engine.connect(sysEQ, to: mixer, format: mixerFormat)
        installLevelTap(on: sysEQ) { [weak self] level in
            self?.levelLock.withLock { $0.system = level }
        }

        // Mixer -> output.
        engine.connect(mixer, to: output, format: mixerFormat)

        updateVolumes()
        updateEQ()
        startLevelUpdates()
    }

    private func installLevelTap(on node: AVAudioNode, handler: @escaping (Float) -> Void) {
        node.installTap(onBus: 0, bufferSize: 1024, format: mixerFormat) { buffer, _ in
            handler(Self.rmsLevel(from: buffer))
        }
    }

    /// Normalised RMS level (0...1) from an AVAudioPCMBuffer.
    private static func rmsLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return 0 }

        var sum: Float = 0
        for channel in 0..<channelCount {
            let data = channelData[channel]
            for frame in 0..<frameLength {
                let sample = data[frame]
                sum += sample * sample
            }
        }
        let rms = sqrt(sum / Float(frameLength * channelCount))
        // Map -60 dBFS...0 dBFS to 0...1.
        let db = 20 * log10(max(rms, 1e-6))
        return Float(clamp((db + 60) / 60, 0, 1))
    }

    private static func clamp<T: Comparable>(_ value: T, _ min: T, _ max: T) -> T {
        Swift.max(min, Swift.min(value, max))
    }

    private func startLevelUpdates() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let raw = self.levelLock.withLock { $0 }
            let activeInputs = zip(zip(raw.inputs, self.inputVolumes), self.inputMuted).map { pair -> Float in
                let ((level, volume), muted) = pair
                return muted ? 0 : level * Float(volume)
            }
            self.microphoneLevel = activeInputs.max() ?? 0
            self.systemLevel = self.systemMuted ? 0 : raw.system * Float(self.systemVolume)
            let inputSum = activeInputs.reduce(0, +)
            let systemContribution = self.systemMuted ? 0 : raw.system * Float(self.systemVolume)
            let combined = inputSum + systemContribution
            self.outputLevel = self.isOutputMuted ? 0 : combined * Float(self.masterVolume)
        }
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
        for capture in microphoneCaptures { capture.start() }
        DispatchQueue.main.async { [weak self] in
            self?.isRunning = true
        }
        startLevelUpdates()
        audioMixerLogger.info("Audio engine started")
    }

    func stop() {
        engine.stop()
        for capture in microphoneCaptures { capture.stop() }
        DispatchQueue.main.async { [weak self] in
            self?.isRunning = false
            self?.microphoneLevel = 0
            self?.systemLevel = 0
            self?.outputLevel = 0
        }
        levelTimer?.invalidate()
        levelLock.withLock {
            $0.inputs = [0, 0, 0]
            $0.system = 0
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
        for index in inputEQNodes.indices {
            let eq = inputEQNodes[index]
            eq.bands[0].gain = Float(inputLowGains[index])
            eq.bands[1].gain = Float(inputMidGains[index])
            eq.bands[2].gain = Float(inputHighGains[index])
        }
        if let sysEQ = systemEQNode {
            sysEQ.bands[0].gain = Float(systemLowGain)
            sysEQ.bands[1].gain = Float(systemMidGain)
            sysEQ.bands[2].gain = Float(systemHighGain)
        }
    }
}
