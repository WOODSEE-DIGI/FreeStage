//
//  SampleWrapGenerationTests.swift
//  FreeStageTests
//
//  One-off generator for bundled animal face-puppet wrap textures.
//  Run this test manually; it is not part of the normal CI suite.
//

import Testing
import Foundation
@testable import FreeStage

struct SampleWrapGenerationTests {

    @Test("Generate bundled animal wrap textures")
    func generateSampleWraps() async throws {
        let model = LocalDiffusionModel.builtIn[0]
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            Issue.record("Could not locate Application Support directory")
            return
        }
        let resourceDirectory = support
            .appendingPathComponent("DiffusionModels", isDirectory: true)
            .appendingPathComponent(model.id, isDirectory: true)
            .appendingPathComponent(model.resourcePath, isDirectory: true)

        let generator = LocalDiffusionTextureGenerator(
            model: model,
            resourceDirectory: resourceDirectory
        )

        let samples: [(filename: String, prompt: String)] = [
            (
                "wrap_panda",
                "front-facing panda face texture map, symmetrical neutral expression, large black eye patches, white fur face, round black ears, black nose and lips, flat lighting, isolated on transparent background, cartoon style"
            ),
            (
                "wrap_red_panda",
                "front-facing red panda face texture map, symmetrical neutral expression, reddish orange fur, white ear tufts, dark tear marks around eyes, black nose, flat lighting, isolated on transparent background, cartoon style"
            ),
            (
                "wrap_fox",
                "front-facing fox face texture map, symmetrical neutral expression, orange fur, white muzzle and cheeks, pointed orange ears with black tips, black nose, flat lighting, isolated on transparent background, cartoon style"
            )
        ]

        let outputDirectory = support.appendingPathComponent("GeneratedWraps", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for sample in samples {
            let generatedURL = try await generator.generatePuppetTexture(promptOverride: sample.prompt)
            let destination = outputDirectory.appendingPathComponent("\(sample.filename).png")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: generatedURL, to: destination)
        }
    }
}
