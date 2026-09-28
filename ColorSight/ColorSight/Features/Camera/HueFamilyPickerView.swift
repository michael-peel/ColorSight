import SwiftUI

/// Horizontally scrollable row of hue-family pills plus a "Custom" pill, shown at
/// the bottom of the camera view when Hue Isolation Mode is active. Selecting
/// Custom opens `CustomColorPickerSheet` to pick a saved color from History; once
/// one's been picked, a sensitivity slider and a "back to families" control appear
/// below the row.
struct HueFamilyPickerView: View {

    @Binding var isolationTarget: IsolationTarget

    // Last-used custom color, persisted so it doesn't have to be re-picked from
    // History every session — Hue Isolation itself still starts on a family each
    // session (see CameraViewModel.isolationTarget's default), this is purely a
    // shortcut for re-selecting the same custom color quickly.
    @AppStorage("customIsolationR") private var customR = -1
    @AppStorage("customIsolationG") private var customG = -1
    @AppStorage("customIsolationB") private var customB = -1
    @AppStorage("customIsolationTolerance") private var customTolerance = IsolationTarget.defaultTolerance

    @State private var showingCustomPicker = false
    @State private var lastFamily: HueFamily = .red

    private var hasSavedCustomColor: Bool { customR >= 0 }
    private var isCustomSelected: Bool {
        if case .custom = isolationTarget { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HueFamily.allCases.filter { $0 != .white && $0 != .gray && $0 != .black }) { family in
                        HueFamilyPill(
                            swatchColor: family.swatchColor,
                            label:       family.displayName,
                            isSelected:  isolationTarget == .family(family)
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                lastFamily = family
                                isolationTarget = .family(family)
                            }
                        }
                    }

                    customPill
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            if case .custom(let r, let g, let b, let tolerance) = isolationTarget {
                customControls(r: r, g: g, b: b, tolerance: tolerance)
            }
        }
        .sheet(isPresented: $showingCustomPicker) {
            CustomColorPickerSheet { swatch in
                customR = swatch.r; customG = swatch.g; customB = swatch.b
                isolationTarget = .custom(r: swatch.r, g: swatch.g, b: swatch.b, tolerance: customTolerance)
            }
        }
    }

    // MARK: - Custom pill

    private var customPill: some View {
        HueFamilyPill(
            swatchColor: hasSavedCustomColor
                ? Color(red: Double(customR) / 255.0, green: Double(customG) / 255.0, blue: Double(customB) / 255.0)
                : Color.primary.opacity(0.12),
            label:      "Custom",
            isSelected: isCustomSelected,
            icon:       hasSavedCustomColor ? nil : "plus"
        )
        .onTapGesture {
            if isCustomSelected {
                // Already active — tapping again reopens the picker to change it.
                showingCustomPicker = true
            } else if hasSavedCustomColor {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isolationTarget = .custom(r: customR, g: customG, b: customB, tolerance: customTolerance)
                }
            } else {
                showingCustomPicker = true
            }
        }
    }

    // MARK: - Sensitivity slider + back-to-families (custom mode only)

    @ViewBuilder
    private func customControls(r: Int, g: Int, b: Int, tolerance: Double) -> some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isolationTarget = .family(lastFamily)
                }
            } label: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .accessibilityLabel("Back to hue families")

            Slider(
                value: Binding(
                    get: { tolerance },
                    set: { newValue in
                        customTolerance = newValue
                        isolationTarget = .custom(r: r, g: g, b: b, tolerance: newValue)
                    }
                ),
                in: 5...40
            )
            .tint(Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0))
            .accessibilityLabel("Match sensitivity")
            .accessibilityValue("\(Int(tolerance))")
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Individual pill

private struct HueFamilyPill: View {

    let swatchColor: Color
    let label:       String
    let isSelected:  Bool
    var icon:        String? = nil   // shown instead of a color dot (e.g. an empty custom slot)

    var body: some View {
        HStack(spacing: 6) {
            // Color swatch — decorative; the label carries accessibility meaning.
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
            } else {
                Circle()
                    .fill(swatchColor)
                    .frame(width: 12, height: 12)
                    .overlay(
                        // Thin border makes white and near-black swatches visible
                        // regardless of background.
                        Circle().strokeBorder(Color.primary.opacity(0.20), lineWidth: 0.5)
                    )
                    .accessibilityHidden(true)
            }

            Text(label)
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
                                ? swatchColor.opacity(0.85)
                                : Color.clear,
                            lineWidth: 1.5
                        )
                )
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        HueFamilyPickerView(isolationTarget: .constant(.family(.red)))
    }
}
