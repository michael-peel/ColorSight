import Foundation

/// Pure, stateless service that generates CVD-profile-aware contextual notes and
/// confusion-pair warnings for an identified color. No UI dependencies — easy to
/// unit test in isolation, same spirit as `ColorEngine`.
enum CVDColorContext {

    // MARK: - Hue category

    /// Coarse bucket used to pick a rule from the tables below. Classified from HSL,
    /// except "brown" (a dark/muted red-orange-yellow) and the achromatic buckets,
    /// which need saturation/lightness as well as hue.
    private enum HueCategory {
        case red, orange, yellow, green, blue, purple, pink, brown, white, gray, black
    }

    private static func hueCategory(h: Double, s: Double, l: Double) -> HueCategory {
        if s < 0.15 {
            if l > 0.85 { return .white }
            if l < 0.15 { return .black }
            return .gray
        }
        // Brown: muted/dark red-orange-yellow — e.g. "Brown" (139,69,19) is h≈25, s≈0.76, l≈0.31.
        if h >= 15 && h < 60 && l < 0.55 && s < 0.80 {
            return .brown
        }
        switch h {
        case 0..<15, 345...360: return .red
        case 15..<45:           return .orange
        case 45..<70:           return .yellow
        case 70..<170:          return .green
        case 170..<255:         return .blue
        case 255..<320:         return .purple
        default:                return .pink   // 320..<345
        }
    }

    /// Perceptual brightness (BT.601 luma), 0–100, rounded to the nearest 5%.
    private static func brightnessPercentRounded5(r: Int, g: Int, b: Int) -> Int {
        let raw = (0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)) / 255.0 * 100.0
        return Int((raw / 5.0).rounded()) * 5
    }

    /// Same formula, rounded to the nearest integer — used for Feature 3's finer buckets.
    private static func brightnessPercent(r: Int, g: Int, b: Int) -> Int {
        let raw = (0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)) / 255.0 * 100.0
        return Int(raw.rounded())
    }

    // MARK: - Feature 1: CVD-aware contextual description

    /// A one-line note explaining what this color likely looks like to the user's CVD
    /// profile, and whether confusion with another color is possible. Returns `nil` for
    /// `.normal` — there's nothing to adapt.
    static func contextNote(for colorName: String, hex: String, r: Int, g: Int, b: Int, profile: CVDProfile) -> String? {
        guard profile != .normal else { return nil }

        let hsl = ColorEngine.rgbToHSL(r: r, g: g, b: b)
        let category = hueCategory(h: hsl.h, s: hsl.s, l: hsl.l)

        if profile == .achromatopsia {
            let pct = brightnessPercentRounded5(r: r, g: g, b: b)
            switch category {
            case .white: return "Appears bright white to you"
            case .black: return "Appears dark/black to you"
            case .gray:  return "Appears as gray to you — brightness: \(pct)%"
            default:     return "You see this as a shade of gray — brightness: \(pct)%"
            }
        }

        switch profile {
        case .deuteranopia:
            switch category {
            case .red:                 return "Reds and greens can look similar — trust the hex value"
            case .green:                return "This may appear brownish or muddy to you"
            case .brown:                return "May look similar to red or green with your profile"
            case .orange:               return "Should be distinguishable — appears yellowish to most with deuteranopia"
            case .yellow:               return "Yellow is usually well-preserved with deuteranopia"
            case .blue, .purple:        return "Blues and purples are typically distinguishable with deuteranopia"
            case .pink:                 return "Pink may appear similar to gray or beige with deuteranopia"
            case .white, .gray, .black: return "Neutral tones are unaffected by deuteranopia"
            }

        case .protanopia:
            switch category {
            case .red:                  return "Reds appear very dark — almost black or brown to you"
            case .green:                 return "May look similar to red or brown with protanopia"
            case .orange:                return "Orange may appear yellow or olive with protanopia"
            case .yellow:                return "Yellow is usually preserved with protanopia"
            case .blue, .purple:         return "Blues are well-preserved with protanopia"
            case .pink:                  return "Pink may appear pale gray or beige with protanopia"
            case .brown:                 return "Brown can be hard to distinguish from red or green with protanopia"
            case .white, .gray, .black:  return "Neutral tones are unaffected by protanopia"
            }

        case .tritanopia:
            switch category {
            case .blue:                       return "Blues and greens can look similar with tritanopia"
            case .yellow:                      return "Yellow may appear pink or violet with tritanopia"
            case .green:                       return "Greens are usually distinguishable with tritanopia"
            case .red, .orange, .pink, .brown: return "Reds are well-preserved with tritanopia"
            case .purple:                      return "Purple may look reddish with tritanopia"
            case .white, .gray, .black:        return "Neutral tones are unaffected by tritanopia"
            }

        case .normal, .achromatopsia:
            return nil   // handled above; unreachable here
        }
    }

    // MARK: - Feature 2: confusion pair warnings

    /// Short warning text for known high-confusion colors under the user's profile, or
    /// `nil` if this color isn't a known risk (or the profile is `.normal`).
    static func confusionWarning(for colorName: String, r: Int, g: Int, b: Int, profile: CVDProfile) -> String? {
        guard profile != .normal else { return nil }

        let hsl = ColorEngine.rgbToHSL(r: r, g: g, b: b)
        let category = hueCategory(h: hsl.h, s: hsl.s, l: hsl.l)
        let lowerName = colorName.lowercased()

        switch profile {
        case .deuteranopia:
            if lowerName.contains("olive") { return "Olive/red confusion risk" }
            switch category {
            case .red:   return "Red/green confusion risk"
            case .green: return "Green/red confusion risk"
            case .brown: return "Brown/green confusion risk"
            default:     return nil
            }

        case .protanopia:
            switch category {
            case .red:   return "Red may appear very dark or black"
            case .brown: return "Brown/red confusion risk"
            default:     return nil
            }

        case .tritanopia:
            switch category {
            case .blue:   return "Blue/green confusion risk"
            case .yellow: return "Yellow/pink confusion risk"
            case .purple: return "Purple/red confusion risk"
            default:      return nil
            }

        case .achromatopsia:
            let pct = brightnessPercent(r: r, g: g, b: b)
            guard hsl.s >= 0.20, (35...65).contains(pct) else { return nil }
            return "Similar brightness to other colors — use hex to distinguish"

        case .normal:
            return nil
        }
    }

    // MARK: - Feature 3: brightness-first mode for achromatopsia

    /// Maps this color's brightness to one of 7 plain-English labels
    /// ("Very Dark" … "Very Light"), for use as the primary display name.
    static func brightnessLabel(r: Int, g: Int, b: Int) -> String {
        switch brightnessPercent(r: r, g: g, b: b) {
        case 0...15:  return "Very Dark"
        case 16...30: return "Dark"
        case 31...45: return "Medium Dark"
        case 46...55: return "Medium"
        case 56...70: return "Medium Light"
        case 71...85: return "Light"
        default:      return "Very Light"   // 86...100
        }
    }
}
