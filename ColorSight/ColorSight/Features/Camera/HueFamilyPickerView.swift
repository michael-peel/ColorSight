import SwiftUI

/// Horizontally scrollable row of hue-family pills shown at the bottom of the camera
/// view when Hue Isolation Mode is active. Each pill has a color swatch and a label.
struct HueFamilyPickerView: View {

    @Binding var selectedFamily: HueFamily

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HueFamily.allCases.filter { $0 != .white && $0 != .gray && $0 != .black }) { family in
                    HueFamilyPill(family: family, isSelected: family == selectedFamily)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedFamily = family
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Individual pill

private struct HueFamilyPill: View {

    let family:     HueFamily
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Color swatch — decorative; the label carries accessibility meaning.
            Circle()
                .fill(family.swatchColor)
                .frame(width: 12, height: 12)
                .overlay(
                    // Thin border makes white and near-black swatches visible
                    // regardless of background.
                    Circle().strokeBorder(Color.primary.opacity(0.20), lineWidth: 0.5)
                )
                .accessibilityHidden(true)

            Text(family.displayName)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)  // WCAG minimum tap target
        .background {
            Capsule()
                .fill(isSelected ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.ultraThinMaterial))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected
                                ? family.swatchColor.opacity(0.85)
                                : Color.clear,
                            lineWidth: 1.5
                        )
                )
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityLabel(family.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        HueFamilyPickerView(selectedFamily: .constant(.red))
    }
}
