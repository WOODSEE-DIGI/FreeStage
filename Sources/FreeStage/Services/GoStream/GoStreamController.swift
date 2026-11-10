//
//  GoStreamController.swift
//  FreeStage
//
//  MainActor-observable mirror of the OSEE GoStream Duet's live state.
//
//  Consumes the client's frame stream, updates published state from "res",
//  "get", and "pus" frames alike (the device pushes every state change, so
//  hardware-panel operations stay in sync automatically), and exposes
//  intent methods (cut, auto, ftb, setPGM…) that the UI calls.
//
//  Protocol facts baked in (verified on fw 2.4.1):
//    - cut/auto/ftb are bare {"id":X,"type":"set"} with no value.
//    - pgmIndex/pvwIndex sets carry [sourceId].
//    - Replies are typed "res" on 2.4.1 but "get" on 2.2.x — both accepted.
//    - pgmTally is pushed automatically whenever PGM changes.
//    - Physical knob: pus audioMixerFader [src, dB] while a channel is
//      selected on the surface, pus audioMixerHeadphone [2301, dB, 10010]
//      when none is (that turn adjusts the monitor output). Selection itself
//      is never pushed — it is inferred from those two.
//    - tBar "get" returns garbage on this firmware; sweep state comes only
//      from transitionStatus [1] (start) / [0] (completed).
//

import Foundation
import OSLog

/// A GoStream macro slot as reported by `macroInfos`.
struct GoStreamMacro: Identifiable, Sendable, Equatable {
    let index: Int
    var name: String
    var description: String
    var id: Int { index }
}

/// Human-readable source labels for the Duet's fixed source-ID namespace
/// (confirmed via `inputList` on our unit: 1,2,3,4,4001,3010,3020,5001).
enum GoStreamSource {
    static func label(_ id: Int) -> String {
        switch id {
        // Silkscreen labels match the physical panel exactly (no spaces).
        case 1: return "IN1"
        case 2: return "IN2"
        case 3: return "IN3"
        case 4: return "IN4"
        // Official OSEE sourceID enum: AUX1 = 4001, Media Players = 3010/3020
        // (silkscreened STILL1/STILL2 on the Duet), MultiSource canvas = 5001
        // (the S/SRC bus button).
        case 4001: return "AUX"
        case 3010: return "STILL1"
        case 3020: return "STILL2"
        case 5001: return "S/SRC"
        case 10010: return "PGM"
        case 21001: return "HDMI Out 1"
        case 21002: return "HDMI Out 2"
        case 22001: return "USB Out"
        default: return "Src \(id)"
        }
    }
}

@MainActor
@Observable
final class GoStreamController {
    private static let logger = Logger(subsystem: "com.woodseedigi.freestage", category: "GoStream")

    private let client = GoStreamClient()

    // MARK: - Connection

    enum ConnectionState: Equatable {
        case idle
        case discovering
        case connecting
        case connected
        case reconnecting
        case failed(String)

        var isConnected: Bool { self == .connected }
    }

    private(set) var connectionState: ConnectionState = .idle
    private(set) var discoveredDevices: [GoStreamDiscoveredDevice] = []

    var isConnected: Bool { connectionState.isConnected }

    var statusText: String {
        switch connectionState {
        case .idle: return "Disconnected"
        case .discovering: return "Discovering…"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting…"
        case .failed(let reason): return "Failed: \(reason)"
        }
    }

    // MARK: - Device identity

    private(set) var deviceName: String?
    private(set) var firmwareVersion: String?
    private(set) var buildInfo: String?
    private(set) var deviceId: String?
    private(set) var deviceType: Int?

    // MARK: - Switcher state

    /// Source IDs currently on the PGM and PVW buses (nil until first known).
    private(set) var pgmSource: Int?
    private(set) var pvwSource: Int?

    /// Source ID the device reports as "on air" tally (usually == pgmSource).
    private(set) var pgmTally: Int?
    /// PVW bus selection as the device pushes it (`pvwTally` — firmware 2.4.1
    /// pushes bus changes under this id, not pvwIndex).
    private(set) var pvwTally: Int?
    /// Headphone output level in dB, pushed while the hardware knob turns.
    private(set) var headphoneLevelDB: Int?

