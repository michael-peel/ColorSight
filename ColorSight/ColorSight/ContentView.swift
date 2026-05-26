import SwiftUI
import AVFoundation

/// Root view — gates on onboarding completion, then on camera permission.
struct ContentView: View {

    /// Observed directly from UserDefaults; flips to true when OnboardingViewModel
    /// calls UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding").
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var authStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        if !hasCompletedOnboarding {
            OnboardingView()
        } else {
            cameraGate
        }
    }

    // MARK: - Camera permission gate

    @ViewBuilder
    private var cameraGate: some View {
        switch authStatus {
        case .authorized:
            CameraView()

        case .denied, .restricted:
            PermissionDeniedView()

        default:
            // .notDetermined — show a request prompt
            PermissionRequestView {
                await requestPermission()
            }
        }
    }

    private func requestPermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        authStatus = granted ? .authorized : .denied
    }
}

// MARK: - Permission screens

private struct PermissionRequestView: View {
    let onRequest: () async -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            Text("Camera Access")
                .font(.title.bold())

            Text("ColorSight needs your camera to identify colors in real time.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Button("Enable Camera") {
                Task { await onRequest() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}

private struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill.badge.ellipsis")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("Camera Access Denied")
                .font(.title2.bold())

            Text("Enable camera access in Settings → Privacy & Security → Camera → ColorSight.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}
