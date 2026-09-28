@preconcurrency import AVFoundation
import Observation
import UIKit

// MARK: - Background-queue mutable state
//
// These two vars must be read/written from background dispatch queues.
// With SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor (an Xcode 26 project default),
// every stored property in the module is implicitly @MainActor unless
// explicitly opted out. `nonisolated(unsafe)` does that opt-out here.
// Each var is accessed from exactly ONE queue, so no locks are needed.

private final class CameraThreadState: @unchecked Sendable {
    nonisolated(unsafe) var isConfigured  = false               // sessionQueue only
    nonisolated(unsafe) var captureDevice: AVCaptureDevice?      // sessionQueue only

    // Hue isolation — written on MainActor, read on sampleQueue
    nonisolated(unsafe) var isHueIsolationActive = false
    nonisolated(unsafe) var selectedHueFamily    = HueFamily.red
    // High contrast — written on MainActor, read on sampleQueue. Mutually exclusive
    // with hue isolation; both share the display layer/output buffer below since only
    // one display filter is ever active at a time.
    nonisolated(unsafe) var isHighContrastActive = false
    // Set when either display filter activates; nil when both are off. enqueue() is
    // thread-safe.
    nonisolated(unsafe) var isolationDisplayLayer: AVSampleBufferDisplayLayer?
    // Allocated lazily on first filtered frame; reused for the session lifetime
    nonisolated(unsafe) var isolationOutputBuffer: CVPixelBuffer?   // sampleQueue only
    // Frame counter for periodic timing prints
    nonisolated(unsafe) var isolationFrameCount: UInt64 = 0         // sampleQueue only
    // @unchecked Sendable services; safe to call from sampleQueue
    let hueIsolationService  = HueIsolationService()
    let highContrastService  = HighContrastService()
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
    var isTorchOn = false
    var zoomFactor: CGFloat = 1.0

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

    // MARK: - White balance calibration

    /// True once the user has calibrated against a white/gray reference and the device
    /// is locked to the corrected gains. Reset whenever the session stops (see
    /// `stopSession()`), same as torch/zoom, so each camera session starts fresh.
    var isWhiteBalanceCalibrated = false
    /// Momentary trigger — set true when a calibration attempt fails (reference too
    /// dark). CameraView observes this, shows feedback, then resets it to false.
    var whiteBalanceCalibrationFailed = false

    // MARK: - Hue Isolation state

    var isHueIsolationActive = false {
        didSet {
            threadState.isHueIsolationActive = isHueIsolationActive
            if isHueIsolationActive {
                // Only one display filter can drive the layer at a time.
                if isHighContrastActive { isHighContrastActive = false }
                // Give sampleQueue a reference so it can enqueue without a main-thread hop.
                threadState.isolationDisplayLayer = isolationDisplayLayer
            } else if !isHighContrastActive {
                threadState.isolationDisplayLayer = nil
                isolationDisplayLayer.sampleBufferRenderer
                    .flush(removingDisplayedImage: true, completionHandler: nil)
            }
        }
    }
    var selectedHueFamily: HueFamily = .red {
        didSet { threadState.selectedHueFamily = selectedHueFamily }
    }

    /// Boosts on-screen brightness/contrast for visibility in low light — hue and
    /// saturation are untouched, so identified colors never shift (see
    /// HighContrastService). Mutually exclusive with hue isolation; both drive the
    /// same display layer, so only one filter is ever active at a time.
    var isHighContrastActive = false {
        didSet {
            threadState.isHighContrastActive = isHighContrastActive
            if isHighContrastActive {
                if isHueIsolationActive { isHueIsolationActive = false }
                threadState.isolationDisplayLayer = isolationDisplayLayer
            } else if !isHueIsolationActive {
                threadState.isolationDisplayLayer = nil
                isolationDisplayLayer.sampleBufferRenderer
                    .flush(removingDisplayedImage: true, completionHandler: nil)
            }
        }
    }

