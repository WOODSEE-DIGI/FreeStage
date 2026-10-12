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
//    Vendor V3 wire frame:  yaw + = camera's LEFT, pitch + = DOWN.
//    UVC absolute frame:    pan + = LEFT (1/10000°), tilt + = UP.
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

    /// Open the first attached OBSBOT matching the given PIDs (tried in order).
    /// Returns the device name on success.
    func connect(productIDs: [UInt16]) -> String? {
        queue.sync {
            let numbers = productIDs.map { NSNumber(value: $0) }
            let name = controller.connect(withProductIDs: numbers)
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

    // MARK: Private state

    private let usb = ObsbotUSBLink()
    private var oscConnection: NWConnection?
    private let oscQueue = DispatchQueue(label: "com.woodseedigi.freestage.obsbot.osc", qos: .userInitiated)

    private var pendingMove: (pan: Double, tilt: Double)?
    private var moveLoop: Task<Void, Never>?
    private var usbSequence: UInt16 = 0

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

    /// Connect over the selected transport. Tears down any prior connection first.
    func connect(transport: Transport, captureUniqueID: String?) {
        disconnect()
        lastError = nil

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

        guard let name = usb.connect(productIDs: pids) else {
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
        // Wake the gimbal immediately so it is out of auto-stow and ready to
        // accept the first move (moves also self-wake via ensureAwake).
        Task { await self.sendWake() }
        Task { await refreshPosition() }
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
        currentPan = clampedPan
        currentTilt = clampedTilt
    }

    /// Recenter the gimbal (send to 0/0 within the physical range).
    func recenter() {
        moveTo(pan: 0, tilt: 0)
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
    ///  - OSC: the documented `/OBSBOT/WebCam/Tiny/SetAiMode` with arg 0 (mode 0
    ///    = the least track-y mode on the Tiny 3 Lite, which has no "off").
    ///  - USB: a framed V3 SET to the AI-mode command. The wire command id is
    ///    best-effort (not confirmed for the Tiny 3 Lite); if the firmware
    ///    ignores it the gimbal simply stays under AI control and the move is a
    ///    no-op - harmless, and we log it so the failure is visible.
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
            // Best-effort V3 SET to the AI-mode command (mode = none/0).
            // Payload: single little-endian Int32 = 0 (AIWorkModeNone).
            let payload: [UInt8] = [0, 0, 0, 0]
            let sequence = nextUSBSequence()
            let frame = ObsbotV3Protocol.buildSetFrame(
                cmd: Self.cmdAiModeSet,
                receiver: ObsbotV3Protocol.receiverDevice,
                payload: payload,
                sequence: sequence
            )
            let ok = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                DispatchQueue.global(qos: .userInitiated).async { [usb] in
                    continuation.resume(returning: usb.send(frame, selector: ObsbotV3Protocol.selectorXU, unit: ObsbotV3Protocol.xuUnit))
                }
            }
            NSLog("[ObsbotPTZ] tracking-off (USB cmd 0x%04X) ok=%d", Self.cmdAiModeSet, ok ? 1 : 0)
            GimbalLog.log("tracking-off: USB cmd 0x\(String(Self.cmdAiModeSet, radix: 16)) ok=\(ok)")
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

    /// Best-effort V3 wire command id for "set AI work mode". Not confirmed for
    /// the Tiny 3 Lite; the Tiny 2 family uses the V3 SET command space near the
    /// gimbal-move commands. Harmless if the firmware ignores it.
    private static let cmdAiModeSet: UInt16 = 0x64C0


    private func sendMove(_ panUser: Double, _ tiltUser: Double) async {
        switch activeTransport {
        case .usb:
            // The camera may have auto-stowed since the last move; wake it so
            // this command actually drives the motors instead of being
            // silently accepted by a parked gimbal.
            await ensureTrackingOff()
            await ensureAwake()
            // Vendor V3 absolute move: wire yaw+ = left, pitch+ = down. Fire-and-
            // forget: the firmware does not reliably acknowledge gimbal moves.
            let yaw = Float(-panUser)
            let pitch = Float(-tiltUser)
            let sequence = nextUSBSequence()
            let frame = ObsbotV3Protocol.gimbalMoveToAngle(roll: 0, pitch: pitch, yaw: yaw, sequence: sequence)
            let v3OK = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                DispatchQueue.global(qos: .userInitiated).async { [usb] in
                    continuation.resume(returning: usb.send(frame, selector: ObsbotV3Protocol.selectorXU, unit: ObsbotV3Protocol.xuUnit))
                }
            }
            // The V3 angle command is ignored by some firmware. Also issue the
            // standard UVC absolute write (known conventions), which is the
            // reference's documented fallback. Whichever the hardware honors
            // moves the camera; running both is harmless.
            let uvcOK = sendUVCAbsoluteMove(panUser: panUser, tiltUser: tiltUser)
            NSLog("[ObsbotPTZ] move user(%.1f,%.1f) v3=%d uvc=%d", panUser, tiltUser, v3OK ? 1 : 0, uvcOK ? 1 : 0)
            GimbalLog.log("move user(\(panUser),\(tiltUser)) → wire yaw=\(Float(-panUser)) pitch=\(Float(-tiltUser)) v3=\(v3OK) uvc=\(uvcOK)")
            if !v3OK && !uvcOK {
                Self.logger.error("OBSBOT USB move FAILED (pan \(panUser, privacy: .public), tilt \(tiltUser, privacy: .public))")
            }
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

    /// Standard UVC `CT_PANTILT_ABSOLUTE` write (selector 0x0D, camera terminal
    /// unit 0x01). 8-byte payload: pan Int32 + tilt Int32, little-endian,
    /// units of 1/3600° (arcseconds). UVC sign convention: pan + = camera's
    /// LEFT, tilt + = UP. FreeStage user frame: pan + = right, tilt + = up.
    /// Returns true if the control transfer succeeded.
    private func sendUVCAbsoluteMove(panUser: Double, tiltUser: Double) -> Bool {
        // user pan + = right  → UVC pan + = left, so negate.
        // user tilt + = up    → UVC tilt + = up, so pass through.
        let panArcSec = Int32((-panUser * 3600.0).rounded())
        let tiltArcSec = Int32((tiltUser * 3600.0).rounded())

        var payload = [UInt8]()
        payload.append(contentsOf: Self.int32LEBytes(panArcSec))
        payload.append(contentsOf: Self.int32LEBytes(tiltArcSec))

        return usb.send(payload, selector: ObsbotV3Protocol.ctPanTiltAbsolute, unit: ObsbotV3Protocol.ctUnit)
    }

    /// Little-endian byte encoding of an Int32.
    private static func int32LEBytes(_ value: Int32) -> [UInt8] {
        let u = UInt32(bitPattern: value)
        return [
            UInt8(u & 0xFF),
            UInt8((u >> 8) & 0xFF),
            UInt8((u >> 16) & 0xFF),
            UInt8((u >> 24) & 0xFF),
        ]
    }

    // MARK: - Position

    /// Re-read the gimbal pose from the device and update currentPan/Tilt.
    func refreshPosition() async {
        guard isConnected else { return }
        switch activeTransport {
        case .usb:
            refreshUSBPosition()
        case .osc:
            requestOSCPosition()
        case .none:
            break
        }
    }

    /// Assemble a little-endian Int32 from bytes without shifting into the sign
    /// bit (a naive `Int32(b[o+3]) << 24` traps on values ≥ 0x80).
    private static func int32LE(_ b: [UInt8], _ o: Int) -> Int32 {
        let u = UInt32(b[o]) |
            (UInt32(b[o + 1]) << 8) |
            (UInt32(b[o + 2]) << 16) |
            (UInt32(b[o + 3]) << 24)
        return Int32(bitPattern: u)
    }

    private func refreshUSBPosition() {
        // UVC CT_PANTILT_ABSOLUTE GET_CUR: pan Int32 + tilt Int32, LE,
        // units 1/3600° (arcseconds). UVC sign convention: pan + = left,
        // tilt + = up.
        guard let bytes = usb.read(length: 8, selector: ObsbotV3Protocol.ctPanTiltAbsolute, unit: ObsbotV3Protocol.ctUnit),
              bytes.count == 8
        else {
            lastError = "Gimbal position read failed."
            NSLog("[ObsbotPTZ] position read failed (selector=0x%02X unit=0x%02X)", ObsbotV3Protocol.ctPanTiltAbsolute, ObsbotV3Protocol.ctUnit)
            GimbalLog.log("position read FAILED (selector=0x\(String(ObsbotV3Protocol.ctPanTiltAbsolute, radix: 16)) unit=0x\(String(ObsbotV3Protocol.ctUnit, radix: 16)))")
            return
        }
        let rawPan = Self.int32LE(bytes, 0)
        let rawTilt = Self.int32LE(bytes, 4)
        NSLog("[ObsbotPTZ] raw position arcsec pan=%d tilt=%d", rawPan, rawTilt)
        GimbalLog.log("raw position arcsec pan=\(rawPan) tilt=\(rawTilt) → user pan=\(Double(-rawPan) / 3600.0) tilt=\(Double(rawTilt) / 3600.0)")
        currentPan = Double(-rawPan) / 3600.0 // flip: user + = right
        currentTilt = Double(rawTilt) / 3600.0 // user + = up matches UVC
        lastError = nil
    }

    /// Read the device's pan/tilt travel limits (user frame) and store them.
    /// Falls back silently to the built-in defaults if unsupported.
    private func discoverUSBRanges() {
        // GET_MIN / GET_MAX on CT_PANTILT_ABSOLUTE (8 bytes each:
        // pan Int32 + tilt Int32, LE, units 1/3600° = arcseconds).
        let unit = ObsbotV3Protocol.ctUnit
        let selector = ObsbotV3Protocol.ctPanTiltAbsolute
        guard let minBytes = usb.read(length: 8, selector: selector, unit: unit, bRequest: 0x82),
              let maxBytes = usb.read(length: 8, selector: selector, unit: unit, bRequest: 0x83),
              minBytes.count == 8, maxBytes.count == 8
        else {
            NSLog("[ObsbotPTZ] range discovery GET_MIN/GET_MAX failed; using defaults pan [%.1f, %.1f] tilt [%.1f, %.1f]",
                  panRange.lowerBound, panRange.upperBound, tiltRange.lowerBound, tiltRange.upperBound)
            GimbalLog.log("range discovery GET_MIN/GET_MAX FAILED; using defaults pan [\(panRange.lowerBound), \(panRange.upperBound)] tilt [\(tiltRange.lowerBound), \(tiltRange.upperBound)]")
            return
        }

        let rawMinPan = Self.int32LE(minBytes, 0), rawMinTilt = Self.int32LE(minBytes, 4)
        let rawMaxPan = Self.int32LE(maxBytes, 0), rawMaxTilt = Self.int32LE(maxBytes, 4)
        NSLog("[ObsbotPTZ] raw range arcsec min(pan=%d,tilt=%d) max(pan=%d,tilt=%d)", rawMinPan, rawMinTilt, rawMaxPan, rawMaxTilt)

        // UVC frame: pan + = left. Convert to user frame (pan + = right) by
        // negating, which also swaps min/max. Tilt already shares + = up.
        let userMinPan = Double(-rawMaxPan) / 3600.0
        let userMaxPan = Double(-rawMinPan) / 3600.0
        let userMinTilt = Double(rawMinTilt) / 3600.0
        let userMaxTilt = Double(rawMaxTilt) / 3600.0

        if userMinPan < userMaxPan { panRange = userMinPan...userMaxPan }
        if userMinTilt < userMaxTilt { tiltRange = userMinTilt...userMaxTilt }

        NSLog("[ObsbotPTZ] user ranges pan [%.1f, %.1f] tilt [%.1f, %.1f]",
              panRange.lowerBound, panRange.upperBound, tiltRange.lowerBound, tiltRange.upperBound)
        GimbalLog.log("user ranges pan [\(panRange.lowerBound), \(panRange.upperBound)] tilt [\(tiltRange.lowerBound), \(tiltRange.upperBound)]")
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
