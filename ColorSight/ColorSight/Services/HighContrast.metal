#include <metal_stdlib>
using namespace metal;

// Must match HighContrastParams in HighContrastService.swift.
struct HighContrastParams {
    float contrast;        // multiplier applied around the midpoint of brightness (V)
    float brightnessLift;  // flat additive lift to brightness (V) — helps dark scenes
};

// Converts an RGB triple (values in [0,1]) to HSB.
static float3 rgbToHSB(float r, float g, float b) {
    float maxC  = max(r, max(g, b));
    float minC  = min(r, min(g, b));
    float delta = maxC - minC;

    float brightness = maxC;
    float saturation = (maxC > 0.001f) ? delta / maxC : 0.0f;

    float hue = 0.0f;
    if (delta > 0.001f) {
        if (maxC == r) {
            hue = fmod((g - b) / delta, 6.0f) * 60.0f;
        } else if (maxC == g) {
            hue = ((b - r) / delta + 2.0f) * 60.0f;
        } else {
            hue = ((r - g) / delta + 4.0f) * 60.0f;
        }
        if (hue < 0.0f) hue += 360.0f;
    }

    return float3(hue, saturation, brightness);
}

// Converts HSB (hue in [0,360), saturation/brightness in [0,1]) back to RGB.
static float3 hsbToRGB(float h, float s, float v) {
    float c  = v * s;
    float hp = h / 60.0f;
    float x  = c * (1.0f - fabs(fmod(hp, 2.0f) - 1.0f));

    float3 rgb1;
    if      (hp < 1.0f) rgb1 = float3(c, x, 0.0f);
    else if (hp < 2.0f) rgb1 = float3(x, c, 0.0f);
    else if (hp < 3.0f) rgb1 = float3(0.0f, c, x);
    else if (hp < 4.0f) rgb1 = float3(0.0f, x, c);
    else if (hp < 5.0f) rgb1 = float3(x, 0.0f, c);
    else                rgb1 = float3(c, 0.0f, x);

    float m = v - c;
    return rgb1 + float3(m, m, m);
}

/// High Contrast kernel — boosts brightness/contrast for on-screen visibility in low
/// light. Hue and saturation are read and written back completely unchanged; only the
/// brightness (V) channel is adjusted, so a color's identity never shifts (e.g. blue
/// never reads as purple). This is a display-only filter: CameraViewModel's
/// color-sampling delegate always reads the original, unprocessed pixel buffer — this
/// kernel only ever writes to a separate output texture for AVSampleBufferDisplayLayer.
kernel void highContrastEnhance(
    texture2d<float, access::read>  inTex  [[ texture(0) ]],
    texture2d<float, access::write> outTex [[ texture(1) ]],
    constant HighContrastParams&    params [[ buffer(0)  ]],
    uint2                           gid    [[ thread_position_in_grid ]]
) {
    if (gid.x >= inTex.get_width() || gid.y >= inTex.get_height()) return;

    float4 px  = inTex.read(gid);
    float3 hsb = rgbToHSB(px.r, px.g, px.b);

    float v = hsb.z;
    v = (v - 0.5f) * params.contrast + 0.5f + params.brightnessLift;
    v = clamp(v, 0.0f, 1.0f);

    float3 rgb = hsbToRGB(hsb.x, hsb.y, v);
    outTex.write(float4(rgb, px.a), gid);
}
