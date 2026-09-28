import SwiftUI

/// What Hue Isolation Mode is currently isolating: either one of the built-in hue
/// families, or a custom color the user picked from History.
///
/// A sibling type to `HueFamily` rather than a case on it — `HueFamily` is
/// `CaseIterable` (its cases drive `HueFamilyPickerView`'s `ForEach` and the
/// `testMetalIndexMatchesCaseOrder` guard), which an associated-value case can't
/// participate in.
enum IsolationTarget: Equatable {
    case family(HueFamily)
    case custom(r: Int, g: Int, b: Int, tolerance: Double)

    /// Default match tolerance (ΔE, simplified CIE76 — see `ColorMath`) for a
    /// freshly picked custom color.
    static let defaultTolerance = 15.0

    var swatchColor: Color {
        switch self {
        case .family(let family):
            return family.swatchColor
        case .custom(let r, let g, let b, _):
            return Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
        }
    }

    var displayName: String {
        switch self {
        case .family(let family): return family.displayName
        case .custom:              return "Custom"
        }
    }

    // MARK: - Pixel classification (CPU fallback only — see HueIsolationService)

    /// Returns true if the pixel with the given RGB values belongs to this
    /// target. Family case delegates to `HueFamily.matches()`; custom case
    /// compares LAB distance to `tolerance`. Same sole-classification-authority
    /// role `HueFamily.matches()` plays for the family case, mirrored by the
    /// Metal kernel's `matchesFamily()`/custom-mode branch for the real-time GPU
    /// path — this is only exercised by the CPU fallback, which never runs on
    /// Metal-capable hardware (all iOS 26+ devices).
    nonisolated func matches(r: Int, g: Int, b: Int) -> Bool {
        switch self {
        case .family(let family):
            return family.matches(r: UInt8(r), g: UInt8(g), b: UInt8(b))
        case .custom(let tr, let tg, let tb, let tolerance):
            let targetLAB = ColorMath.rgbToLAB(r: tr, g: tg, b: tb)
            let pixelLAB  = ColorMath.rgbToLAB(r: r, g: g, b: b)
            return ColorMath.squaredDeltaE(pixelLAB, targetLAB) <= tolerance * tolerance
        }
    }
}
