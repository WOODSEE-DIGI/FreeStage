//
//  Composite.metal
//  FreeStage
//
//  Compute kernels for compositing layers onto the stage output, including
//  per-layer color correction and chroma keying.
//

#include <metal_stdlib>
using namespace metal;

#define MAX_KEY_COLORS 4

struct LayerParams {
    /// Normalized position of the layer center in output UV space.
    float2 position;
    /// Normalized size: 1.0 = full output width/height.
    float2 scale;
    /// Layer opacity.
    float opacity;
    /// Padding to keep the struct 16-byte aligned.
    float pad;
};

struct FilterParams {
    uint flags;
    uint keyColorCount;
    float4 keyColors[MAX_KEY_COLORS];
    float keyThreshold;
    float keySmoothing;
    float keyEdgeFeather;
    float keySpillAmount;
    float keySpillRange;
    float ccBrightness;
    float ccContrast;
    float ccSaturation;
    float ccHue;
    float ccExposure;
    float ccGamma;
    float ccTemperature;
    float ccTint;
    float _pad;
};

constant uint FLAG_COLOR_CORRECTION = 1u;
constant uint FLAG_CHROMA_KEY = 2u;
constant uint FLAG_CHROMA_KEY_BACKGROUND = 4u;

constant float3 rgbToCb = float3(-0.168736, -0.331264, 0.5);
constant float3 rgbToCr = float3(0.5, -0.418688, -0.081312);

static float2 chromaVector(float3 rgb) {
    float cb = dot(rgb, rgbToCb) + 0.5;
    float cr = dot(rgb, rgbToCr) + 0.5;
    return float2(cb, cr);
}

static float minChromaDistance(float3 fg, constant float4 *keyColors, int count) {
    if (count <= 0) { return 1000.0; }
    float2 fgChroma = chromaVector(fg);
    float minDist = distance(fgChroma, chromaVector(keyColors[0].rgb));
    for (int i = 1; i < count; i++) {
        float d = distance(fgChroma, chromaVector(keyColors[i].rgb));
        minDist = min(minDist, d);
    }
    return minDist;
}

static float3 dominantKeyColor(constant float4 *keyColors, int count) {
    if (count <= 0) { return float3(0.0, 1.0, 0.0); }
    float3 sum = float3(0.0);
    for (int i = 0; i < count; i++) { sum += keyColors[i].rgb; }
    return sum / float(count);
}

static float3 applyColorCorrection(float3 rgb, constant FilterParams &filters) {
    // Exposure and gamma.
    float3 c = rgb * pow(2.0, filters.ccExposure);
    c = pow(max(c, 0.0), 1.0 / max(filters.ccGamma, 0.01));

    // Brightness/contrast.
    c = c + filters.ccBrightness;
    c = (c - 0.5) * filters.ccContrast + 0.5;

    // Saturation.
    float luma = dot(c, float3(0.299, 0.587, 0.114));
    c = mix(float3(luma), c, filters.ccSaturation);

    // Hue rotation.
    float angle = filters.ccHue;
    float cosA = cos(angle);
    float sinA = sin(angle);
    float3x3 hueMatrix = float3x3(
        float3(0.299 + 0.701 * cosA + 0.168 * sinA,
               0.299 - 0.299 * cosA - 0.328 * sinA,
               0.299 - 0.300 * cosA + 1.250 * sinA),
        float3(0.587 - 0.587 * cosA + 0.330 * sinA,
               0.587 + 0.413 * cosA + 0.035 * sinA,
               0.587 - 0.588 * cosA - 1.050 * sinA),
        float3(0.114 - 0.114 * cosA - 0.497 * sinA,
               0.114 - 0.114 * cosA + 0.292 * sinA,
               0.114 + 0.886 * cosA - 0.203 * sinA)
    );
    c = hueMatrix * c;

    // Temperature / tint approximation.
    float temp = filters.ccTemperature / 100.0;
    c.r *= 1.0 + temp;
    c.b *= 1.0 - temp;
    c.g *= 1.0 + filters.ccTint * 0.5;

    return clamp(c, 0.0, 1.0);
}

