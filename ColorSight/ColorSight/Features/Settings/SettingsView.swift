import SwiftUI

// MARK: - Root settings sheet

struct SettingsView: View {

    /// Called when the user taps "Replay Feature Tour". The caller is responsible
    /// for dismissing this sheet and navigating to the camera.
    var onReplayTour: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    // CVD profile — read/written via CVDProfile.load() / profile.save()
    @State private var selectedProfile: CVDProfile = CVDProfile.load()

    @AppStorage("hapticsEnabled")            private var hapticsEnabled            = true
    @AppStorage("voiceFeedbackEnabled")      private var voiceFeedbackEnabled      = true
    @AppStorage("regionSamplingEnabled")     private var regionSamplingEnabled     = true
    @AppStorage("hasSeenCameraTooltip")      private var hasSeenCameraTooltip      = false
    @AppStorage("confusionWarningsEnabled")  private var confusionWarningsEnabled  = true

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Preferences
                Section {
                    NavigationLink {
                        ProfilePickerPage(selectedProfile: $selectedProfile)
                    } label: {
                        LabeledContent("Color Profile", value: selectedProfile.shortSettingsName)
                    }

                    Toggle("Vibration",           isOn: $hapticsEnabled)
                    Toggle("Voice Feedback",      isOn: $voiceFeedbackEnabled)
                    Toggle("Sample Region",       isOn: $regionSamplingEnabled)
                    Toggle("Confusion Warnings",  isOn: $confusionWarningsEnabled)

                    Button("Replay Feature Tour") {
                        if let onReplayTour {
                            onReplayTour()
                        } else {
                            hasSeenCameraTooltip = false
                            dismiss()
                        }
                    }
                    .foregroundStyle(Color.accentColor)
                } header: {
                    Text("Preferences")
                } footer: {
                    Text("Recommended for clothing and textured surfaces. Averages a small area of pixels for more stable readings.")
                }

                // MARK: About
                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build",   value: appBuild)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Save profile whenever the picker page changes it
            .onChange(of: selectedProfile) { _, newProfile in
                newProfile.save()
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

// MARK: - Profile picker page (pushed from Settings)

private struct ProfilePickerPage: View {
    @Binding var selectedProfile: CVDProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(CVDProfile.allCases, id: \.self) { profile in
                    ProfileCard(
                        profile: profile,
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
    }
}

// MARK: - Profile card (mirrors the onboarding card style)

private struct ProfileCard: View {
    let profile: CVDProfile
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                Image(systemName: profile.settingsIcon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(isSelected
                            ? Color.accentColor.opacity(0.12)
                            : Color(.tertiarySystemBackground))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.shortSettingsName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(profile.settingsDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

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
        .accessibilityLabel("\(profile.shortSettingsName). \(profile.settingsDescription)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - CVDProfile UI extensions (settings only)

private extension CVDProfile {

    var shortSettingsName: String {
        switch self {
        case .normal:        return "Normal Vision"
        case .deuteranopia:  return "Deuteranopia"
        case .protanopia:    return "Protanopia"
        case .tritanopia:    return "Tritanopia"
        case .achromatopsia: return "Achromatopsia"
        }
    }

    var settingsDescription: String {
        switch self {
        case .normal:        return "Standard color vision — no adjustments applied"
        case .deuteranopia:  return "Red-green (green-type) — most common"
        case .protanopia:    return "Red-green (red-type) — reds appear dark"
        case .tritanopia:    return "Blue-yellow — blues and greens look alike"
        case .achromatopsia: return "Full color blindness — mostly shades of gray"
        }
    }

    var settingsIcon: String {
        switch self {
        case .normal:
            return "eye"
        case .deuteranopia, .protanopia, .tritanopia:
            return "eye.trianglebadge.exclamationmark"
        case .achromatopsia:
            return "eye.slash"
        }
    }
}
