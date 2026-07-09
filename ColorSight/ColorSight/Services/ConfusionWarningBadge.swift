import SwiftUI

/// Small warning capsule shown when the identified color falls into a known
/// high-confusion pair for the user's active CVD profile. See `CVDColorContext`.
struct ConfusionWarningBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Text("⚠️")
            Text(text)
        }
        .font(.caption2.bold())
        // A light orange tint with orange text reads fine on a plain background, but
        // washes out against the live camera feed showing through the card's
        // ultraThinMaterial. Solid fill + dark text keeps it legible over any backdrop.
        .foregroundStyle(Color(red: 0.35, green: 0.16, blue: 0))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.9), in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.orange, lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: true)
    }
}
