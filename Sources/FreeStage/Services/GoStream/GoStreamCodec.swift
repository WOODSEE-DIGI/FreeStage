//
//  GoStreamCodec.swift
//  FreeStage
//
//  GSP (GoStream Protocol) framing for the OSEE GoStream Duet switcher.
//
//  Wire format, verified live against fw 2.4.1 (2026-10-13):
//    [0]=0xEB [1]=0xA6 [2]=protoid(0x00) [3..4]=UInt16LE(json.count + 2)
//    [5..]=compact JSON {"id":<cmd>,"type":<get|set>} [, "value":[...]]
//    [last 2]=UInt16LE CRC16-Modbus over every byte before the CRC.
//
//  Message types seen on the wire:
//    "get"  = request (and, on fw ≤2.2.0, also the reply to a get)
//    "set"  = request to change state
//    "res"  = reply to a get (fw 2.4.1)
//    "pus"  = unsolicited push, broadcast by the device on any state change
//    "err"  = {"id":"parse_error","value":["PARSE_ERROR_NOT_FOND_ID", ...]}
//
//  Cut/auto/FTB are bare sets with no value key. PGM/PVW sets carry the
//  source id: {"id":"pgmIndex","type":"set","value":[2]}.
//

import Foundation

/// A single decoded element of a command's `value` array.
/// The device sends ints, doubles (rates/positions) and strings (names, styles).
enum GoStreamValue: Sendable, Equatable {
    case int(Int)
    case double(Double)
    case string(String)

    var intValue: Int? {
        switch self {
        case .int(let v): return v
        case .double(let v): return Int(v)
        case .string: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .int(let v): return Double(v)
        case .double(let v): return v
        case .string: return nil
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let v): return v
        default: return nil
        }
    }

    /// Bridge from JSONSerialization output.
    init?(jsonValue: Any) {
        if let s = jsonValue as? String {
            self = .string(s)
        } else if let n = jsonValue as? NSNumber {
            // JSON booleans arrive as NSNumber; the device only ever sends
            // numeric 0/1 for booleans, so an integral value stays an int.
            let d = n.doubleValue
            if d.rounded() == d, abs(d) < 1e15 {
                self = .int(n.intValue)
            } else {
                self = .double(d)
            }
        } else {
            return nil
        }
    }

    var jsonValue: Any {
        switch self {
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        }
    }
}

/// One decoded GSP frame.
struct GoStreamCommand: Sendable, Equatable {
    let id: String
    let type: String
    let value: [GoStreamValue]

    init(id: String, type: String, value: [GoStreamValue] = []) {
        self.id = id
        self.type = type
        self.value = value
    }

    /// True for state updates — either a direct reply ("res"/"get") or a
    /// push ("pus"). Both update our mirrored state identically.
    var isStateUpdate: Bool {
        type == "res" || type == "get" || type == "pus"
    }

    var isError: Bool { type == "err" }
}

enum GoStreamCodec {

    // MARK: - CRC16-Modbus

