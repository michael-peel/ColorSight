import SwiftUI
import SwiftData

// MARK: - HomeView (root container after onboarding)
//
// Two-screen flow managed by a single state flag:
//   • Welcome screen  — logo + "Get Started" button
//   • Main menu       — Camera (primary), Eyedropper, History, Settings
//
// The transition mirrors the onboarding page-turn pattern.

struct HomeView: View {
    @State private var showingMenu = false

    var body: some View {
        Group {
            if showingMenu {
                MainMenuView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                WelcomeScreen {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showingMenu = true
                    }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Welcome screen

private struct WelcomeScreen: View {
    let onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            ColorSightLogo(size: 160)
                .padding(.bottom, 20)

            // Two-tone word-mark: "Color" dark, "Sight" purple
            HStack(spacing: 0) {
                Text("Color")
                    .foregroundStyle(.primary)
                Text("Sight")
                    .foregroundStyle(Color.purple)
            }
            .font(.system(size: 40, weight: .bold))

            Spacer()

            // Welcome text
            VStack(spacing: 14) {
                Text("Welcome to ColorSight")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("Point your camera at anything and get an instant color name — adapted for the way *you* see color.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            Spacer()

            // CTA
            Button(action: onGetStarted) {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }
}

// MARK: - Main menu

private struct MainMenuView: View {
    @State private var showingCamera      = false
    @State private var showingEyedropper  = false
    @State private var showingHistory     = false
    @State private var showingSettings    = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Camera — primary feature, larger card
                    FeatureCard(
                        icon:        "camera.fill",
                        title:       "Camera",
                        description: "Point at anything and get an instant color name.",
                        isPrimary:   true,
                        action:      { showingCamera = true }
                    )

                    // Eyedropper — full-width so text never hyphenates
                    FeatureCard(
                        icon:        "eyedropper.halffull",
                        title:       "Eyedropper",
                        description: "Sample colors from a photo or screenshot.",
                        isPrimary:   false,
                        action:      { showingEyedropper = true }
                    )

                    // History — full-width
                    FeatureCard(
                        icon:        "clock.arrow.circlepath",
                        title:       "History",
                        description: "Browse your saved colors.",
                        isPrimary:   false,
                        action:      { showingHistory = true }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("ColorSight")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera)      { CameraView() }
        .fullScreenCover(isPresented: $showingEyedropper)  { EyedropperView() }
        .sheet(isPresented: $showingHistory)               { HistoryView() }
        .sheet(isPresented: $showingSettings)              { SettingsView() }
    }
}

// MARK: - Feature card (full-width, no side-by-side layout)

private struct FeatureCard: View {
    let icon:        String
    let title:       String
    let description: String
    let isPrimary:   Bool
    let action:      () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon badge
                Image(systemName: icon)
                    .font(isPrimary ? .title : .title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: isPrimary ? 52 : 44, height: isPrimary ? 52 : 44)
                    .background(Color.accentColor.opacity(0.1), in: Circle())

                // Text block — gets all remaining width, so long words never wrap
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(isPrimary ? .title3.bold() : .headline)
                        .foregroundStyle(.primary)

                    Text(description)
                        .font(isPrimary ? .subheadline : .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(isPrimary ? 20 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(description)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - ColorSight logo
//
// A color-wheel "C" arc (11 segments, 270° span, gap upper-right)
// with a dark eye/pupil in the centre — matching the app icon.
//
// Coordinate convention used here (for clarity):
//   • 0° = 12 o'clock, positive = clockwise
//   • Gap runs from 30° (top of C, yellow ends) to 120° (bottom of C, cyan starts)
//   • Arc runs from 120° clockwise through 180°, 270°, 0°, back to 30° = 270°

private struct ColorSightLogo: View {
    var size: CGFloat = 160

    // 11 segments: colours arranged from bottom-of-C (cyan) clockwise to top-of-C (yellow)
    private let segmentColors: [Color] = [
        Color(red: 0.12, green: 0.78, blue: 0.92),   // cyan-blue  (arc start ~120°)
        Color(red: 0.18, green: 0.58, blue: 0.96),   // blue
        Color(red: 0.35, green: 0.40, blue: 0.93),   // blue-violet
        Color(red: 0.53, green: 0.25, blue: 0.88),   // violet
        Color(red: 0.68, green: 0.18, blue: 0.85),   // purple
        Color(red: 0.83, green: 0.10, blue: 0.52),   // magenta
        Color(red: 0.90, green: 0.10, blue: 0.16),   // red
        Color(red: 0.95, green: 0.32, blue: 0.05),   // red-orange
        Color(red: 0.97, green: 0.55, blue: 0.03),   // orange
        Color(red: 0.97, green: 0.73, blue: 0.03),   // yellow-orange
        Color(red: 0.97, green: 0.89, blue: 0.08),   // yellow     (arc end ~30°)
    ]

    var body: some View {
        Canvas { ctx, _ in
            let cx      = size / 2
            let cy      = size / 2
            let center  = CGPoint(x: cx, y: cy)
            let outerR: CGFloat = size * 0.47
            let innerR: CGFloat = size * 0.29

            let arcStartDeg: Double = 120   // where the arc begins (clockwise from top)
            let arcSpan:     Double = 270   // total degrees covered
            let n = segmentColors.count
            let segSpan   = arcSpan / Double(n)
            let gapBetween: Double = 1.5    // degrees of blank space between segments

            for i in 0..<n {
                let segStart = arcStartDeg + Double(i) * segSpan + gapBetween / 2
                let segEnd   = arcStartDeg + Double(i + 1) * segSpan - gapBetween / 2

                // addArc uses standard math angles (0° = right, counterclockwise positive),
                // but in UIKit's flipped Y coordinate system clockwise:false → clockwise on screen.
                // Convert "degrees clockwise from top" → "degrees from right" by subtracting 90.
                let aStart = Angle(degrees: segStart - 90)
                let aEnd   = Angle(degrees: segEnd   - 90)

                // Build the donut-segment path: outer arc + inner arc back
                var path = Path()
                path.addArc(center: center, radius: outerR,
                            startAngle: aStart, endAngle: aEnd, clockwise: false)
                path.addArc(center: center, radius: innerR,
                            startAngle: aEnd, endAngle: aStart, clockwise: true)
                path.closeSubpath()
                ctx.fill(path, with: .color(segmentColors[i]))
            }

            // White fill inside the ring so the dark eye sits on a clean white base
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - innerR + 1, y: cy - innerR + 1,
                                       width: (innerR - 1) * 2, height: (innerR - 1) * 2)),
                with: .color(.white)
            )
        }
        .frame(width: size, height: size)
        .overlay {
            // Dark navy eye circle
            Circle()
                .fill(Color(red: 0.09, green: 0.10, blue: 0.16))
                .frame(width: size * 0.37, height: size * 0.37)

            // White pupil highlight (upper-left offset, like a light reflection)
            Circle()
                .fill(.white)
                .frame(width: size * 0.10, height: size * 0.10)
                .offset(x: -size * 0.07, y: -size * 0.07)
        }
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .modelContainer(for: ColorSwatch.self, inMemory: true)
}