static float4 applyChromaKey(float4 src, constant FilterParams &filters) {
    int count = min(int(filters.keyColorCount), MAX_KEY_COLORS);
    float chromaDist = minChromaDistance(src.rgb, filters.keyColors, count);

    float halfSmooth = max(filters.keySmoothing, 0.001) * 0.5;
    float matte = smoothstep(
        filters.keyThreshold - halfSmooth,
        filters.keyThreshold + halfSmooth,
        chromaDist
    );

    if (filters.keyEdgeFeather > 0.0) {
        float feather = clamp(filters.keyEdgeFeather, 0.0, 0.5);
        matte = smoothstep(0.0 + feather, 1.0 - feather, matte);
    }

    float spillRange = max(filters.keySpillRange, filters.keyThreshold);
    float spillFactor = 1.0 - smoothstep(
        filters.keyThreshold,
        spillRange,
        chromaDist
    );
    spillFactor *= (1.0 - matte) * filters.keySpillAmount;

    float3 keyColor = dominantKeyColor(filters.keyColors, count);
    float3 spill = src.rgb;
    bool isGreen = keyColor.g > max(keyColor.r, keyColor.b);
    bool isBlue  = keyColor.b > max(keyColor.r, keyColor.g);

    if (isGreen) {
        float greenExcess = max(0.0, spill.g - (spill.r + spill.b) * 0.5);
        spill.g -= greenExcess * spillFactor;
        spill.r += greenExcess * spillFactor * 0.45;
        spill.b += greenExcess * spillFactor * 0.45;
    } else if (isBlue) {
        float blueExcess = max(0.0, spill.b - (spill.r + spill.g) * 0.5);
        spill.b -= blueExcess * spillFactor;
        spill.r += blueExcess * spillFactor * 0.45;
        spill.g += blueExcess * spillFactor * 0.45;
    } else {
        float3 toKey = keyColor - spill;
        spill -= toKey * spillFactor * 0.5;
    }

    return float4(clamp(spill, 0.0, 1.0), src.a * matte);
}

/// Composite one source layer over the current output using source-over alpha.
/// When a chroma-key filter carries a backgroundSource, the background is
/// cover-fitted to the layer's on-screen bounds and used as the destination
/// behind the keyed subject, so the keyed-out area reveals the background
/// within the layer's rectangle. Outside the layer bounds the existing
/// output (lower layers) is left untouched.
kernel void compositeLayer(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::read_write> output [[texture(1)]],
    texture2d<float, access::read> background [[texture(2)]],
    constant LayerParams &params [[buffer(0)]],
    constant FilterParams &filters [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
)
{
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }

    float2 outputSize = float2(output.get_width(), output.get_height());
    float2 outputUV = float2(gid) / outputSize;

    float2 sourceUV = (outputUV - params.position) / params.scale + 0.5;

    // Outside the layer bounds: leave the existing output untouched.
    if (sourceUV.x < 0.0 || sourceUV.x > 1.0 || sourceUV.y < 0.0 || sourceUV.y > 1.0) {
        return;
    }

    bool hasBackground = (filters.flags & FLAG_CHROMA_KEY_BACKGROUND) != 0u;

    // Sample and filter the source layer.
    float2 sourceSize = float2(source.get_width(), source.get_height());
    uint2 sourceCoord = uint2(clamp(sourceUV * sourceSize, 0.0, sourceSize - 1.0));
    float4 src = source.read(sourceCoord);

    if ((filters.flags & FLAG_COLOR_CORRECTION) != 0u) {
        src.rgb = applyColorCorrection(src.rgb, filters);
    }

    if ((filters.flags & FLAG_CHROMA_KEY) != 0u) {
        src = applyChromaKey(src, filters);
    }

    src.a *= params.opacity;
    // Premultiply so the source-over blend below is correct. Without this,
    // a keyed-out pixel keeps its green RGB at alpha 0 and the background
    // gets tinted/overwritten by green.
    src.rgb *= src.a;

    // Determine destination pixels. With a background, cover-fit it to the
    // layer's on-screen rectangle (using the layer-local UV) so the aspect
    // ratio is preserved. Without a background, read the existing output.
    float4 dst;
    if (hasBackground) {
        float2 bgSize = float2(background.get_width(), background.get_height());
        float layerAspect = params.scale.x * outputSize.x / (params.scale.y * outputSize.y);
        float bgAspect = bgSize.x / bgSize.y;
        float2 bgScale = (bgAspect > layerAspect)
            ? float2(layerAspect / bgAspect, 1.0)
            : float2(1.0, bgAspect / layerAspect);
        float2 bgUV = (sourceUV - 0.5) / bgScale + 0.5;
        bgUV = clamp(bgUV, 0.0, 1.0);
        uint2 bgCoord = uint2(bgUV * bgSize);
        dst = background.read(bgCoord);
    } else {
        dst = output.read(gid);
    }

    // Premultiplied source-over.
    float4 result = src + dst * (1.0 - src.a);
    output.write(result, gid);
}

/// Clear the output texture to transparent black.
kernel void clearOutput(
    texture2d<float, access::write> output [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]
)
{
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
    output.write(float4(0.0), gid);
}
