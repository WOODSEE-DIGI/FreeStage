//
//  GimbalLog.swift
//  FreeStage
//
//  Append-only file logger for gimbal/PTZ diagnostics.
//
//  Why this exists: NSLog/os_log output is unreliable to surface. Depending on
//  how the app is launched (detached `open`, xcodebuild test, lldb), the
//  unified-log routing and debugger piping vary, and the signal drowns in
//  system noise (linkd, NDI, VFX). Writing to a plain file guarantees the
//  operator can open and copy the diagnostic trail regardless of launch method.
//
//  Path: ~/Library/Logs/FreeStage/gimbal.log
//

import Foundation

enum GimbalLog {
    static let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/FreeStage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("gimbal.log")
    }()

    private static let lock = NSLock()

    /// Append one timestamped line. Best-effort; never throws, never crashes
    /// the gimbal path. Thread-safe (called from MainActor and USB queues).
    static func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        lock.lock()
        defer { lock.unlock() }

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Diagnostics only — swallow so a full disk or permissions issue
            // can never take down gimbal control.
        }
    }
}
