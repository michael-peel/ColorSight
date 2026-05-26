import SwiftUI

struct CameraView: View {

    @State private var viewModel = CameraViewModel()

    var body: some View {
        ZStack {
            // MARK: - Live preview (full screen)
            CameraPreviewView(session: viewModel.session)
                .ignoresSafeArea()

            // MARK: - Center crosshair
            CrosshairView()

            // MARK: - Bottom HUD
            VStack {
                Spacer()
                colorInfoCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
            }

            // MARK: - Error banner (if any)
            if let error = viewModel.errorMessage {
                VStack {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.top, 60)
                    Spacer()
                }
            }
        }
        .onAppear { viewModel.startSession() }
        .onDisappear { viewModel.stopSession() }
    }

    // MARK: - Color info card

    @ViewBuilder
    private var colorInfoCard: some View {
        if let color = viewModel.identifiedColor {
            HStack(spacing: 0) {
                // Swatch
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

                // Text info
                VStack(alignment: .leading, spacing: 4) {
                    // Primary: plain English ("Dark Blue")
                    Text(color.simpleName)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    // Secondary: specific name ("Midnight Blue")
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
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 100)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .animation(.easeInOut(duration: 0.15), value: color.hex)

        } else {
            // Placeholder while waiting for first frame
            HStack {
                ProgressView()
                    .tint(.white)
                Text("Identifying color…")
                    .font(.body)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Crosshair

private struct CrosshairView: View {

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .strokeBorder(.white, lineWidth: 2)
                .frame(width: 40, height: 40)
                .shadow(color: .black.opacity(0.4), radius: 3)

            // Horizontal tick
            Rectangle()
                .fill(.white)
                .frame(width: 12, height: 1.5)
                .offset(x: -26)

            Rectangle()
                .fill(.white)
                .frame(width: 12, height: 1.5)
                .offset(x: 26)

            // Vertical tick
            Rectangle()
                .fill(.white)
                .frame(width: 1.5, height: 12)
                .offset(y: -26)

            Rectangle()
                .fill(.white)
                .frame(width: 1.5, height: 12)
                .offset(y: 26)
        }
        .shadow(color: .black.opacity(0.3), radius: 2)
    }
}

#Preview {
    CameraView()
}
