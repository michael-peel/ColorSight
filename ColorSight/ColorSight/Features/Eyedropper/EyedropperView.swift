import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Root view

struct EyedropperView: View {

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // See CameraView — scales the standard card's height cap with Dynamic Type so
    // larger-but-not-yet-accessibility text sizes don't truncate the CVD note.
    @ScaledMetric(relativeTo: .body) private var standardCardMaxHeight: CGFloat = 180

    @State private var viewModel     = EyedropperViewModel()
    @State private var pickerItem:   PhotosPickerItem?
    @State private var isDragging    = false

    // Same UserDefaults key CVDProfile.save()/load() use, so this stays in sync
    // whenever the profile changes in Settings.
    @AppStorage("cvdProfile") private var cvdProfileRaw = CVDProfile.defaultProfile.rawValue
    private var activeCVDProfile: CVDProfile { CVDProfile(rawValue: cvdProfileRaw) ?? .normal }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isLoadingImage {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)

            } else if let image = viewModel.displayImage {
                imageCanvas(image: image)
            } else {
                emptyState
            }

            // Top bar always visible
            topBar
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await viewModel.loadImage(from: newItem) }
        }
        // Save the final identified color to history when the user closes the eyedropper.
        // Doing it here (once on dismiss) rather than on every finger lift means the user
        // can freely drag around without flooding history with intermediate samples.
        .onDisappear {
            if let color = viewModel.identifiedColor {
                modelContext.insert(ColorSwatch(from: color, source: "eyedropper"))
            }
        }
        .statusBar(hidden: true)
    }

    // MARK: - Empty state (no photo selected yet)

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundStyle(.white.opacity(0.6))

            Text("Open a photo to identify its colors")
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choose Photo", systemImage: "photo")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: Capsule())
            }
        }
    }

    // MARK: - Image canvas (photo + gesture + loupe + color card)

    private func imageCanvas(image: UIImage) -> some View {
        GeometryReader { geo in
            let viewSize  = geo.size
            let imgRect   = imageRect(imageSize: image.size, in: viewSize)
            let sampleView = CGPoint(
                x: imgRect.minX + viewModel.sampleNorm.x * imgRect.width,
                y: imgRect.minY + viewModel.sampleNorm.y * imgRect.height
            )

            ZStack {
                // MARK: Full-screen photo
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // MARK: Sample crosshair dot
                if !isDragging {
                    Circle()
                        .strokeBorder(.white, lineWidth: 2)
                        .frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .position(sampleView)
                        .animation(.easeInOut(duration: 0.1), value: sampleView)
                }

                // MARK: Loupe (only while dragging)
                if isDragging {
                    loupeView(image: image, imgRect: imgRect)
                        .position(loupePosition(sampleView: sampleView, viewSize: viewSize))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                        .animation(.spring(response: 0.2), value: sampleView)
                }

                // MARK: Color card
                VStack {
                    Spacer()
                    colorInfoCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        withAnimation(.interactiveSpring(response: 0.15)) {
                            isDragging = true
                        }
                        let loc = value.location
                        let cx  = max(imgRect.minX, min(imgRect.maxX, loc.x))
                        let cy  = max(imgRect.minY, min(imgRect.maxY, loc.y))
                        let norm = CGPoint(
                            x: (cx - imgRect.minX) / imgRect.width,
                            y: (cy - imgRect.minY) / imgRect.height
                        )
                        viewModel.sampleColor(atNormalized: norm)
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.2)) {
                            isDragging = false
                        }
                        // Announce the final color once the user lifts their finger.
                        viewModel.announceCurrentColor()
                        // Note: history save happens on dismiss, not on every finger lift.
                        // That way the user can freely sample around and only the final
                        // color they settle on gets added to history.
                    }
            )
        }
    }

    // MARK: - Loupe

    private let loupeDiameter: CGFloat = 120

    private func loupeView(image: UIImage, imgRect: CGRect) -> some View {
        let zoom: CGFloat = 3.0
        let loupeW     = imgRect.width  * zoom
        let loupeH     = imgRect.height * zoom
        // SwiftUI centers children in a ZStack, so the image's center sits at (60,60)
        // before any offset is applied.  We want sampleNorm → center of loupe (60,60):
        //   (60 - loupeW/2 + sampleNorm.x * loupeW) + offsetX = 60
        //   offsetX = loupeW/2 - sampleNorm.x * loupeW = loupeW * (0.5 - sampleNorm.x)
        let offsetX    = loupeW * (0.5 - viewModel.sampleNorm.x)
        let offsetY    = loupeH * (0.5 - viewModel.sampleNorm.y)

        return ZStack {
            // Magnified image
            Image(uiImage: image)
                .resizable()
                .frame(width: loupeW, height: loupeH)
                .offset(x: offsetX, y: offsetY)

            // Centre crosshair
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 1.5)
                    .frame(width: 10, height: 10)
                Rectangle()
                    .fill(.white)
                    .frame(width: 10, height: 1)
                Rectangle()
                    .fill(.white)
                    .frame(width: 1, height: 10)
            }
        }
        .frame(width: loupeDiameter, height: loupeDiameter)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
    }

    private func loupePosition(sampleView: CGPoint, viewSize: CGSize) -> CGPoint {
        let r = loupeDiameter / 2
        let idealY = sampleView.y - 90          // hover above finger
        let clampedX = max(r + 8, min(viewSize.width  - r - 8, sampleView.x))
        let clampedY = max(r + 60, min(viewSize.height - r - 150, idealY))
        return CGPoint(x: clampedX, y: clampedY)
    }

    // MARK: - Color info card (reused from CameraView style)

    @ViewBuilder
    private var colorInfoCard: some View {
        if let color = viewModel.identifiedColor {
            let note = CVDColorContext.contextNote(for: color.simpleName, hex: color.hex, r: color.rgb.r, g: color.rgb.g, b: color.rgb.b, profile: activeCVDProfile)

            // See CameraView for why the layout branches and the range is capped —
            // same fix, same reasoning, applied here for the eyedropper's card.
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityColorCard(color: color, note: note)
                } else {
                    standardColorCard(color: color, note: note)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        } else {
            HStack {
                ProgressView().tint(.white)
                Text("Drag to identify a color…")
                    .font(.body)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    /// Default layout: color swatch on the left, text stacked to its right.
    @ViewBuilder
    private func standardColorCard(color: IdentifiedColor, note: String?) -> some View {
        HStack(spacing: 0) {
            color.swiftUIColor
                .frame(width: 100)
                .clipShape(
                    .rect(
                        topLeadingRadius: 16,
                        bottomLeadingRadius: 16,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(color.simpleName)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if color.name != color.simpleName {
                    Text(color.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                HStack(spacing: 12) {
                    Text(color.hex)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(color.rgbDisplayString)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 88, maxHeight: standardCardMaxHeight)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .animation(.easeInOut(duration: 0.15), value: color.hex)
    }

    /// Accessibility-size layout: a small swatch chip beside the title, everything
    /// else stacked full-width below — see CameraView's variant for the rationale.
    @ViewBuilder
    private func accessibilityColorCard(color: IdentifiedColor, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                color.swiftUIColor
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(color.simpleName)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            if color.name != color.simpleName {
                Text(color.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Text(color.hex)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(color.rgbDisplayString)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .animation(.easeInOut(duration: 0.15), value: color.hex)
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack {
            HStack {
                // Dismiss
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.3), radius: 4)
                }
                .padding(.leading, 16)

                Spacer()

                // Change photo
                if viewModel.displayImage != nil {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4)
                    }
                    .padding(.trailing, 16)
                }
            }
            .padding(.top, 12)
            Spacer()
        }
    }
}

// MARK: - Helpers

/// Compute the axis-aligned rect of an image displayed with `.scaledToFit()` inside `viewSize`.
private func imageRect(imageSize: CGSize, in viewSize: CGSize) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
    let imageAspect = imageSize.width / imageSize.height
    let viewAspect  = viewSize.width  / viewSize.height

    let w: CGFloat
    let h: CGFloat
    if imageAspect > viewAspect {
        // Image is wider relative to view → letterboxed
        w = viewSize.width
        h = viewSize.width / imageAspect
    } else {
        // Image is taller relative to view → pillarboxed
        h = viewSize.height
        w = viewSize.height * imageAspect
    }

    return CGRect(
        x: (viewSize.width  - w) / 2,
        y: (viewSize.height - h) / 2,
        width:  w,
        height: h
    )
}

#Preview {
    EyedropperView()
}
