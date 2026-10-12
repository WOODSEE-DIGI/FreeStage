//
//  Filter.swift
//  FreeStage
//
//  Per-layer video filters applied to the source texture before compositing.
//  Includes the chroma key and color-correction pipeline from DualCast.
//

import Foundation

enum Filter: Identifiable, Hashable, Codable, Sendable {
    case chromaKey(ChromaKeyFilter)
    case colorCorrection(ColorCorrectionFilter)
    case crop(CropFilter)
    case aiKeyer(AIKeyerFilter)

    var id: String {
        switch self {
        case .chromaKey(let f): return "chromaKey:\(f.id)"
        case .colorCorrection(let f): return "colorCorrection:\(f.id)"
        case .crop(let f): return "crop:\(f.id)"
        case .aiKeyer(let f): return "aiKeyer:\(f.id)"
        }
    }

    var displayName: String {
        switch self {
        case .chromaKey: return "Chroma Key"
        case .colorCorrection: return "Color Correction"
        case .crop: return "Crop"
        case .aiKeyer: return "AI Keyer"
        }
    }
}

struct ChromaKeyFilter: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    /// Sampled key colors. The first color is the primary key; additional
    /// colors allow multi-point sampling (e.g. uneven green screens).
    var keyColors: [RGBColor]
    var threshold: Double
    var smoothing: Double
    var edgeFeather: Double
    var spillSuppression: Double
    var spillRange: Double
    /// Optional background image or video that is composited behind the
    /// keyed subject. If nil, keyed areas reveal whatever is behind this
    /// layer in the scene.
    var backgroundSource: Source?

    init(
        id: UUID = UUID(),
        keyColors: [RGBColor] = [RGBColor(r: 0, g: 1, b: 0)],
        threshold: Double = 0.35,
        smoothing: Double = 0.08,
        edgeFeather: Double = 0.0,
        spillSuppression: Double = 0.5,
        spillRange: Double = 0.25,
        backgroundSource: Source? = nil
    ) {
        self.id = id
        self.keyColors = keyColors
        self.threshold = threshold
        self.smoothing = smoothing
        self.edgeFeather = edgeFeather
        self.spillSuppression = spillSuppression
        self.spillRange = spillRange
        self.backgroundSource = backgroundSource
    }

    /// Convenience accessor for the primary key color.
    var keyColor: RGBColor {
        get { keyColors.first ?? RGBColor(r: 0, g: 1, b: 0) }
        set {
            if keyColors.isEmpty {
                keyColors = [newValue]
            } else {
                keyColors[0] = newValue
            }
        }
    }
}

struct ColorCorrectionFilter: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var brightness: Double
    var contrast: Double
    var saturation: Double
    var hue: Double
    var exposure: Double
    var gamma: Double
    var temperature: Double
    var tint: Double

    init(
        id: UUID = UUID(),
        brightness: Double = 0,
        contrast: Double = 1,
        saturation: Double = 1,
        hue: Double = 0,
        exposure: Double = 0,
        gamma: Double = 1,
        temperature: Double = 0,
        tint: Double = 0
    ) {
        self.id = id
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.hue = hue
        self.exposure = exposure
        self.gamma = gamma
        self.temperature = temperature
        self.tint = tint
    }
}

struct CropFilter: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var rect: NormalizedRect

    init(id: UUID = UUID(), rect: NormalizedRect = NormalizedRect(x: 0, y: 0, width: 1, height: 1)) {
        self.id = id
        self.rect = rect
    }
}

struct AIKeyerFilter: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var enabled: Bool
    var serverURL: URL

    init(
        id: UUID = UUID(),
        enabled: Bool = false,
        serverURL: URL = URL(string: "http://127.0.0.1:9123")!
    ) {
        self.id = id
        self.enabled = enabled
        self.serverURL = serverURL
    }
}

struct RGBColor: Hashable, Codable, Sendable {
    var r: Double
    var g: Double
    var b: Double
}

struct NormalizedRect: Hashable, Codable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}
