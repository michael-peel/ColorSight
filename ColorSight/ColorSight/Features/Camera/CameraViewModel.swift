@preconcurrency import AVFoundation
import Observation

// MARK: - Background-queue mutable state
//
// These two vars must be read/written from background dispatch queues.
// With SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor (an Xcode 26 project default),
// every stored property in the module is implicitly @MainActor unless
// explicitly opted out. `nonisolated(unsafe)` does that opt-out here.
// Each var is accessed from exactly ONE queue, so no locks are needed.

private final class CameraThreadState: @unchecked Sendable {
    nonisolated(unsafe) var isConfigured   = false  // sessionQueue only
    nonisolated(unsafe) var lastSampleTime: Double = 0  // sampleQueue only
}

// MARK: - ViewModel

/// Manages the AVCaptureSession lifecycle and pixel sampling.
///
/// Threading model:
///   sessionQueue  — AVCaptureSession configure / start / stop
///   sampleQueue   — CMSampleBuffer callbacks + pixel reads
///   MainActor     — ColorEngine.identify() call + all UI state updates
@Observable
@MainActor
final class CameraViewModel: NSObject {

    // MARK: - UI state

    var identifiedColor: IdentifiedColor?
    var isFrozen       = false
    var sessionIsRunning = false
    var errorMessage: String?

    // MARK: - Internals

    let session     = AVCaptureSession()
    let colorEngine = ColorEngine()          // called on MainActor; pure + fast

    private let sessionQueue = DispatchQueue(label: "com.colorsight.session", qos: .userInitiated)
    private let sampleQueue  = DispatchQueue(label: "com.colorsight.sample",  qos: .userInitiated)
    private let threadState  = CameraThreadState()

    // MARK: - Public (MainActor)

    func startSession() {
        let session     = self.session
        let sampleQueue = self.sampleQueue
        let threadState = self.threadState
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureIfNeeded(session: session, sampleQueue: sampleQueue, threadState: threadState)
            guard !session.isRunning else { return }
            session.startRunning()
            DispatchQueue.main.async { self.sessionIsRunning = true }
        }
    }

    func stopSession() {
        let session = self.session
        sessionQueue.async { [weak self] in
            guard let self, session.isRunning else { return }
            session.stopRunning()
            DispatchQueue.main.async { self.sessionIsRunning = false }
        }
    }

    // MARK: - Session configuration (nonisolated — runs on sessionQueue)

    nonisolated private func configureIfNeeded(
        session:     AVCaptureSession,
        sampleQueue: DispatchQueue,
        threadState: CameraThreadState
    ) {
        guard !threadState.isConfigured else { return }
        threadState.isConfigured = true

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .hd1280x720

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input  = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { postError("Could not access the back camera."); return }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sampleQueue)

        guard session.canAddOutput(output) else { postError("Could not add video output."); return }
        session.addOutput(output)

        if let conn = output.connection(with: .video), conn.isVideoRotationAngleSupported(90) {
            conn.videoRotationAngle = 90
        }
    }

    nonisolated private func postError(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.errorMessage = message }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Throttle to ~20 fps. threadState has no actor isolation so this
        // read/write is direct — no stale values, no queued hops.
        let now = CACurrentMediaTime()
        guard now - threadState.lastSampleTime >= 0.05 else { return }
        threadState.lastSampleTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width       = CVPixelBufferGetWidth(pixelBuffer)
        let height      = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base  = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        // Read center pixel — BGRA layout
        let offset = (height / 2) * bytesPerRow + (width / 2) * 4
        let pixel  = base.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
        let b = pixel[0], g = pixel[1], r = pixel[2]

        // ColorEngine.identify() is ~10µs — fast enough to run on MainActor.
        // Skip the update when frozen so the card holds its last value.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isFrozen else { return }
            self.identifiedColor = self.colorEngine.identify(r: r, g: g, b: b)
        }
    }

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) { }
}
