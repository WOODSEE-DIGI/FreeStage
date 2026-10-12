//
//  Show.swift
//  FreeStage
//
//  A show is the top-level document. It owns scenes, an ordered cue list,
//  and a set of global layers that are composited over every scene.
//

import Foundation

struct Show: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var scenes: [Scene]
    var cues: [Cue]
    /// Layers that are rendered over every scene (e.g. a persistent camera overlay).
    var globalLayers: [Layer]
    /// Named camera setting presets that can be recalled by cues.
    var cameraPresets: [CameraPreset]
    /// Per-camera gimbal limit zones, keyed by AVCaptureDevice uniqueID.
    var cameraLimitZones: [String: CameraLimitZone]

    init(
        id: UUID = UUID(),
        name: String = "Untitled Show",
        scenes: [Scene] = [],
        cues: [Cue] = [],
        globalLayers: [Layer] = [],
        cameraPresets: [CameraPreset] = [],
        cameraLimitZones: [String: CameraLimitZone] = [:]
    ) {
        self.id = id
        self.name = name
        self.scenes = scenes
        self.cues = cues
        self.globalLayers = globalLayers
        self.cameraPresets = cameraPresets
        self.cameraLimitZones = cameraLimitZones
    }

    // MARK: - Codable (back-compat with shows saved before limit zones)

    private enum CodingKeys: String, CodingKey {
        case id, name, scenes, cues, globalLayers, cameraPresets, cameraLimitZones
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        scenes = try container.decode([Scene].self, forKey: .scenes)
        cues = try container.decode([Cue].self, forKey: .cues)
        globalLayers = try container.decode([Layer].self, forKey: .globalLayers)
        cameraPresets = try container.decodeIfPresent([CameraPreset].self, forKey: .cameraPresets) ?? []
        cameraLimitZones = try container.decodeIfPresent([String: CameraLimitZone].self, forKey: .cameraLimitZones) ?? [:]
    }

    /// Create a minimal show with a demo scene containing two color layers.
    static func `default`() -> Show {
        let backgroundLayer = Layer(
            name: "Background",
            source: .color(CGColorComponents(r: 0.1, g: 0.1, b: 0.3, a: 1)),
            transform: ItemTransform(x: 0.5, y: 0.5, scaleX: 1.0, scaleY: 1.0, rotation: 0, crop: .zero)
        )
        let boxLayer = Layer(
            name: "Box",
            source: .color(CGColorComponents(r: 0.9, g: 0.2, b: 0.2, a: 1)),
            transform: ItemTransform(x: 0.5, y: 0.5, scaleX: 0.4, scaleY: 0.4, rotation: 0, crop: .zero),
            opacity: 0.9
        )
        let scene = Scene(
            name: "Opening",
            layers: [backgroundLayer, boxLayer],
            outputSize: CGSize(width: 1920, height: 1080)
        )
        let cue = Cue(
            number: "1",
            name: "Opening",
            sceneID: scene.id,
            transition: .cut
        )
        return Show(
            name: "Untitled Show",
            scenes: [scene],
            cues: [cue],
            globalLayers: [],
            cameraPresets: []
        )
    }

    func scene(withID id: UUID) -> Scene? {
        scenes.first { $0.id == id }
    }

    mutating func append(scene: Scene) {
        scenes.append(scene)
    }

    mutating func append(cue: Cue) {
        cues.append(cue)
    }
}