    private(set) var inputList: [Int] = []
    private(set) var transitionStyle: String = "Mix"
    private(set) var transitionInProgress: Bool = false
    /// 0 = off, 1 = fully black, 2 = in transition.
    private(set) var ftbStatus: Int = 0
    /// index → onAir, per DSK.
    private(set) var dskOnAir: [Int: Bool] = [:]
    private(set) var macros: [Int: GoStreamMacro] = [:]

    // MARK: - Keyer arming (NEXT TRANSITION area)

    /// Upstream keyer taken directly on air (`keyOnAir`).
    private(set) var uskOnAir: Bool = false
    /// Upstream keyer armed for the next transition (`keyEnable`).
    private(set) var uskArmed: Bool = false
    /// Downstream keyer armed for the next transition (`dskEnable`).
    private(set) var dskArmed: Bool = false
    /// PREV — preview the transition on the PVW output first.
    private(set) var previewTransitionOn: Bool = false

    // MARK: - Transport

    /// Master stream state (`live`): ON AIR.
    private(set) var isLive: Bool = false
    /// PGM recording state (`recordStatus`).
    private(set) var isRecording: Bool = false
    /// Media player status: 0 = stopped, 1 = playing, 2 = paused.
    private(set) var playStatus: Int = 0

    // MARK: - Audio

    /// One mixer channel's state. `mixState` follows GSP `AfvState`:
    /// 0 = off, 1 = ON (always mixed), 2 = AFV (follows video).
    struct GoStreamAudioChannel: Equatable, Sendable {
        var mixState: Int = 0
        var faderDB: Double = 0
    }

    private(set) var audioChannels: [Int: GoStreamAudioChannel] = [:]
    /// Mixer input sources (Duet: IN1-4, AUX, MIC1, MIC2).
    private(set) var audioInputs: [Int] = []
    /// Which channel the surface's knob / ON / AFV control (local selection).
    private(set) var selectedAudioInput: Int?

    var isFTBActive: Bool { ftbStatus != 0 }

    // MARK: - Tasks

    private var frameTask: Task<Void, Never>?
    private var deviceTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?

    init() {
        // Prime the client's continuations and start consuming its streams in a
        // single round-trip. Splitting this across two awaited calls raced the
        // first connection against stream setup, so early frames were dropped.
        Task { [weak self] in
            guard let self else { return }
            await self.primeAndConsume()
        }
    }

    private func primeAndConsume() async {
        await client.primeFrameStream()
        await client.primeDeviceStream()
        await client.primeStateStream()

        guard let frames = await client.takeFrameStream(),
              let devices = await client.takeDeviceStream(),
              let states = await client.takeStateStream() else {
            GoStreamLog.log("controller: stream handoff failed — client not primed")
            return
        }

        frameTask = Task { [weak self] in
            for await command in frames {
                self?.handle(command)
            }
        }
        deviceTask = Task { [weak self] in
            for await device in devices {
                self?.handleDiscovered(device)
            }
        }
        stateTask = Task { [weak self] in
            for await event in states {
                self?.handleConnectionEvent(event)
            }
        }
    }

    // MARK: - Connection intent

    func startDiscovery() {
        GoStreamLog.log("controller: startDiscovery")
        if case .idle = connectionState {
            connectionState = .discovering
        }
        Task { await client.startBrowsing() }
    }

    func stopDiscovery() {
        Task { await client.stopBrowsing() }
    }

    func connect(host: String) {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        GoStreamLog.log("controller: connect host=\(trimmed)")
        connectionState = .connecting
        Task { await client.connect(host: trimmed) }
    }

    func connect(device: GoStreamDiscoveredDevice) {
        GoStreamLog.log("controller: connect device=\(device.id)")
        connectionState = .connecting
        Task { await client.connect(serviceName: device.id) }
    }

