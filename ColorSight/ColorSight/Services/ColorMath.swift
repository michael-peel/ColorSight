import Foundation

/// Shared RGB ↔ LAB conversion and perceptual distance. Pure, stateless,
/// thread-safe — same pattern as `ColorEngine`/`HueFamily`. Used by
/// `ColorEngine`'s nearest-name matching and by `IsolationTarget`'s custom-color
/// matching (Hue Isolation Mode).
enum ColorMath {

    struct LAB: Sendable {
        let l: Double
        let a: Double
        let b: Double
    }

    // MARK: - RGB → LAB

    nonisolated static func rgbToLAB(r: Int, g: Int, b: Int) -> LAB {
        // Step 1: normalize to 0–1
        var rr = Double(r) / 255.0
        var gg = Double(g) / 255.0
        var bb = Double(b) / 255.0

        // Step 2: sRGB gamma → linear
        rr = rr > 0.04045 ? pow((rr + 0.055) / 1.055, 2.4) : rr / 12.92
        gg = gg > 0.04045 ? pow((gg + 0.055) / 1.055, 2.4) : gg / 12.92
        bb = bb > 0.04045 ? pow((bb + 0.055) / 1.055, 2.4) : bb / 12.92

        // Step 3: linear RGB → XYZ (sRGB / D65)
        let x = (rr * 0.4124564 + gg * 0.3575761 + bb * 0.1804375) / 0.95047
        let y = (rr * 0.2126729 + gg * 0.7151522 + bb * 0.0721750) / 1.00000
        let z = (rr * 0.0193339 + gg * 0.1191920 + bb * 0.9503041) / 1.08883

        // Step 4: XYZ → LAB
        func f(_ t: Double) -> Double {
            t > 0.008856 ? pow(t, 1.0/3.0) : (7.787 * t + 16.0/116.0)
        }

        let fx = f(x)
        let fy = f(y)
        let fz = f(z)

        return LAB(
            l: max(0, 116.0 * fy - 16.0),
            a: 500.0 * (fx - fy),
            b: 200.0 * (fy - fz)
        )
    }

    // MARK: - Distance

    /// Squared Euclidean distance in LAB (a simplified ΔE, no `sqrt`). Good enough
    /// for nearest-neighbor and tolerance comparisons — full CIE2000 isn't needed
    /// here, and skipping `sqrt` keeps hot-path comparisons cheap.
    nonisolated static func squaredDeltaE(_ a: LAB, _ b: LAB) -> Double {
        let dl = a.l - b.l; let da = a.a - b.a; let db = a.b - b.b
        return dl*dl + da*da + db*db
    }

    /// Euclidean distance in LAB (`sqrt` of `squaredDeltaE`) — use only where the
    /// actual ΔE magnitude matters (e.g. a user-facing tolerance value); prefer
    /// `squaredDeltaE` for pure comparisons.
    nonisolated static func deltaE(_ a: LAB, _ b: LAB) -> Double {
        squaredDeltaE(a, b).squareRoot()
    }
}
