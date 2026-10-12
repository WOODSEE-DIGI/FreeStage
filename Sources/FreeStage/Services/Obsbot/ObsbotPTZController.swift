//
//  ObsbotPTZController.swift
//  FreeStage
//
//  Gimbal (PTZ) control for OBSBOT Tiny-series webcams with two transports:
//
//    - .usb  (primary): direct UVC/vendor control transfers via the ObjC
//      IOKit backend (ObsbotIOKitController). Opens the USB *device*, not the
//      interface, so it coexists with macOS UVCAssistant while AVCapture
//      captures video. Ported from SwiftMaestro's proven implementation.
//
//    - .osc  (fallback): OSC messages to OBSBOT Center running on this Mac
//      (default UDP 16284), per the official OBSBOT OSC definition
//      (obsbot_center_osc_definition 2026-05-08).
//
//  Coordinate frames (kept in one place, conversions are one-liners):
//
//    FreeStage/user frame:  pan + = camera pans RIGHT, tilt + = camera tilts UP.
//    Vendor V3 wire frame:  pan + = LEFT, pitch + = DOWN, degrees (sniffed
//      from the official SDK; same-sign verified: command sign == reading delta).
//    No UVC pan/tilt control exists on the Tiny 3 Lite (descriptor dump), and
//      no absolute-angle V3 command either — absolute framing is closed-loop
//      (read encoders → pulse speeds → re-read until arrival).
//    OSC frame:             same as vendor wire (pan + = left, pitch + = down),
//                           degrees, pan ∈ [-129, 129], pitch ∈ [-59, 59].
//

import AVFoundation
import Foundation
import Network
import OSLog

// MARK: - USB link (ObjC IOKit backend wrapper)

/// Serializes all USB control transfers for one OBSBOT device onto a private
/// queue. Safe to use from any thread.
private final class ObsbotUSBLink: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.woodseedigi.freestage", category: "ObsbotPTZ")

    private let controller = ObsbotIOKitController()
    private let queue = DispatchQueue(label: "com.woodseedigi.freestage.obsbot.usb", qos: .userInitiated)

    var isConnected: Bool { controller.isConnected }

    /// Open the attached OBSBOT matching the given PIDs (tried in order),
    /// preferring the given USB location ID (0 = first match). The location
    /// disambiguates identical cameras on the same bus.
    /// Returns the device name on success.
    func connect(productIDs: [UInt16], locationID: UInt32 = 0) -> String? {
        queue.sync {
            let numbers = productIDs.map { NSNumber(value: $0) }
            let name = controller.connect(withProductIDs: numbers, locationID: locationID)
            if let name {
                Self.logger.info("OBSBOT USB connected: \(name, privacy: .public)")
            } else {
                Self.logger.error("OBSBOT USB connect failed for PIDs \(productIDs.map { String(format: "0x%04X", $0) }.joined(separator: ","), privacy: .public)")
            }
            return name
        }
    }

    func disconnect() {
        queue.sync { controller.disconnect() }
    }

    /// UVC SET_CUR on a control selector/unit pair.
    @discardableResult
    func send(_ bytes: [UInt8], selector: UInt16, unit: UInt8) -> Bool {
        queue.sync { controller.send(Data(bytes), selector: selector, unit: unit) }
    }

    /// UVC GET with explicit bRequest (GET_CUR 0x81, GET_MIN 0x82, GET_MAX 0x83…).
    func read(length: UInt16, selector: UInt16, unit: UInt8, bRequest: UInt8 = 0x81) -> [UInt8]? {
        queue.sync {
            guard let data = controller.readBytes(withLength: UInt(length), selector: selector, unit: unit, bRequest: bRequest) else { return nil }
            return [UInt8](data)
        }
    }
}

// MARK: - Controller

/// Drives an OBSBOT gimbal. All methods are MainActor-isolated; USB/OSC I/O
/// happens off the main thread internally.
@MainActor
@Observable
final class ObsbotPTZController {
    private static let logger = Logger(subsystem: "com.woodseedigi.freestage", category: "ObsbotPTZ")

    static let defaultOSCUint: UInt16 = 16284

    enum Transport: String, CaseIterable, Identifiable, Sendable {
        case usb = "USB (direct)"
        case osc = "OBSBOT Center (OSC)"
        var id: String { rawValue }
    }

    // MARK: Published state

    private(set) var isConnected = false
    private(set) var activeTransport: Transport?
    private(set) var deviceName: String?
    var lastError: String?

    /// Latest known pose in user frame (pan + = right, tilt + = up), degrees.
    private(set) var currentPan: Double = 0
    private(set) var currentTilt: Double = 0

