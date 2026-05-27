import SwiftUI
import PhotosUI

// MARK: - ViewModel

/// Manages photo selection and pixel sampling for the eyedropper feature.
/// All state is on the MainActor; pixel reads are fast (single CGContext call).
@Observable
@MainActor
final class EyedropperViewModel {

    // MARK: - UI state

    var displayImage: UIImage?          // Orientation-normalised image ready for display
    var identifiedColor: IdentifiedColor?
    var sampleNorm: CGPoint = CGPoint(x: 0.5, y: 0.5)  // Normalised 0–1 within image
    var isLoadingImage = false

    // MARK: - Internals

    let colorEngine = ColorEngine()

    // MARK: - Photo loading

    /// Load, normalise orientation, scale to display size, and sample the centre pixel.
    func loadImage(from item: PhotosPickerItem) async {
        isLoadingImage = true
        defer { isLoadingImage = false }

        // loadTransferable can throw on iOS 26 if NSPhotoLibraryUsageDescription
        // is missing or if the picker result is unavailable — use do/catch so we
        // see the error rather than silently returning.
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        guard let raw = UIImage(data: data) else { return }

        // Scale + fix orientation in one render pass.
        // Avoids holding two copies of a potentially 48MP image in memory.
        displayImage = raw.scaledForDisplay()
        sampleColor(atNormalized: CGPoint(x: 0.5, y: 0.5))
    }

    // MARK: - Color sampling

    /// Sample the pixel at `point` (normalised 0–1 in image space) and update identifiedColor.
    func sampleColor(atNormalized point: CGPoint) {
        guard let image = displayImage else { return }
        sampleNorm = point
        guard let (r, g, b) = image.pixelColor(atNormalized: point) else { return }
        identifiedColor = colorEngine.identify(r: r, g: g, b: b)
    }

    /// Called when the user lifts their finger after dragging the loupe.
    /// Fires haptics and/or speaks the current color name per the user's preferences.
    func announceCurrentColor() {
        guard let color = identifiedColor else { return }
        let haptics = UserDefaults.standard.object(forKey: "hapticsEnabled")      as? Bool ?? true
        let voice   = UserDefaults.standard.object(forKey: "voiceFeedbackEnabled") as? Bool ?? true
        AccessibilityService.shared.announceColor(color, haptics: haptics, voice: voice)
    }
}

// MARK: - UIImage helpers

extension UIImage {

    /// Returns the image scaled to fit within `maxDimension` points and with orientation
    /// corrected to `.up` — all in a single render pass.
    ///
    /// Doing orientation + scale together avoids holding two full-resolution bitmaps
    /// in memory simultaneously, which can OOM on 48MP ProRAW images.
    func scaledForDisplay(maxDimension: CGFloat = 3_000) -> UIImage {
        let scale = min(maxDimension / max(size.width, size.height), 1.0)
        let target = CGSize(width: (size.width  * scale).rounded(),
                            height: (size.height * scale).rounded())
        // UIGraphicsImageRenderer always produces a `.up` image, so this also
        // fixes orientation without a separate normalisation step.
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Reads the RGBA pixel at a normalised point (0–1) and returns (r, g, b).
    func pixelColor(atNormalized point: CGPoint) -> (r: UInt8, g: UInt8, b: UInt8)? {
        guard let cg = cgImage else { return nil }

        let px = Int((point.x * CGFloat(cg.width)).rounded())
        let py = Int((point.y * CGFloat(cg.height)).rounded())
        let cx = max(0, min(cg.width  - 1, px))
        let cy = max(0, min(cg.height - 1, py))

        guard let crop = cg.cropping(to: CGRect(x: cx, y: cy, width: 1, height: 1)) else { return nil }

        // Use withUnsafeMutableBytes so the buffer is guaranteed pinned in memory
        // for the entire lifetime of the CGContext — including the ctx.draw() call.
        // Passing &pixel directly only pins it for the CGContext.init() call, making
        // the pointer dangle by the time ctx.draw() runs (crash on iOS 26).
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()

        return pixel.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(
                data: ptr.baseAddress,
                width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }

            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return (ptr[0], ptr[1], ptr[2])
        }
    }
}
