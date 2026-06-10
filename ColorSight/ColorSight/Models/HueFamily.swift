import SwiftUI

/// A broad perceptual hue category used by Hue Isolation Mode.
///
/// Each case knows how to classify a pixel by testing its HSB values.
/// `matches(r:g:b:)` is the sole pixel-classification authority —
/// HueIsolationService delegates all decisions here.
enum HueFamily: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple, pink
    case brown, white, gray, black

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    /// Reference swatch shown in the pill selector.
    /// Chosen for maximum saturation/brightness to aid legibility across CVD types;
    /// the text label is the primary affordance.
    var swatchColor: Color {
        switch self {
        case .red:    return Color(red: 0.882, green: 0.114, blue: 0.282) // #E11D48
        case .orange: return Color(red: 0.976, green: 0.451, blue: 0.086) // #F97316
        case .yellow: return Color(red: 0.984, green: 0.749, blue: 0.141) // #FBBF24
        case .green:  return Color(red: 0.133, green: 0.773, blue: 0.369) // #22C55E
        case .blue:   return Color(red: 0.231, green: 0.510, blue: 0.965) // #3B82F6
        case .purple: return Color(red: 0.659, green: 0.333, blue: 0.969) // #A855F7
        case .pink:   return Color(red: 0.925, green: 0.286, blue: 0.600) // #EC4899
        case .brown:  return Color(red: 0.573, green: 0.251, blue: 0.055) // #92400E
        case .white:  return Color.white
        case .gray:   return Color(white: 0.50)
        case .black:  return Color(white: 0.10)
        }
    }

    // MARK: - Pixel classification

    /// Returns true if the pixel with the given RGB values belongs to this hue family.
    ///
    /// Steps:
    /// 1. Convert RGB → HSB (hue 0–360°, saturation 0–1, brightness 0–1).
    /// 2. If saturation < 0.12, pixel is achromatic — only .white/.gray/.black match.
    /// 3. Otherwise test hue angle against each family's range + minimum S/B thresholds.
    ///
    /// Priority rule for the brown/orange overlap (hue 10–45°):
    ///   .brown  requires brightness < 0.45
    ///   .orange requires brightness ≥ 0.45
    /// The ranges are mutually exclusive — no pixel can satisfy both.
    ///
    /// Called per-pixel on a background thread; uses Float arithmetic throughout.
    func matches(r: UInt8, g: UInt8, b: UInt8) -> Bool {
        let rf = Float(r) / 255.0
        let gf = Float(g) / 255.0
        let bf = Float(b) / 255.0

        let maxC  = max(rf, gf, bf)
        let minC  = min(rf, gf, bf)
        let delta = maxC - minC

        let brightness = maxC
        let saturation = maxC > 0.001 ? delta / maxC : 0

        // Achromatic guard — desaturated pixels only match the neutral families.
        if saturation < 0.12 {
            switch self {
            case .white: return brightness > 0.80
            case .gray:  return brightness >= 0.15 && brightness <= 0.80
            case .black: return brightness < 0.15
            default:     return false
            }
        }

        // Hue angle in [0, 360).
        // When maxC == rf, (gf - bf)/delta is in [-1, 1]; negative values become
        // [300°, 360°) after the +360 correction, correctly representing warm reds.
        var hue: Float = 0
        if delta > 0.001 {
            if maxC == rf {
                hue = ((gf - bf) / delta).truncatingRemainder(dividingBy: 6) * 60
            } else if maxC == gf {
                hue = ((bf - rf) / delta + 2) * 60
            } else {
                hue = ((rf - gf) / delta + 4) * 60
            }
            if hue < 0 { hue += 360 }
        }

        switch self {
        case .red:
            // Hue wraps at 0°/360°; accept both flanks.
            return saturation >= 0.35 && brightness >= 0.15 &&
                   (hue < 15 || hue >= 345)

        case .orange:
            // brightness >= 0.45 enforces priority over .brown in the shared hue band.
            return saturation >= 0.35 && brightness >= 0.45 && hue >= 15 && hue < 45

        case .yellow:
            return saturation >= 0.30 && hue >= 45 && hue < 70

        case .green:
            return saturation >= 0.20 && hue >= 70 && hue < 150

        case .blue:
            return saturation >= 0.20 && hue >= 150 && hue < 260

        case .purple:
            return saturation >= 0.25 && hue >= 260 && hue < 310

        case .pink:
            return saturation >= 0.20 && brightness >= 0.40 && hue >= 310 && hue < 345

        case .brown:
            // Shares hue band with .orange but claims the darker end (brightness < 0.45).
            // Covers rust, sienna, chestnut, chocolate — all warm, dark, and earthy.
            return saturation >= 0.25 && brightness < 0.45 && hue >= 10 && hue < 40

        case .white:
            return brightness > 0.80 && saturation < 0.20

        case .gray:
            return brightness >= 0.15 && brightness <= 0.80 && saturation < 0.15

        case .black:
            return brightness < 0.15
        }
    }
}