    func disconnect() {
        GoStreamLog.log("controller: disconnect")
        connectionState = .idle
        clearDeviceState()
        Task { await client.disconnect() }
    }

    // MARK: - Robust send

    /// Last failure to reach the device, shown in the panel so a dead socket is
    /// never mistaken for a working one.
    private(set) var lastSendError: String?

    /// Send a command, awaiting the socket's verdict. A false (transient drop)
    /// is retried once after a short beat — enough to ride out a reconnect that
    /// is mid-flight — and a hard failure is recorded for the UI.
    private func sendCommand(id: String, type: String, value: [GoStreamValue]? = nil) {
        Task {
            if await client.send(id: id, type: type, value: value) {
                lastSendError = nil
                return
            }
            // First attempt failed. Give a racing reconnect a moment, then retry once.
            try? await Task.sleep(nanoseconds: 250_000_000)
            let ok = await client.send(id: id, type: type, value: value)
            if ok {
                lastSendError = nil
            } else {
                let message = "Send failed: \(id)"
                lastSendError = message
                GoStreamLog.log("controller: \(message) (after retry)")
            }
        }
    }

    // MARK: - Switcher intent

    func cut() {
        GoStreamLog.log("controller: CUT")
        sendCommand(id: "cutTransition", type: "set")
    }

    func autoTransition() {
        GoStreamLog.log("controller: AUTO transition")
        sendCommand(id: "autoTransition", type: "set")
    }

    func toggleFTB() {
        GoStreamLog.log("controller: FTB toggle (was ftbStatus=\(ftbStatus))")
        sendCommand(id: "ftb", type: "set")
    }

    func setPGM(_ source: Int) {
        GoStreamLog.log("controller: setPGM \(GoStreamSource.label(source)) (\(source))")
        sendCommand(id: "pgmIndex", type: "set", value: [.int(source)])
    }

    func setPVW(_ source: Int) {
        GoStreamLog.log("controller: setPVW \(GoStreamSource.label(source)) (\(source))")
        sendCommand(id: "pvwIndex", type: "set", value: [.int(source)])
    }

    func setTransitionStyle(_ style: String) {
        GoStreamLog.log("controller: setTransitionStyle \(style)")
        sendCommand(id: "transitionStyle", type: "set", value: [.string(style)])
    }

    func runMacro(_ index: Int) {
        GoStreamLog.log("controller: runMacro \(index)")
        sendCommand(id: "macroRunStart", type: "set", value: [.int(index)])
    }

    // MARK: - Keyer / next-transition intent

    func setPreviewTransition(_ on: Bool) {
        GoStreamLog.log("controller: previewTransition \(on)")
        sendCommand(id: "previewTransition", type: "set", value: [.int(on ? 1 : 0)])
    }

    func toggleUSKOnAir() {
        let next = !uskOnAir
        GoStreamLog.log("controller: USK ON AIR \(next)")
        sendCommand(id: "keyOnAir", type: "set", value: [.int(0), .int(next ? 1 : 0)])
    }

    func toggleUSKArmed() {
        let next = !uskArmed
        GoStreamLog.log("controller: KEY arm \(next)")
        sendCommand(id: "keyEnable", type: "set", value: [.int(0), .int(next ? 1 : 0)])
    }

    func toggleDSKArmed() {
        let next = !dskArmed
        GoStreamLog.log("controller: DSK arm \(next)")
        sendCommand(id: "dskEnable", type: "set", value: [.int(0), .int(next ? 1 : 0)])
    }

    /// Take a DSK immediately on/off air (`dskOnAir [index, enable]`).
    func toggleDSKOnAir(_ index: Int = 0) {
        let next = !(dskOnAir[index] ?? false)
        GoStreamLog.log("controller: DSK \(index) ON AIR \(next)")
        sendCommand(id: "dskOnAir", type: "set", value: [.int(index), .int(next ? 1 : 0)])
    }

    // MARK: - Transport intent

    func toggleLive() {
        let next = !isLive
        GoStreamLog.log("controller: LIVE (stream) \(next)")
        sendCommand(id: "live", type: "set", value: [.int(next ? 1 : 0)])
    }

