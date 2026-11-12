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
    /// Which show system this document uses.
    var kind: ShowKind
    var scenes: [Scene]
    var cues: [Cue]
    /// Presenter-mode data. Used when `kind == .presenter`.
    var presenterRundown: PresenterRundown?
    /// Layers that are rendered over every scene (e.g. a persistent camera overlay).
    var globalLayers: [Layer]
    /// Named camera setting presets that can be recalled by cues.
    var cameraPresets: [CameraPreset]
    /// Per-camera gimbal limit zones, keyed by AVCaptureDevice uniqueID.
    var cameraLimitZones: [String: CameraLimitZone]
    /// Security-scoped bookmark data for file URLs referenced by layer sources.
    /// Keyed by the URL's `absoluteString` at the time the bookmark was created.
    var bookmarks: [String: Data]
    /// Workspace UI/selection state restored when the show is reopened.
    var workspace: WorkspaceState
    /// Global graphic style used as the default for new template layers.
    var style: ShowStyle

    init(
        id: UUID = UUID(),
        name: String = "Untitled Show",
        kind: ShowKind = .theatre,
        scenes: [Scene] = [],
        cues: [Cue] = [],
        presenterRundown: PresenterRundown? = nil,
        globalLayers: [Layer] = [],
        cameraPresets: [CameraPreset] = [],
        cameraLimitZones: [String: CameraLimitZone] = [:],
        bookmarks: [String: Data] = [:],
        workspace: WorkspaceState = WorkspaceState(),
        style: ShowStyle = .default
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.scenes = scenes
        self.cues = cues
        self.presenterRundown = presenterRundown
        self.globalLayers = globalLayers
        self.cameraPresets = cameraPresets
        self.cameraLimitZones = cameraLimitZones
        self.bookmarks = bookmarks
        self.workspace = workspace
        self.style = style
    }

    // MARK: - Codable (back-compat with shows saved before limit zones/bookmarks/workspace/style)

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, scenes, cues, presenterRundown
        case globalLayers, cameraPresets, cameraLimitZones, bookmarks, workspace, style
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decodeIfPresent(ShowKind.self, forKey: .kind) ?? .theatre
        scenes = try container.decodeIfPresent([Scene].self, forKey: .scenes) ?? []
        cues = try container.decodeIfPresent([Cue].self, forKey: .cues) ?? []
        presenterRundown = try container.decodeIfPresent(PresenterRundown.self, forKey: .presenterRundown)
        globalLayers = try container.decodeIfPresent([Layer].self, forKey: .globalLayers) ?? []
        cameraPresets = try container.decodeIfPresent([CameraPreset].self, forKey: .cameraPresets) ?? []
        cameraLimitZones = try container.decodeIfPresent([String: CameraLimitZone].self, forKey: .cameraLimitZones) ?? [:]
        bookmarks = try container.decodeIfPresent([String: Data].self, forKey: .bookmarks) ?? [:]
        workspace = try container.decodeIfPresent(WorkspaceState.self, forKey: .workspace) ?? WorkspaceState()
        style = try container.decodeIfPresent(ShowStyle.self, forKey: .style) ?? .default
    }

    /// Resolve saved bookmarks and apply them to all file URLs in the show.
    /// Should be called immediately after decoding a show from disk.
    mutating func resolveBookmarks() {
        for sceneIndex in scenes.indices {
            for layerIndex in scenes[sceneIndex].layers.indices {
                scenes[sceneIndex].layers[layerIndex].resolveBookmarks(using: bookmarks)
            }
        }
        for layerIndex in globalLayers.indices {
            globalLayers[layerIndex].resolveBookmarks(using: bookmarks)
        }
        if presenterRundown != nil {
            for index in presenterRundown!.segments.indices {
                if presenterRundown!.segments[index].videoClip != nil {
                    presenterRundown!.segments[index].videoClip!.sourceURL = resolveBookmarkedURL(presenterRundown!.segments[index].videoClip!.sourceURL)
                    presenterRundown!.segments[index].videoClip!.proxyURL = presenterRundown!.segments[index].videoClip!.proxyURL.map(resolveBookmarkedURL)
                    presenterRundown!.segments[index].videoClip!.subclipURL = presenterRundown!.segments[index].videoClip!.subclipURL.map(resolveBookmarkedURL)
                }
            }
        }
    }

    private func resolveBookmarkedURL(_ url: URL) -> URL {
        guard url.isFileURL,
              let data = bookmarks[url.absoluteString],
              let resolved = SecurityScopedBookmark.resolve(data) else {
            return url
        }
        return resolved
    }

    /// Return a copy of the show with every file URL transformed by `map`.
    /// Used when packaging assets for a portable show file.
    func withFileURLs(_ map: (URL) -> URL) -> Show {
        var copy = self
        for sceneIndex in copy.scenes.indices {
            for layerIndex in copy.scenes[sceneIndex].layers.indices {
                copy.scenes[sceneIndex].layers[layerIndex].withFileURLs(map)
            }
        }
        for layerIndex in copy.globalLayers.indices {
            copy.globalLayers[layerIndex].withFileURLs(map)
        }
        if var rundown = copy.presenterRundown {
            for index in rundown.segments.indices {
                if var clip = rundown.segments[index].videoClip {
                    clip.sourceURL = map(clip.sourceURL)
                    clip.proxyURL = clip.proxyURL.map(map)
                    clip.subclipURL = clip.subclipURL.map(map)
                    rundown.segments[index].videoClip = clip
                }
            }
            copy.presenterRundown = rundown
        }
        return copy
    }

    /// Create a minimal theatre show with a demo scene containing two color layers.
    static func theatreDefault(style: ShowStyle = .default) -> Show {
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
            kind: .theatre,
            scenes: [scene],
            cues: [cue],
            globalLayers: [],
            cameraPresets: [],
            style: style
        )
    }

    /// Create a minimal presenter-to-camera show with a default segment rundown.
    static func presenterDefault(style: ShowStyle = .default) -> Show {
        return Show(
            name: "Untitled Presenter Show",
            kind: .presenter,
            presenterRundown: .default(),
            globalLayers: [],
            cameraPresets: [],
            style: style
        )
    }

    /// Backward-compatible default factory. New code should use `theatreDefault`
    /// or `presenterDefault` explicitly.
    static func `default`(style: ShowStyle = .default) -> Show {
        theatreDefault(style: style)
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
