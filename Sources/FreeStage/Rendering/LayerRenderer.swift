//
//  LayerRenderer.swift
//  FreeStage
//
//  Composites a single layer (source texture + transform + opacity + filters)
//  onto the stage output texture.
//

import Metal
import CoreGraphics

struct LayerRenderer: @unchecked Sendable {
    private let device: MTLDevice
    private let pipelineState: MTLComputePipelineState
    private let placeholderTexture: MTLTexture

    init(device: MTLDevice) throws {
        self.device = device
        let library = try device.makeDefaultLibrary(bundle: Bundle(for: BundleFinder.self))
        guard let function = library.makeFunction(name: "compositeLayer") else {
            throw LayerRendererError.kernelNotFound
        }
        self.pipelineState = try device.makeComputePipelineState(function: function)
        self.placeholderTexture = LayerRenderer.makePlaceholderTexture(device: device)
    }

    /// Composite `sourceTexture` onto `outputTexture` using the layer's transform
    /// and filters. An optional `backgroundTexture` is used when a chroma-key
    /// filter on the layer has a backgroundSource.
    func render(
        layer: Layer,
        sourceTexture: MTLTexture,
        backgroundTexture: MTLTexture? = nil,
        outputTexture: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) throws {
        guard layer.isVisible else { return }

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw LayerRendererError.encodeFailed
        }

        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(sourceTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        encoder.setTexture(backgroundTexture ?? placeholderTexture, index: 2)

        var params = LayerParams(
            position: SIMD2<Float>(Float(layer.transform.x), Float(layer.transform.y)),
            scale: SIMD2<Float>(Float(layer.transform.scaleX), Float(layer.transform.scaleY)),
            opacity: Float(layer.opacity),
            preserveAspect: layer.source.preservesAspect ? 1.0 : 0.0
        )
        encoder.setBytes(&params, length: MemoryLayout<LayerParams>.stride, index: 0)

        var filterParams = FilterParams(layer: layer)
        encoder.setBytes(&filterParams, length: MemoryLayout<FilterParams>.stride, index: 1)

        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (outputTexture.width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (outputTexture.height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
    }

    private static func makePlaceholderTexture(device: MTLDevice) -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.width = 1
        descriptor.height = 1
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("Failed to create placeholder texture")
        }
        var pixel = SIMD4<UInt8>(0, 0, 0, 0)
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &pixel, bytesPerRow: 4)
        return texture
    }
}

// MARK: - Errors

enum LayerRendererError: Error {
    case kernelNotFound
    case encodeFailed
}

// MARK: - C bridge layout

private struct LayerParams {
    var position: SIMD2<Float>
    var scale: SIMD2<Float>
    var opacity: Float
    var preserveAspect: Float
}

/// Must stay byte-compatible with the struct declared in Composite.metal.
private struct FilterParams {
    var flags: UInt32
    var keyColorCount: UInt32
    var _pad0: SIMD2<Float>
    var keyColors: KeyColorArray
    var keyThreshold: Float
    var keySmoothing: Float
    var keyEdgeFeather: Float
    var keySpillAmount: Float
    var keySpillRange: Float
    var keyEdgeDespill: Float
    var keySkinProtection: Float
    var ccBrightness: Float
    var ccContrast: Float
    var ccSaturation: Float
    var ccHue: Float
    var ccExposure: Float
    var ccGamma: Float
    var ccTemperature: Float
    var ccTint: Float
    var pad: Float
    var bgPositionX: Float
    var bgPositionY: Float
    var bgZoom: Float
    var hueShift: Float

