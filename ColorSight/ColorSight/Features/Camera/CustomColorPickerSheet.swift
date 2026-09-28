import SwiftUI
import SwiftData

/// Sheet for picking a custom Hue Isolation target from History. Reuses the same
/// SwiftData query and empty-state shape as HistoryView.
struct CustomColorPickerSheet: View {

    @Environment(\.dismiss) private var dismiss

    @Query(sort: \ColorSwatch.timestamp, order: .reverse)
    private var swatches: [ColorSwatch]

    let onSelect: (ColorSwatch) -> Void

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if swatches.isEmpty {
                    emptyState
                } else {
                    swatchGrid
                }
            }
            .navigationTitle("Choose a Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Grid

    private var swatchGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(swatches) { swatch in
                    Button {
                        onSelect(swatch)
                        dismiss()
                    } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(swatch.swiftUIColor)
                                .frame(height: 64)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                                )
                            Text(swatch.simpleName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(swatch.simpleName), \(swatch.hex)")
                }
            }
            .padding(16)
        }
    }

    // MARK: - Empty state (mirrors HistoryView.emptyState)

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "swatchpalette")
                .font(.system(size: 56))
                .foregroundStyle(.quaternary)

            VStack(spacing: 8) {
                Text("No saved colors yet")
                    .font(.title3.weight(.semibold))

                Text("Freeze the camera or use the eyedropper to save a color first — then you can isolate it here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }
}

#Preview {
    CustomColorPickerSheet(onSelect: { _ in })
        .modelContainer(for: ColorSwatch.self, inMemory: true)
}