    /// CRC16-Modbus: poly 0xA001 (reflected 0x8005), init 0xFFFF, no final xor.
    static func crc16Modbus<C: Collection>(_ bytes: C) -> UInt16 where C.Element == UInt8 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xA001
                } else {
                    crc >>= 1
                }
            }
        }
        return crc
    }

    // MARK: - Packing

    /// Pack a command into a wire frame. `value == nil` omits the key entirely
    /// (bare sets: cutTransition / autoTransition / ftb).
    static func pack(id: String, type: String, value: [GoStreamValue]? = nil) -> Data {
        // Build JSON by hand with deterministic key order id, type, value.
        // JSONSerialization does not guarantee key order, and the hardware was
        // verified against exactly this layout — never rely on dictionary order.
        var json = "{\"id\":\"\(id)\",\"type\":\"\(type)\""
        if let value, !value.isEmpty {
            let elems = value.map { element -> String in
                switch element {
                case .int(let v): return String(v)
                case .double(let v): return String(v)
                case .string(let s): return "\"\(s)\""
                }
            }.joined(separator: ",")
            json += ",\"value\":[\(elems)]"
        }
        json += "}"
        guard let payload = json.data(using: .utf8) else {
            return Data()
        }
        return frame(payload: payload)
    }

    private static func frame(payload: Data) -> Data {
        var out = Data(capacity: payload.count + 7)
        out.append(0xEB)
        out.append(0xA6)
        out.append(0x00)
        var length = UInt16(payload.count + 2).littleEndian
        withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
        out.append(payload)
        var crc = crc16Modbus(out).littleEndian
        withUnsafeBytes(of: &crc) { out.append(contentsOf: $0) }
        return out
    }

    // MARK: - Parsing

    /// Parse one complete frame body (the JSON bytes, CRC already stripped).
    /// Returns nil for non-JSON or structurally invalid bodies.
    static func parseCommand(payload: Data) -> GoStreamCommand? {
        guard let obj = try? JSONSerialization.jsonObject(with: payload),
              let dict = obj as? [String: Any],
              let id = dict["id"] as? String,
              let type = dict["type"] as? String
        else {
            return nil
        }
        var values: [GoStreamValue] = []
        if let raw = dict["value"] as? [Any] {
            for element in raw {
                if let v = GoStreamValue(jsonValue: element) {
                    values.append(v)
                }
            }
        }
        return GoStreamCommand(id: id, type: type, value: values)
    }
}

/// Incremental frame reassembler for a TCP byte stream.
///
/// GSP has no outer length framing beyond its own header, so a receive chunk
/// may contain a partial frame, several frames, or both. Feed every chunk in;
/// complete frames come out.
struct GoStreamFrameReassembler {
    private var buffer = Data()

    static let maxFrameBytes = 64 * 1024

    /// Append received bytes and return every complete command now available.
    /// Frames that fail CRC or JSON decode are dropped (and counted) so one
    /// corrupt frame can never wedge the stream.
    mutating func append(_ data: Data) -> [GoStreamCommand] {
        buffer.append(data)
        var commands: [GoStreamCommand] = []

        while buffer.count >= 5 {
            // Hunt for the EB A6 sync — discards any leading garbage.
            guard let headerIndex = buffer.firstIndex(of: 0xEB) else {
                buffer.removeAll(keepingCapacity: true)
                break
            }
            if headerIndex > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<headerIndex)
            }
            guard buffer.count >= 5 else { break }
            guard buffer[buffer.startIndex + 1] == 0xA6 else {
                buffer.removeFirst()
                continue
            }

            let length = readUInt16LE(buffer, atOffset: 3)
            let total = 5 + Int(length)
            guard total <= Self.maxFrameBytes else {
                // Implausible length — resync from the next byte.
                buffer.removeFirst()
                continue
            }
            guard buffer.count >= total else { break } // wait for more data

            let frame = Data(buffer[buffer.startIndex..<(buffer.startIndex + total)])
            buffer.removeFirst(total)

            guard length >= 2 else { continue } // payload + crc at minimum
            let bodyStart = frame.startIndex + 5
            let bodyEnd = frame.startIndex + total - 2
            let payload = Data(frame[bodyStart..<bodyEnd])

            let expectedCRC = readUInt16LE(frame, atOffset: total - 2)
            guard expectedCRC == GoStreamCodec.crc16Modbus(frame[frame.startIndex..<(frame.startIndex + total - 2)]) else {
                GoStreamLog.log("GoStreamCodec: CRC mismatch, dropping frame (len=\(total))")
                continue
            }
            if let command = GoStreamCodec.parseCommand(payload: payload) {
                commands.append(command)
            } else {
                GoStreamLog.log("GoStreamCodec: undecodable payload dropped (\(payload.count)B)")
            }
        }
        return commands
    }

    /// Read a little-endian UInt16 at a byte offset from the buffer start.
    /// `loadUnaligned` is unavailable on the macOS 14 target, so decode by hand.
    private func readUInt16LE(_ data: Data, atOffset offset: Int) -> UInt16 {
        let base = data.startIndex + offset
        guard base + 1 < data.endIndex else { return 0 }
        let lo = UInt16(data[base])
        let hi = UInt16(data[base + 1])
        return lo | (hi << 8)
    }
}
