//
//  AppSettingsLibraryTests.swift
//  FreeStageTests
//
//  Tests for the library/recording-directory relationship in AppSettings.
//

import Foundation
import Testing
@testable import FreeStage

/// These tests touch `UserDefaults.standard` (the app's own domain), so every
/// test snapshots and restores the keys it writes.
@Suite(.serialized)
struct AppSettingsLibraryTests {

    private static let persistedKeys = [
        "libraryRootPath",
        "librarySetupCompleted",
        "recordingDirectoryPath"
    ]

    private func withCleanDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let saved = Self.persistedKeys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        for key in Self.persistedKeys {
            defaults.removeObject(forKey: key)
        }
        try body(defaults)
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreeStage-AppSettings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("changing the library root creates the template and adopts recordings")
    func changingRootCreatesTemplate() throws {
        try withCleanDefaults { _ in
            let root = try makeTemporaryRoot()
            defer { try? FileManager.default.removeItem(at: root) }

            let settings = AppSettings()
            settings.libraryRoot = root

            #expect(settings.libraryRoot.path == root.standardizedFileURL.path)
            #expect(settings.lastLibraryPreparation?.isComplete == true)
            #expect(ShowLibrary(root: root).isPrepared)
            #expect(!settings.hasCustomRecordingDirectory)
            #expect(settings.recordingDirectory.path == ShowLibrary(root: root).recordings.path)
        }
    }

    @Test("a recording override inside the old library follows the new root")
    func overrideInsideLibraryFollowsRoot() throws {
        try withCleanDefaults { _ in
            let first = try makeTemporaryRoot()
            let second = try makeTemporaryRoot()
            defer {
                try? FileManager.default.removeItem(at: first)
                try? FileManager.default.removeItem(at: second)
            }

            let settings = AppSettings()
            settings.libraryRoot = first

            let custom = first.appendingPathComponent("Output/Client A", isDirectory: true)
            settings.recordingDirectory = custom
            #expect(settings.hasCustomRecordingDirectory)
            #expect(settings.recordingDirectory.path == custom.standardizedFileURL.path)

            settings.libraryRoot = second

            #expect(!settings.hasCustomRecordingDirectory)
            #expect(settings.recordingDirectory.path == ShowLibrary(root: second).recordings.path)
        }
    }

    @Test("a recording override outside the library is preserved")
    func overrideOutsideLibraryIsKept() throws {
        try withCleanDefaults { _ in
            let library = try makeTemporaryRoot()
            let elsewhere = try makeTemporaryRoot()
            defer {
                try? FileManager.default.removeItem(at: library)
                try? FileManager.default.removeItem(at: elsewhere)
            }

            let settings = AppSettings()
            settings.libraryRoot = library
            settings.recordingDirectory = elsewhere

            let moved = try makeTemporaryRoot()
            defer { try? FileManager.default.removeItem(at: moved) }
            settings.libraryRoot = moved

            #expect(settings.hasCustomRecordingDirectory)
            #expect(settings.recordingDirectory.path == elsewhere.standardizedFileURL.path)

            settings.resetRecordingDirectory()
            #expect(settings.recordingDirectory.path == ShowLibrary(root: moved).recordings.path)
        }
    }

    @Test("the next recording URL lands in Output/Recordings and the folder exists")
    func nextRecordingURLCreatesFolder() throws {
        try withCleanDefaults { _ in
            let root = try makeTemporaryRoot()
            defer { try? FileManager.default.removeItem(at: root) }

            let settings = AppSettings()
            settings.libraryRoot = root

            let url = settings.nextRecordingURL()
            #expect(url.deletingLastPathComponent().path == ShowLibrary(root: root).recordings.path)
            #expect(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
            #expect(url.pathExtension == settings.recordingFormat.fileExtension)
        }
    }
}
