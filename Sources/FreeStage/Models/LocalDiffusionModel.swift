//
//  LocalDiffusionModel.swift
//  FreeStage
//
//  Describes a Stable Diffusion model that can be downloaded from Hugging Face
//  and run locally through Apple's ml-stable-diffusion package.
//

import Foundation

/// A locally-runnable Stable Diffusion model definition.
struct LocalDiffusionModel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Hugging Face repo ID, e.g. "apple/coreml-stable-diffusion-v1-5".
    let repo: String
    /// Subdirectory inside the repo that contains the compiled .mlmodelc files
    /// and tokenizer files (vocab.json / merges.txt).
    let resourcePath: String
    let kind: Kind
    /// Approximate download size in bytes, used for progress display.
    let estimatedSize: Int64?

    enum Kind: String, Sendable {
        case sd15
        case sd2
        case sdXL
        case sd3
    }
}

extension LocalDiffusionModel {
    /// Built-in models we want to expose. The user can add more later.
    static let builtIn: [LocalDiffusionModel] = [
        LocalDiffusionModel(
            id: "apple-sd15-split_einsum",
            name: "Stable Diffusion 1.5 (CoreML, ANE)",
            repo: "apple/coreml-stable-diffusion-v1-5",
            resourcePath: "split_einsum/compiled",
            kind: .sd15,
            estimatedSize: 2_800_000_000
        ),
        LocalDiffusionModel(
            id: "apple-sd21-split_einsum",
            name: "Stable Diffusion 2.1 (CoreML, ANE)",
            repo: "apple/coreml-stable-diffusion-2-1-base",
            resourcePath: "split_einsum/compiled",
            kind: .sd2,
            estimatedSize: 2_800_000_000
        )
    ]
}