    init(layer: Layer) {
        var flags: UInt32 = 0
        var keyColorCount: UInt32 = 0
        let _pad0: SIMD2<Float> = .zero
        var keyColors = KeyColorArray(
            SIMD4<Float>(0, 0, 0, 1), SIMD4<Float>(0, 0, 0, 1),
            SIMD4<Float>(0, 0, 0, 1), SIMD4<Float>(0, 0, 0, 1)
        )
        var keyThreshold: Float = 0.35
        var keySmoothing: Float = 0.08
        var keyEdgeFeather: Float = 0.0
        var keySpillAmount: Float = 0.5
        var keySpillRange: Float = 0.25
        var keyEdgeDespill: Float = 0.5
        var keySkinProtection: Float = 0.3
        var ccBrightness: Float = 0.0
        var ccContrast: Float = 1.0
        var ccSaturation: Float = 1.0
        var ccHue: Float = 0.0
        var ccExposure: Float = 0.0
        var ccGamma: Float = 1.0
        var ccTemperature: Float = 0.0
        var ccTint: Float = 0.0
        var bgPositionX: Float = 0.5
        var bgPositionY: Float = 0.5
        var bgZoom: Float = 1.0
        var hueShift: Float = 0.0

        for filter in layer.filters {
            switch filter {
            case .chromaKey(let f):
                let colors = f.keyColors.isEmpty ? [RGBColor(r: 0, g: 1, b: 0)] : f.keyColors
                let count = max(min(colors.count, 4), 1)
                keyColorCount = UInt32(count)
                keyColors = makeKeyColorArray(from: colors)
                keyThreshold = Float(f.threshold)
                keySmoothing = Float(f.smoothing)
                keyEdgeFeather = Float(f.edgeFeather)
                keySpillAmount = Float(f.spillSuppression)
                keySpillRange = Float(f.spillRange)
                keyEdgeDespill = Float(f.edgeDespill)
                keySkinProtection = Float(f.skinToneProtection)
                if f.isEnabled && !f.bypass {
                    flags |= 2
                    if f.backgroundSource != nil {
                        flags |= 4
                    }
                }
                bgPositionX = Float(f.backgroundTransform.x)
                bgPositionY = Float(f.backgroundTransform.y)
                bgZoom = Float(max(f.backgroundTransform.scaleX, 0.01))
                hueShift = Float(f.hueShift)
            case .colorCorrection(let f):
                flags |= 1
                ccBrightness = Float(f.brightness)
                ccContrast = Float(f.contrast)
                ccSaturation = Float(f.saturation)
                ccHue = Float(f.hue)
                ccExposure = Float(f.exposure)
                ccGamma = Float(f.gamma)
                ccTemperature = Float(f.temperature)
                ccTint = Float(f.tint)
            default:
                break
            }
        }

        self.flags = flags
        self.keyColorCount = keyColorCount
        self._pad0 = _pad0
        self.keyColors = keyColors
        self.keyThreshold = keyThreshold
        self.keySmoothing = keySmoothing
        self.keyEdgeFeather = keyEdgeFeather
        self.keySpillAmount = keySpillAmount
        self.keySpillRange = keySpillRange
        self.keyEdgeDespill = keyEdgeDespill
        self.keySkinProtection = keySkinProtection
        self.ccBrightness = ccBrightness
        self.ccContrast = ccContrast
        self.ccSaturation = ccSaturation
        self.ccHue = ccHue
        self.ccExposure = ccExposure
        self.ccGamma = ccGamma
        self.ccTemperature = ccTemperature
        self.ccTint = ccTint
        self.pad = 0
        self.bgPositionX = bgPositionX
        self.bgPositionY = bgPositionY
        self.bgZoom = bgZoom
        self.hueShift = hueShift
    }
}

private typealias KeyColorArray = (
    SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>
)

private func makeKeyColorArray(from colors: [RGBColor]) -> KeyColorArray {
    let defaultColor = SIMD4<Float>(0, 0, 0, 1)
    var array = (defaultColor, defaultColor, defaultColor, defaultColor)
    let count = min(colors.count, 4)
    if count > 0 { array.0 = SIMD4<Float>(Float(colors[0].r), Float(colors[0].g), Float(colors[0].b), 1) }
    if count > 1 { array.1 = SIMD4<Float>(Float(colors[1].r), Float(colors[1].g), Float(colors[1].b), 1) }
    if count > 2 { array.2 = SIMD4<Float>(Float(colors[2].r), Float(colors[2].g), Float(colors[2].b), 1) }
    if count > 3 { array.3 = SIMD4<Float>(Float(colors[3].r), Float(colors[3].g), Float(colors[3].b), 1) }
    return array
}

/// Empty helper class so `Bundle(for:)` can locate the framework/main bundle
/// containing the compiled Metal library.
private final class BundleFinder {}
