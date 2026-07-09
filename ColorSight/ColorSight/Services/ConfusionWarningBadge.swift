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
        .foregroundStyle(Color.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.15), in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: true)
    }
}
