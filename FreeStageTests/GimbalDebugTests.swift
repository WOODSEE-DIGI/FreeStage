//
//  GimbalDebugTests.swift
//  FreeStageTests
//
//  Placeholder test so `xcodebuild test` can launch FreeStage under the
//  Xcode debugger. The real debugging target is the unified-log stream, which
//  xcodebuild captures into the .xcresult bundle and prints to stdout — that
//  is how gimbal NSLog/os_log output becomes visible and copy-pasteable.
//

import XCTest

final class GimbalDebugTests: XCTestCase {
    func testAppLaunches() throws {
        // Launching the app under the debugger is the point; this assertion
        // just proves the process came up without crashing.
        XCTAssertTrue(true)
    }
}
