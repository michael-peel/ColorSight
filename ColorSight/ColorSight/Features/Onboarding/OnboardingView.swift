import SwiftUI

// MARK: - Root onboarding shell

struct OnboardingView: View {
    @State private var vm = OnboardingViewModel()
    @State private var showProfilePicker = false

    var body: some View {
        Group {
            if showProfilePicker {
                ProfilePickerPage(vm: vm)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                WelcomePage(onStart: {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showProfilePicker = true
                    }
                })
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.25), Color.purple.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)

                Image(systemName: "eye.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.bottom, 40)

            // Title + body
            VStack(spacing: 16) {
                Text("Welcome to ColorSight")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text("Point your camera at anything and get an instant color name — adapted for the way *you* see color.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            Spacer()

            // CTA
            Button(action: onStart) {
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

// MARK: - Page 2: Profile Picker

private struct ProfilePickerPage: View {
    var vm: OnboardingViewModel

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
                        ProfileCard(
                            profile: profile,
                            isSelected: vm.pendingProfile == profile,
                            onSelect: { vm.pendingProfile = profile }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            Divider()

            // Bottom actions
            VStack(spacing: 14) {
                // Continue (enabled only when a profile is selected)
                Button(action: { vm.confirmSelection() }) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(vm.pendingProfile == nil)
                .padding(.horizontal, 32)

                // Skip
                Button(action: { vm.skip() }) {
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

// MARK: - Profile Card

private struct ProfileCard: View {
    let profile: CVDProfile
    let isSelected: Bool
    let onSelect: () -> Void

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

                // Confusion swatch pair (or placeholder for custom)
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
                } else {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                        .font(.title3)
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
        .accessibilityLabel("\(profile.onboardingTitle). \(profile.experienceDescription)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - CVDProfile UI extensions (onboarding only)

private extension CVDProfile {

    /// Short plain-English name shown on the card heading.
    var onboardingTitle: String {
        switch self {
        case .normal:        return "No Color Deficiency"
        case .deuteranopia:  return "Red-Green (Green-type)"
        case .protanopia:    return "Red-Green (Red-type)"
        case .tritanopia:    return "Blue-Yellow"
        case .achromatopsia: return "Full Color Blindness"
        case .custom:        return "Custom Profile"
        }
    }

    /// One-line description of what the user actually experiences.
    var experienceDescription: String {
        switch self {
        case .normal:
            return "Colors appear as most people see them."
        case .deuteranopia:
            return "Reds and greens can look brownish or the same."
        case .protanopia:
            return "Reds look very dark; hard to separate from brown or black."
        case .tritanopia:
            return "Blues and greens look alike; yellows can look pink."
        case .achromatopsia:
            return "Little to no color — mostly shades of gray."
        case .custom:
            return "Set your own parameters in Settings."
        }
    }

    /// SF Symbol for the card icon.
    var onboardingIcon: String {
        switch self {
        case .normal:        return "eye"
        case .deuteranopia:  return "eye.trianglebadge.exclamationmark"
        case .protanopia:    return "eye.trianglebadge.exclamationmark"
        case .tritanopia:    return "eye.trianglebadge.exclamationmark"
        case .achromatopsia: return "eye.slash"
        case .custom:        return "slider.horizontal.3"
        }
    }

    /// Classic confusion pair for this CVD type.
    /// nil for profiles that don't have a simple two-color confusion.
    var confusionColors: (Color, Color)? {
        switch self {
        case .normal:
            return nil
        case .deuteranopia:
            // Red (#CC3300) and olive green (#6B8E00) look similar
            return (Color(red: 0.80, green: 0.20, blue: 0.00),
                    Color(red: 0.42, green: 0.56, blue: 0.00))
        case .protanopia:
            // Red (#CC3300) looks like dark brown (#5C3800)
            return (Color(red: 0.80, green: 0.20, blue: 0.00),
                    Color(red: 0.36, green: 0.22, blue: 0.00))
        case .tritanopia:
            // Blue (#0055CC) and green (#00884B) look similar
            return (Color(red: 0.00, green: 0.33, blue: 0.80),
                    Color(red: 0.00, green: 0.53, blue: 0.30))
        case .achromatopsia:
            // Vivid orange looks gray
            return (Color(red: 1.00, green: 0.40, blue: 0.00),
                    Color(red: 0.55, green: 0.55, blue: 0.55))
        case .custom:
            return nil
        }
    }
}
