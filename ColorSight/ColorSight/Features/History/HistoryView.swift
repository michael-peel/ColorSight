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
        VStack(spacing: 20) {
            Image(systemName: "swatchpalette")
                .font(.system(size: 56))
                .foregroundStyle(.quaternary)

            VStack(spacing: 8) {
                Text("No saved colors yet")
                    .font(.title3.weight(.semibold))

                Text("Identify a color with the camera or eyedropper — every color you lock in is saved here automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)   // shift slightly above true center
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
    @State private var copied       = false
    @State private var sharePayload: SharePayload?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Same UserDefaults key CVDProfile.save()/load() use, so this stays in sync
    // whenever the profile changes in Settings.
    @AppStorage("cvdProfile") private var cvdProfileRaw = CVDProfile.defaultProfile.rawValue
    private var activeCVDProfile: CVDProfile { CVDProfile(rawValue: cvdProfileRaw) ?? .normal }
    @AppStorage("confusionWarningsEnabled") private var confusionWarningsEnabled = true

    private var contextNote: String? {
        CVDColorContext.contextNote(for: swatch.simpleName, hex: swatch.hex, r: swatch.r, g: swatch.g, b: swatch.b, profile: activeCVDProfile)
    }

    // History entries are static, so — unlike the camera — the warning is always
    // shown for a known high-risk color, regardless of any "frozen" state.
    private var confusionWarning: String? {
        guard confusionWarningsEnabled else { return nil }
        return CVDColorContext.confusionWarning(for: swatch.simpleName, r: swatch.r, g: swatch.g, b: swatch.b, profile: activeCVDProfile)
    }

    private var primaryText: String {
        activeCVDProfile == .achromatopsia
            ? "\(CVDColorContext.brightnessLabel(r: swatch.r, g: swatch.g, b: swatch.b)) — \(swatch.simpleName)"
            : swatch.simpleName
    }

    var body: some View {
        // Same reasoning as CameraView/EyedropperView: at accessibility text sizes
        // a fixed-width swatch squeezes wrapped text, so stack vertically instead,
        // and cap the range so a row never grows unreasonably tall.
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityRow
            } else {
                standardRow
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(swatch.simpleName), \(swatch.hex), saved \(swatch.timestamp.formatted(.relative(presentation: .named)))")
        .sheet(item: $sharePayload) { payload in
            ActivityView(items: payload.items, subject: payload.subject)
        }
    }

    // MARK: - Default layout

    private var standardRow: some View {
        HStack(spacing: 14) {

            // Color swatch block
            RoundedRectangle(cornerRadius: 10)
                .fill(swatch.swiftUIColor)
                .frame(width: 56, height: 56)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

            // Name + hex + timestamp
            VStack(alignment: .leading, spacing: 3) {
                Text(primaryText)
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

                if let contextNote {
                    Text(contextNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let confusionWarning {
                    ConfusionWarningBadge(text: confusionWarning)
                }
            }

            Spacer(minLength: 8)

            // Copy + Share buttons
            HStack(spacing: 16) {
                copyButton
                shareButton
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Accessibility-size layout

    /// Swatch + title on top, everything else stacked full-width below, and the
    /// copy/share buttons moved to their own row with visible labels now that
    /// there's room — see CameraView's accessibility card for the same rationale.
    private var accessibilityRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(swatch.swiftUIColor)
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

                Text(primaryText)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            if swatch.name != swatch.simpleName {
                Text(swatch.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

            if let contextNote {
                Text(contextNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let confusionWarning {
                ConfusionWarningBadge(text: confusionWarning)
            }

            HStack(spacing: 20) {
                copyButton
                shareButton
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Shared buttons

    private var copyButton: some View {
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

    private var shareButton: some View {
        Button {
            let img = SwatchImageRenderer.render(swatch: swatch)
            sharePayload = SharePayload(
                items:   [img, "\(swatch.simpleName) – \(swatch.hex)"],
                subject: swatch.simpleName
            )
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share \(swatch.simpleName)")
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: ColorSwatch.self, inMemory: true)
}
