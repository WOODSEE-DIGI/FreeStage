//
//  OscCodec.swift
//  FreeStage
//
//  Minimal OSC 1.0 encoder/decoder for talking to OBSBOT Center
//  (default UDP port 16284). Ported from SMArchyOS, trimmed to the
//  argument types and reply parsing FreeStage needs.
//

import Foundation

enum OSCArgument: Equatable, Sendable {
    case int32(Int32)
    case float32(Float)
    case string(String)

    var typeTag: Character {
        switch self {
        case .int32: return "i"
        case .float32: return "f"
        case .string: return "s"
        }
    }
}

struct OSCMessage: Equatable, Sendable {
    let address: String
    let arguments: [OSCArgument]

    /// Encode to a UDP packet (address, ",typetags", then arguments, all 4-byte aligned).
    var encoded: Data {
        var data = Self.oscStringBytes(address)
        var typeTag = ","
        for arg in arguments { typeTag.append(arg.typeTag) }
        data.append(Self.oscStringBytes(typeTag))
        for arg in arguments {
            switch arg {
            case .int32(let value):
                var be = value.bigEndian
                withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
            case .float32(let value):
                var be = value.bitPattern.bigEndian
                withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
            case .string(let value):
                data.append(Self.oscStringBytes(value))
            }
        }
        return data
    }

    /// Decode a received UDP packet. Returns nil for bundles or malformed data.
    static func decode(_ data: Data) -> OSCMessage? {
        var offset = 0
        guard let address = readString(data, offset: &offset), address.hasPrefix("/") else { return nil }
        guard let typeTag = readString(data, offset: &offset), typeTag.hasPrefix(",") else { return nil }

        var arguments: [OSCArgument] = []
        for tag in typeTag.dropFirst() {
            switch tag {
            case "i":
                guard let value = readInt32(data, offset: &offset) else { return nil }
                arguments.append(.int32(value))
            case "f":
                guard let value = readFloat32(data, offset: &offset) else { return nil }
                arguments.append(.float32(value))
            case "s":
                guard let value = readString(data, offset: &offset) else { return nil }
                arguments.append(.string(value))
            case "T", "F", "N":
                continue // no-op type tags carry no payload
            default:
                return nil // unsupported tag; bail rather than misalign
            }
        }
        return OSCMessage(address: address, arguments: arguments)
    }

    // MARK: - Private decoding helpers

    private static func readString(_ data: Data, offset: inout Int) -> String? {
        let bytes = [UInt8](data)
        guard offset < bytes.count else { return nil }
        var end = offset
        while end < bytes.count, bytes[end] != 0 { end += 1 }
        guard end < bytes.count else { return nil }
        let string = String(decoding: bytes[offset..<end], as: UTF8.self)
        // Advance past the string plus NUL and pad to the next 4-byte boundary.
        offset = end + 1
        offset += (4 - (offset % 4)) % 4
        return string
    }

    private static func readInt32(_ data: Data, offset: inout Int) -> Int32? {
        guard offset + 4 <= data.count else { return nil }
        let value = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes {
            $0.load(as: Int32.self).bigEndian
        }
        offset += 4
        return value
    }

    private static func readFloat32(_ data: Data, offset: inout Int) -> Float? {
        guard offset + 4 <= data.count else { return nil }
        let bits = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }
        offset += 4
        return Float(bitPattern: bits)
    }

    /// Pack a NUL-terminated string padded to a 4-byte boundary.
    private static func oscStringBytes(_ string: String) -> Data {
        var data = Data(string.utf8)
        data.append(0)
        let pad = (4 - (data.count % 4)) % 4
        data.append(contentsOf: [UInt8](repeating: 0, count: pad))
        return data
    }
}
