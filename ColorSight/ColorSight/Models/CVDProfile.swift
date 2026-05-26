import Foundation

/// The user's color vision deficiency profile.
/// Stored in UserDefaults under "cvdProfile".
enum CVDProfile: String, CaseIterable, Codable {
    case deuteranopia   // Red-green (most common) — missing M cones
    case protanopia     // Red deficiency — missing L cones
    case tritanopia     // Blue-yellow — missing S cones
    case achromatopsia  // Full color blindness — rod monochromacy
    case custom         // User-defined parameters

    static let defaultProfile: CVDProfile = .deuteranopia
    private static let userDefaultsKey = "cvdProfile"

    /// Loads the saved profile, or returns the default.
    static func load() -> CVDProfile {
        guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
              let profile = CVDProfile(rawValue: raw) else {
            return .defaultProfile
        }
        return profile
    }

    /// Saves this profile to UserDefaults immediately.
    func save() {
        UserDefaults.standard.set(rawValue, forKey: CVDProfile.userDefaultsKey)
    }

    var displayName: String {
        switch self {
        case .deuteranopia:  return "Deuteranopia (Red-Green)"
        case .protanopia:    return "Protanopia (Red)"
        case .tritanopia:    return "Tritanopia (Blue-Yellow)"
        case .achromatopsia: return "Achromatopsia (Full)"
        case .custom:        return "Custom"
        }
    }
}