    /// Physical travel limits in user frame. Refined from the device on connect
    /// when the USB transport supports GET_MIN/GET_MAX.
    private(set) var panRange: ClosedRange<Double> = -130...130
    private(set) var tiltRange: ClosedRange<Double> = -32...60
    /// Move speed for absolute moves (degrees of the leading axis per second
    /// hint; the firmware maps it internally). 0 = device default.
    var moveSpeed: Double = 30
    /// Jog speed for direction-pad nudges (wire-frame degrees/second).
    var nudgeSpeed: Double = 25
    /// Repeats the active jog command while a pad arrow is held (some
    /// firmware treats a speed frame as a momentary pulse).
    private var nudgeLoop: Task<Void, Never>?

    // MARK: Private state

    private let usb = ObsbotUSBLink()
    private var oscConnection: NWConnection?
    private let oscQueue = DispatchQueue(label: "com.woodseedigi.freestage.obsbot.osc", qos: .userInitiated)

    private var pendingMove: (pan: Double, tilt: Double)?
    private var moveLoop: Task<Void, Never>?
    private var usbSequence: UInt16 = 0
    /// Status poll loop (selector 0x06 read): the official library polls this
    /// channel continuously; the 60-byte blocks carry live device status and
    /// may gate write acceptance. Changes are logged for analysis.
    private var statusLoop: Task<Void, Never>?
    private var lastStatusHead: String?

    /// AI-roam watchdog: first encoder reading after connect + whether any
    /// nonzero speed has been sent since. If the head drifts with no commands
    /// sent, AI tracking owns the motors (our ai-off was ignored).
    private var connectBaseline: (pan: Double, tilt: Double)?
    private var speedsSentSinceConnect = false
    private var roamCheckDone = false

    /// When the current closed-loop move started (nil = no move in progress).
    /// Safety stop fires after Self.closedLoopTimeout.
    private var moveStart: Date?
    private static let closedLoopTimeout: TimeInterval = 8.0
    private static let arrivalTolerance: Double = 1.5 // degrees per axis
    private static let speedGain: Double = 3.0 // (deg/s) per degree of error
    private static let maxSpeed: Double = 60.0 // deg/s

    // Auto-stow wake state (the Tiny parks its motors after idle; while asleep
    // it ACKs pan/tilt writes but nothing physically moves).
    private var gimbalAwake = false
    private var lastWakeSentAt: Date?
    private static let wakeRefreshInterval: TimeInterval = 8.0

    // AI-tracking interlock. The official libdev SDK states: "If the AI smart
    // tracking is enabled, gimbal is always controlled by AI." A gimbal with AI
    // tracking on ignores every manual pan/tilt command, which is why our moves
    // were silently accepted yet never moved the head. We send an explicit
    // tracking-disable on connect and re-assert it lazily before moves.
    private var trackingDisabled = false
    private var lastTrackingDisableAt: Date?
    private static let trackingRefreshInterval: TimeInterval = 15.0

    /// Next monotonically increasing USB frame sequence number (16-bit, wraps).
    private func nextUSBSequence() -> UInt16 {
        usbSequence &+= 1
        return usbSequence
    }

    /// One-line frame diagnostic: label + IOKit result + first 22 bytes hex
    /// (header + cmd + plen + CRC + payload head). Compare against sniffed
    /// official frames when debugging ignored commands.
    private func logFrame(_ label: String, _ frame: [UInt8], ok: Bool) {
        let head = frame.prefix(22).map { String(format: "%02x", $0) }.joined(separator: " ")
        GimbalLog.log("\(label) ok=\(ok) [\(head)]")
    }

    /// Connect over the selected transport. Tears down any prior connection first.
    func connect(transport: Transport, captureUniqueID: String?) {
        disconnect()
        lastError = nil
        connectBaseline = nil
        speedsSentSinceConnect = false
        roamCheckDone = false

        switch transport {
        case .usb:
            connectUSB(captureUniqueID: captureUniqueID)
        case .osc:
            connectOSC()
        }
    }

    func disconnect() {
        moveLoop?.cancel()
        moveLoop = nil
        statusLoop?.cancel()
        statusLoop = nil
        nudgeLoop?.cancel()
        nudgeLoop = nil
        pendingMove = nil
        usb.disconnect()
        oscConnection?.cancel()
        oscConnection = nil
        isConnected = false
        activeTransport = nil
        deviceName = nil
        // Wake state is per-connection; a fresh connect must wake again.
        gimbalAwake = false
        lastWakeSentAt = nil
    }

