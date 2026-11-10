//
//  FacePuppet.metal
//  FreeStage
//
//  Render pass that maps a puppet texture onto the 468-point MediaPipe face
//  mesh and composites it over the live camera frame.
//

#include <metal_stdlib>
using namespace metal;

struct PuppetVertexIn {
    float2 position [[attribute(0)]];  // normalized 0..1 screen coords
    float2 uv       [[attribute(1)]];  // puppet texture UV
};

struct PuppetVertexOut {
    float4 position [[position]];
    float2 uv;
    float2 screenUV;
};

vertex PuppetVertexOut puppetVertex(PuppetVertexIn in [[stage_in]]) {
    PuppetVertexOut out;
    float2 clip = in.position * 2.0f - 1.0f;
    // Metal clip space has +Y up; our normalized screen coords have +Y down.
    out.position = float4(clip.x, -clip.y, 0.0f, 1.0f);
    out.uv = in.uv;
    out.screenUV = in.position;
    return out;
}

fragment float4 copyCameraFragment(
    PuppetVertexOut in [[stage_in]],
    texture2d<float> cameraTexture [[texture(0)]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    return cameraTexture.sample(s, in.screenUV);
}

struct PuppetFragmentUniforms {
    float opacity;
};

fragment float4 puppetFragment(
    PuppetVertexOut in [[stage_in]],
    constant PuppetFragmentUniforms &uniforms [[buffer(0)]],
    texture2d<float> cameraTexture [[texture(0)]],
    texture2d<float> puppetTexture [[texture(1)]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    float4 cameraColor = cameraTexture.sample(s, in.screenUV);
    float4 puppetColor = puppetTexture.sample(s, in.uv);

    float alpha = puppetColor.a * uniforms.opacity;
    float3 outColor = mix(cameraColor.rgb, puppetColor.rgb, alpha);
    return float4(outColor, 1.0f);
}

fragment float4 wireframeFragment(
    PuppetVertexOut in [[stage_in]],
    constant PuppetFragmentUniforms &uniforms [[buffer(0)]]
) {
    return float4(0.0f, 1.0f, 0.0f, 1.0f);
}
