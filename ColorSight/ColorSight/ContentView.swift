import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var permissionGranted = false
    @State private var permissionDenied = false

    var body: some View {
        VStack(spacing: 24) {
            if permissionGranted {
                Text("Camera ready!")
                    .font(.title2)
                Text("We'll build the viewfinder here next.")
                    .foregroundStyle(.secondary)
            } else if permissionDenied {
                Text("Camera access denied.")
                    .foregroundStyle(.red)
                Text("Enable it in Settings → ColorSight.")
                    .foregroundStyle(.secondary)
            } else {
                Text("ColorSight")
                    .font(.largeTitle)
                    .bold()
                Text("Tap below to enable your camera.")
                    .foregroundStyle(.secondary)
                Button("Enable Camera") {
                    requestCameraPermission()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onAppear {
            checkCameraPermission()
        }
    }

    func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
        case .denied, .restricted:
            permissionDenied = true
        default:
            break
        }
    }

    func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                permissionGranted = granted
                permissionDenied = !granted
            }
        }
    }
}
