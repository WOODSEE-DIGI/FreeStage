//
//  ShowLibraryTests.swift
//  FreeStageTests
//
//  Tests for the show-library folder template.
//

import Foundation
import Testing
@testable import FreeStage

struct ShowLibraryTests {

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreeStage-ShowLibrary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeRoot(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    @Test("prepare creates every template folder plus the readmes")
    func createsTemplate() throws {
        let root = try makeTemporaryRoot()
        defer { removeRoot(root) }

        let library = ShowLibrary(root: root)
        let result = library.prepare()

        #expect(result.isComplete)
        #expect(result.createdDirectories.count == ShowLibrary.templateFolders.count)
        #expect(!result.writtenReadmes.isEmpty)
        #expect(library.isPrepared)

        let fileManager = FileManager.default
        for folder in ShowLibrary.templateFolders {
            var isDirectory: ObjCBool = false
            let path = folder.url(under: root).path
            #expect(fileManager.fileExists(atPath: path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
            #expect(fileManager.fileExists(atPath: folder.url(under: root)
                .appendingPathComponent(ShowLibrary.Folder.folderReadme).path))
        }

        #expect(fileManager.fileExists(atPath: root
            .appendingPathComponent(ShowLibrary.Folder.rootReadme).path))
    }

    @Test("recordings and shows live where the template says they do")
    func canonicalLocations() throws {
        let root = try makeTemporaryRoot()
        defer { removeRoot(root) }

        let library = ShowLibrary(root: root)
        library.prepare()

        #expect(library.recordings.path.hasPrefix(root.path))
        #expect(library.recordings.path.hasSuffix("Output/Recordings"))
        #expect(library.shows.path.hasSuffix("Shows"))
        #expect(library.assetFolder(.luts).path.hasSuffix("GlobalAssets/LUTs"))
        #expect(library.assetFolder(.soundEffects).path.hasSuffix("GlobalAssets/Sound Effects"))

        for folder in AssetFolder.allCases {
            #expect(library.assetFolder(folder).path.hasPrefix(library.globalAssets.path))
        }
    }

    @Test("prepare is idempotent and leaves user files alone")
    func idempotentAndNonDestructive() throws {
        let root = try makeTemporaryRoot()
        defer { removeRoot(root) }

        let library = ShowLibrary(root: root)
        library.prepare()

        // Simulate a user dropping assets in and editing a readme.
        let luts = library.assetFolder(.luts)
        let asset = luts.appendingPathComponent("teal-orange.cube")
        try "LUT DATA".write(to: asset, atomically: true, encoding: .utf8)

        let readme = luts.appendingPathComponent(ShowLibrary.Folder.folderReadme)
        try "# My own notes\n".write(to: readme, atomically: true, encoding: .utf8)

        let second = library.prepare()

        #expect(second.isComplete)
        #expect(second.createdDirectories.isEmpty)
        #expect(second.writtenReadmes.isEmpty)
        #expect(second.existingDirectories.count == ShowLibrary.templateFolders.count)
        #expect(try String(contentsOf: readme, encoding: .utf8) == "# My own notes\n")
        #expect(FileManager.default.fileExists(atPath: asset.path))
    }

    @Test("removed folders are recreated on the next prepare")
    func repairsMissingFolders() throws {
        let root = try makeTemporaryRoot()
        defer { removeRoot(root) }

        let library = ShowLibrary(root: root)
        library.prepare()

        let memes = library.assetFolder(.memes)
        try FileManager.default.removeItem(at: memes)
        #expect(!library.isPrepared)

        let result = library.prepare()

        #expect(result.isComplete)
        #expect(library.isPrepared)
        #expect(result.createdDirectories.contains(memes))
    }

    @Test("a file squatting on a folder name is reported, not deleted")
    func reportsBlockingFile() throws {
        let root = try makeTemporaryRoot()
        defer { removeRoot(root) }

        let library = ShowLibrary(root: root)
        let squatter = root.appendingPathComponent(ShowLibrary.Folder.shows, isDirectory: false)
        try "not a folder".write(to: squatter, atomically: true, encoding: .utf8)

        let result = library.prepare()

        #expect(!result.isComplete)
        #expect(result.failures.contains { $0.path == squatter.path })
        #expect(try String(contentsOf: squatter, encoding: .utf8) == "not a folder")
    }

    @Test("default root is the FreeStage folder in Movies")
    func defaultRootIsInMovies() {
        let root = ShowLibrary.defaultRoot()
        #expect(root.lastPathComponent == "FreeStage")
        #expect(root.path.contains("Movies"))
    }
}
