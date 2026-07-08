import SwiftUI
import AVFoundation

/// Root view — gates on camera permission, then routes to HomeView.
/// First-run CVD profile selection is handled inside HomeView itself.
struct ContentView: View {

    @State private var showSplash = true
    @State private var authStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        ZStack {
            cameraGate

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.45)) {
                    showSplash = false
                }
            }
        }
        // Re-check camera permission whenever the app returns to the foreground.
        // Covers the case where the user went to Settings, granted access, and came back.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    // MARK: - Camera permission gate

    @ViewBuilder
    private var cameraGate: some View {
        switch authStatus {
        case .authorized:
            HomeView()

        case .denied:
            // User explicitly denied — they can fix it in Settings.
            PermissionDeniedView()

        case .restricted:
            // Parental controls or MDM — the user cannot grant access themselves.
            PermissionRestrictedView()

        default:
            // .notDetermined — first time asking.
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

/// Shown on first launch before the system dialog appears.
private struct PermissionRequestView: View {
    let onRequest: () async -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            Text("Camera Access")
                .font(.title.bold())

            Text("ColorSight uses your camera to identify colors in real time. Your camera feed never leaves your device.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Button("Enable Camera") {
                Task { await onRequest() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("A permission prompt will appear — tap Allow.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}

/// Shown after the user taps "Don't Allow" on the system dialog, or after
/// revoking access in Settings. The "Open Settings" button deep-links directly
/// to ColorSight's settings page where Camera can be toggled back on.
/// ContentView re-checks the status when the app returns to the foreground,
/// so no restart is needed after granting access.
private struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill.badge.ellipsis")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("Camera Access Needed")
                .font(.title2.bold())

            Text("ColorSight needs camera access to identify colors. Tap Open Settings and turn on Camera — the app will resume automatically when you come back.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}

/// Shown when camera access is restricted by parental controls or device management.
/// The user cannot change this themselves — no "Open Settings" button.
private struct PermissionRestrictedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("Camera Restricted")
                .font(.title2.bold())

            Text("Camera access is restricted on this device — this is usually set by parental controls or a device administrator. ColorSight can't be used until the restriction is lifted.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .padding()
    }
}

// MARK: - Splash screen (shown on every cold launch, fades out after ~1.5 s)

private struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            Image("SplashWaveImage")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image("AppLogoImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)

                HStack(spacing: 0) {
                    Text("Color").foregroundStyle(.primary)
                    Text("Sight").foregroundStyle(Color.purple)
                }
                .font(.system(size: 36, weight: .bold))

                Text("Identify Colors. Live Clearly.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
