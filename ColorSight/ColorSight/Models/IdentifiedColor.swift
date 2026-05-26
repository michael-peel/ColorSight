import SwiftUI

/// The result of identifying a color — returned by ColorEngine.
struct IdentifiedColor: Equatable {
    let simpleName: String                  // e.g. "Light Blue" — plain English, primary display
    let name: String                        // e.g. "Sky Blue" — specific DB match, secondary display
    let hex: String                         // e.g. "#87CEEB"
    let rgb: RGBComponents
    let hsl: HSLComponents
    let cvdDescription: String              // Profile-adapted description (v1: algorithmic)

    // MARK: - Component types

    struct RGBComponents: Equatable {
        let r: Int
        let g: Int
        let b: Int
    }

    struct HSLComponents: Equatable {
        let h: Double   // 0–360
        let s: Double   // 0–1
        let l: Double   // 0–1
    }

    // MARK: - SwiftUI convenience

    /// The identified color as a SwiftUI Color for rendering swatches.
    var swiftUIColor: Color {
        Color(
            red: Double(rgb.r) / 255.0,
            green: Double(rgb.g) / 255.0,
            blue: Double(rgb.b) / 255.0
        )
    }

    /// Formatted RGB string for display.
    var rgbDisplayString: String {
        "R \(rgb.r)  G \(rgb.g)  B \(rgb.b)"
    }

    // MARK: - Equatable
    static func == (lhs: IdentifiedColor, rhs: IdentifiedColor) -> Bool {
        lhs.hex == rhs.hex
    }
}
