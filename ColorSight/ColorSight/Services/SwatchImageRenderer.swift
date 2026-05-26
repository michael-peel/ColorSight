import SwiftUI

/// Renders a shareable swatch card image from a color.
/// Must be called on the MainActor (ImageRenderer requirement).
@MainActor
enum SwatchImageRenderer {

    // MARK: - Public overloads

    static func render(color: IdentifiedColor) -> UIImage {
        render(
            simpleName: color.simpleName,
            name:        color.name,
            hex:         color.hex,
            rgbDisplay:  color.rgbDisplayString,
            swatchColor: color.swiftUIColor
        )
    }

    static func render(swatch: ColorSwatch) -> UIImage {
        render(
            simpleName: swatch.simpleName,
            name:        swatch.name,
            hex:         swatch.hex,
            rgbDisplay:  "R \(swatch.r)  G \(swatch.g)  B \(swatch.b)",
            swatchColor: swatch.swiftUIColor
        )
    }

    // MARK: - Core renderer

    private static func render(
        simpleName: String,
        name: String,
        hex: String,
        rgbDisplay: String,
        swatchColor: Color
    ) -> UIImage {
        let card = SwatchExportCard(
            simpleName: simpleName,
            name:        name,
            hex:         hex,
            rgbDisplay:  rgbDisplay,
            swatchColor: swatchColor
        )
        // Render in light mode so the card is always on white — consistent
        // regardless of the device's dark-mode setting.
        let renderer = ImageRenderer(content: card.environment(\.colorScheme, .light))
        renderer.scale = 3.0   // @3x — crisp on all retina devices
        return renderer.uiImage ?? UIImage()
    }
}

// MARK: - Export card view (never shown directly in UI — only rendered to UIImage)

private struct SwatchExportCard: View {
    let simpleName: String
    let name:       String
    let hex:        String
    let rgbDisplay: String
    let swatchColor: Color

    private let cardWidth: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {

            // ── Color block ───────────────────────────────────────────────
            swatchColor
                .frame(width: cardWidth, height: 160)

            // ── Info panel ────────────────────────────────────────────────
            VStack(spacing: 0) {
                VStack(spacing: 5) {
                    Text(simpleName)
                        .font(.title2.bold())
                        .foregroundColor(Color(.label))
                        .multilineTextAlignment(.center)

                    if name != simpleName {
                        Text(name)
                            .font(.subheadline)
                            .foregroundColor(Color(.secondaryLabel))
                    }

                    Text(hex)
                        .font(.system(.callout, design: .monospaced).weight(.medium))
                        .foregroundColor(Color(.secondaryLabel))
                        .padding(.top, 4)

                    Text(rgbDisplay)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Color(.tertiaryLabel))
                }
                .padding(.top, 18)
                .padding(.horizontal, 24)

                Divider()
                    .padding(.horizontal, 24)
                    .padding(.top, 14)

                Text("ColorSight")
                    .font(.caption2.weight(.medium))
                    .tracking(1.5)
                    .foregroundColor(Color(.tertiaryLabel))
                    .padding(.vertical, 10)
            }
            .frame(width: cardWidth)
            .background(Color(.systemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        // Outer padding + white background so the shadow has room to render
        .padding(28)
        .background(Color(.systemBackground))
    }
}
