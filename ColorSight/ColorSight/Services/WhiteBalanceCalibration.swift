import Foundation

/// Pure, stateless math for white balance calibration. Given a sampled RGB pixel that
/// the user has indicated should be neutral (white or gray) and the camera's current
/// auto-white-balance gains, computes the corrected gains that would make that pixel
/// read as neutral. Same "pure service, easy to unit test" pattern as ColorEngine.
enum WhiteBalanceCalibration {

    struct Gains {
        let red: Double
        let green: Double
        let blue: Double
    }

    /// A reference darker than this (average of R/G/B, 0–255) is rejected — at low
    /// brightness, sensor noise dominates the actual color and the correction would be
    /// more noise than signal.
    private static let minReferenceBrightness = 15.0

    /// Computes corrected white balance gains from a reference sample.
    ///
    /// - Parameters:
    ///   - measuredR/G/B: the sampled pixel's RGB (0–255) — already reflects whatever
    ///     gains the camera was applying when the frame was captured.
    ///   - currentGains: the gains the camera was applying at sample time.
    ///   - maxGain: the device's maximum supported gain
    ///     (`AVCaptureDevice.maxWhiteBalanceGain`).
    /// - Returns: gains clamped to `[1, maxGain]`, or `nil` if the reference is too dark
    ///   to trust.
    static func correctedGains(
        measuredR: Double, measuredG: Double, measuredB: Double,
        currentGains: Gains,
        maxGain: Double
    ) -> Gains? {
        let targetGray = (measuredR + measuredG + measuredB) / 3.0
        guard targetGray >= minReferenceBrightness else { return nil }

        func corrected(_ measured: Double, _ current: Double) -> Double {
            let correction = targetGray / measured
            return min(max(current * correction, 1.0), maxGain)
        }

        return Gains(
            red:   corrected(measuredR, currentGains.red),
            green: corrected(measuredG, currentGains.green),
            blue:  corrected(measuredB, currentGains.blue)
        )
    }
}
