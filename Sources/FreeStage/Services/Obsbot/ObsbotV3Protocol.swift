//
//  ObsbotV3Protocol.swift
//  FreeStage
//
//  V3-framed command encoder for the OBSBOT Tiny 3 Lite vendor extension-unit
//  protocol. Byte-exact port of the official libdev SDK's traffic, captured
//  from the shipping macOS library and validated frame-by-frame (every header
//  and payload CRC verifies with crc16USB below).
//
//  Validated wire layout (60-byte UVC XU SET_CUR, selector 0x02, unit 0x02,
//  wValue 0x0200, wIndex 0x0200):
//    [0]    = 0xAA (magic)
//    [1]    = flags (0x25 = SET with payload, 0x01 = GET request)
//    [2..3] = sequence, LE (increments per frame; replies echo it)
//    [4..5] = 12 (header length, always)
//    [6..7] = CRC-16 of [0, 12) with these bytes zeroed
//    [8]    = 0x0A (host)
//    [9]    = receiver (0x03 = gimbal, 0x04 = AI)
//    [10..11] = command, LE
//    [12..13] = payload length, LE
//    [14..15] = CRC-16 of (plen field + zeroed CRC field + payload)
//    [16..] = payload, zero-padded to 60 bytes
//
//  Wire conventions: pitch + = DOWN, pan + = LEFT (same-sign verified:
//  a negative pitch speed decreases the pitch reading). FreeStage's UI uses
//  pan + = right, tilt + = up; conversion happens in ObsbotPTZController.
//
//  There is NO absolute-angle command on the Tiny 3 Lite (the vendor library
//  itself refuses it for this model), so absolute framing is closed-loop:
//  read the motor encoders, pulse proportional speeds, re-read until arrival.
//

import Foundation

enum ObsbotV3Protocol {
    static let payloadSize = 60
    static let magic: UInt8 = 0xAA
    /// SET-with-payload flag (seen on speed, AI-enable frames).
    static let flagsSet: UInt8 = 0x25
    /// GET-request flag (seen on attitude-request frames).
    static let flagsGet: UInt8 = 0x01
    static let senderHost: UInt8 = 0x0A

    // MARK: - Receivers

    /// Gimbal subsystem (move + attitude read).
    static let receiverGimbal: UInt8 = 0x03
    /// AI subsystem (tracking enable).
    static let receiverAI: UInt8 = 0x04
    static let receiverSystem: UInt8 = 0x02

    // MARK: - Wire commands (Tiny 3 Lite, sniffed)

    /// Speed control. Payload: roll/pitch/pan speeds, int16 LE, degrees×100.
    static let cmdGimbalSpeed: UInt16 = 0x0103
    /// AI tracking enable. Payload: 1 byte (0 = off, 1 = on).
    static let cmdAiEnable: UInt16 = 0x0244
    /// Attitude (encoder) read. Empty payload. Reply echoes cmd 0x0043 with a
    /// 32-byte payload; roll/pitch/pan are int16 LE degrees×100 at [22,24,26].
    static let cmdAttitudeGet: UInt16 = 0x0043

    /// Session-open queries, sent (in order) right after USB connect, exactly
    /// as the official library does. Receiver 0x0d, flags 0x01, empty payload,
    /// explicit sequences 0/1/2. Replies are drained with a 60-byte GET.
    /// (A 4th query + a device-filesystem touch exist in the official flow;
    /// omitted: the 4th carries device-specific UUID bytes and the touch writes
    /// a file on the camera. Added only if motion still fails without them.)
    static let receiverSession: UInt8 = 0x0D
    static let cmdSession1: UInt16 = 0x1808
    static let cmdSession2: UInt16 = 0x0408
    static let cmdSession3: UInt16 = 0x1948
    static let cmdSessionBind: UInt16 = 0x18C8

    /// Wake/sleep (unproven on this model; harmless to send).
    static let cmdWakeSleep: UInt16 = 0xA0C2

    // MARK: - UVC selectors/units

    /// Vendor extension unit carrying the framed V3 command channel.
    static let selectorXU: UInt16 = 0x02
    static let xuUnit: UInt8 = 0x02
    /// Raw status/control selector (seen on event-poll traffic).
    static let selectorStatus: UInt16 = 0x06

