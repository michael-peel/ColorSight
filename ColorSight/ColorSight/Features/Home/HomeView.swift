import SwiftUI
import SwiftData

// MARK: - HomeView (root container after camera permission)
//
// Three-stage flow managed by a single enum:
//
//   • .welcome       — logo + "Get Started" button (first launch only)
//   • .profilePicker — CVD profile selection (first launch only)
//   • .menu          — Camera / Eyedropper / History / Settings
//
// `hasLaunchedBefore` gates whether .welcome is shown at all — true means skip to .menu.
// `hasCompletedOnboarding` gates whether the first "Get Started" tap goes to
// the profile picker or straight to the menu.

struct HomeView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasLaunchedBefore")      private var hasLaunchedBefore = false

    private enum Stage { case welcome, profilePicker, menu }
    // Read UserDefaults directly at init time so the correct stage is set before
    // the first render — avoids a one-frame flash of the welcome screen on repeat launches.
    @State private var stage: Stage = UserDefaults.standard.bool(forKey: "hasLaunchedBefore") ? .menu : .welcome
    @State private var pendingProfile: CVDProfile? = nil

    var body: some View {
        Group {
            switch stage {


            case .welcome:
                WelcomeScreen {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        stage = hasCompletedOnboarding ? .menu : .profilePicker
                    }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))

            case .profilePicker:
                ProfilePickerScreen(
                    pending: $pendingProfile,
                    onConfirm: {
                        finishOnboarding()
                        withAnimation(.easeInOut(duration: 0.35)) { stage = .menu }
                    },
                    onSkip: {
                        finishOnboarding()
                        withAnimation(.easeInOut(duration: 0.35)) { stage = .menu }
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))

            case .menu:
                MainMenuView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onAppear { markLaunched() }
    }

    private func markLaunched() {
        if !hasLaunchedBefore { hasLaunchedBefore = true }
    }

    private func finishOnboarding() {
        // Persist whichever profile the user chose (or the default on skip).
        (pendingProfile ?? CVDProfile.defaultProfile).save()
        hasCompletedOnboarding = true
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

            // Two-tone wordmark: "Color" dark, "Sight" purple
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

// MARK: - Profile picker screen (first launch only)

private struct ProfilePickerScreen: View {
    @Binding var pending: CVDProfile?
    let onConfirm: () -> Void
    let onSkip:    () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 10) {
                Text("How do you see color?")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text("ColorSight adapts its descriptions for you.\nPick the closest match — you can change it anytime in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 52)
            .padding(.bottom, 24)

            // Profile cards
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(CVDProfile.allCases, id: \.self) { profile in
                        CVDProfileCard(
                            profile:    profile,
                            isSelected: pending == profile,
                            onSelect:   { pending = profile }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            Divider()

            // Bottom actions
            VStack(spacing: 14) {
                Button(action: onConfirm) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(pending == nil)
                .padding(.horizontal, 32)

                Button(action: onSkip) {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 32)
            }
            .padding(.top, 16)
        }
    }
}

// MARK: - Profile card

private struct CVDProfileCard: View {
    let profile:    CVDProfile
    let isSelected: Bool
    let onSelect:   () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Icon
                Image(systemName: profile.onboardingIcon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isSelected
                                  ? Color.accentColor.opacity(0.12)
                                  : Color(.tertiarySystemBackground))
                    )

                // Text
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.onboardingTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(profile.experienceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                // Confusion swatch pair
                if let (c1, c2) = profile.confusionColors {
                    VStack(spacing: 2) {
                        HStack(spacing: -8) {
                            Circle()
                                .fill(c1)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                            Circle()
                                .fill(c2)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                        }
                        Text("look similar")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.2))
                    .font(.title3)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.07)
                          : Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityLabel("\(profile.onboardingTitle). \(profile.experienceDescription)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - CVDProfile display properties (used by the picker above)

private extension CVDProfile {
    var onboardingTitle: String {
        switch self {
        case .normal:        return "No Color Deficiency"
        case .deuteranopia:  return "Red-Green (Green-type)"
        case .protanopia:    return "Red-Green (Red-type)"
        case .tritanopia:    return "Blue-Yellow"
        case .achromatopsia: return "Full Color Blindness"
        }
    }

    var experienceDescription: String {
        switch self {
        case .normal:        return "Colors appear as most people see them."
        case .deuteranopia:  return "Reds and greens can look brownish or the same."
        case .protanopia:    return "Reds look very dark; hard to separate from brown or black."
        case .tritanopia:    return "Blues and greens look alike; yellows can look pink."
        case .achromatopsia: return "Little to no color — mostly shades of gray."
        }
    }

    var onboardingIcon: String {
        switch self {
        case .normal:        return "eye"
        case .deuteranopia,
             .protanopia,
             .tritanopia:    return "eye.trianglebadge.exclamationmark"
        case .achromatopsia: return "eye.slash"
        }
    }

    var confusionColors: (Color, Color)? {
        switch self {
        case .normal:        return nil
        case .deuteranopia:
            return (Color(red: 0.80, green: 0.20, blue: 0.00),
                    Color(red: 0.42, green: 0.56, blue: 0.00))
        case .protanopia:
            return (Color(red: 0.80, green: 0.20, blue: 0.00),
                    Color(red: 0.36, green: 0.22, blue: 0.00))
        case .tritanopia:
            return (Color(red: 0.00, green: 0.33, blue: 0.80),
                    Color(red: 0.00, green: 0.53, blue: 0.30))
        case .achromatopsia:
            return (Color(red: 1.00, green: 0.40, blue: 0.00),
                    Color(red: 0.55, green: 0.55, blue: 0.55))
        }
    }
}

// MARK: - Main menu

private struct MainMenuView: View {
    @State private var showingCamera             = false
    @State private var showingEyedropper         = false
    @State private var showingHistory            = false
    @State private var showingSettings           = false
    @State private var showingProfilePicker      = false
    @State private var showingCameraHueIsolation = false
    @State private var openCameraOnSettingsDismiss = false

    @AppStorage("hasSeenCameraTooltip") private var hasSeenCameraTooltip = false

    @Query(sort: \ColorSwatch.timestamp, order: .reverse)
    private var allSwatches: [ColorSwatch]

    @AppStorage("cvdProfile") private var cvdProfileRaw: String = CVDProfile.normal.rawValue
    private var currentProfile: CVDProfile { CVDProfile(rawValue: cvdProfileRaw) ?? .normal }

    // Binding that keeps @AppStorage and UserDefaults in sync when the picker writes.
    private var profileBinding: Binding<CVDProfile> {
        Binding(
            get: { currentProfile },
            set: { cvdProfileRaw = $0.rawValue }
        )
    }

    // Forest green that reads clearly as an icon fill in both light and dark mode.
    private static let historyGreen = Color(red: 0.15, green: 0.42, blue: 0.18)

    var body: some View {
        ZStack(alignment: .top) {
            // Full-bleed background so the color reaches under status bar and home indicator.
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom header — large left-aligned wordmark, gear button right.
                HStack {
                    HStack(spacing: 0) {
                        Text("Color").foregroundStyle(.primary)
                        Text("Sight").foregroundStyle(Color.purple)
                    }
                    .font(.title.bold())

                    Spacer()

                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 38, height: 38)
                            .background(Color(.secondarySystemGroupedBackground), in: Circle())
                    }
                    .accessibilityLabel("Settings")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 12) {
                        HeroCameraCard(action: { showingCamera = true })
                            .frame(height: 210)

                        HStack(spacing: 12) {
                            SecondaryCard(
                                icon:      "drop.fill",
                                iconColor: .blue,
                                title:     "Eyedropper",
                                subtitle:  "From a photo",
                                action:    { showingEyedropper = true }
                            )
                            SecondaryCard(
                                icon:      "clock.fill",
                                iconColor: MainMenuView.historyGreen,
                                title:     "History",
                                subtitle:  "Saved colors",
                                action:    { showingHistory = true }
                            )
                        }
                        .frame(height: 140)

                        // Hue Isolation — full-width card, opens camera straight into the mode
                        Button { showingCameraHueIsolation = true } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "paintpalette.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .background(Color.purple,
                                                in: RoundedRectangle(cornerRadius: 12))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Hue Isolation")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("Highlight one color, gray out the rest")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(16)
                            .background(Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Hue Isolation. Highlight one color, gray out the rest")

                        if !allSwatches.isEmpty {
                            RecentColorsStrip(swatches: Array(allSwatches.prefix(5)))
                        }

                        HomeProfileCard(profile: currentProfile,
                                        action: { showingProfilePicker = true })
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 32)
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera)             { CameraView() }
        .fullScreenCover(isPresented: $showingCameraHueIsolation) { CameraView(startHueIsolation: true) }
        .fullScreenCover(isPresented: $showingEyedropper)         { EyedropperView() }
        .sheet(isPresented: $showingHistory)                      { HistoryView() }
        .sheet(isPresented: $showingSettings, onDismiss: {
            guard openCameraOnSettingsDismiss else { return }
            openCameraOnSettingsDismiss = false
            Task { @MainActor in showingCamera = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                hasSeenCameraTooltip = false
            }
        }) {
            SettingsView(onReplayTour: {
                openCameraOnSettingsDismiss = true
                showingSettings = false
            })
        }
        .sheet(isPresented: $showingProfilePicker) {
            HomeProfilePickerSheet(selectedProfile: profileBinding)
        }
    }
}

// MARK: - Home profile picker sheet

private struct HomeProfilePickerSheet: View {
    @Binding var selectedProfile: CVDProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(CVDProfile.allCases, id: \.self) { profile in
                        CVDProfileCard(
                            profile:    profile,
                            isSelected: selectedProfile == profile,
                            onSelect: {
                                selectedProfile = profile
                                dismiss()
                            }
                        )
                    }
                }
                .padding(20)
            }
            .navigationTitle("Color Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Hero camera card

private struct HeroCameraCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Spacer()

                Image(systemName: "camera.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .background(Color.purple, in: Circle())

                VStack(spacing: 6) {
                    Text("Open Camera")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                    Text("Point at anything to identify its color")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20))
            .overlay(alignment: .topTrailing) {
                Text("Primary")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.purple, in: Capsule())
                    .padding(12)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Camera. Point at anything to identify its color")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Secondary feature card (eyedropper / history)

private struct SecondaryCard: View {
    let icon:      String
    let iconColor: Color
    let title:     String
    let subtitle:  String
    let action:    () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(iconColor, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Recent colors strip

private struct RecentColorsStrip: View {
    let swatches: [ColorSwatch]
    @State private var tappedID: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            HStack(spacing: 8) {
                ForEach(swatches) { swatch in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            tappedID = tappedID == swatch.id ? nil : swatch.id
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(swatch.swiftUIColor)
                            .frame(height: 62)
                            .frame(maxWidth: .infinity)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(.white.opacity(0.5), lineWidth: 2)
                                    .opacity(tappedID == swatch.id ? 1 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(swatch.simpleName)
                }
            }

            // Name label — slides in below the row when a swatch is tapped
            if let id = tappedID, let s = swatches.first(where: { $0.id == id }) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(s.swiftUIColor)
                        .frame(width: 10, height: 10)
                    Text(s.simpleName)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(s.hex)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontDesign(.monospaced)
                }
                .padding(.horizontal, 2)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Home CVD profile card

private struct HomeProfileCard: View {
    let profile: CVDProfile
    let action:  () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "eye.fill")
                    .font(.callout)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.purple, in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Color profile")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(profile.displayName)
                        .font(.body.bold())
                        .foregroundStyle(.primary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Color profile: \(profile.displayName)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - ColorSight logo
//
// A colour-wheel "C" arc (11 segments, 270° span) with a dark eye/pupil.
//
// Coordinate convention (used only within this view):
//   • 0° = 12 o'clock, positive = clockwise
//   • Gap from 45° (top-right) → 135° (bottom-right) — centred at 90° (right)
//   • Arc from 135° → 45° clockwise = 270° — this forms a proper "C"

private struct ColorSightLogo: View {
    var size: CGFloat = 160

    // 11 segments: cyan → … → yellow, going clockwise from the bottom of the C
    private let segmentColors: [Color] = [
        Color(red: 0.12, green: 0.78, blue: 0.92),   // cyan-blue  (arc start ~135°)
        Color(red: 0.18, green: 0.58, blue: 0.96),   // blue
        Color(red: 0.35, green: 0.40, blue: 0.93),   // blue-violet
        Color(red: 0.53, green: 0.25, blue: 0.88),   // violet
        Color(red: 0.68, green: 0.18, blue: 0.85),   // purple
        Color(red: 0.83, green: 0.10, blue: 0.52),   // magenta
        Color(red: 0.90, green: 0.10, blue: 0.16),   // red
        Color(red: 0.95, green: 0.32, blue: 0.05),   // red-orange
        Color(red: 0.97, green: 0.55, blue: 0.03),   // orange
        Color(red: 0.97, green: 0.73, blue: 0.03),   // yellow-orange
        Color(red: 0.97, green: 0.89, blue: 0.08),   // yellow     (arc end ~45°)
    ]

    var body: some View {
        Canvas { ctx, _ in
            let cx      = size / 2
            let cy      = size / 2
            let center  = CGPoint(x: cx, y: cy)
            let outerR: CGFloat = size * 0.47
            let innerR: CGFloat = size * 0.29

            // Arc begins at 135° (lower-right, bottom arm of C) and runs 270° clockwise
            // to 45° (upper-right, top arm of C). Gap = 45°→135° = right side.
            let arcStartDeg: Double = 135
            let arcSpan:     Double = 270
            let n = segmentColors.count
            let segSpan     = arcSpan / Double(n)
            let gapBetween: Double = 1.5   // degrees of blank space between segments

            for i in 0..<n {
                let segStart = arcStartDeg + Double(i)       * segSpan + gapBetween / 2
                let segEnd   = arcStartDeg + Double(i + 1)   * segSpan - gapBetween / 2

                // addArc uses math angles (0° = right, positive = counterclockwise) but in
                // UIKit's flipped Y system clockwise:false means clockwise on screen.
                // Convert "degrees clockwise from top" → "degrees from right" by -90°.
                let aStart = Angle(degrees: segStart - 90)
                let aEnd   = Angle(degrees: segEnd   - 90)

                var path = Path()
                path.addArc(center: center, radius: outerR,
                            startAngle: aStart, endAngle: aEnd, clockwise: false)
                path.addArc(center: center, radius: innerR,
                            startAngle: aEnd,   endAngle: aStart, clockwise: true)
                path.closeSubpath()
                ctx.fill(path, with: .color(segmentColors[i]))
            }
            // Inner fill is handled by the systemBackground overlay below the eye circle.
        }
        .frame(width: size, height: size)
        .overlay {
            // Adaptive fill behind the eye — matches the system background so the
            // inner ring area looks clean in both light and dark mode.
            Circle()
                .fill(Color(.systemBackground))
                .frame(width: (size * 0.29 - 1) * 2, height: (size * 0.29 - 1) * 2)

            // Dark navy eye circle
            Circle()
                .fill(Color(red: 0.09, green: 0.10, blue: 0.16))
                .frame(width: size * 0.37, height: size * 0.37)

            // White pupil highlight (upper-left, like a light reflection)
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
