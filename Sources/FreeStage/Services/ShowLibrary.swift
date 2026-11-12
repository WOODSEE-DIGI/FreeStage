//
//  ShowLibrary.swift
//  FreeStage
//
//  Canonical on-disk layout for a FreeStage show library.
//

import Foundation
import OSLog

/// One folder in the show-library template.
struct LibraryFolder: Identifiable, Hashable, Sendable {
    /// Folder name as it appears in Finder.
    let name: String
    /// Path components relative to the library root, parents first.
    let components: [String]
    /// One-sentence explanation written to the folder's README.
    let summary: String
    /// SF Symbol used to represent the folder in setup and settings UI.
    let symbolName: String

    var id: String { relativePath }

    /// Forward-slash path relative to the library root, e.g. `GlobalAssets/LUTs`.
    var relativePath: String { components.joined(separator: "/") }

    /// Nesting depth inside the library root; `0` for top-level folders.
    var depth: Int { max(0, components.count - 1) }

    /// Resolve this folder under a library root.
    func url(under root: URL) -> URL {
        components.reduce(root) { $0.appendingPathComponent($1, isDirectory: true) }
    }
}

/// The named asset folders created inside `GlobalAssets`.
enum AssetFolder: String, CaseIterable, Identifiable, Hashable, Sendable {
    case luts = "LUTs"
    case plugins = "Plugins"
    case soundEffects = "Sound Effects"
    case music = "Music"
    case memes = "Memes"
    case logos = "Logos"
    case images = "Images"
    case videos = "Videos"
    case templates = "Templates"

    var id: String { rawValue }

    /// Human-readable name, identical to the folder name in Finder.
    var name: String { rawValue }

    var summary: String {
        switch self {
        case .luts:
            return "Colour lookup tables (.cube) for colour-correction filters."
        case .plugins:
            return "Third-party effect bundles and handler plugins."
        case .soundEffects:
            return "Stings, applause and rimshots fired by cues."
        case .music:
            return "Walk-on, walk-off and backing music beds."
        case .memes:
            return "Reaction images and clips for ad-hoc drops."
        case .logos:
            return "Pre-keyed logos for bugs, lower thirds and mastheads."
        case .images:
            return "Stills, backdrops and backgrounds."
        case .videos:
            return "Video clips, loops and VT rolls."
        case .templates:
            return "Imported show styles and template layer packs."
        }
    }

    var symbolName: String {
        switch self {
        case .luts: return "camera.filters"
        case .plugins: return "puzzlepiece.extension"
        case .soundEffects: return "waveform"
        case .music: return "music.note"
        case .memes: return "face.smiling"
        case .logos: return "signature"
        case .images: return "photo"
        case .videos: return "video"
        case .templates: return "rectangle.3.group"
        }
    }

    /// Folder metadata used by the template and by UI lists.
    var libraryFolder: LibraryFolder {
        LibraryFolder(
            name: name,
            components: [ShowLibrary.Folder.globalAssets, name],
            summary: summary,
            symbolName: symbolName
        )
    }
}

/// A FreeStage show library: the folder picked during setup that holds global
/// assets, saved show packages and rendered output.
///
/// The layout is a template, created once per install and repaired on demand:
///
/// ```
/// <root>/
///   FreeStage Library.md
///   GlobalAssets/
///     LUTs/  Plugins/  Sound Effects/  Music/  Memes/
///     Logos/  Images/  Videos/  Templates/
///   Shows/
///   Output/
///     Recordings/
///     Exports/
/// ```
struct ShowLibrary: Hashable, Sendable {
    /// Folder names used by the template. Kept as constants so the layout can be
    /// changed in one place.
    enum Folder {
        static let globalAssets = "GlobalAssets"
        static let shows = "Shows"
        static let output = "Output"
        static let recordings = "Recordings"
        static let exports = "Exports"

        /// Marker written to the library root. Deliberately not `README.md` so a
        /// library placed in an existing project folder never clobbers anything.
        static let rootReadme = "FreeStage Library.md"
        /// Readme written inside each created folder.
        static let folderReadme = "README.md"
    }

