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
    nonisolated(unsafe) var isConfigured   = false               // sessionQueue only
    nonisolated(unsafe) var lastSampleTime: Double = 0           // sampleQueue only
    nonisolated(unsafe) var captureDevice: AVCaptureDevice?      // sessionQueue only
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
    var isFrozen = false {
        didSet {
            // Announce the current color whenever the user freezes the camera.
            // Unfreezing is silent — no need to re-read a color that's about to change.
            guard isFrozen, let color = identifiedColor else { return }
            let haptics = UserDefaults.standard.object(forKey: "hapticsEnabled")      as? Bool ?? true
            let voice   = UserDefaults.standard.object(forKey: "voiceFeedbackEnabled") as? Bool ?? true
            AccessibilityService.shared.announceColor(color, haptics: haptics, voice: voice)
        }
    }
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
        threadState.captureDevice = device   // kept for refocus()

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

    // MARK: - Refocus (MainActor entry point, runs on sessionQueue)

    func refocus() {
        let threadState = self.threadState
        sessionQueue.async {
            guard let device = threadState.captureDevice else { return }
            do {
                try device.lockForConfiguration()
                let center = CGPoint(x: 0.5, y: 0.5)
                // Re-trigger continuous AF — resets any locked or drifted focus.
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusPointOfInterest = center
                    device.focusMode = .continuousAutoFocus
                } else if device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = center
                    device.focusMode = .autoFocus
                }
                // Reset exposure at the same point for consistency.
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = center
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {
                // Non-critical — silently ignore
            }
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

        // Sample the center — either a single pixel or an averaged 21×21 region.
        // UserDefaults is thread-safe; reading a Bool here is fast (~µs).
        let r: UInt8, g: UInt8, b: UInt8
        if UserDefaults.standard.bool(forKey: "regionSamplingEnabled") {
            (r, g, b) = Self.averageRegion(
                base: base, width: width, height: height,
                bytesPerRow: bytesPerRow,
                cx: width / 2, cy: height / 2, radius: 10   // 21×21 = 441 pixels
            )
        } else {
            let offset = (height / 2) * bytesPerRow + (width / 2) * 4
            let pixel  = base.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
            (r, g, b) = (pixel[2], pixel[1], pixel[0])      // BGRA → RGB
        }

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

    // MARK: - Region averaging

    /// Averages all pixels in a (2*radius+1) × (2*radius+1) square centered on (cx, cy).
    /// Returns the mean R, G, B as UInt8. BGRA pixel layout assumed.
    nonisolated private static func averageRegion(
        base: UnsafeRawPointer,
        width: Int, height: Int, bytesPerRow: Int,
        cx: Int, cy: Int, radius: Int
    ) -> (r: UInt8, g: UInt8, b: UInt8) {
        var sumR = 0, sumG = 0, sumB = 0, n = 0

        let rowMin = max(0, cy - radius);  let rowMax = min(height - 1, cy + radius)
        let colMin = max(0, cx - radius);  let colMax = min(width  - 1, cx + radius)

        for row in rowMin...rowMax {
            for col in colMin...colMax {
                let px = base
                    .advanced(by: row * bytesPerRow + col * 4)
                    .assumingMemoryBound(to: UInt8.self)
                sumB += Int(px[0]); sumG += Int(px[1]); sumR += Int(px[2])
                n += 1
            }
        }

        guard n > 0 else { return (0, 0, 0) }
        return (r: UInt8(sumR / n), g: UInt8(sumG / n), b: UInt8(sumB / n))
    }
}