    /// `recordStart [opt]`: 0 = PGM record, 1 = ISO. This unit reports no ISO
    /// channels, so PGM only.
    func startRecord() {
        GoStreamLog.log("controller: record START (PGM)")
        sendCommand(id: "recordStart", type: "set", value: [.int(0)])
    }

    func stopRecord() {
        GoStreamLog.log("controller: record STOP")
        sendCommand(id: "recordStop", type: "set")
    }

    /// `playPause [player, status]` with playStatus semantics (1 = play).
    func play() {
        GoStreamLog.log("controller: player PLAY")
        sendCommand(id: "playPause", type: "set", value: [.int(0), .int(1)])
    }

    func pausePlayback() {
        GoStreamLog.log("controller: player PAUSE")
        sendCommand(id: "playPause", type: "set", value: [.int(0), .int(2)])
    }

    // MARK: - Audio intent

    /// Select the mixer channel the surface's knob / ON / AFV act on.
    func selectAudioInput(_ source: Int?) {
        selectedAudioInput = source
    }

    /// Direct mix state: 0 = off, 1 = ON, 2 = AFV (`audioMixerEnable`).
    func setAudioMixState(_ state: Int, for source: Int? = nil) {
        guard let source = source ?? selectedAudioInput else { return }
        GoStreamLog.log("controller: audio \(GoStreamSource.label(source)) mixState=\(state)")
        sendCommand(id: "audioMixerEnable", type: "set", value: [.int(source), .int(state)])
    }

    func toggleAudioOn() {
        guard let source = selectedAudioInput else { return }
        let current = audioChannels[source]?.mixState ?? 0
        setAudioMixState(current == 1 ? 0 : 1, for: source)
    }

    func toggleAudioAFV() {
        guard let source = selectedAudioInput else { return }
        let current = audioChannels[source]?.mixState ?? 0
        setAudioMixState(current == 2 ? 0 : 2, for: source)
    }

    /// Fader in dB (-75...+10, 0.5 steps per the official module range).
    func setAudioFader(_ db: Double, for source: Int? = nil) {
        guard let source = source ?? selectedAudioInput else { return }
        let clamped = min(10, max(-75, db))
        var channel = audioChannels[source] ?? GoStreamAudioChannel()
        channel.faderDB = clamped
        audioChannels[source] = channel
        sendCommand(id: "audioMixerFader", type: "set", value: [.int(source), .double(clamped)])
    }

    /// Monitor ("OUT") level — `audioMixerHeadphone [2301, dB, 10010]`,
    /// range −31…0 in 1 dB steps (official module). The hardware pushes this
    /// while its knob turns with no source selected; the panel's OUT knob
    /// drives it back the same way.
    func setHeadphoneLevel(_ db: Double) {
        let clamped = Int(min(0, max(-31, db)).rounded())
        headphoneLevelDB = clamped
        GoStreamLog.log("controller: headphone OUT \(clamped) dB")
        sendCommand(id: "audioMixerHeadphone", type: "set",
                    value: [.int(2301), .int(clamped), .int(10010)])
    }

    /// Full state pull — called once on connect; the device answers every get.
    func requestFullState() {
        GoStreamLog.log("controller: requesting full state")
        var gets = [
            "deviceName", "version", "buildInfo", "deviceId", "deviceType",
            "inputList", "pgmIndex", "pvwIndex", "pgmTally", "pvwTally",
            "transitionStyle", "transitionStatus", "ftb", "ftbStatus",
            "macroInfos", "keyCount", "dskCount", "dskOnAir",
            "keyOnAir", "keyEnable", "dskEnable", "previewTransition",
            "audioMixerInputSourceList",
            // Monitor output level — needs a [2301] value (verified probe:
            // answers [2301, level, 10010, …]; a bare get is ignored).
            "audioMixerHeadphone:2301",
        ]
        // Mixer state per input channel (fixed Duet input set).
        for source in [1, 2, 3, 4, 4001, 1301, 1302] {
            gets.append("audioMixerEnable:\(source)")
            gets.append("audioMixerFader:\(source)")
        }
        Task {
            for id in gets {
                // "audioMixerEnable:1301" style entries carry a [source] value.
                if let sep = id.firstIndex(of: ":") {
                    let base = String(id[..<sep])
                    let source = Int(id[id.index(after: sep)...]) ?? 0
                    let ok = await client.send(id: base, type: "get", value: [.int(source)])
                    if !ok {
                        GoStreamLog.log("controller: state get '\(id)' failed to send")
                    }
                } else {
                    let ok = await client.send(id: id, type: "get")
                    if !ok {
                        GoStreamLog.log("controller: state get '\(id)' failed to send")
                    }
                }
            }
        }
    }