    // MARK: - Known product IDs

    static let vendorID: UInt16 = 0x3564
    static let knownProductIDs: [UInt16] = [
        0xFEF8, // Tiny 2
        0xFEF9, // Tiny 2 Lite
        0xFF02, // Tiny 3
        0xFF04, // Tiny 3 Lite
        0xFEFB, // Meet 2 (present in the lab; same XU family)
    ]

    // MARK: - CRC-16/USB (init/xor 0xFFFF, poly 0xA001 — verified)

    private static let crcPoly: UInt16 = 0xA001

    static func crc16USB(_ data: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ crcPoly
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFF
    }

    // MARK: - Frame builders

    /// Build a framed V3 command. Header length is always 12.
    static func buildFrame(cmd: UInt16, receiver: UInt8, flags: UInt8, payload: [UInt8], sequence: UInt16) -> [UInt8] {
        var frame = [UInt8](repeating: 0, count: payloadSize)
        frame[0] = magic
        frame[1] = flags
        frame[2] = UInt8(sequence & 0xFF)
        frame[3] = UInt8((sequence >> 8) & 0xFF)
        frame[4] = 12
        frame[5] = 0

        frame[8] = senderHost
        frame[9] = receiver
        frame[10] = UInt8(cmd & 0xFF)
        frame[11] = UInt8((cmd >> 8) & 0xFF)

        if !payload.isEmpty {
            let payloadLen = UInt16(payload.count)
            frame[12] = UInt8(payloadLen & 0xFF)
            frame[13] = UInt8((payloadLen >> 8) & 0xFF)

            // Payload CRC covers [12..16+plen): the plen field itself, the
            // zeroed CRC field, then the payload (libdev _calc_crc16 call at
            // frmHeaderProcessForReceiveV3; verified against sniffed frames).
            var payloadSegment = [UInt8](repeating: 0, count: 4 + payload.count)
            payloadSegment[0] = UInt8(payloadLen & 0xFF)
            payloadSegment[1] = UInt8((payloadLen >> 8) & 0xFF)
            for i in 0..<payload.count {
                payloadSegment[4 + i] = payload[i]
            }
            let payloadCRC = crc16USB(payloadSegment)
            frame[14] = UInt8(payloadCRC & 0xFF)
            frame[15] = UInt8((payloadCRC >> 8) & 0xFF)

            for i in 0..<payload.count {
                frame[16 + i] = payload[i]
            }
        }

        var headerForCRC = Array(frame[0..<12])
        headerForCRC[6] = 0
        headerForCRC[7] = 0
        let headerCRC = crc16USB(headerForCRC)
        frame[6] = UInt8(headerCRC & 0xFF)
        frame[7] = UInt8((headerCRC >> 8) & 0xFF)

        return frame
    }

    // MARK: - Gimbal commands (wire frame; degrees, same-sign verified)

    /// Speed control. Speeds in degrees/second, wire frame
    /// (pitch + = down, pan + = left). Send zeros to stop.
    static func speedCommand(roll: Double, pitch: Double, pan: Double, sequence: UInt16) -> [UInt8] {
        var payload = [UInt8]()
        payload.append(contentsOf: int16LEBytes(Int16((roll * 100).rounded())))
        payload.append(contentsOf: int16LEBytes(Int16((pitch * 100).rounded())))
        payload.append(contentsOf: int16LEBytes(Int16((pan * 100).rounded())))
        return buildFrame(cmd: cmdGimbalSpeed, receiver: receiverGimbal, flags: flagsSet, payload: payload, sequence: sequence)
    }

    /// AI tracking on/off (payload [1]/[0]).
    static func aiEnableCommand(_ enabled: Bool, sequence: UInt16) -> [UInt8] {
        buildFrame(cmd: cmdAiEnable, receiver: receiverAI, flags: flagsSet, payload: [enabled ? 1 : 0], sequence: sequence)
    }

    /// Attitude-request frame (empty payload). The reply is parsed by
    /// parseAttitudeReply.
    static func attitudeGetCommand(sequence: UInt16) -> [UInt8] {
        buildFrame(cmd: cmdAttitudeGet, receiver: receiverGimbal, flags: flagsGet, payload: [], sequence: sequence)
    }

