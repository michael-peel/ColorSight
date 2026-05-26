import SwiftUI

struct CameraView: View {

    @State private var viewModel         = CameraViewModel()
    @State private var showingSettings   = false
    @State private var showingEyedropper = false
    @State private var isRefocusing      = false

    // Safe-area insets read directly from UIKit so we can place UI elements
    // correctly after making the ZStack full-screen with .ignoresSafeArea().
    // The ZStack must fill the full screen so CrosshairView is centered at the
    // same pixel the camera actually samples (the geometric center of the frame),
    // not the center of the smaller safe-area rectangle.
    private var safeInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.safeAreaInsets ?? .zero
    }

    var body: some View {
        ZStack {
            // MARK: - Live preview (full screen)
            CameraPreviewView(session: viewModel.session)

            // MARK: - Center crosshair
            // Because the ZStack ignores safe areas, this is centered on the
            // true screen center — matching the camera's sampled pixel exactly.
            CrosshairView(isFrozen: viewModel.isFrozen)

            // MARK: - Refocus feedback pill (appears just below crosshair)
            if isRefocusing {
                Text("Refocusing…")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .offset(y: 36)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .allowsHitTesting(false)
            }

            // MARK: - Bottom HUD
            VStack {
                Spacer()
                colorInfoCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40 + safeInsets.bottom)
            }

            // MARK: - Top bar (eyedropper left, settings right)
            VStack {
                HStack {
                    // Eyedropper button — top-left
                    Button {
                        showingEyedropper = true
                    } label: {
                        Image(systemName: "eyedropper.halffull")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4)
                    }
                    .padding(.leading, 16)

                    Spacer()

                    // Settings button — top-right
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
                    .padding(.trailing, 16)
                }
                .padding(.top, safeInsets.top + 12)   // clear Dynamic Island / status bar
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
                        .padding(.top, safeInsets.top + 8)
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()   // ← ZStack fills full screen; crosshair at true center
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                viewModel.isFrozen.toggle()
            }
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            viewModel.refocus()
            withAnimation(.easeIn(duration: 0.15))  { isRefocusing = true  }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.3)) { isRefocusing = false }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $showingEyedropper) {
            EyedropperView()
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
