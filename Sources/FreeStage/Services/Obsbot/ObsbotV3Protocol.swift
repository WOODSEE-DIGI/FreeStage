//
//  ObsbotV3Protocol.swift
//  FreeStage
//
//  V3-framed command encoder for the OBSBOT Tiny 2/3 vendor extension-unit
//  protocol. Ported from SwiftMaestro's Tethering/Obsbot implementation,
//  trimmed to the gimbal commands FreeStage needs.
//
//  Wire conventions (vendor protocol):
//    - pitch positive = gimbal tilts DOWN
//    - yaw positive   = gimbal pans to the CAMERA'S LEFT
//  FreeStage's UI uses the intuitive inverse (pan + = right, tilt + = up);
//  conversion happens in ObsbotPTZController.
//

import Foundation

enum ObsbotV3Protocol {
    static let payloadSize = 60
    static let magic: UInt8 = 0xAA
    static let flagsSet: UInt8 = 0x25 // SET with nested payload
    static let senderHost: UInt8 = 0x0A

    // MARK: - Wire commands

    static let cmdRecenter: UInt16 = 0x00C3
    static let cmdGimbalSpeed: UInt16 = 0x6484
    static let cmdGimbalMoveToAngle: UInt16 = 0x6444
    /// Wake/sleep share wire command 0xA0C2; payload 0x00 = wake, 0x01 = sleep.
    /// The Tiny auto-stows after idle, and while asleep it accepts pan/tilt
    /// writes silently but moves nothing — a wake is required first.
    static let cmdWakeSleep: UInt16 = 0xA0C2

    static let receiverSystem: UInt8 = 0x02
    static let receiverDevice: UInt8 = 0x03
    static let receiverGimbal: UInt8 = 0x04

    // MARK: - UVC selectors/units

    /// Vendor extension unit carrying the framed V3 command channel.
    static let selectorXU: UInt16 = 0x02
    static let xuUnit: UInt8 = 0x02
    /// Raw status/control writes.
    static let selectorStatus: UInt16 = 0x06

    /// Standard UVC camera-terminal controls.
    static let ctPanTiltAbsolute: UInt16 = 0x0D
    static let ctPanTiltRelative: UInt16 = 0x0E
    static let ctZoomAbsolute: UInt16 = 0x0B
    static let ctUnit: UInt8 = 0x01

    // MARK: - Known product IDs

    static let vendorID: UInt16 = 0x3564
    static let knownProductIDs: [UInt16] = [
        0xFEF8, // Tiny 2
        0xFEF9, // Tiny 2 Lite
        0xFF02, // Tiny 3
        0xFF04, // Tiny 3 Lite
    ]

    // MARK: - CRC-16/USB

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

    /// Build a framed V3 SET command with a nested payload.
    static func buildSetFrame(cmd: UInt16, receiver: UInt8, payload: [UInt8], sequence: UInt16) -> [UInt8] {
        var frame = [UInt8](repeating: 0, count: payloadSize)
        frame[0] = magic
        frame[1] = flagsSet
        frame[2] = UInt8(sequence & 0xFF)
        frame[3] = UInt8((sequence >> 8) & 0xFF)

        let headerLen: UInt16 = payload.isEmpty ? 12 : UInt16(16 + payload.count)
        frame[4] = UInt8(headerLen & 0xFF)
        frame[5] = UInt8((headerLen >> 8) & 0xFF)

        frame[8] = senderHost
        frame[9] = receiver
        frame[10] = UInt8(cmd & 0xFF)
        frame[11] = UInt8((cmd >> 8) & 0xFF)

        if !payload.isEmpty {
            let payloadLen = UInt16(payload.count)
            frame[12] = UInt8(payloadLen & 0xFF)
            frame[13] = UInt8((payloadLen >> 8) & 0xFF)

            var payloadSegment = [UInt8](repeating: 0, count: 4 + payload.count)
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

        var headerForCRC = Array(frame[0..<Int(headerLen)])
        headerForCRC[6] = 0
        headerForCRC[7] = 0
        let headerCRC = crc16USB(headerForCRC)
        frame[6] = UInt8(headerCRC & 0xFF)
        frame[7] = UInt8((headerCRC >> 8) & 0xFF)

        return frame
    }

    // MARK: - Gimbal commands

    /// Absolute gimbal move. Arguments are WIRE angles (pitch+ = down, yaw+ = left).
    static func gimbalMoveToAngle(roll: Float, pitch: Float, yaw: Float, sequence: UInt16) -> [UInt8] {
        var payload = [UInt8]()
        payload.append(contentsOf: float32Bytes(roll))
        payload.append(contentsOf: float32Bytes(pitch))
        payload.append(contentsOf: float32Bytes(yaw))
        return buildSetFrame(cmd: cmdGimbalMoveToAngle, receiver: receiverGimbal, payload: payload, sequence: sequence)
    }

    /// Gimbal recenter.
    static func recenterCommand(sequence: UInt16) -> [UInt8] {
        buildSetFrame(
            cmd: cmdRecenter,
            receiver: receiverDevice,
            payload: [UInt8](repeating: 0, count: 6),
            sequence: sequence
        )
    }

    /// Wake the gimbal out of idle/stowed sleep (payload 0x00).
    static func wakeCommand(sequence: UInt16) -> [UInt8] {
        buildSetFrame(cmd: cmdWakeSleep, receiver: receiverSystem, payload: [0x00], sequence: sequence)
    }

    // MARK: - Helpers

    static func float32Bytes(_ value: Float) -> [UInt8] {
        var v = value
        var bytes = [UInt8](repeating: 0, count: 4)
        memcpy(&bytes, &v, 4)
        return bytes
    }
}
