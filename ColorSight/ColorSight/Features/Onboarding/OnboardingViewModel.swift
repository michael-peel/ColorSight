import Foundation

/// Manages onboarding state.
/// Writes the selected CVD profile and completion flag to UserDefaults,
/// which causes ContentView's @AppStorage to re-render automatically.
@Observable
final class OnboardingViewModel {

    /// The profile the user has tapped (but not yet confirmed).
    var pendingProfile: CVDProfile? = nil

    // MARK: - Actions

    /// Called when the user taps "Continue" after selecting a profile.
    func confirmSelection() {
        let profile = pendingProfile ?? CVDProfile.defaultProfile
        profile.save()
        markComplete()
    }

    /// Called when the user taps "Skip for now".
    func skip() {
        CVDProfile.defaultProfile.save()
        markComplete()
    }

    // MARK: - Private

    private func markComplete() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        // ContentView's @AppStorage("hasCompletedOnboarding") observes this key
        // and will re-render to the main camera flow automatically.
    }
}
