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
    /// 1.0 to aspect-fit the source texture inside the layer rectangle,
    /// 0.0 to stretch it to fill the rectangle.
    float preserveAspect;
    /// Border color (RGBA).
    float4 borderColor;
    /// Border width in pixels.
    float borderWidth;
    /// Border corner radius in pixels.
    float borderCornerRadius;
    /// 1.0 when the border should be drawn.
    float borderEnabled;
};

struct FilterParams {
    uint flags;
    uint keyColorCount;
    float2 _pad0;
    float4 keyColors[MAX_KEY_COLORS];
    float keyThreshold;
    float keySmoothing;
    float keyEdgeFeather;
    float keySpillAmount;
    float keySpillRange;
    float keyEdgeDespill;
    float keySkinProtection;
    float ccBrightness;
    float ccContrast;
    float ccSaturation;
    float ccHue;
    float ccExposure;
    float ccGamma;
    float ccTemperature;
    float ccTint;
    float _pad;
    float bgPositionX;
    float bgPositionY;
    float bgZoom;
    float hueShift;
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

static float minChromaDistance(float3 fg, float4 keyColors[MAX_KEY_COLORS], int count) {
    int safeCount = max(count, 1);
    float2 fgChroma = chromaVector(fg);
    float minDist = distance(fgChroma, chromaVector(keyColors[0].rgb));
    for (int i = 1; i < safeCount; i++) {
        float d = distance(fgChroma, chromaVector(keyColors[i].rgb));
        minDist = min(minDist, d);
    }
    return minDist;
}

static float3 dominantKeyColor(float4 keyColors[MAX_KEY_COLORS], int count) {
    int safeCount = max(count, 1);
    float3 sum = float3(0.0);
    for (int i = 0; i < safeCount; i++) { sum += keyColors[i].rgb; }
    return sum / float(safeCount);
}

static float3 rotateHue(float3 rgb, float angle) {
    float cosA = cos(angle);
    float sinA = sin(angle);
    float3x3 matrix = float3x3(
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
    return saturate(matrix * rgb);
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

    // Temperature / tint approximation. The UI range is -1...1, so scale it
    // to a visibly effective ±20% red/blue shift.
    float temp = filters.ccTemperature * 0.2;
    c.r *= 1.0 + temp;
    c.b *= 1.0 - temp;
    c.g *= 1.0 + filters.ccTint * 0.5;

    return clamp(c, 0.0, 1.0);
}

static float skinToneMask(float3 rgb, float protection) {
    // Continuous skin-tone mask based on YCbCr chroma and luma.
    // Fair skin clusters around Cb ~0.47, Cr ~0.56 with Cr > Cb. Green spill
    // pushes Cb up and Cr down, so the mask widens as protection increases
    // so skin edges still register even when they carry a strong green cast.
    float y = dot(rgb, float3(0.299, 0.587, 0.114));
    float cb = dot(rgb, rgbToCb) + 0.5;
    float cr = dot(rgb, rgbToCr) + 0.5;

    // Warmth: skin has Cr > Cb. At full protection allow slightly negative
    // warmth so green-spilled fair skin is still caught.
    float warm = cr - cb;
    float warmMin = mix(0.02, -0.04, protection);
    float warmMax = mix(0.22, 0.28, protection);
    float warmScore = smoothstep(warmMin, warmMin + 0.04, warm)
                    * (1.0 - smoothstep(warmMax - 0.04, warmMax, warm));

    // Distance from a typical fair-skin centre in CbCr space.
    float2 center = float2(0.47, 0.56);
    float dist = distance(float2(cb, cr), center);
    float distRadius = mix(0.10, 0.18, protection);
    float distScore = 1.0 - smoothstep(distRadius * 0.4, distRadius, dist);

    // Luma: skin is neither very dark nor blown out.
    float lumaMin = mix(0.12, 0.08, protection);
    float lumaScore = smoothstep(lumaMin, lumaMin + 0.10, y)
                    * (1.0 - smoothstep(0.82, 0.95, y));

    return saturate(warmScore * distScore * lumaScore);
}

static float4 applyChromaKey(float4 src, constant FilterParams &filters) {
    int count = max(min(int(filters.keyColorCount), MAX_KEY_COLORS), 1);

    // Apply hue shift to the stored key colors so preset green/blue can be
    // fine-tuned without editing the base color.
    float4 shiftedKeyColors[MAX_KEY_COLORS];
    for (int i = 0; i < MAX_KEY_COLORS; i++) {
        shiftedKeyColors[i] = float4(rotateHue(filters.keyColors[i].rgb, filters.hueShift), 1.0);
    }

    float chromaDist = minChromaDistance(src.rgb, shiftedKeyColors, count);

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

    // Edge proximity: 1.0 right at the key threshold, falling off into
    // solid foreground and solid background. Used to boost despill on edges.
    float edgeProximity = 1.0 - abs(matte - 0.5) * 2.0;
    edgeProximity = pow(edgeProximity, 2.0);

    // Spill range is the distance *past* the key threshold where green/blue
    // fringing on foreground edges should be suppressed. Apply the correction
    // to visible foreground pixels (matte > 0), not to fully keyed-out areas.
    float spillEnd = filters.keyThreshold + filters.keySpillRange;
    float spillFactor = 0.0;
    if (spillEnd > filters.keyThreshold) {
        spillFactor = 1.0 - smoothstep(
            filters.keyThreshold,
            spillEnd,
            chromaDist
        );
    }

    // Boost spill suppression near the edge and by the edge-despill control.
    float edgeBoost = 1.0 + edgeProximity * filters.keyEdgeDespill * 2.0;
    spillFactor *= matte * filters.keySpillAmount * edgeBoost;

    // Split spill suppression between skin and non-skin areas. Skin-tone
    // protection no longer just disables despill on skin; it switches to a
    // skin-safe correction that removes the green/blue cast while preserving
    // warm skin hues, which is essential for fair skin on bald heads/faces.
    float skinMask = skinToneMask(src.rgb, filters.keySkinProtection);
    float skinProtect = saturate(skinMask * filters.keySkinProtection);
    float nonSkinSpill = spillFactor * (1.0 - skinProtect);
    float skinSpill    = spillFactor * skinProtect;

    // Hue-targeted vector despill: subtract the actual selected key color
    // (after hue shift) from the foreground, then add back a target hue to
    // keep the image from going flat or picking up a magenta cast. This is
    // far more direct than the old green/blue channel heuristic.
    float3 keyColor = dominantKeyColor(shiftedKeyColors, count);
    float3 keyDir = keyColor.rgb;
    float keyLen = length(keyDir);
    keyDir = (keyLen > 0.001) ? keyDir / keyLen : float3(0.0, 1.0, 0.0);

    // How much of the pixel is aligned with the key hue beyond the average
    // of the other channels. For a pure green key this becomes the familiar
    // greenExcess = max(0, g - (r+b)/2).
    float3 inverseMask = 1.0 - keyDir;
    float otherSum = dot(src.rgb, inverseMask);
    float otherCount = max(dot(inverseMask, float3(1.0)), 0.001);
    float avgOther = otherSum / otherCount;
    float keyProjection = dot(src.rgb, keyDir);
    float excess = max(0.0, keyProjection - avgOther);

    // Split correction between skin and non-skin. Skin gets a warm target;
    // non-skin gets the complementary hue (e.g. green -> magenta).
    float3 complement = normalize(max(float3(1.0) - keyDir, 0.0));
    float3 skinTarget = normalize(float3(0.95, 0.45, 0.25));
    float3 target = normalize(mix(complement, skinTarget, skinProtect));

    float3 lumaCoeffs = float3(0.299, 0.587, 0.114);
    float keyLuma = dot(keyDir, lumaCoeffs);
    float targetLuma = max(dot(target, lumaCoeffs), 0.001);

    float3 spill = src.rgb;
    float removed = excess * nonSkinSpill + excess * skinSpill;
    spill -= keyDir * removed;

    // Add back enough of the target hue to roughly preserve luminance,
    // but cap the replacement so we don't oversaturate.
    float addAmount = removed * keyLuma / targetLuma;
    addAmount = min(addAmount, removed * 1.5);
    spill += target * addAmount;

    return float4(clamp(spill, 0.0, 1.0), src.a * matte);
}

static float roundedRectSDF(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + float2(radius);
    return length(max(q, 0.0)) - radius;
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

    float2 sourceSize = float2(source.get_width(), source.get_height());

    // Aspect-fit the source into the layer rectangle when requested. The
    // layer's scale becomes a bounding box and the image is letter- or
    // pillar-boxed inside it instead of being stretched.
    float2 displayScale = params.scale;
    if (params.preserveAspect > 0.5 && sourceSize.y > 0.0) {
        float layerAspect = params.scale.x * outputSize.x / max(params.scale.y * outputSize.y, 0.0001);
        float sourceAspect = sourceSize.x / sourceSize.y;
        if (sourceAspect > layerAspect) {
            displayScale = float2(
                params.scale.x,
                params.scale.x * outputSize.x / (sourceAspect * outputSize.y)
            );
        } else {
            displayScale = float2(
                params.scale.y * sourceAspect * outputSize.y / outputSize.x,
                params.scale.y
            );
        }
    }

    bool borderEnabled = params.borderEnabled > 0.5;
    float pixelThickness = max(params.borderWidth, 0.0);
    float pixelRadius = max(params.borderCornerRadius, 0.0);

    // Work in pixel space so border width and corner radius are uniform on
    // screen regardless of layer scale or output aspect.
    float2 pixelP = (outputUV - params.position) * outputSize;
    float2 pixelHalfSize = displayScale * outputSize * 0.5;
    float maxRadius = min(pixelHalfSize.x, pixelHalfSize.y);
    pixelRadius = min(pixelRadius, maxRadius);

    // Anti-alias over ~1 pixel.
    float aa = 1.0;

    float dInner = roundedRectSDF(pixelP, pixelHalfSize, pixelRadius);
    float innerMask = 1.0 - smoothstep(0.0, aa, dInner);

    // No border and outside the layer shape: leave the existing output alone.
    if (!borderEnabled && innerMask <= 0.0) {
        return;
    }

    float2 layerUV = pixelP / (displayScale * outputSize) + 0.5;

    bool hasBackground = (filters.flags & FLAG_CHROMA_KEY_BACKGROUND) != 0u;

    // Sample and filter the source layer (only inside the rounded layer shape).
    float4 src = float4(0.0);
    if (innerMask > 0.0) {
        uint2 sourceCoord = uint2(clamp(layerUV * sourceSize, 0.0, sourceSize - 1.0));
        src = source.read(sourceCoord);

        if ((filters.flags & FLAG_COLOR_CORRECTION) != 0u) {
            src.rgb = applyColorCorrection(src.rgb, filters);
        }

        if ((filters.flags & FLAG_CHROMA_KEY) != 0u) {
            src = applyChromaKey(src, filters);
        }

        src.a *= params.opacity * innerMask;
        // Premultiply so the source-over blend below is correct. Without this,
        // a keyed-out pixel keeps its green RGB at alpha 0 and the background
        // gets tinted/overwritten by green.
        src.rgb *= src.a;
    }

    // Determine destination pixels. With a background, cover-fit it to the
    // layer's on-screen rectangle (using the layer-local UV) so the aspect
    // ratio is preserved, then apply independent pan/zoom from the chroma-key
    // filter. Without a background, read the existing output.
    float4 dst;
    if (hasBackground && innerMask > 0.0) {
        float2 bgSize = float2(background.get_width(), background.get_height());
        float layerAspect = displayScale.x * outputSize.x / (displayScale.y * outputSize.y);
        float bgAspect = bgSize.x / bgSize.y;
        float2 coverScale = (bgAspect > layerAspect)
            ? float2(layerAspect / bgAspect, 1.0)
            : float2(1.0, bgAspect / layerAspect);
        float2 bgCenter = float2(filters.bgPositionX, filters.bgPositionY);
        float zoom = max(filters.bgZoom, 0.01);
        float2 effectiveScale = coverScale * zoom;
        float2 bgUV = (layerUV - bgCenter) / effectiveScale + 0.5;
        bgUV = clamp(bgUV, 0.0, 1.0);
        uint2 bgCoord = uint2(bgUV * bgSize);
        dst = background.read(bgCoord);
    } else {
        dst = output.read(gid);
    }

    // Border sits between the source and the existing output / background.
    float4 border = float4(0.0);
    if (borderEnabled && pixelThickness > 0.0) {
        float dOuter = roundedRectSDF(pixelP, pixelHalfSize + pixelThickness, pixelRadius + pixelThickness);
        float outerMask = 1.0 - smoothstep(0.0, aa, dOuter);
        float borderMask = outerMask * (1.0 - innerMask);
        if (borderMask > 0.0) {
            border = params.borderColor;
            border.a *= borderMask * params.opacity;
            border.rgb *= border.a;
        }
    }

    // Border behind source, source over everything.
    float4 behindSource = border + dst * (1.0 - border.a);
    float4 result = src + behindSource * (1.0 - src.a);
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

/// Copy a source texture into a destination texture of a different size using
/// bilinear sampling. Used when the on-screen drawable is smaller than the
/// program output texture (e.g. during recording or virtual camera output).
kernel void blitScaled(
    texture2d<float, access::sample> source [[texture(0)]],
    texture2d<float, access::write> destination [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
)
{
    if (gid.x >= destination.get_width() || gid.y >= destination.get_height()) { return; }

    constexpr sampler linearSampler(coord::normalized, filter::linear, address::clamp_to_edge);
    float2 uv = float2(gid) / float2(destination.get_width(), destination.get_height());
    float4 color = source.sample(linearSampler, uv);
    destination.write(color, gid);
}
