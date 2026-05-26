import SwiftUI
import SwiftData

// MARK: - Root history sheet

struct HistoryView: View {

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ColorSwatch.timestamp, order: .reverse)
    private var swatches: [ColorSwatch]

    @State private var showingClearConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if swatches.isEmpty {
                    emptyState
                } else {
                    swatchList
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }

                if !swatches.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear All", role: .destructive) {
                            showingClearConfirmation = true
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete all \(swatches.count) saved colors?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) { deleteAll() }
                Button("Cancel",     role: .cancel)      { }
            }
        }
    }

    // MARK: - List

    private var swatchList: some View {
        List {
            ForEach(swatches) { swatch in
                SwatchRow(swatch: swatch)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            .onDelete(perform: delete)
        }
        .listStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            Text("No colors saved yet")
                .font(.title3.weight(.medium))

            Text("Tap the viewfinder to freeze a color.\nIt will appear here automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Delete helpers

    private func delete(at offsets: IndexSet) {
        for i in offsets { modelContext.delete(swatches[i]) }
    }

    private func deleteAll() {
        for swatch in swatches { modelContext.delete(swatch) }
    }
}

// MARK: - Row

private struct SwatchRow: View {
    let swatch: ColorSwatch
    @State private var copied = false

    var body: some View {
        HStack(spacing: 14) {

            // Color swatch block
            RoundedRectangle(cornerRadius: 10)
                .fill(swatch.swiftUIColor)
                .frame(width: 56, height: 56)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

            // Name + hex + timestamp
            VStack(alignment: .leading, spacing: 3) {
                Text(swatch.simpleName)
                    .font(.headline)
                    .lineLimit(1)

                if swatch.name != swatch.simpleName {
                    Text(swatch.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(swatch.hex)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(swatch.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            // Source icon + copy button
            VStack(spacing: 6) {
                Image(systemName: swatch.sourceIcon)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Button {
                    UIPasteboard.general.string = swatch.hex
                    withAnimation(.spring(response: 0.2)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation(.spring(response: 0.2)) { copied = false }
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.callout)
                        .foregroundStyle(copied ? Color.green : Color.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copied ? "Copied" : "Copy hex code")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(swatch.simpleName), \(swatch.hex), saved \(swatch.timestamp.formatted(.relative(presentation: .named)))")
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: ColorSwatch.self, inMemory: true)
}
