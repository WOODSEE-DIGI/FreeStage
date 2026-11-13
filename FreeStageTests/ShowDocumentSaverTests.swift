//
//  ShowDocumentSaverTests.swift
//  FreeStageTests
//
//  Tests for show saving: dirty-state tracking used by Cmd-S and autosave,
//  plus package writer idempotence (autosave must not create duplicate assets)
//  and coverage of per-cue layer assets.
//

import Foundation
import Testing
@testable import FreeStage

@MainActor
struct ShowDocumentSaverTests {

    // MARK: - Fixtures

    private func makeTemporaryDirectory(_ label: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreeStage-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeAsset(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        return url
    }

    private func makePresenterShow(assetURL: URL, globalImageURL: URL? = nil) -> Show {
        let cueLayer = Layer(name: "Screen Share Image", source: .image(url: assetURL))
        let segment = PresenterSegment(
            name: "Screen Share Cue",
            type: .cameraGraphic,
            cameraAngle: .primary,
            layers: [cueLayer]
        )
        let rundown = PresenterRundown(segments: [segment])
        var globalLayers: [Layer] = []
        if let globalImageURL {
            globalLayers.append(Layer(name: "Bug", source: .image(url: globalImageURL)))
        }
        return Show(name: "Save Test", kind: .presenter, presenterRundown: rundown, globalLayers: globalLayers)
    }

    private func assetNames(in packageURL: URL) throws -> [String] {
        let assetsURL = packageURL.appendingPathComponent(ShowPackage.assetsFolderName)
        return try FileManager.default.contentsOfDirectory(atPath: assetsURL.path).sorted()
    }

    // MARK: - Content hash

    @Test("contentHash ignores workspace selection changes")
    func contentHashIgnoresWorkspace() {
        var show = Show(name: "Hash")
        let firstHash = show.contentHash

        show.workspace.activeCueID = UUID()
        show.workspace.isEditMode = false
        show.workspace.panicDuration = 4.5

        #expect(show.contentHash == firstHash)
    }

    @Test("contentHash changes when document content changes")
    func contentHashTracksContent() {
        var show = Show(name: "Hash")
        let firstHash = show.contentHash

        show.name = "Renamed"

        #expect(show.contentHash != firstHash)
    }

    // MARK: - Dirty state

    @Test("A never-saved show always needs saving")
    func unsavedShowNeedsSave() {
        let saver = ShowDocumentSaver()

        #expect(saver.needsSave(Show(name: "Draft")))
        #expect(saver.lastSavedAt == nil)
    }

    @Test("noteSaved clears the dirty flag for the same content")
    func noteSavedClearsDirtyFlag() {
        let saver = ShowDocumentSaver()
        let show = Show(name: "Saved")
        let url = URL(fileURLWithPath: "/tmp/Saved.fst")

        saver.noteSaved(show, at: url)

        #expect(!saver.needsSave(show))
        #expect(saver.lastSavedURL == url)
        #expect(saver.lastSavedAt != nil)
    }

    @Test("Editing after a save marks the show dirty again")
    func editsMarkShowDirty() {
        let saver = ShowDocumentSaver()
        var show = Show(name: "Saved")
        saver.noteSaved(show, at: URL(fileURLWithPath: "/tmp/Saved.fst"))

        show.name = "Edited"

        #expect(saver.needsSave(show))
    }

    @Test("Autosave interval is three minutes")
    func autosaveIntervalIsThreeMinutes() {
        #expect(ShowDocumentSaver().autosaveInterval == 180)
    }

    @Test("reset forgets the saved state without touching the file")
    func resetForgetsSavedState() throws {
        let directory = try makeTemporaryDirectory("SaverReset")
        defer { try? FileManager.default.removeItem(at: directory) }

        let assetURL = try makeAsset(named: "cue.png", in: directory)
        let show = makePresenterShow(assetURL: assetURL)
        let packageURL = directory.appendingPathComponent("Reset.fst")

        let saver = ShowDocumentSaver()
        saver.noteSaved(show, at: packageURL)
        saver.reset()

        #expect(saver.needsSave(show))
        #expect(saver.lastSavedURL == nil)
        #expect(saver.lastSavedAt == nil)
        #expect(!FileManager.default.fileExists(atPath: packageURL.path))
    }

    // MARK: - Package writing

    @Test("Writing the same show twice keeps a single copy of each asset")
    func repeatedWritesDoNotDuplicateAssets() throws {
        let directory = try makeTemporaryDirectory("SaverIdempotent")
        defer { try? FileManager.default.removeItem(at: directory) }

        let cueURL = try makeAsset(named: "cue.png", in: directory)
        let globalURL = try makeAsset(named: "bug.png", in: directory)
        let show = makePresenterShow(assetURL: cueURL, globalImageURL: globalURL)
        let packageURL = directory.appendingPathComponent("Idempotent.fst")

        _ = try ShowPackage.write(show, to: packageURL)
        let firstWrite = try assetNames(in: packageURL)

        let secondShow = try ShowPackage.read(from: packageURL)
        _ = try ShowPackage.write(secondShow, to: packageURL)
        let secondWrite = try assetNames(in: packageURL)

        #expect(firstWrite.count == 2)
        #expect(secondWrite == firstWrite)
    }

    @Test("Autosave writes only when the show changed")
    func autosaveSkipsUnchangedShow() async throws {
        let directory = try makeTemporaryDirectory("SaverAutosave")
        defer { try? FileManager.default.removeItem(at: directory) }

        let cueURL = try makeAsset(named: "cue.png", in: directory)
        let show = makePresenterShow(assetURL: cueURL)
        let packageURL = directory.appendingPathComponent("Autosave.fst")
        let saver = ShowDocumentSaver()

        guard let first = await saver.autosave(show, to: packageURL) else {
            Issue.record("The first autosave should have written the package")
            return
        }
        // The caller adopts `first`, whose asset URLs point inside the package.
        // That state must be considered clean so autosave never rewrites an
        // unchanged show.
        #expect(!saver.needsSave(first))
        let second = await saver.autosave(first, to: packageURL)
        #expect(second == nil)

        var edited = first
        edited.name = "Edited During Rehearsal"
        #expect(saver.needsSave(edited))
        let third = await saver.autosave(edited, to: packageURL)
        #expect(third != nil)
    }

    // MARK: - Cue layer assets

    @Test("Cue layer assets are copied into the package and remapped on save")
    func cueLayerAssetsArePackaged() throws {
        let directory = try makeTemporaryDirectory("SaverCueLayer")
        defer { try? FileManager.default.removeItem(at: directory) }

        let cueURL = try makeAsset(named: "screenshare.png", in: directory)
        let show = makePresenterShow(assetURL: cueURL)
        let packageURL = directory.appendingPathComponent("CueLayer.fst")

        let saved = try ShowPackage.write(show, to: packageURL)
        let savedLayerSource = try #require(saved.presenterRundown?.segments.first?.layers.first?.source)

        guard case .image(let packagedURL) = savedLayerSource else {
            Issue.record("Expected an image source on the cue layer")
            return
        }
        #expect(packagedURL.path.hasPrefix(packageURL.path))
        #expect(FileManager.default.fileExists(atPath: packagedURL.path))

        // The JSON on disk stores a package-relative path, so reading it back
        // must resolve to the same packaged asset.
        let reloaded = try ShowPackage.read(from: packageURL)
        let reloadedSource = try #require(reloaded.presenterRundown?.segments.first?.layers.first?.source)
        guard case .image(let reloadedURL) = reloadedSource else {
            Issue.record("Expected an image source on the reloaded cue layer")
            return
        }
        #expect(reloadedURL.standardizedFileURL == packagedURL.standardizedFileURL)
    }
}
