import SwiftUI
import SwiftData

/// Root landing screen shown after onboarding. Presents each feature
/// (Camera, Eyedropper, History) as a full-screen or sheet presentation
/// so the user always has a home to return to.
struct HomeView: View {

    @State private var showingCamera      = false
    @State private var showingEyedropper  = false
    @State private var showingHistory     = false
    @State private var showingSettings    = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {

                    // MARK: - Hero
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.25), Color.purple.opacity(0.15)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 100, height: 100)

                            Image(systemName: "eye.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }

                        Text("ColorSight")
                            .font(.largeTitle.bold())

                        Text("Identify any color, adapted for how you see.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.top, 48)
                    .padding(.bottom, 40)

                    // MARK: - Feature cards
                    VStack(spacing: 12) {
                        // Camera — primary feature, taller card
                        FeatureCard(
                            icon:        "camera.fill",
                            title:       "Camera",
                            description: "Point at anything and get an instant color name.",
                            isPrimary:   true,
                            action:      { showingCamera = true }
                        )

                        HStack(spacing: 12) {
                            FeatureCard(
                                icon:        "eyedropper.halffull",
                                title:       "Eyedropper",
                                description: "Sample colors from a photo.",
                                isPrimary:   false,
                                action:      { showingEyedropper = true }
                            )

                            FeatureCard(
                                icon:        "clock.arrow.circlepath",
                                title:       "History",
                                description: "Browse your saved colors.",
                                isPrimary:   false,
                                action:      { showingHistory = true }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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
        .fullScreenCover(isPresented: $showingCamera) {
            CameraView()
        }
        .fullScreenCover(isPresented: $showingEyedropper) {
            EyedropperView()
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

// MARK: - Feature card

private struct FeatureCard: View {
    let icon:        String
    let title:       String
    let description: String
    let isPrimary:   Bool
    let action:      () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: icon)
                    .font(isPrimary ? .title : .title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: isPrimary ? 52 : 44, height: isPrimary ? 52 : 44)
                    .background(Color.accentColor.opacity(0.1), in: Circle())

                // Text
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
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(description)")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    HomeView()
        .modelContainer(for: ColorSwatch.self, inMemory: true)
}
