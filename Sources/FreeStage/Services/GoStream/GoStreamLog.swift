//
//  GoStreamLog.swift
//  FreeStage
//
//  Append-only file logger for GoStream/GSP diagnostics — same rationale as
//  GimbalLog: NSLog routing varies by launch method, a plain file does not.
//
//  Path: ~/Library/Logs/FreeStage/gostream.log
//

import Foundation

enum GoStreamLog {
    static let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/FreeStage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("gostream.log")
    }()

    private static let lock = NSLock()

    /// Append one timestamped line. Best-effort; never throws.
    /// Thread-safe (MainActor + NW queue callers).
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
            // Diagnostics only — swallow.
        }
    }
}