    private func connectUSB(captureUniqueID: String?) {
        // Prefer the product matching the selected capture device; fall back to
        // scanning all known Tiny-series PIDs (Tiny 2 / 2 Lite / 3 / 3 Lite).
        var pids = ObsbotV3Protocol.knownProductIDs
        if let pid = Self.productID(fromCaptureUniqueID: captureUniqueID),
           let index = pids.firstIndex(of: pid) {
            pids.remove(at: index)
            pids.insert(pid, at: 0)
        }

        let locationID = Self.locationID(fromCaptureUniqueID: captureUniqueID) ?? 0
        GimbalLog.log("USB connect targeting location 0x\(String(locationID, radix: 16))")
        guard let name = usb.connect(productIDs: pids, locationID: locationID) else {
            lastError = "No OBSBOT camera reachable over USB."
            GimbalLog.log("USB connect FAILED (no device reachable for PIDs \(pids.map { String(format: "0x%04x", $0) }.joined(separator: ",")))")
            return
        }

        deviceName = name
        activeTransport = .usb
        isConnected = true
        NSLog("[ObsbotPTZ] USB connected: %@", name)
        GimbalLog.log("USB connected: \(name)")
        discoverUSBRanges()
        startMoveLoop()
        startStatusPoll()
        // Ordered startup, mirroring the official flow: session open
        // (seqs 0/1/2) first, then wake, AI-off, and the first encoder read.
        Task { [weak self] in
            guard let self else { return }
            await self.openSession()
            _ = await self.sendWake()
            await self.disableTracking()
            await self.refreshPosition()
        }
        // Roam check: 20 s after connect, with no speeds sent in between, the
        // encoders must be still. Drift proves AI tracking owns the gimbal.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard let self, self.isConnected, self.activeTransport == .usb, !self.roamCheckDone else { return }
            self.roamCheckDone = true
            guard !self.speedsSentSinceConnect, let base = self.connectBaseline else {
                GimbalLog.log("roam check skipped (commands were sent since connect)")
                return
            }
            guard let pose = await self.readAttitude() else {
                GimbalLog.log("roam check skipped (read failed)")
                return
            }
            let driftPan = abs(-pose.pan - base.pan)
            let driftTilt = abs(-pose.pitch - base.tilt)
            let drift = max(driftPan, driftTilt)
            if drift > 3.0 {
                GimbalLog.log("AI-ROAMING suspected: head drifted \(driftPan)/\(driftTilt)° with zero commands sent — AI tracking owns the motors")
            } else {
                GimbalLog.log("roam check: head still (drift \(driftPan)/\(driftTilt)°) — motors accept our session")
            }
        }
    }

    /// Drain queued reply frames: GET repeatedly until consecutive misses.
    /// The firmware queues replies (and request echoes); every GET consumes
    /// one frame. Returns the last AA-framed 60-byte reply seen, if any.
    /// One synchronous transaction: send a request frame, then poll for ITS
    /// reply — an AA frame echoing our command AND sequence — up to `timeout`.
    /// Anything else (request echoes, stale replies) is consumed and skipped.
    /// Strictly serial pacing mirrors the official library; blasting frames
    /// makes the firmware answer late and jumbled.
    private func transact(_ frame: [UInt8], timeout: TimeInterval = 4.0) async -> [UInt8]? {
        guard frame.count >= 16 else { return nil }
        let cmd = UInt16(frame[10]) | (UInt16(frame[11]) << 8)
        let seq = UInt16(frame[2]) | (UInt16(frame[3]) << 8)
        let sent: Bool = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { [usb] in
                continuation.resume(returning: usb.send(frame, selector: ObsbotV3Protocol.selectorXU, unit: ObsbotV3Protocol.xuUnit))
            }
        }
        guard sent else {
            GimbalLog.log("transact cmd=0x\(String(cmd, radix: 16)) seq=\(seq): write FAILED")
            return nil
        }
        let deadline = Date().addingTimeInterval(timeout)
        var strained = 0
        while Date() < deadline {
            let reply: [UInt8]? = await withCheckedContinuation { (continuation: CheckedContinuation<[UInt8]?, Never>) in
                DispatchQueue.global(qos: .userInitiated).async { [usb] in
                    continuation.resume(returning: usb.read(length: 60, selector: ObsbotV3Protocol.selectorXU, unit: ObsbotV3Protocol.xuUnit))
                }
            }
            if let r = reply, r.count >= 16, r[0] == ObsbotV3Protocol.magic {
                let rcmd = UInt16(r[10]) | (UInt16(r[11]) << 8)
                let rseq = UInt16(r[2]) | (UInt16(r[3]) << 8)
                if rcmd == cmd && rseq == seq {
                    return r
                }
                strained += 1
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        GimbalLog.log("transact cmd=0x\(String(cmd, radix: 16)) seq=\(seq): TIMEOUT (\(strained) stray frames drained)")
        return nil
    }

    /// Session-open handshake, byte-identical to the official library's
    /// post-connect flow (receiver 0x0d, flags 0x01, explicit seqs 0/1/2).
    /// The q0 (0x1808) reply payload IS the 24-byte device UUID; its last
    /// 4 bytes are needed by the bind frame (per-camera, not hardcoded).
    private func openSession() async {
        var uuidLast4: [UInt8] = [0x92, 0x9D, 0xC9, 0xBE] // fallback (RMOWUHI1283QVS)
        let queries: [(UInt16, UInt16)] = [
            (ObsbotV3Protocol.cmdSession1, 0),
            (ObsbotV3Protocol.cmdSession2, 1),
            (ObsbotV3Protocol.cmdSession3, 2),
        ]
        for (cmd, seq) in queries {
            let frame = ObsbotV3Protocol.buildFrame(cmd: cmd, receiver: ObsbotV3Protocol.receiverSession, flags: ObsbotV3Protocol.flagsGet, payload: [], sequence: seq)
            if let reply = await transact(frame) {
                let head = reply.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
                GimbalLog.log("session q\(seq) cmd=0x\(String(cmd, radix: 16)) ok [\(head)]")
                // q0 reply: plen=24, payload = 24-byte device UUID.
                // Bind frame needs its last 4 bytes — extract dynamically so
                // every Tiny 3 Lite (not just RMOWUHI1283QVS) binds correctly.
                if seq == 0, reply.count >= 40 {
                    let plen = Int(UInt16(reply[12]) | (UInt16(reply[13]) << 8))
                    if plen >= 24 {
                        uuidLast4 = Array(reply[36..<40])
                        let uuidHex = reply[16..<40].map { String(format: "%02x", $0) }.joined()
                        GimbalLog.log("device UUID (from q0 reply): \(uuidHex) → bind tail [\(uuidLast4.map { String(format: "%02x", $0) }.joined(separator: " "))]")
                    }
                }
            } else {
                GimbalLog.log("session q\(seq) cmd=0x\(String(cmd, radix: 16)) FAILED")
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        // Session bind (4th query): per-camera UUID tail inline, explicit seq 3.
        // The firmware answers it (AA echo of cmd 0x18C8 + device serial in ASCII).
        let bind = ObsbotV3Protocol.sessionBindFrame(uuidLast4: uuidLast4, sequence: 3)
        if let reply = await transact(bind) {
            let head = reply.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
            GimbalLog.log("session bind ok [\(head)]")
            // Bind reply plen=14, payload = device serial number in ASCII.
            if reply.count >= 30 {
                let plen = Int(UInt16(reply[12]) | (UInt16(reply[13]) << 8))
                if plen >= 14 {
                    let serial = String(bytes: reply[16..<(16 + min(plen, 14))], encoding: .ascii) ?? "?"
                    GimbalLog.log("device serial (from bind reply): \(serial)")
                }
            }
        } else {
            GimbalLog.log("session bind FAILED")
        }
        usbSequence = 4 // handshake consumed seqs 0..3; continue monotonically
    }

    /// Poll the status channel (UVC GET, selector 0x06, 60 bytes) twice per
    /// second, mirroring the official library. Logs only on change.
    private func startStatusPoll() {
        statusLoop?.cancel()
        lastStatusHead = nil
        statusLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isConnected, self.activeTransport == .usb else { return }
                let head: String? = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                    DispatchQueue.global(qos: .utility).async { [usb] in
                        guard let bytes = usb.read(length: 60, selector: ObsbotV3Protocol.selectorStatus, unit: ObsbotV3Protocol.xuUnit) else {
                            continuation.resume(returning: nil)
                            return
                        }
                        continuation.resume(returning: bytes.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " "))
                    }
                }
                if let head, head != self.lastStatusHead {
                    self.lastStatusHead = head
                    GimbalLog.log("status block: \(head)")
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func connectOSC() {
        let connection = NWConnection(
            to: .hostPort(host: .init("127.0.0.1"), port: .init(integerLiteral: Self.defaultOSCUint)),
            using: .udp
        )
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                Task { @MainActor [weak self] in
                    self?.lastError = "OBSBOT Center OSC failed: \(error.localizedDescription)"
                }
            }
        }
        connection.start(queue: oscQueue)
        listenForOSCReplies(on: connection)
        oscConnection = connection

        activeTransport = .osc
        isConnected = true
        deviceName = "OBSBOT Center (OSC :\(Self.defaultOSCUint))"
        GimbalLog.log("OSC connected to OBSBOT Center UDP :\(Self.defaultOSCUint) (requires OBSBOT Center running)")
        startMoveLoop()
        // Announce presence per the OSC definition, then ask for the pose.
        sendOSC("/OBSBOT/WebCam/General/Connected", [.int32(1)])
        requestOSCPosition()
    }

    // MARK: - Movement

    /// Move the gimbal to an absolute pose (user frame degrees). Values are
    /// clamped to the physical range here; the caller (CameraControlService)
    /// applies the show's limit zone before calling.
    func moveTo(pan: Double, tilt: Double) {
        guard isConnected else { return }
        let clampedPan = min(max(pan, panRange.lowerBound), panRange.upperBound)
        let clampedTilt = min(max(tilt, tiltRange.lowerBound), tiltRange.upperBound)
        pendingMove = (pan: clampedPan, tilt: clampedTilt)
        moveStart = nil
        currentPan = clampedPan
        currentTilt = clampedTilt
    }

    /// Recenter the gimbal (send to 0/0 within the physical range).
    func recenter() {
        moveTo(pan: 0, tilt: 0)
    }

    // MARK: - Direction-pad jogging (no position reads needed)

    /// Start jogging the head. Speeds are WIRE frame (pitch + = down,
    /// pan + = left), degrees/second — the view converts from user frame.
    /// Fire-and-forget: works even when encoder reads fail.
    func nudgeStart(pitchWire: Double, panWire: Double) {
        guard isConnected else { return }
        if activeTransport == .usb {
            nudgeLoop?.cancel()
            nudgeLoop = Task { [weak self] in
                guard let self else { return }
                self.speedsSentSinceConnect = true
                await self.ensureTrackingOff()
                // Send immediately, then refresh ~4×/s until nudgeStop cancels.
                var first = true
                while !Task.isCancelled {
                    let frame = ObsbotV3Protocol.speedCommand(roll: 0, pitch: pitchWire, pan: panWire, sequence: self.nextUSBSequence())
                    let ok = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                        DispatchQueue.global(qos: .userInitiated).async { [usb] in
                            continuation.resume(returning: usb.send(frame, selector: ObsbotV3Protocol.selectorXU, unit: ObsbotV3Protocol.xuUnit))
                        }
                    }
                    if first {
                        self.logFrame("nudge start wire(pitch=\(pitchWire),pan=\(panWire))", frame, ok: ok)
                        first = false
                    }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        } else {
            // OSC fallback: one small absolute step in the pressed direction
            // (wire + = user − on both axes).
            let stepPan = panWire == 0 ? 0 : (panWire > 0 ? -5.0 : 5.0)
            let stepTilt = pitchWire == 0 ? 0 : (pitchWire > 0 ? -5.0 : 5.0)
            moveTo(pan: currentPan + stepPan, tilt: currentTilt + stepTilt)
        }
    }

    /// Stop a jog started by nudgeStart.
    func nudgeStop() {
        nudgeLoop?.cancel()
        nudgeLoop = nil
        guard isConnected, activeTransport == .usb else { return }
        Task { [weak self] in
            await self?.sendStop()
            GimbalLog.log("nudge stop")
        }
    }

    /// Start the coalescing drain loop if not already running.
    private func startMoveLoop() {
        guard moveLoop == nil else { return }
        moveLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isConnected else { return }
                if let target = self.pendingMove {
                    self.pendingMove = nil
                    await self.sendMove(target.pan, target.tilt)
                }
                try? await Task.sleep(nanoseconds: 40_000_000) // 25 Hz drain
            }
        }
    }

    /// Send a framed V3 wake command (0xA0C2, payload 0x00). The Tiny auto-stows
    /// after idle; while asleep it accepts pan/tilt writes silently (IOKit
    /// reports success) but the motors are parked and nothing moves. A wake is
    /// required before moves take effect.
    private func sendWake() async -> Bool {
        let frame = ObsbotV3Protocol.wakeCommand(sequence: nextUSBSequence())
        let ok = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { [usb] in
                continuation.resume(returning: usb.send(frame, selector: ObsbotV3Protocol.selectorXU, unit: ObsbotV3Protocol.xuUnit))
            }
        }
        if ok {
            gimbalAwake = true
            lastWakeSentAt = Date()
        }
        NSLog("[ObsbotPTZ] wake sent ok=%d", ok ? 1 : 0)
        GimbalLog.log("wake sent ok=\(ok)")
        return ok
    }

    /// Ensure the gimbal is awake before a move. Wakes on first use and re-wakes
    /// if we haven't sent a wake recently (the camera may have re-stowed).
    private func ensureAwake() async {
        let stale = lastWakeSentAt.map { Date().timeIntervalSince($0) > Self.wakeRefreshInterval } ?? true
        if !gimbalAwake || stale {
            _ = await sendWake()
        }
    }

    // MARK: - AI tracking interlock

    /// Force the camera's AI smart-tracking OFF so the firmware will accept
    /// manual gimbal moves. Per the official libdev SDK ("If the AI smart
    /// tracking is enabled, gimbal is always controlled by AI"), a gimbal with
    /// AI tracking active silently ignores every pan/tilt command - which is
    /// exactly the failure we observed (moves ACKed, head never moved).
    ///
    /// Transport strategy:
    ///  - USB: sniffed `aiEnable(false)` frame (receiver 0x04, cmd 0x0244,
    ///    payload [00]) — the official library's own call, rc=0, verified.
    ///  - OSC: the documented `/OBSBOT/WebCam/Tiny/SetAiMode` with arg 0 (mode 0
    ///    = the least track-y mode on the Tiny 3 Lite, which has no "off").
    /// Returns true if a control write was delivered.
    @discardableResult
    private func disableTracking() async -> Bool {
        switch activeTransport {
        case .osc:
            // Tiny 3 Lite SetAiMode has no "off"; 0 (Human-Single) is the
            // closest to a non-roaming mode. ToggleAILock is also sent on
            // connect to stop it re-acquiring a subject.
            sendOSC("/OBSBOT/WebCam/Tiny/SetAiMode", [.int32(0)])
            GimbalLog.log("tracking-off: OSC SetAiMode 0 sent")
            trackingDisabled = true
            lastTrackingDisableAt = Date()
            return true
        case .usb:
            // Sniffed aiEnable(false): receiver 0x04, cmd 0x0244, payload [00].
            let frame = ObsbotV3Protocol.aiEnableCommand(false, sequence: nextUSBSequence())
            let ok = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                DispatchQueue.global(qos: .userInitiated).async { [usb] in
                    continuation.resume(returning: usb.send(frame, selector: ObsbotV3Protocol.selectorXU, unit: ObsbotV3Protocol.xuUnit))
                }
            }
            NSLog("[ObsbotPTZ] tracking-off (USB aiEnable=0) ok=%d", ok ? 1 : 0)
            GimbalLog.log("tracking-off: USB aiEnable(false) ok=\(ok)")
            self.logFrame("tracking-off frame", frame, ok: ok)
            trackingDisabled = ok
            lastTrackingDisableAt = Date()
            return ok
        case .none:
            return false
        }
    }

    /// Re-assert tracking-off before a move if we haven't sent it recently.
    /// The firmware can re-enable AI tracking on its own (power-cycle, mode
    /// button, reconnection), so this is cheap insurance at the top of sendMove.
    private func ensureTrackingOff() async {
        let stale = lastTrackingDisableAt.map { Date().timeIntervalSince($0) > Self.trackingRefreshInterval } ?? true
        if !trackingDisabled || stale {
            await disableTracking()
        }
    }



    private func sendMove(_ panUser: Double, _ tiltUser: Double) async {
        switch activeTransport {
        case .usb:
            // The camera may have auto-stowed since the last move; wake it so
            // this command actually drives the motors instead of being
            // silently accepted by a parked gimbal.
            await ensureTrackingOff()
            await ensureAwake()
            // No absolute-angle command exists on the Tiny 3 Lite, so this is
            // one closed-loop step toward the user-frame target (the 25 Hz
            // drain loop calls back until arrival or timeout).
            await driveToward(pan: panUser, tilt: tiltUser)
        case .osc:
            // OSC absolute move: same wire convention as vendor (pan + = left,
            // pitch + = down), degrees. Speed 0-90.
            await ensureTrackingOff()
            sendOSC("/OBSBOT/WebCam/General/SetGimMotorDegreeEx", [
                .float32(Float(moveSpeed)),
                .float32(Float(-panUser)),
                .float32(Float(-tiltUser)),
            ])
        case .none:
            break
        }
    }

    /// Read the motor encoders (wire frame: roll/pitch/pan degrees).
    /// The firmware answers the request asynchronously: after the SET, the
    /// 60-byte reply is polled (the official library resends/retries the same
    /// way). Returns nil if nothing valid arrives.
    /// Read the motor encoders via one synchronous transaction
    /// (request + matching AA reply, up to 4 s).
    private func readAttitude() async -> (roll: Double, pitch: Double, pan: Double)? {
        let frame = ObsbotV3Protocol.attitudeGetCommand(sequence: nextUSBSequence())
        guard let reply = await transact(frame) else {
            GimbalLog.log("attitude read FAILED (no matching reply)")
            return nil
        }
        guard let pose = ObsbotV3Protocol.parseAttitudeReply(reply) else {
            let head = reply.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
            GimbalLog.log("attitude reply rejected validation [\(head)]")
            return nil
        }
        return (roll: pose.roll, pitch: pose.pitch, pan: pose.pan)
    }

    /// Send a speed frame (wire frame, degrees/second). Zeros stop the head.
    private func sendSpeed(roll: Double, pitch: Double, pan: Double) async -> Bool {
        if pitch != 0 || pan != 0 { speedsSentSinceConnect = true }
        let frame = ObsbotV3Protocol.speedCommand(roll: roll, pitch: pitch, pan: pan, sequence: nextUSBSequence())
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { [usb] in
                continuation.resume(returning: usb.send(frame, selector: ObsbotV3Protocol.selectorXU, unit: ObsbotV3Protocol.xuUnit))
            }
        }
    }

    private func sendStop() async {
        _ = await sendSpeed(roll: 0, pitch: 0, pan: 0)
    }

    /// One closed-loop step toward a user-frame (pan + = right, tilt + = up)
    /// target: read the encoders, pulse proportional speeds, stop on arrival.
    private func driveToward(pan panUser: Double, tilt tiltUser: Double) async {
        if moveStart == nil { moveStart = Date() }
        if let start = moveStart, Date().timeIntervalSince(start) > Self.closedLoopTimeout {
            await sendStop()
            pendingMove = nil
            moveStart = nil
            lastError = "Gimbal move timed out."
            GimbalLog.log("driveToward TIMEOUT at user(\(panUser),\(tiltUser))")
            return
        }
        guard let pose = await readAttitude() else {
            await sendStop()
            pendingMove = nil
            moveStart = nil
            lastError = "Gimbal read failed; move aborted."
            GimbalLog.log("driveToward ABORTED (attitude read failed)")
            return
        }
        // Wire frame: pitch + = down, pan + = left. User frame flips both.
        // (Same-sign command→reading mapping verified against official SDK
        // traffic; if motion ever appears mirrored, flip these negations.)
        let errPan = -panUser - pose.pan
        let errTilt = -tiltUser - pose.pitch
        if abs(errPan) < Self.arrivalTolerance, abs(errTilt) < Self.arrivalTolerance {
            await sendStop()
            pendingMove = nil
            moveStart = nil
            currentPan = -pose.pan
            currentTilt = -pose.pitch
            GimbalLog.log("driveToward ARRIVED user(\(panUser),\(tiltUser)) encoders(pan=\(pose.pan),pitch=\(pose.pitch))")
            return
        }
        let speedPan = min(max(errPan * Self.speedGain, -Self.maxSpeed), Self.maxSpeed)
        let speedTilt = min(max(errTilt * Self.speedGain, -Self.maxSpeed), Self.maxSpeed)
        let ok = await sendSpeed(roll: 0, pitch: speedTilt, pan: speedPan)
        currentPan = -pose.pan
        currentTilt = -pose.pitch
        GimbalLog.log("driveToward step target=(\(panUser),\(tiltUser)) enc=(\(pose.pan),\(pose.pitch)) err=(\(errPan),\(errTilt)) spd=(\(speedPan),\(speedTilt)) ok=\(ok)")
        if !ok {
            Self.logger.error("OBSBOT USB speed send FAILED")
        }
    }

    // MARK: - Position

    /// Re-read the gimbal pose from the device and update currentPan/Tilt.
    func refreshPosition() async {
        guard isConnected else { return }
        switch activeTransport {
        case .usb:
            await refreshUSBPosition()
        case .osc:
            requestOSCPosition()
        case .none:
            break
        }
    }

    private func refreshUSBPosition() async {
        // Motor-encoder read: receiver 0x03, cmd 0x0043, empty payload;
        // 60-byte reply validated (magic, echoed cmd, both CRCs).
        guard let pose = await readAttitude() else {
            lastError = "Gimbal position read failed."
            NSLog("[ObsbotPTZ] position read failed (attitude GET)")
            GimbalLog.log("position read FAILED (attitude GET)")
            return
        }
        NSLog("[ObsbotPTZ] encoders roll=%.2f pitch=%.2f pan=%.2f", pose.roll, pose.pitch, pose.pan)
        GimbalLog.log("encoders roll=\(pose.roll) pitch=\(pose.pitch) pan=\(pose.pan) → user pan=\(-pose.pan) tilt=\(-pose.pitch)")
        currentPan = -pose.pan // wire pan + = left; user + = right
        currentTilt = -pose.pitch // wire pitch + = down; user + = up
        if connectBaseline == nil {
            connectBaseline = (pan: currentPan, tilt: currentTilt)
            GimbalLog.log("roam baseline set user(pan=\(currentPan),tilt=\(currentTilt))")
        }
        lastError = nil
    }

    /// Travel limits. The Tiny 3 Lite exposes no UVC pan/tilt control
    /// (proven by USB descriptor dump), so there is nothing to discover —
    /// keep the built-in defaults, which match observed travel (pan end-stop
    /// seen at ≈ +144° wire).
    private func discoverUSBRanges() {
        NSLog("[ObsbotPTZ] using built-in ranges pan [%.1f, %.1f] tilt [%.1f, %.1f] (no UVC pan/tilt control on this model)",
              panRange.lowerBound, panRange.upperBound, tiltRange.lowerBound, tiltRange.upperBound)
        GimbalLog.log("using built-in ranges pan [\(panRange.lowerBound), \(panRange.upperBound)] tilt [\(tiltRange.lowerBound), \(tiltRange.upperBound)]")
    }

    // MARK: - OSC helpers

    private func sendOSC(_ address: String, _ arguments: [OSCArgument]) {
        guard let connection = oscConnection else { return }
        let message = OSCMessage(address: address, arguments: arguments)
        let data = message.encoded
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.lastError = "OSC send failed: \(error.localizedDescription)"
                }
            }
        })
    }

    private func requestOSCPosition() {
        sendOSC("/OBSBOT/WebCam/General/GetGimbalPosInfo", [.int32(0)])
    }

    private func listenForOSCReplies(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            if let data, let message = OSCMessage.decode(data) {
                Task { @MainActor [weak self] in
                    self?.handleOSCReply(message)
                }
            }
            if error == nil {
                // receiveMessage completions run on oscQueue (nonisolated);
                // hop back to MainActor for the next recursive listen.
                Task { @MainActor [weak self] in
                    self?.listenForOSCReplies(on: connection)
                }
            }
        }
    }

    private func handleOSCReply(_ message: OSCMessage) {
        // GimbalPosInfoResp: roll, pitch, yaw in whole degrees (OSC type "iii",
        // wire frame: pitch + = down, yaw + = left).
        guard message.address.hasSuffix("GimbalPosInfoResp"),
              message.arguments.count >= 3,
              let pitch = message.arguments[1].asInt32,
              let yaw = message.arguments[2].asInt32
        else { return }
        // Wire → user: yaw + = left → user pan = -yaw; pitch + = down → user tilt = -pitch.
        currentPan = Double(-yaw)
        currentTilt = Double(-pitch)
    }

    // MARK: - Misc helpers

    /// Parse the vendor/product ID pair out of an AVCaptureDevice uniqueID.
    /// macOS external-camera uniqueIDs embed the USB IDs, e.g.
    /// "0x35640xFF04_538067968" or a location-based suffix containing them.
    /// Parse the USB location ID out of an AVCaptureDevice uniqueID
    /// ("0x201300003564ff04" → 0x20130000: leading 8 hex digits).
    static func locationID(fromCaptureUniqueID uniqueID: String?) -> UInt32? {
        guard var hex = uniqueID?.uppercased(), hex.hasPrefix("0X") else { return nil }
        hex.removeFirst(2)
        guard hex.count >= 8 else { return nil }
        return UInt32(hex.prefix(8), radix: 16)
    }

    static func productID(fromCaptureUniqueID uniqueID: String?) -> UInt16? {
        guard let uniqueID else { return nil }
        // Look for a 8-hex-digit VID+PID run and take its low 16 bits.
        let hex = uniqueID.uppercased()
        for pid in ObsbotV3Protocol.knownProductIDs {
            let needle = String(format: "%04X", pid)
            if hex.contains(needle) { return pid }
        }
        return nil
    }
}

private extension OSCArgument {
    var asInt32: Int32? {
        if case .int32(let value) = self { return value }
        return nil
    }
}
