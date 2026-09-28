#include <metal_stdlib>
using namespace metal;

// Must match HueIsolationParams in HueIsolationService.swift.
struct HueIsolationParams {
    uint mode;     // 0 = hue family, 1 = custom color (LAB distance)
    uint family;   // valid when mode == 0. HueFamily.metalIndex: red=0 orange=1 yellow=2
                   // green=3 blue=4 purple=5 pink=6 brown=7 white=8 gray=9 black=10
    float targetL; // valid when mode == 1 — custom target color in LAB
    float targetA;
    float targetB;
    float toleranceSquared;   // squared ΔE — compared without sqrt, same as matchesFamily's thresholds
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

// Converts an RGB triple (values in [0,1]) to CIE LAB (D65 white point).
// Mirrors ColorMath.rgbToLAB in ColorMath.swift exactly — used for the custom
// color isolation target, mode == 1 in HueIsolationParams.
static float3 rgbToLAB(float r, float g, float b) {
    r = (r > 0.04045f) ? pow((r + 0.055f) / 1.055f, 2.4f) : r / 12.92f;
    g = (g > 0.04045f) ? pow((g + 0.055f) / 1.055f, 2.4f) : g / 12.92f;
    b = (b > 0.04045f) ? pow((b + 0.055f) / 1.055f, 2.4f) : b / 12.92f;

    float x = (r * 0.4124564f + g * 0.3575761f + b * 0.1804375f) / 0.95047f;
    float y = (r * 0.2126729f + g * 0.7151522f + b * 0.0721750f) / 1.00000f;
    float z = (r * 0.0193339f + g * 0.1191920f + b * 0.9503041f) / 1.08883f;

    float fx = (x > 0.008856f) ? pow(x, 1.0f/3.0f) : (7.787f * x + 16.0f/116.0f);
    float fy = (y > 0.008856f) ? pow(y, 1.0f/3.0f) : (7.787f * y + 16.0f/116.0f);
    float fz = (z > 0.008856f) ? pow(z, 1.0f/3.0f) : (7.787f * z + 16.0f/116.0f);

    return float3(max(0.0f, 116.0f * fy - 16.0f), 500.0f * (fx - fy), 200.0f * (fy - fz));
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

    bool matches;
    if (params.mode == 1u) {
        float3 lab = rgbToLAB(r, g, b);
        float dl = lab.x - params.targetL;
        float da = lab.y - params.targetA;
        float db = lab.z - params.targetB;
        matches = (dl*dl + da*da + db*db) <= params.toleranceSquared;
    } else {
        float3 hsb = rgbToHSB(r, g, b);
        matches = matchesFamily(hsb.x, hsb.y, hsb.z, params.family);
    }

    float4 out;
    if (matches) {
        out = px;                                          // keep original colour
    } else {
        float luma = 0.299f * r + 0.587f * g + 0.114f * b;  // ITU-R BT.601
        out = float4(luma, luma, luma, 1.0f);
    }

    outTex.write(out, gid);
}

// MARK: - Display pipeline (fullscreen quad for MTKView)

// Must match DisplayParams in HueIsolationMetalView.swift.
struct DisplayParams {
    float2 textureSize;
    float2 drawableSize;
};

struct QuadVertex {
    float4 position [[position]];
    float2 texCoord;
};

/// Vertex shader for a fullscreen triangle strip (4 vertices, no vertex buffer).
/// Computes aspect-fill UV coordinates so the texture fills the MTKView the same
/// way AVCaptureVideoPreviewLayer uses .resizeAspectFill — centers and crops.
vertex QuadVertex displayVertex(
    uint                    vid    [[vertex_id]],
    constant DisplayParams& params [[buffer(0)]]
) {
    constexpr float2 positions[4] = { {-1,-1}, {1,-1}, {-1,1}, {1,1} };

    float viewAspect = params.drawableSize.x / params.drawableSize.y;
    float texAspect  = params.textureSize.x  / params.textureSize.y;

    // Aspect-fill: scale until both screen dimensions are covered; crop the excess.
    float uvRangeX, uvRangeY;
    if (viewAspect >= texAspect) {
        // View wider → fit width, crop height
        uvRangeX = 1.0f;
        uvRangeY = texAspect / viewAspect;
    } else {
        // View taller → fit height, crop width
        uvRangeX = viewAspect / texAspect;
        uvRangeY = 1.0f;
    }
    float uvCropX = (1.0f - uvRangeX) * 0.5f;
    float uvCropY = (1.0f - uvRangeY) * 0.5f;

    float2 clip = positions[vid];
    // Map clip [-1,1] → base UV [0,1]; flip Y (Metal NDC +Y=top, texture (0,0)=top-left)
    float2 uv = float2(
        uvCropX + ( clip.x * 0.5f + 0.5f) * uvRangeX,
        uvCropY + (-clip.y * 0.5f + 0.5f) * uvRangeY
    );

    QuadVertex out;
    out.position = float4(clip, 0.0f, 1.0f);
    out.texCoord = uv;
    return out;
}

fragment float4 displayFragment(
    QuadVertex       in  [[stage_in]],
    texture2d<float> tex [[texture(0)]]
) {
    constexpr sampler s(min_filter::linear, mag_filter::linear, address::clamp_to_edge);
    return tex.sample(s, in.texCoord);
}