    // MARK: - Frame handling

    private func handleDiscovered(_ device: GoStreamDiscoveredDevice) {
        if !discoveredDevices.contains(device) {
            discoveredDevices.append(device)
        }
    }

    private func handleConnectionEvent(_ event: String) {
        switch event {
        case "ready":
            connectionState = .connected
            requestFullState()
        case "connecting":
            connectionState = .connecting
        case "reconnecting":
            connectionState = .reconnecting
        case "idle":
            if connectionState != .idle {
                connectionState = .idle
                clearDeviceState()
            }
        default:
            if event.hasPrefix("failed") {
                connectionState = .failed(String(event.dropFirst("failed: ".count)))
            } else if event.hasPrefix("waiting") {
                connectionState = .reconnecting
            }
        }
    }

    private func handle(_ command: GoStreamCommand) {
        if command.isError {
            let detail = command.value.compactMap(\.stringValue).joined(separator: ", ")
            GoStreamLog.log("controller: device error for '\(command.id)': \(detail)")
            return
        }
        guard command.isStateUpdate else { return }

        switch command.id {
        case "pgmIndex":
            pgmSource = command.value.first?.intValue ?? pgmSource
        case "pvwIndex":
            pvwSource = command.value.first?.intValue ?? pvwSource
        case "pgmTally":
            pgmTally = command.value.first?.intValue ?? pgmTally
        case "pvwTally":
            // Firmware 2.4.1 pushes PVW bus selection as pvwTally [source].
            if let source = command.value.first?.intValue {
                pvwTally = source
                pvwSource = source
            }
        case "audioMixerHeadphone":
            // value = [channel(2301), dB, outSource] — pushed while the
            // hardware audio knob turns with NO source selected (the knob then
            // adjusts the monitor/PGM output level, range −31…0 dB). A changed
            // push means the surface has nothing selected — mirror that. An
            // unchanged value is our own set echoed back (the UI updates
            // optimistically), so it must not wipe the channel selection.
            if command.value.count >= 2, let db = command.value[1].intValue {
                if command.type == "pus" {
                    // DIAG: log every pus so we can tell MENU-dial pushes from
                    // audio-knob pushes and see whether the view should update.
                    GoStreamLog.log("device: headphone pus \(db) dB (was \(headphoneLevelDB.map(String.init) ?? "nil"), type=\(command.type))")
                }
                let changed = headphoneLevelDB != db
                headphoneLevelDB = db
                if command.type == "pus" && changed {
                    selectedAudioInput = nil
                }
            }
        case "transitionStyle":
            if let style = command.value.first?.stringValue {
                transitionStyle = style
            }
        case "transitionStatus":
            transitionInProgress = (command.value.first?.intValue ?? 0) == 1
        case "ftbStatus":
            ftbStatus = command.value.first?.intValue ?? 0
        case "dskOnAir":
            // value = [index, onAir]
            if command.value.count >= 2,
               let index = command.value[0].intValue,
               let on = command.value[1].intValue {
                dskOnAir[index] = on == 1
            }
        case "keyOnAir":
            // value = [keyIndex, onAir]
            if let on = command.value.last?.intValue {
                uskOnAir = on == 1
            }
        case "keyEnable":
            if let on = command.value.last?.intValue {
                uskArmed = on == 1
            }
        case "dskEnable":
            if let on = command.value.last?.intValue {
                dskArmed = on == 1
            }
        case "previewTransition":
            previewTransitionOn = (command.value.first?.intValue ?? 0) == 1
        case "live":
            isLive = (command.value.first?.intValue ?? 0) == 1
        case "liveStreamOutputStatus":
            // value = [streamIndex, LiveStatus]; any stream On means ON AIR.
            if command.value.count >= 2 {
                isLive = (command.value[1].intValue ?? 0) == 1
            }
        case "recordStatus":
            isRecording = (command.value.first?.intValue ?? 0) == 1
        case "playStatus":
            // value = [status] or [playerIndex, status].
            let status = command.value.count >= 2
                ? (command.value[1].intValue ?? 0)
                : (command.value.first?.intValue ?? 0)
            playStatus = status
        case "audioMixerEnable":
            // value = [source, AfvState(0 off / 1 on / 2 afv)]
            if command.value.count >= 2,
               let source = command.value[0].intValue,
               let state = command.value[1].intValue {
                var channel = audioChannels[source] ?? GoStreamAudioChannel()
                channel.mixState = state
                audioChannels[source] = channel
            }
        case "audioMixerFader":
            // value = [source, dB]
            if command.value.count >= 2,
               let source = command.value[0].intValue,
               let db = command.value[1].doubleValue {
                var channel = audioChannels[source] ?? GoStreamAudioChannel()
                channel.faderDB = db
                audioChannels[source] = channel
                // Verified on fw 2.4.1: the device only pushes a fader change
                // for the channel selected on the hardware surface — so a push
                // also tells us what the knob is pointed at. Mirror it (full-
                // state "res" replies must not steal the local selection).
                if command.type == "pus" {
                    selectedAudioInput = source
                }
            }
        case "audioMixerInputSourceList":
            audioInputs = command.value.compactMap(\.intValue)
        case "deviceName":
            deviceName = command.value.first?.stringValue
        case "version":
            firmwareVersion = command.value.first?.stringValue
        case "buildInfo":
            buildInfo = command.value.first?.stringValue
        case "deviceId":
            deviceId = command.value.first?.stringValue
        case "deviceType":
            deviceType = command.value.first?.intValue
        case "inputList":
            inputList = command.value.compactMap(\.intValue)
        case "macroInfos":
            parseMacroInfos(command.value)
        case "keyCount", "dskCount", "recordISOChannelList",
             "audioMixerOutSourceList", "outSourceList",
             "audioMixerSwitchType":
            // Inventory values we don't yet surface in the UI; logged for
            // the evidence trail only.
            GoStreamLog.log("controller: \(command.id) = \(command.value)")
        default:
            GoStreamLog.log("controller: unhandled frame \(command.id) type=\(command.type) value=\(command.value)")
        }
    }

    /// macroInfos arrives as flat triples: [index, name, description, …].
    private func parseMacroInfos(_ values: [GoStreamValue]) {
        var i = 0
        while i + 2 < values.count {
            let index = values[i].intValue ?? -1
            let name = values[i + 1].stringValue ?? ""
            let desc = values[i + 2].stringValue ?? ""
            if index >= 0 {
                macros[index] = GoStreamMacro(index: index, name: name, description: desc)
            }
            i += 3
        }
    }

    private func clearDeviceState() {
        deviceName = nil
        firmwareVersion = nil
        buildInfo = nil
        deviceId = nil
        deviceType = nil
        pgmSource = nil
        pvwSource = nil
        pgmTally = nil
        pvwTally = nil
        headphoneLevelDB = nil
        inputList = []
        transitionInProgress = false
        ftbStatus = 0
        dskOnAir = [:]
        macros = [:]
        uskOnAir = false
        uskArmed = false
        dskArmed = false
        previewTransitionOn = false
        isLive = false
        isRecording = false
        playStatus = 0
        audioChannels = [:]
        audioInputs = []
        selectedAudioInput = nil
    }
}