    /// Parse a 60-byte attitude reply into wire-frame degrees
    /// (roll, pitch, pan). Returns nil unless the frame validates
    /// (magic, echoed command, both CRCs).
    static func parseAttitudeReply(_ bytes: [UInt8]) -> (roll: Double, pitch: Double, pan: Double)? {
        guard bytes.count >= 28,
              bytes[0] == magic,
              bytes[10] == UInt8(cmdAttitudeGet & 0xFF),
              bytes[11] == UInt8((cmdAttitudeGet >> 8) & 0xFF)
        else { return nil }

        var header = Array(bytes[0..<12])
        let wantHeaderCRC = UInt16(header[6]) | (UInt16(header[7]) << 8)
        header[6] = 0
        header[7] = 0
        guard crc16USB(header) == wantHeaderCRC else { return nil }

        let payloadLen = Int(UInt16(bytes[12]) | (UInt16(bytes[13]) << 8))
        guard payloadLen >= 12, bytes.count >= 16 + payloadLen else { return nil }
        var segment = [UInt8](bytes[12..<16])
        segment[2] = 0
        segment[3] = 0
        segment.append(contentsOf: bytes[16..<(16 + payloadLen)])
        let wantPayloadCRC = UInt16(bytes[14]) | (UInt16(bytes[15]) << 8)
        guard crc16USB(segment) == wantPayloadCRC else { return nil }

        // Motor encoders: int16 LE, degrees × 100.
        let roll = Double(int16LE(bytes, 22)) / 100.0
        let pitch = Double(int16LE(bytes, 24)) / 100.0
        let pan = Double(int16LE(bytes, 26)) / 100.0
        return (roll: roll, pitch: pitch, pan: pan)
    }

    /// Session-bind frame (4th session query, sniffed byte-exact). Unlike the
    /// other frames it carries inline data instead of a plen/CRC payload:
    /// the LAST 4 BYTES OF THE DEVICE UUID at [12..15] plus 01 00 at [16..17].
    /// Hypothesis: binds the session so the firmware accepts state-changing
    /// writes (reads answer without it; speeds/AI-off may not).
    /// Default UUID tail = sniffed bytes of RMOWUHI1283QVS (9E57…929DC9BE).
    static func sessionBindFrame(uuidLast4: [UInt8] = [0x92, 0x9D, 0xC9, 0xBE], sequence: UInt16) -> [UInt8] {
        precondition(uuidLast4.count == 4)
        var frame = [UInt8](repeating: 0, count: payloadSize)
        frame[0] = magic
        frame[1] = flagsGet
        frame[2] = UInt8(sequence & 0xFF)
        frame[3] = UInt8((sequence >> 8) & 0xFF)
        frame[4] = 12
        frame[5] = 0
        frame[8] = senderHost
        frame[9] = receiverSession
        frame[10] = UInt8(cmdSessionBind & 0xFF)
        frame[11] = UInt8((cmdSessionBind >> 8) & 0xFF)
        frame[12] = uuidLast4[0]
        frame[13] = uuidLast4[1]
        frame[14] = uuidLast4[2]
        frame[15] = uuidLast4[3]
        frame[16] = 0x01
        frame[17] = 0x00
        var header = Array(frame[0..<12])
        header[6] = 0
        header[7] = 0
        let headerCRC = crc16USB(header)
        frame[6] = UInt8(headerCRC & 0xFF)
        frame[7] = UInt8((headerCRC >> 8) & 0xFF)
        return frame
    }

    /// Wake the gimbal out of idle/stowed sleep (payload 0x00).
    static func wakeCommand(sequence: UInt16) -> [UInt8] {
        buildFrame(cmd: cmdWakeSleep, receiver: receiverSystem, flags: flagsSet, payload: [0x00], sequence: sequence)
    }

    // MARK: - Helpers

    static func int16LEBytes(_ value: Int16) -> [UInt8] {
        let u = UInt16(bitPattern: value)
        return [UInt8(u & 0xFF), UInt8((u >> 8) & 0xFF)]
    }

    /// Assemble a little-endian Int16 without shifting into the sign bit.
    static func int16LE(_ b: [UInt8], _ o: Int) -> Int16 {
        let u = UInt16(b[o]) | (UInt16(b[o + 1]) << 8)
        return Int16(bitPattern: u)
    }
}
