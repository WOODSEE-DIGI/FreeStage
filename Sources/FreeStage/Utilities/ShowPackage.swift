//
//  ShowPackage.swift
//  FreeStage
//
//  Reads and writes .fst show files as document packages. Every referenced
//  file asset (images, video, slideshows, face-puppet images, filter
//  backgrounds) is copied into the package's Assets folder so shows are
//  fully portable and sandbox-safe.
//

import Foundation
import OSLog

private let packageLogger = Logger(subsystem: "com.woodseedigi.freestage", category: "ShowPackage")

enum ShowPackage {
    static let showJSONName = "show.json"
    static let assetsFolderName = "Assets"

    /// Write a show as a document package at `packageURL`, copying all
    /// referenced file assets into the package. Returns the in-memory show
    /// with absolute URLs pointing at the copied assets inside the package.
    static func write(_ show: Show, to packageURL: URL) throws -> Show {
        let manager = FileManager.default
        try manager.createDirectory(at: packageURL, withIntermediateDirectories: true)

        let assetsURL = packageURL.appendingPathComponent(assetsFolderName)
        try manager.createDirectory(at: assetsURL, withIntermediateDirectories: true)

        // Collect unique file URLs and copy each into Assets/. Existing
        // package-relative URLs are resolved against the package first so
        // "Save As" still copies assets out of the old package.
        var showWithAbsoluteURLs = show
        showWithAbsoluteURLs = showWithAbsoluteURLs.withFileURLs { url in
            resolvePackageRelative(url: url, packageURL: packageURL)
        }

        let fileURLs = collectFileURLs(from: showWithAbsoluteURLs)
        var assetMap: [URL: URL] = [:]
        for url in fileURLs where url.isFileURL {
            // Skip URLs already inside this package.
            guard !isInsidePackage(url, packageURL: packageURL) else { continue }

            let assetName = uniqueAssetName(for: url, in: assetsURL)
            let destinationURL = assetsURL.appendingPathComponent(assetName)

            if manager.fileExists(atPath: destinationURL.path) {
                try manager.removeItem(at: destinationURL)
            }
            do {
                try accessSecurityScopedResource(url: url) {
                    try manager.copyItem(at: url, to: destinationURL)
                }
                assetMap[url] = destinationURL
            } catch {
                packageLogger.error("Failed to copy asset \(url.path) to package: \(error.localizedDescription)")
            }
        }

        if !assetMap.isEmpty {
            showWithAbsoluteURLs = showWithAbsoluteURLs.withFileURLs { assetMap[$0] ?? $0 }
        }
        showWithAbsoluteURLs.bookmarks = [:]

        // Encode with relative URLs so the package remains portable.
        var showToEncode = showWithAbsoluteURLs
        showToEncode = showToEncode.withFileURLs { url in
            makePackageRelative(url: url, packageURL: packageURL)
        }

        let jsonURL = packageURL.appendingPathComponent(showJSONName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(showToEncode)
        try data.write(to: jsonURL, options: .atomic)

        return showWithAbsoluteURLs
    }

    /// Read a show from a document package (or a legacy single-file .fst JSON),
    /// resolving relative asset paths against the package location.
    static func read(from packageURL: URL) throws -> Show {
        let manager = FileManager.default
        var isDir: ObjCBool = false
        let exists = manager.fileExists(atPath: packageURL.path, isDirectory: &isDir)
        guard exists else {
            throw CocoaError(.fileNoSuchFile)
        }

        let data: Data
        if isDir.boolValue {
            let jsonURL = packageURL.appendingPathComponent(showJSONName)
            data = try Data(contentsOf: jsonURL)
        } else {
            // Legacy single-file .fst.
            data = try Data(contentsOf: packageURL)
        }

        var show = try JSONDecoder().decode(Show.self, from: data)
        if isDir.boolValue {
            show = show.withFileURLs { url in
                resolvePackageRelative(url: url, packageURL: packageURL)
            }
        }
        show.resolveBookmarks()
        return show
    }

    // MARK: - Helpers

    private static func uniqueAssetName(for url: URL, in assetsURL: URL) -> String {
        let filename = url.lastPathComponent
        guard !filename.isEmpty else { return "asset" }

        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = filename
        var counter = 1
        while FileManager.default.fileExists(atPath: assetsURL.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            counter += 1
        }
        return candidate
    }

    /// Convert an absolute file URL inside the package to a relative path
    /// so the JSON remains portable when the package is moved.
    private static func makePackageRelative(url: URL, packageURL: URL) -> URL {
        guard url.isFileURL, isInsidePackage(url, packageURL: packageURL) else { return url }

        let packageComponents = packageURL.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        let relativeComponents = Array(urlComponents.dropFirst(packageComponents.count))
        let relativePath = relativeComponents.joined(separator: "/")
        guard !relativePath.isEmpty else { return url }

        let encoded = relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? relativePath
        return URL(string: encoded) ?? url
    }

    /// Convert a relative path URL back to an absolute file URL inside the
    /// package. Leaves absolute non-file URLs unchanged.
    private static func resolvePackageRelative(url: URL, packageURL: URL) -> URL {
        guard url.scheme == nil || url.scheme!.isEmpty else { return url }
        return packageURL.appendingPathComponent(url.path)
    }

    private static func isInsidePackage(_ url: URL, packageURL: URL) -> Bool {
        let packageComponents = packageURL.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        return urlComponents.count > packageComponents.count && urlComponents.starts(with: packageComponents)
    }

    private static func collectFileURLs(from show: Show) -> [URL] {
        var urls: [URL] = []
        for scene in show.scenes {
            for layer in scene.layers {
                urls.append(contentsOf: layer.source.fileURLs().filter(\.isFileURL))
                for filter in layer.filters {
                    urls.append(contentsOf: filterFileURLs(in: filter).filter(\.isFileURL))
                }
            }
        }
        for layer in show.globalLayers {
            urls.append(contentsOf: layer.source.fileURLs().filter(\.isFileURL))
            for filter in layer.filters {
                urls.append(contentsOf: filterFileURLs(in: filter).filter(\.isFileURL))
            }
        }
        return Array(Set(urls))
    }

    private static func filterFileURLs(in filter: Filter) -> [URL] {
        switch filter {
        case .chromaKey(let f):
            return f.backgroundSource?.fileURLs() ?? []
        default:
            return []
        }
    }
}
