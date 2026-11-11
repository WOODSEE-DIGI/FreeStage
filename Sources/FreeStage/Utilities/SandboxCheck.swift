//
//  SandboxCheck.swift
//  FreeStage
//
//  Runtime check for App Sandbox. Used to gracefully disable features
//  (e.g., Syphon output) that cannot initialize inside a sandboxed process.
//

import Foundation

/// Returns true if the current process is running inside the App Sandbox.
/// The kernel sets APP_SANDBOX_CONTAINER_ID for every sandboxed process,
/// so this works for ad-hoc, development, and App Store signed builds.
func isAppSandboxed() -> Bool {
    ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
}
