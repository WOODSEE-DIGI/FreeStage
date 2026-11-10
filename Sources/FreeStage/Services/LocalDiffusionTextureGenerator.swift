//
//  LocalDiffusionTextureGenerator.swift
//  FreeStage
//
//  Generates puppet skin textures using a local CoreML Stable Diffusion model.
//  Falls back to a freshly downloaded model directory managed by
//  DiffusionModelDownloader.
//

import Foundation
import StableDiffusion
import CoreML
import CoreGraphics
import ImageIO
import OSLog
import UniformTypeIdentifiers

enum LocalDiffusionTextureGeneratorError: Error, LocalizedError {
    case modelNotDownloaded
    case pipelineCreationFailed(Error)
    case generationFailed(Error)
    case noImageProduced
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded:
            return "The selected diffusion model has not been downloaded yet."
        case .pipelineCreationFailed(let error):
            return "Could not load the local diffusion pipeline: \(error.localizedDescription)"
        case .generationFailed(let error):
            return "Image generation failed: \(error.localizedDescription)"
        case .noImageProduced:
            return "The model finished but produced no image."
        case .saveFailed:
            return "Failed to save the generated texture."
        }
    }
}

/// Generates puppet textures with Apple's ml-stable-diffusion package.
@available(macOS 14.0, *)
actor LocalDiffusionTextureGenerator {
    private static let logger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "LocalDiffusionTextureGenerator")

    private let model: LocalDiffusionModel
    private let resourceDirectory: URL
    private var pipeline: StableDiffusionPipelineProtocol?

    init(model: LocalDiffusionModel, resourceDirectory: URL) {
        self.model = model
        self.resourceDirectory = resourceDirectory
    }

    /// Ensure the pipeline is loaded. This can be slow the first time.
    func loadPipeline() async throws {
        guard pipeline == nil else { return }
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all

            switch model.kind {
            case .sd15, .sd2:
                let sdPipeline = try StableDiffusionPipeline(
                    resourcesAt: resourceDirectory,
                    controlNet: [],
                    configuration: config,
                    disableSafety: true,
                    reduceMemory: true
                )
                try sdPipeline.loadResources()
                pipeline = sdPipeline
            case .sdXL:
                let xlPipeline = try StableDiffusionXLPipeline(
                    resourcesAt: resourceDirectory,
                    configuration: config,
                    reduceMemory: true
                )
                try xlPipeline.loadResources()
                pipeline = xlPipeline
            case .sd3:
                throw LocalDiffusionTextureGeneratorError.generationFailed(
                    NSError(domain: "FreeStage", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Stable Diffusion 3 is not available in this build."
                    ])
                )
            }
        } catch {
            throw LocalDiffusionTextureGeneratorError.pipelineCreationFailed(error)
        }
    }

    func generatePuppetTexture(
        promptOverride: String? = nil,
        seed: UInt32? = nil
    ) async throws -> URL {
        try await loadPipeline()
        guard let pipeline else {
            throw LocalDiffusionTextureGeneratorError.noImageProduced
        }

        let prompt = promptOverride ?? LocalDiffusionTextureGenerator.defaultPrompt
        let usedSeed = seed ?? UInt32.random(in: 0...UInt32.max)

        var config = StableDiffusionPipeline.Configuration(prompt: prompt)
        config.negativePrompt = LocalDiffusionTextureGenerator.defaultNegativePrompt
        config.imageCount = 1
        config.stepCount = 20
        config.seed = usedSeed
        config.guidanceScale = 7.5
        config.schedulerType = .dpmSolverMultistepScheduler
        config.disableSafety = true
        config.useDenoisedIntermediates = true

        if model.kind == .sd2 {
            config.encoderScaleFactor = 0.18215
            config.decoderScaleFactor = 0.18215
        } else if model.kind == .sd15 {
            config.encoderScaleFactor = 0.18215
            config.decoderScaleFactor = 0.18215
        }

        // Use the bundled canonical face UV template as the starting image so
        // generated textures line up with the MediaPipe face mesh.
        let targetSize = Self.inputImageSize(for: model)
        if let template = Self.loadTemplateImage(targetSize: targetSize) {
            config.startingImage = template
            config.strength = 0.65
            Self.logger.debug("Using puppet UV template as starting image at \(targetSize)x\(targetSize)")
        } else {
            Self.logger.warning("Could not load puppet UV template; falling back to text-to-image.")
        }

        let images: [CGImage?]
        do {
            images = try pipeline.generateImages(configuration: config) { progress in
                Self.logger.debug("Diffusion step \(progress.step)/\(progress.stepCount)")
                return true
            }
        } catch {
            throw LocalDiffusionTextureGeneratorError.generationFailed(error)
        }

        guard let cgImage = images.first.flatMap({ $0 }) else {
            throw LocalDiffusionTextureGeneratorError.noImageProduced
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("local_puppet_\(usedSeed)_\(UUID().uuidString).png")
        try Self.writePNG(cgImage: cgImage, to: outputURL)
        return outputURL
    }

    // MARK: - Defaults

    static let defaultPrompt = """
    front-facing stylized puppet face texture, symmetrical neutral expression, \
    large clear eyes, nose and mouth centered, looking directly at camera, \
    flat lighting, isolated on transparent background, anime style
    """

    static let defaultNegativePrompt = """
    text, watermark, signature, low quality, blurry, asymmetrical, profile, \
    side view, multiple faces, background
    """

    // MARK: - Puppet UV template

    /// The size the VAE encoder expects for the given model family.
    private static func inputImageSize(for model: LocalDiffusionModel) -> Int {
        switch model.kind {
        case .sdXL:
            return 1024
        case .sd15, .sd2, .sd3:
            return 512
        }
    }

    /// Loads the bundled `puppet_uv_template.png` and scales it to the model's
    /// expected VAE input size. Returns `nil` if the template is missing.
    private static func loadTemplateImage(targetSize: Int) -> CGImage? {
        guard let url = Bundle.main.url(forResource: "puppet_uv_template", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let size = CGSize(width: targetSize, height: targetSize)
        guard let context = CGContext(
            data: nil,
            width: targetSize,
            height: targetSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    // MARK: - Private

    private static func writePNG(cgImage: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw LocalDiffusionTextureGeneratorError.saveFailed
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        if !CGImageDestinationFinalize(destination) {
            throw LocalDiffusionTextureGeneratorError.saveFailed
        }
    }
}