    private static let logger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "ShowLibrary")

    let root: URL

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    /// Default library root: `~/Movies/FreeStage`.
    static func defaultRoot() -> URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
        return base.appendingPathComponent("FreeStage", isDirectory: true)
    }

    // MARK: - Template

    /// Every folder in the template, parents before children.
    static var templateFolders: [LibraryFolder] {
        let topLevel = [
            LibraryFolder(
                name: Folder.globalAssets,
                components: [Folder.globalAssets],
                summary: "Shared assets available to every show.",
                symbolName: "folder.fill"
            ),
            LibraryFolder(
                name: Folder.shows,
                components: [Folder.shows],
                summary: "Saved show packages (.fst).",
                symbolName: "film.stack"
            ),
            LibraryFolder(
                name: Folder.output,
                components: [Folder.output],
                summary: "Everything FreeStage writes out.",
                symbolName: "tray.and.arrow.down"
            )
        ]

        let outputFolders = [
            LibraryFolder(
                name: Folder.recordings,
                components: [Folder.output, Folder.recordings],
                summary: "Recordings started with ⇧⌘R or GO.",
                symbolName: "record.circle"
            ),
            LibraryFolder(
                name: Folder.exports,
                components: [Folder.output, Folder.exports],
                summary: "Manual exports and renders.",
                symbolName: "shippingbox"
            )
        ]

        return topLevel
            + AssetFolder.allCases.map(\.libraryFolder)
            + outputFolders
    }

    // MARK: - Locations

    private func directory(_ components: String...) -> URL {
        components.reduce(root) { $0.appendingPathComponent($1, isDirectory: true) }
    }

    var globalAssets: URL { directory(Folder.globalAssets) }
    var shows: URL { directory(Folder.shows) }
    var output: URL { directory(Folder.output) }
    var recordings: URL { directory(Folder.output, Folder.recordings) }
    var exports: URL { directory(Folder.output, Folder.exports) }

    /// URL for one of the named asset folders inside `GlobalAssets`.
    func assetFolder(_ folder: AssetFolder) -> URL {
        directory(Folder.globalAssets, folder.rawValue)
    }

    /// True when every template folder already exists on disk.
    var isPrepared: Bool {
        let fileManager = FileManager.default
        return Self.templateFolders.allSatisfy { folder in
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(
                atPath: folder.url(under: root).path,
                isDirectory: &isDirectory
            )
            return exists && isDirectory.boolValue
        }
    }

    // MARK: - Preparing

    /// Outcome of `prepare()`.
    struct PreparationResult: Sendable, Equatable {
        /// A folder that could not be created or a README that could not be written.
        struct Failure: Sendable, Equatable {
            let path: String
            let reason: String
        }

        var createdDirectories: [URL] = []
        var existingDirectories: [URL] = []
        var writtenReadmes: [URL] = []
        var failures: [Failure] = []

        var isComplete: Bool { failures.isEmpty }
        var didChangeDisk: Bool { !createdDirectories.isEmpty || !writtenReadmes.isEmpty }
    }

    /// Create the folder template under `root`, writing a README into each folder
    /// it creates.
    ///
    /// Idempotent and additive: existing folders, existing READMEs and any files
    /// the user has added are never modified or removed, so this is safe to call
    /// on every launch.
    @discardableResult
    func prepare() -> PreparationResult {
        let fileManager = FileManager.default
        var result = PreparationResult()

        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            Self.logger.error("Could not create library root \(self.root.path, privacy: .public): \(error.localizedDescription)")
            result.failures.append(.init(path: root.path, reason: error.localizedDescription))
            return result
        }

        writeReadme(
            at: root.appendingPathComponent(Folder.rootReadme, isDirectory: false),
            contents: rootReadme(),
            into: &result
        )

        for folder in Self.templateFolders {
            let url = folder.url(under: root)
            var isDirectory: ObjCBool = false

            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    result.existingDirectories.append(url)
                } else {
                    // A stray file is squatting on the folder name; leave it alone
                    // and report the collision rather than deleting user data.
                    result.failures.append(.init(
                        path: url.path,
                        reason: "A file with this name blocks the folder."
                    ))
                    continue
                }
            } else {
                do {
                    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                    result.createdDirectories.append(url)
                } catch {
                    Self.logger.error("Could not create \(url.path, privacy: .public): \(error.localizedDescription)")
                    result.failures.append(.init(path: url.path, reason: error.localizedDescription))
                    continue
                }
            }

            writeReadme(
                at: url.appendingPathComponent(Folder.folderReadme, isDirectory: false),
                contents: folderReadme(for: folder),
                into: &result
            )
        }

        if result.isComplete {
            Self.logger.debug("Show library ready at \(self.root.path, privacy: .public)")
        } else {
            Self.logger.error(
                "Show library at \(self.root.path, privacy: .public) has \(result.failures.count) problem(s)"
            )
        }
        return result
    }

    /// Ensure a single directory exists, e.g. before starting a recording.
    @discardableResult
    func ensureDirectory(_ url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            Self.logger.error("Could not create \(url.path, privacy: .public): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - READMEs

    private func writeReadme(at url: URL, contents: String, into result: inout PreparationResult) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            result.writtenReadmes.append(url)
        } catch {
            Self.logger.error("Could not write \(url.path, privacy: .public): \(error.localizedDescription)")
            result.failures.append(.init(path: url.path, reason: error.localizedDescription))
        }
    }

    private func folderReadme(for folder: LibraryFolder) -> String {
        """
        # \(folder.relativePath)

        \(folder.summary)

        FreeStage never deletes or overwrites files in this folder — anything you
        add here is left alone. Removing the folder is safe; it is recreated the
        next time FreeStage checks the library.
        """
    }

    private func rootReadme() -> String {
        let stamp = Date.now.formatted(date: .numeric, time: .omitted)

        var lines = [
            "# FreeStage Library",
            "",
            "Created by FreeStage on \(stamp).",
            "",
            "FreeStage stores global assets, saved shows and recordings here. It never",
            "deletes or overwrites files in this library, and any missing folder below is",
            "recreated automatically.",
            "",
            "```"
        ]

        for folder in Self.templateFolders {
            let indent = String(repeating: "  ", count: folder.depth)
            let entry = indent + folder.name + "/"
            let padding = String(repeating: " ", count: max(2, 24 - entry.count))
            lines.append(entry + padding + folder.summary)
        }

        lines.append("```")
        lines.append("")
        lines.append("Change the library location in FreeStage → Settings → Show Library.")
        return lines.joined(separator: "\n") + "\n"
    }
}
