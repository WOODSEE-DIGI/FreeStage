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
    /// Whether the chroma key effect is active. Kept as a property so the
    /// controls can remain visible (and editable) even when the effect is
    /// temporarily disabled.
    var isEnabled: Bool
    /// Sampled key colors. The first color is the primary key; additional
    /// colors allow multi-point sampling (e.g. uneven green screens).
    var keyColors: [RGBColor]
    var threshold: Double
    var smoothing: Double
    var edgeFeather: Double
    var spillSuppression: Double
    var spillRange: Double
    /// Extra despill applied to pixels near the key edge, where reflected
    /// key color is most visible. Range 0...2.
    var edgeDespill: Double
    /// Protect warm skin-tone hues from aggressive green/blue despill.
    /// 0 = no protection, 1 = full protection. Range 0...1.
    var skinToneProtection: Double
    /// Temporarily bypass the key for A/B comparison without changing isEnabled.
    var bypass: Bool
    /// Optional background image or video that is composited behind the
    /// keyed subject. If nil, keyed areas reveal whatever is behind this
    /// layer in the scene.
    var backgroundSource: Source?
    /// Independent transform for the background source. Position and scale are
    /// relative to the layer bounds (0.5 = centered, 1.0 = cover-fit size).
    var backgroundTransform: ItemTransform

    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        keyColors: [RGBColor] = [RGBColor(r: 0, g: 1, b: 0)],
        threshold: Double = 0.35,
        smoothing: Double = 0.08,
        edgeFeather: Double = 0.0,
        spillSuppression: Double = 0.5,
        spillRange: Double = 0.25,
        edgeDespill: Double = 0.5,
        skinToneProtection: Double = 0.3,
        bypass: Bool = false,
        backgroundSource: Source? = nil,
        backgroundTransform: ItemTransform = .identity
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.keyColors = keyColors
        self.threshold = threshold
        self.smoothing = smoothing
        self.edgeFeather = edgeFeather
        self.spillSuppression = spillSuppression
        self.spillRange = spillRange
        self.edgeDespill = edgeDespill
        self.skinToneProtection = skinToneProtection
        self.bypass = bypass
        self.backgroundSource = backgroundSource
        self.backgroundTransform = backgroundTransform
    }

    private enum CodingKeys: String, CodingKey {
        case id, isEnabled, keyColors, threshold, smoothing
        case edgeFeather, spillSuppression, spillRange
        case edgeDespill, skinToneProtection, bypass, backgroundSource
        case backgroundTransform
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.keyColors = try container.decodeIfPresent([RGBColor].self, forKey: .keyColors)
            ?? [RGBColor(r: 0, g: 1, b: 0)]
        self.threshold = try container.decodeIfPresent(Double.self, forKey: .threshold) ?? 0.35
        self.smoothing = try container.decodeIfPresent(Double.self, forKey: .smoothing) ?? 0.08
        self.edgeFeather = try container.decodeIfPresent(Double.self, forKey: .edgeFeather) ?? 0.0
        self.spillSuppression = try container.decodeIfPresent(Double.self, forKey: .spillSuppression) ?? 0.5
        self.spillRange = try container.decodeIfPresent(Double.self, forKey: .spillRange) ?? 0.25
        self.edgeDespill = try container.decodeIfPresent(Double.self, forKey: .edgeDespill) ?? 0.5
        self.skinToneProtection = try container.decodeIfPresent(Double.self, forKey: .skinToneProtection) ?? 0.3
        self.bypass = try container.decodeIfPresent(Bool.self, forKey: .bypass) ?? false
        self.backgroundSource = try container.decodeIfPresent(Source.self, forKey: .backgroundSource)
        self.backgroundTransform = try container.decodeIfPresent(ItemTransform.self, forKey: .backgroundTransform) ?? .identity
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(keyColors, forKey: .keyColors)
        try container.encode(threshold, forKey: .threshold)
        try container.encode(smoothing, forKey: .smoothing)
        try container.encode(edgeFeather, forKey: .edgeFeather)
        try container.encode(spillSuppression, forKey: .spillSuppression)
        try container.encode(spillRange, forKey: .spillRange)
        try container.encode(edgeDespill, forKey: .edgeDespill)
        try container.encode(skinToneProtection, forKey: .skinToneProtection)
        try container.encode(bypass, forKey: .bypass)
        try container.encode(backgroundSource, forKey: .backgroundSource)
        try container.encode(backgroundTransform, forKey: .backgroundTransform)
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
