//
//  DiffusionModelDownloader.swift
//  FreeStage
//
//  Downloads compiled CoreML Stable Diffusion models from Hugging Face into
//  the app's Application Support directory.
//

import Foundation
import OSLog

enum DiffusionModelDownloaderError: Error, LocalizedError {
    case missingApplicationSupport
    case invalidRepoResponse
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingApplicationSupport:
            return "Could not locate the Application Support folder."
        case .invalidRepoResponse:
            return "Hugging Face returned an unexpected repo listing."
        case .downloadFailed(let path):
            return "Failed to download \(path)."
        }
    }
}

/// Downloads Hugging Face CoreML model repositories for local inference.
actor DiffusionModelDownloader {
    private static let logger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "DiffusionModelDownloader")
    private let session: URLSession
    private let maxConcurrentDownloads = 4

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 3_600
        self.session = URLSession(configuration: config)
    }

    /// Returns the local directory that holds the compiled models and tokenizer
    /// files for the given model, or nil if it has not been downloaded.
    func localDirectory(for model: LocalDiffusionModel) -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = support
            .appendingPathComponent("DiffusionModels", isDirectory: true)
            .appendingPathComponent(model.id, isDirectory: true)
            .appendingPathComponent(model.resourcePath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
        return directory
    }

    /// True if the model appears to be fully downloaded.
    func isDownloaded(_ model: LocalDiffusionModel) -> Bool {
        guard let directory = localDirectory(for: model) else { return false }
        let requiredFiles = ["TextEncoder.mlmodelc", "Unet.mlmodelc", "VAEDecoder.mlmodelc", "VAEEncoder.mlmodelc", "vocab.json", "merges.txt"]
        return requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    /// Download the model's files and return the local resource directory.
    func download(
        model: LocalDiffusionModel,
        progressHandler: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw DiffusionModelDownloaderError.missingApplicationSupport
        }

        let baseDirectory = support
            .appendingPathComponent("DiffusionModels", isDirectory: true)
            .appendingPathComponent(model.id, isDirectory: true)
            .appendingPathComponent(model.resourcePath, isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        let files = try await listFiles(repo: model.repo, prefix: model.resourcePath)
        guard !files.isEmpty else {
            throw DiffusionModelDownloaderError.invalidRepoResponse
        }

        let totalEstimated = Double(model.estimatedSize ?? Int64(files.count))
        let progress = DownloadProgress(totalEstimated: totalEstimated)

        let prefix = model.resourcePath.hasSuffix("/") ? model.resourcePath : model.resourcePath + "/"
        try await withThrowingTaskGroup(of: (String, Int64).self) { group in
            var pending = files
            var active = 0

            while !pending.isEmpty || active > 0 {
                while active < maxConcurrentDownloads, !pending.isEmpty {
                    let file = pending.removeFirst()
                    active += 1
                    group.addTask {
                        let bytes = try await self.downloadFile(
                            repo: model.repo,
                            path: file,
                            prefix: prefix,
                            to: baseDirectory
                        )
                        return (file, bytes)
                    }
                }

                if let result = try await group.next() {
                    active -= 1
                    let fraction = await progress.report(bytes: result.1)
                    progressHandler(fraction)
                }
            }
        }

        progressHandler(1.0)
        return baseDirectory
    }

    // MARK: - Private

    private func listFiles(repo: String, prefix: String) async throws -> [String] {
        let apiURL = URL(string: "https://huggingface.co/api/models/\(repo)")!
        let (data, response) = try await session.data(from: apiURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DiffusionModelDownloaderError.invalidRepoResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let siblings = json["siblings"] as? [[String: Any]] else {
            throw DiffusionModelDownloaderError.invalidRepoResponse
        }

        let prefixWithSlash = prefix.hasSuffix("/") ? prefix : prefix + "/"
        let files = siblings.compactMap { $0["rfilename"] as? String }
            .filter { $0.hasPrefix(prefixWithSlash) && !$0.hasSuffix("/") }
            .filter { !$0.hasSuffix(".gitattributes") && !$0.hasSuffix(".gitignore") && !$0.lowercased().hasSuffix("readme.md") }
        return files
    }

    private func downloadFile(repo: String, path: String, prefix: String, to baseDirectory: URL) async throws -> Int64 {
        let sourceURL = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(path)")!
        let relativePath = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
        let destination = baseDirectory.appendingPathComponent(relativePath)

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let (localURL, response) = try await session.download(from: sourceURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DiffusionModelDownloaderError.downloadFailed(path)
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: localURL, to: destination)

        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        return attributes[.size] as? Int64 ?? 0
    }
}

private actor DownloadProgress {
    private let totalEstimated: Double
    private var received: Double = 0

    init(totalEstimated: Double) {
        self.totalEstimated = totalEstimated
    }

    func report(bytes: Int64) -> Double {
        received += Double(bytes)
        return min(received / totalEstimated, 0.99)
    }
}
