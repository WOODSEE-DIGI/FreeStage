//
//  ComfyUITextureGenerator.swift
//  FreeStage
//
//  Queues a prompt against the local ComfyUI HTTP API, waits for the image
//  output, and returns a local file URL. No WebSocket dependency — it polls
//  the /history endpoint so it works with ComfyUI's offline venv.
//

import Foundation
import OSLog

enum ComfyUITextureGeneratorError: Error, LocalizedError {
    case workflowNotFound
    case invalidResponse
    case noImageOutput
    case serverError(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .workflowNotFound: return "Could not find puppet_skin_texture.json in the app bundle."
        case .invalidResponse: return "ComfyUI returned an unexpected response."
        case .noImageOutput: return "The workflow finished but produced no image."
        case .serverError(let msg): return "ComfyUI error: \(msg)"
        case .timedOut: return "Timed out waiting for ComfyUI to finish."
        }
    }
}

/// Generates puppet skin textures by driving the local ComfyUI API.
actor ComfyUITextureGenerator {
    private static let logger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "ComfyUITextureGenerator")
    private let serverAddress: String
    private let timeout: TimeInterval
    private let session: URLSession

    init(serverAddress: String = "127.0.0.1:8188", timeout: TimeInterval = 300) {
        self.serverAddress = serverAddress
        self.timeout = timeout
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: config)
    }

    /// Queue the puppet texture workflow and return a local file URL to the
    /// generated PNG.
    func generatePuppetTexture(
        promptOverride: String? = nil,
        seed: Int? = nil
    ) async throws -> URL {
        Self.logger.info("Loading puppet texture workflow from bundle")
        let workflow = try loadWorkflow()
        Self.logger.info("Uploading puppet UV template to ComfyUI")
        let templateFilename = try await uploadTemplateImage()
        Self.logger.info("Template uploaded as \(templateFilename)")
        Self.logger.info("Queuing prompt on ComfyUI \(self.serverAddress)")
        let (promptID, usedSeed) = try await queuePrompt(
            workflow: workflow,
            templateFilename: templateFilename,
            promptOverride: promptOverride,
            seed: seed
        )
        Self.logger.info("Prompt queued: \(promptID)")
        let imageData = try await pollForImage(promptID: promptID)
        Self.logger.info("Downloaded image for \(promptID)")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("comfy_puppet_\(usedSeed)_\(promptID).png")
        try imageData.write(to: outputURL)
        return outputURL
    }

    // MARK: - Private

    private func loadWorkflow() throws -> [String: Any] {
        guard let url = Bundle.main.url(
            forResource: "puppet_skin_texture_img2img",
            withExtension: "json"
        ) else {
            throw ComfyUITextureGeneratorError.workflowNotFound
        }
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ComfyUITextureGeneratorError.workflowNotFound
        }
        return json
    }

    private func queuePrompt(
        workflow: [String: Any],
        templateFilename: String,
        promptOverride: String?,
        seed: Int?
    ) async throws -> (promptID: String, seed: Int) {
        var prompt = workflow
        if let promptOverride, var node = prompt["2"] as? [String: Any], var inputs = node["inputs"] as? [String: Any] {
            inputs["text"] = promptOverride
            node["inputs"] = inputs
            prompt["2"] = node
        }

        let usedSeed = seed ?? Int.random(in: 0...Int(UInt32.max))
        if var node = prompt["5"] as? [String: Any], var inputs = node["inputs"] as? [String: Any] {
            inputs["seed"] = usedSeed
            inputs["denoise"] = 0.65
            node["inputs"] = inputs
            prompt["5"] = node
        }

        if var node = prompt["8"] as? [String: Any], var inputs = node["inputs"] as? [String: Any] {
            inputs["image"] = templateFilename
            node["inputs"] = inputs
            prompt["8"] = node
        }

        let clientID = UUID().uuidString.lowercased()
        let payload: [String: Any] = [
            "prompt": prompt,
            "client_id": clientID
        ]

        let url = URL(string: "http://\(serverAddress)/prompt")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ComfyUITextureGeneratorError.serverError("/prompt returned \(code): \(body)")
        }

        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let promptID = result["prompt_id"] as? String else {
            throw ComfyUITextureGeneratorError.invalidResponse
        }
        return (promptID, usedSeed)
    }

    private func uploadTemplateImage() async throws -> String {
        guard let url = Bundle.main.url(forResource: "puppet_uv_template", withExtension: "png") else {
            throw ComfyUITextureGeneratorError.workflowNotFound
        }

        let uploadURL = URL(string: "http://\(serverAddress)/upload/image")!
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let imageData = try Data(contentsOf: url)
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"puppet_uv_template.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw ComfyUITextureGeneratorError.serverError("/upload/image returned \(code): \(bodyText)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String else {
            throw ComfyUITextureGeneratorError.invalidResponse
        }
        return name
    }

    private func pollForImage(promptID: String) async throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        let historyURL = URL(string: "http://\(serverAddress)/history/\(promptID)")!

        while Date() < deadline {
            Self.logger.debug("Polling history for \(promptID)")
            let (data, response) = try await session.data(from: historyURL)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                Self.logger.debug("History not ready, sleeping…")
                try await Task.sleep(nanoseconds: 500_000_000)
                continue
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entry = json[promptID] as? [String: Any],
                  let outputs = entry["outputs"] as? [String: Any] else {
                Self.logger.debug("History has no outputs yet, sleeping…")
                try await Task.sleep(nanoseconds: 500_000_000)
                continue
            }

            Self.logger.info("Found \(outputs.count) output node(s) for \(promptID)")
            for (nodeID, value) in outputs {
                guard let nodeOutput = value as? [String: Any],
                      let images = nodeOutput["images"] as? [[String: String]],
                      let first = images.first else { continue }

                Self.logger.info("Fetching image from node \(nodeID): \(first["filename"] ?? "")")
                var components = URLComponents(string: "http://\(serverAddress)/view")!
                components.queryItems = [
                    URLQueryItem(name: "filename", value: first["filename"]),
                    URLQueryItem(name: "subfolder", value: first["subfolder"] ?? ""),
                    URLQueryItem(name: "type", value: first["type"] ?? "output")
                ]
                guard let viewURL = components.url else { continue }
                let (imageData, imageResponse) = try await session.data(from: viewURL)
                guard let imageHTTP = imageResponse as? HTTPURLResponse, imageHTTP.statusCode == 200 else {
                    throw ComfyUITextureGeneratorError.invalidResponse
                }
                return imageData
            }

            try await Task.sleep(nanoseconds: 500_000_000)
        }

        throw ComfyUITextureGeneratorError.timedOut
    }
}
