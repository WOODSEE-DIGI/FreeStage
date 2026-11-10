//
//  GoStreamCodecTests.swift
//  FreeStageTests
//
//  Locks the GSP framing to the wire bytes verified live against the OSEE
//  GoStream Duet (fw 2.4.1) on 2026-10-13. If JSON key order or the CRC/length
//  offsets ever drift, these fail before anything reaches hardware.
//

import XCTest
@testable import FreeStage

final class GoStreamCodecTests: XCTestCase {

    /// Bare cut frame — the exact bytes the Duet accepted and acted on.
    func testPackBareCutMatchesHardware() {
        let packed = GoStreamCodec.pack(id: "cutTransition", type: "set")
        let expected = Data([
            0xeb, 0xa6, 0x00, 0x25, 0x00,
            0x7b, 0x22, 0x69, 0x64, 0x22, 0x3a, 0x22, 0x63, 0x75, 0x74,
            0x54, 0x72, 0x61, 0x6e, 0x73, 0x69, 0x74, 0x69, 0x6f, 0x6e,
            0x22, 0x2c, 0x22, 0x74, 0x79, 0x70, 0x65, 0x22, 0x3a, 0x22,
            0x73, 0x65, 0x74, 0x22, 0x7d,
            0xfc, 0xf3,
        ])
        XCTAssertEqual(packed, expected, "cutTransition frame drifted from hardware-verified bytes")
    }

    /// pgmIndex set frame with a value array.
    func testPackPgmSetMatchesHardware() {
        let packed = GoStreamCodec.pack(id: "pgmIndex", type: "set", value: [.int(2)])
        let expected = Data([
            0xeb, 0xa6, 0x00, 0x2c, 0x00,
            0x7b, 0x22, 0x69, 0x64, 0x22, 0x3a, 0x22, 0x70, 0x67, 0x6d,
            0x49, 0x6e, 0x64, 0x65, 0x78, 0x22, 0x2c, 0x22, 0x74, 0x79,
            0x70, 0x65, 0x22, 0x3a, 0x22, 0x73, 0x65, 0x74, 0x22, 0x2c,
            0x22, 0x76, 0x61, 0x6c, 0x75, 0x65, 0x22, 0x3a, 0x5b, 0x32,
            0x5d, 0x7d,
            0xc1, 0xc6,
        ])
        XCTAssertEqual(packed, expected, "pgmIndex set frame drifted from hardware-verified bytes")
    }

    /// A pushed tally frame must parse back out of the reassembler.
    func testReassemblerParsesPush() {
        let frame = Data([
            0xeb, 0xa6, 0x00, 0x2c, 0x00,
            0x7b, 0x22, 0x69, 0x64, 0x22, 0x3a, 0x22, 0x70, 0x67, 0x6d,
            0x54, 0x61, 0x6c, 0x6c, 0x79, 0x22, 0x2c, 0x22, 0x74, 0x79,
            0x70, 0x65, 0x22, 0x3a, 0x22, 0x70, 0x75, 0x73, 0x22, 0x2c,
            0x22, 0x76, 0x61, 0x6c, 0x75, 0x65, 0x22, 0x3a, 0x5b, 0x32,
            0x5d, 0x7d,
            0xc9, 0x4c,
        ])
        var reassembler = GoStreamFrameReassembler()
        let commands = reassembler.append(frame)
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands[0].id, "pgmTally")
        XCTAssertEqual(commands[0].type, "pus")
        XCTAssertEqual(commands[0].value, [.int(2)])
        XCTAssertTrue(commands[0].isStateUpdate)
    }

    /// Round-trip: pack a command, feed it to the reassembler, get it back.
    func testPackParseRoundTrip() {
        let packed = GoStreamCodec.pack(id: "deviceName", type: "set", value: [.string("hello")])
        var reassembler = GoStreamFrameReassembler()
        let parsed = reassembler.append(packed)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].id, "deviceName")
        XCTAssertEqual(parsed[0].value, [.string("hello")])
    }

    /// Bytes split across two receives must still reassemble.
    func testReassemblerHandlesFragmentedFrame() {
        let packed = GoStreamCodec.pack(id: "pvwIndex", type: "set", value: [.int(1)])
        var reassembler = GoStreamFrameReassembler()
        let first = reassembler.append(Data(packed.prefix(6)))
        XCTAssertTrue(first.isEmpty, "no command should emit from a partial frame")
        let second = reassembler.append(Data(packed.dropFirst(6)))
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second[0].id, "pvwIndex")
    }
}
