//
//  Scene.swift
//  FreeStage
//
//  A scene is a canvas of layers. Scenes are referenced by cues.
//

import Foundation

struct Scene: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var layers: [Layer]
    var outputSize: CGSizeCodable

    init(
        id: UUID = UUID(),
        name: String,
        layers: [Layer] = [],
        outputSize: CGSize = CGSize(width: 1920, height: 1080)
    ) {
        self.id = id
        self.name = name
        self.layers = layers
        self.outputSize = CGSizeCodable(outputSize)
    }

    static func empty(named name: String) -> Scene {
        Scene(name: name)
    }
}