    /// AVSampleBufferDisplayLayer owned here so sampleQueue can enqueue processed
    /// CVPixelBuffers directly without dispatching to the main thread each frame.
    /// Shared by hue isolation and high contrast — never both at once.
    let isolationDisplayLayer = AVSampleBufferDisplayLayer()

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
        let session    = self.session
        let threadState = self.threadState
        sessionQueue.async { [weak self] in
            guard let self, session.isRunning else { return }
            // Turn off the torch, reset zoom, and clear any white balance calibration
            // before stopping the session, so the next time the camera opens it starts
            // from a predictable, un-zoomed, auto-white-balanced state.
            Self.setTorch(false, device: threadState.captureDevice)
            Self.setZoom(1.0, device: threadState.captureDevice)
            Self.resetWhiteBalanceMode(device: threadState.captureDevice)
            session.stopRunning()
            DispatchQueue.main.async {
                self.sessionIsRunning = false
                self.isTorchOn = false
                self.zoomFactor = 1.0
                self.isWhiteBalanceCalibrated = false
            }
        }
    }

    /// Toggles the rear torch on/off.
    func toggleTorch() {
        let wantOn     = !isTorchOn
        let threadState = self.threadState
        sessionQueue.async { [weak self] in
            guard Self.setTorch(wantOn, device: threadState.captureDevice) else { return }
            DispatchQueue.main.async { self?.isTorchOn = wantOn }
        }
    }

    /// Sets the torch mode. Returns true if the change succeeded.
    @discardableResult
    nonisolated private static func setTorch(_ on: Bool, device: AVCaptureDevice?) -> Bool {
        guard let device, device.hasTorch, device.isTorchAvailable else { return false }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            return true
        } catch {
            return false
        }
    }

    /// Live pinch-to-zoom entry point. Sets `videoZoomFactor` directly on the capture
    /// device, so the CMSampleBuffer the color-sampling delegate reads already reflects
    /// the zoomed frame — the center-pixel and area-average sampling in
    /// `captureOutput(_:didOutput:from:)` need no changes to stay correct at any zoom level.
    func setZoomFactor(_ factor: CGFloat) {
        let threadState = self.threadState
        sessionQueue.async { [weak self] in
            guard let self, let device = threadState.captureDevice else { return }
            let maxZoom = min(device.maxAvailableVideoZoomFactor, Self.maxUsableZoomFactor)
            let clamped = min(max(factor, device.minAvailableVideoZoomFactor), maxZoom)
            guard Self.setZoom(clamped, device: device) else { return }
            DispatchQueue.main.async { self.zoomFactor = clamped }
        }
    }

    /// Beyond ~5x, digital zoom on the single wide-angle lens is heavily interpolated —
    /// capped here so zoomed color samples stay meaningfully accurate.
    private static let maxUsableZoomFactor: CGFloat = 5.0

    /// Sets the zoom factor. Returns true if the change succeeded. Caller is
    /// responsible for clamping to the device's supported range.
    @discardableResult
    nonisolated private static func setZoom(_ factor: CGFloat, device: AVCaptureDevice?) -> Bool {
        guard let device else { return false }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = factor
            device.unlockForConfiguration()
            return true
        } catch {
            return false
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
        threadState.captureDevice = device

        // Lock capture to exactly 30fps. At 7–9 ms GPU processing per frame this
        // leaves ~24 ms of headroom and produces smooth, consistent frame delivery.
        do {
            try device.lockForConfiguration()
            let thirtyFPS = CMTime(value: 1, timescale: 30)
            device.activeVideoMinFrameDuration = thirtyFPS
            device.activeVideoMaxFrameDuration = thirtyFPS
            device.unlockForConfiguration()
        } catch {
            // Non-critical — device runs at its default rate if lock fails.
        }

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

    // MARK: - White balance calibration (MainActor entry points, run on sessionQueue)

    /// Locks the camera's white balance using `measured` as a white/gray reference —
    /// the user has just tapped a spot they identified as neutral. Reads the device's
    /// current auto-WB gains, computes the correction (see `WhiteBalanceCalibration`),
    /// and locks the device to the corrected gains.
    ///
    /// This corrects the raw `CVPixelBuffer` itself (in the ISP, before it ever reaches
    /// `captureOutput`), so live color ID, Hue Isolation, and High Contrast all inherit
    /// the correction automatically — no changes needed in `ColorEngine`,
    /// `HueIsolationService`, or the Metal kernel.
    func calibrateWhiteBalance(using measured: IdentifiedColor.RGBComponents) {
        let threadState = self.threadState
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let succeeded = Self.applyWhiteBalanceCalibration(
                measuredR: Double(measured.r), measuredG: Double(measured.g), measuredB: Double(measured.b),
                device: threadState.captureDevice
            )
            DispatchQueue.main.async {
                if succeeded {
                    self.isWhiteBalanceCalibrated = true
                } else {
                    self.whiteBalanceCalibrationFailed = true
                }
            }
        }
    }

    /// Resets white balance to continuous auto — the one-tap "undo" for calibration.
    func resetWhiteBalance() {
        let threadState = self.threadState
        sessionQueue.async { [weak self] in
            guard let self else { return }
            Self.resetWhiteBalanceMode(device: threadState.captureDevice)
            DispatchQueue.main.async { self.isWhiteBalanceCalibrated = false }
        }
    }

    /// Reads the device's current auto-WB gains, computes the corrected gains for
    /// `measured` via `WhiteBalanceCalibration`, and locks the device to them. Returns
    /// false (no-op) if the device doesn't support locked white balance or the
    /// reference sample is too dark to trust.
    @discardableResult
    nonisolated private static func applyWhiteBalanceCalibration(
        measuredR: Double, measuredG: Double, measuredB: Double, device: AVCaptureDevice?
    ) -> Bool {
        guard let device, device.isWhiteBalanceModeSupported(.locked) else { return false }
        let current = device.deviceWhiteBalanceGains
        guard let corrected = WhiteBalanceCalibration.correctedGains(
            measuredR: measuredR, measuredG: measuredG, measuredB: measuredB,
            currentGains: .init(
                red:   Double(current.redGain),
                green: Double(current.greenGain),
                blue:  Double(current.blueGain)
            ),
            maxGain: Double(device.maxWhiteBalanceGain)
        ) else { return false }

        do {
            try device.lockForConfiguration()
            device.setWhiteBalanceModeLocked(with: AVCaptureDevice.WhiteBalanceGains(
                redGain:   Float(corrected.red),
                greenGain: Float(corrected.green),
                blueGain:  Float(corrected.blue)
            ))
            device.unlockForConfiguration()
            return true
        } catch {
            return false
        }
    }

    /// Sets the white balance mode back to continuous auto. Returns true if the change
    /// succeeded.
    @discardableResult
    nonisolated private static func resetWhiteBalanceMode(device: AVCaptureDevice?) -> Bool {
        guard let device, device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) else { return false }
        do {
            try device.lockForConfiguration()
            device.whiteBalanceMode = .continuousAutoWhiteBalance
            device.unlockForConfiguration()
            return true
        } catch {
            return false
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
        // Frame rate is hardware-locked to 30fps via activeVideoMinFrameDuration /
        // activeVideoMaxFrameDuration; no software throttle needed.
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
        if (UserDefaults.standard.object(forKey: "regionSamplingEnabled") as? Bool) ?? true {
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

        // Display filters — hue isolation and high contrast are mutually exclusive,
        // both share isolationOutputBuffer/isolationDisplayLayer. GPU kernel writes to
        // outBuffer; we wrap it in a CMSampleBuffer and enqueue directly on
        // sampleQueue — no main-thread dispatch per frame. Neither filter ever touches
        // `pixelBuffer` itself, so the color sample taken above is always unaffected.
        if threadState.isHueIsolationActive {
            threadState.isolationFrameCount &+= 1
            if threadState.isolationOutputBuffer == nil {
                threadState.isolationOutputBuffer =
                    HueIsolationService.makeOutputBuffer(matchingFormat: pixelBuffer)
            }
            if let outBuffer = threadState.isolationOutputBuffer {
                let t0 = CACurrentMediaTime()
                let wrote = threadState.hueIsolationService.process(
                    input:  pixelBuffer,
                    family: threadState.selectedHueFamily,
                    output: outBuffer
                )
                let ms = (CACurrentMediaTime() - t0) * 1000
                if threadState.isolationFrameCount.isMultiple(of: 30) {
                    print("[HueIsolation] \(String(format: "%.1f", ms)) ms/frame")
                }
                if wrote, let sampleBuf = Self.makeSampleBuffer(from: outBuffer) {
                    threadState.isolationDisplayLayer?.enqueue(sampleBuf)
                }
            }
        } else if threadState.isHighContrastActive {
            threadState.isolationFrameCount &+= 1
            if threadState.isolationOutputBuffer == nil {
                threadState.isolationOutputBuffer =
                    HueIsolationService.makeOutputBuffer(matchingFormat: pixelBuffer)
            }
            if let outBuffer = threadState.isolationOutputBuffer {
                let wrote = threadState.highContrastService.process(
                    input:  pixelBuffer,
                    output: outBuffer
                )
                if wrote, let sampleBuf = Self.makeSampleBuffer(from: outBuffer) {
                    threadState.isolationDisplayLayer?.enqueue(sampleBuf)
                }
            }
        }
    }

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) { }

    // MARK: - CMSampleBuffer helper

    /// Wraps a CVPixelBuffer in a CMSampleBuffer stamped with the current host time.
    /// AVSampleBufferDisplayLayer.enqueue() is thread-safe; call from any queue.
    nonisolated private static func makeSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        ) == noErr, let formatDescription else { return nil }

        var timingInfo = CMSampleTimingInfo(
            duration:              .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp:       .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateForImageBuffer(
            allocator:             kCFAllocatorDefault,
            imageBuffer:           pixelBuffer,
            dataReady:             true,
            makeDataReadyCallback: nil,
            refcon:                nil,
            formatDescription:     formatDescription,
            sampleTiming:          &timingInfo,
            sampleBufferOut:       &sampleBuffer
        ) == noErr else { return nil }
        return sampleBuffer
    }

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
