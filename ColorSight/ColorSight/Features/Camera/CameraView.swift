import SwiftUI

struct CameraView: View {

    @State private var viewModel      = CameraViewModel()
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            // MARK: - Live preview (full screen)
            CameraPreviewView(session: viewModel.session)
                .ignoresSafeArea()

            // MARK: - Center crosshair
            CrosshairView(isFrozen: viewModel.isFrozen)

            // MARK: - Bottom HUD
            VStack {
                Spacer()
                colorInfoCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
            }

            // MARK: - Top bar (settings gear)
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4)
                    }
                    .padding(.top, 12)
                    .padding(.trailing, 16)
                }
                Spacer()
            }

            // MARK: - Error banner
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
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                viewModel.isFrozen.toggle()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onAppear  { viewModel.startSession() }
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
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Frozen badge
                if viewModel.isFrozen {
                    Image(systemName: "lock.fill")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.trailing, 14)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 100)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        viewModel.isFrozen ? Color.accentColor.opacity(0.6) : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .animation(.easeInOut(duration: 0.15), value: color.hex)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: viewModel.isFrozen)

        } else {
            HStack {
                ProgressView().tint(.white)
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
    var isFrozen: Bool

    var body: some View {
        ZStack {
            // Ring — accent-colored when frozen
            Circle()
                .strokeBorder(
                    isFrozen ? Color.accentColor : .white,
                    lineWidth: isFrozen ? 2.5 : 2
                )
                .frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.4), radius: 3)

            if isFrozen {
                // Lock icon in the center
                Image(systemName: "lock.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .transition(.scale.combined(with: .opacity))
            } else {
                // Normal tick marks
                Group {
                    Rectangle().fill(.white).frame(width: 12, height: 1.5).offset(x: -28)
                    Rectangle().fill(.white).frame(width: 12, height: 1.5).offset(x: 28)
                    Rectangle().fill(.white).frame(width: 1.5, height: 12).offset(y: -28)
                    Rectangle().fill(.white).frame(width: 1.5, height: 12).offset(y: 28)
                }
                .transition(.opacity)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 2)
    }
}

#Preview {
    CameraView()
}
