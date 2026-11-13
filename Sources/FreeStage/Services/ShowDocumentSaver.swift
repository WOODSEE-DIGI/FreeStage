//
//  ShowDocumentSaver.swift
//  FreeStage
//
//  Single owner of show-package writes. Manual saves (Cmd-S / Save As) and the
//  periodic autosave both go through here so two writes can never overlap and
//  the package is never half-written.
//

import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class ShowDocumentSaver {
    private static let logger = Logger(subsystem: "com.woodseedigi.freestage", category: "ShowDocumentSaver")

    enum SaveError: LocalizedError {
        case saveAlreadyInProgress

        var errorDescription: String? {
            switch self {
            case .saveAlreadyInProgress:
                return "A save is already in progress."
            }
        }
    }

    /// Seconds between autosaves. The app triggers the timer; this value only
    /// documents and drives the UI label.
    var autosaveInterval: TimeInterval = 180

    private(set) var isSaving = false
    private(set) var lastSavedAt: Date?
    private(set) var lastSavedURL: URL?
    private(set) var lastErrorMessage: String?

    /// Content hash of the last successful write. `nil` until something is saved.
    private var lastSavedContentHash: Int?

    /// True when the show differs from what was last written.
    func needsSave(_ show: Show) -> Bool {
        lastSavedContentHash != show.contentHash
    }

    /// Record a state that already matches disk — used after opening a package
    /// so autosave does not immediately rewrite an unchanged file.
    func noteSaved(_ show: Show, at url: URL) {
        lastSavedURL = url
        lastSavedContentHash = show.contentHash
        lastSavedAt = Date()
        lastErrorMessage = nil
    }

    /// Forget the last saved state, for when the workspace is reset to a new
    /// unsaved show. No file is touched.
    func reset() {
        lastSavedURL = nil
        lastSavedContentHash = nil
        lastSavedAt = nil
        lastErrorMessage = nil
    }

    /// Write the package and return the rewritten show, whose asset URLs now
    /// point inside the package. Throws so manual saves can surface failures.
    @discardableResult
    func save(_ show: Show, to url: URL) async throws -> Show {
        guard !isSaving else { throw SaveError.saveAlreadyInProgress }
        isSaving = true
        defer { isSaving = false }

        do {
            // Package writing copies assets, so keep it off the main actor.
            let saved = try await Task.detached(priority: .utility) {
                try ShowPackage.write(show, to: url)
            }.value
            // Record the *rewritten* show: its asset URLs now point inside the
            // package, which is the state the caller adopts. Hashing the
            // pre-save copy would make the next autosave look dirty.
            noteSaved(saved, at: url)
            Self.logger.info("Saved show package to \(url.path, privacy: .public)")
            return saved
        } catch {
            lastErrorMessage = error.localizedDescription
            Self.logger.error("Failed to save show: \(error.localizedDescription)")
            throw error
        }
    }

    /// Autosave: silently skips when nothing changed or a save is in flight.
    /// Returns the rewritten show when a write happened.
    @discardableResult
    func autosave(_ show: Show, to url: URL) async -> Show? {
        guard !isSaving, needsSave(show) else { return nil }
        return try? await save(show, to: url)
    }
}
