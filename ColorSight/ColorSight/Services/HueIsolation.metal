#include <metal_stdlib>
using namespace metal;

// Must match HueIsolationParams in HueIsolationService.swift.
struct HueIsolationParams {
    uint family;   // HueFamily.metalIndex: red=0 orange=1 yellow=2 green=3 blue=4
                   //                       purple=5 pink=6 brown=7 white=8 gray=9 black=10
};

// Converts an RGB triple (values in [0,1]) to HSB.
// Returns float3(hue°, saturation, brightness) where hue is in [0, 360).
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

// Returns true if the pixel (hue°, sat, bri) belongs to the given family index.
// Thresholds mirror HueFamily.matches() in HueFamily.swift exactly.
static bool matchesFamily(float hue, float sat, float bri, uint family) {
    // Achromatic guard — desaturated pixels only qualify for white / gray / black.
    if (sat < 0.12f) {
        if (family == 8u) return bri > 0.80f;
        if (family == 9u) return bri >= 0.15f && bri <= 0.80f;
        if (family == 10u) return bri < 0.15f;
        return false;
    }

    switch (family) {
        case 0u:  // red — hue wraps at 0°/360°
            return sat >= 0.35f && bri >= 0.15f && (hue < 15.0f || hue >= 345.0f);
        case 1u:  // orange — brightness >= 0.45 enforces priority over brown
            return sat >= 0.35f && bri >= 0.45f && hue >= 15.0f && hue < 45.0f;
        case 2u:  // yellow
            return sat >= 0.30f && hue >= 45.0f && hue < 70.0f;
        case 3u:  // green
            return sat >= 0.20f && hue >= 70.0f && hue < 150.0f;
        case 4u:  // blue
            return sat >= 0.20f && hue >= 150.0f && hue < 260.0f;
        case 5u:  // purple
            return sat >= 0.25f && hue >= 260.0f && hue < 310.0f;
        case 6u:  // pink
            return sat >= 0.20f && bri >= 0.40f && hue >= 310.0f && hue < 345.0f;
        case 7u:  // brown — dark end of the orange-red hue band
            return sat >= 0.25f && bri < 0.45f && hue >= 10.0f && hue < 40.0f;
        case 8u:  // white
            return bri > 0.80f && sat < 0.20f;
        case 9u:  // gray
            return bri >= 0.15f && bri <= 0.80f && sat < 0.15f;
        case 10u: // black
            return bri < 0.15f;
        default:
            return false;
    }
}

/// Hue isolation kernel.
///
/// Each thread processes one pixel:
///   • Reads RGBA from `inTex`  (bgra8Unorm — Metal normalises byte order to RGBA).
///   • Classifies the pixel via HSB against `params.family`.
///   • Writes the original colour if it matches; otherwise writes the BT.601 luma
///     as a grayscale RGBA pixel.
///
/// Threads are dispatched with `dispatchThreads(_:threadsPerThreadgroup:)` so the
/// shader must guard against out-of-bounds gid values.
kernel void hueIsolate(
    texture2d<float, access::read>  inTex  [[ texture(0) ]],
    texture2d<float, access::write> outTex [[ texture(1) ]],
    constant HueIsolationParams&    params [[ buffer(0)  ]],
    uint2                           gid    [[ thread_position_in_grid ]]
) {
    if (gid.x >= inTex.get_width() || gid.y >= inTex.get_height()) return;

    float4 px = inTex.read(gid);   // float4(r, g, b, a) in [0,1]
    float r = px.r, g = px.g, b = px.b;

    float3 hsb = rgbToHSB(r, g, b);

    float4 out;
    if (matchesFamily(hsb.x, hsb.y, hsb.z, params.family)) {
        out = px;                                          // keep original colour
    } else {
        float luma = 0.299f * r + 0.587f * g + 0.114f * b;  // ITU-R BT.601
        out = float4(luma, luma, luma, 1.0f);
    }

    outTex.write(out, gid);
}
