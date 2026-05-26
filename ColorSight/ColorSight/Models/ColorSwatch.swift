import Foundation
import SwiftData
import SwiftUI

/// A color the user has saved to their history (by freezing the camera or lifting
/// the eyedropper loupe). Stored in SwiftData / SQLite.
@Model
final class ColorSwatch {

    // MARK: - Stored fields

    var id:         UUID
    var simpleName: String      // e.g. "Sky Blue"  — primary display
    var name:       String      // e.g. "Cornflower Blue" — specific DB match
    var hex:        String      // e.g. "#6495ED"
    var r:          Int
    var g:          Int
    var b:          Int
    var hue:        Double      // 0–360
    var saturation: Double      // 0–1
    var lightness:  Double      // 0–1
    var timestamp:  Date
    var source:     String      // "camera" | "eyedropper"

    // MARK: - Init

    init(from color: IdentifiedColor, source: String) {
        id         = UUID()
        simpleName = color.simpleName
        name       = color.name
        hex        = color.hex
        r          = color.rgb.r
        g          = color.rgb.g
        b          = color.rgb.b
        hue        = color.hsl.h
        saturation = color.hsl.s
        lightness  = color.hsl.l
        timestamp  = Date()
        self.source = source
    }

    // MARK: - Derived

    /// Reconstructs the color as a SwiftUI Color for rendering swatches.
    var swiftUIColor: Color {
        Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
    }

    /// SF Symbol name for the source of this swatch.
    var sourceIcon: String {
        source == "camera" ? "camera" : "eyedropper.halffull"
    }
}
