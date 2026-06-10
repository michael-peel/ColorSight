import CoreVideo
import CoreImage
import UIKit

/// Stateless, thread-safe service that applies a per-pixel hue isolation filter
/// to a CVPixelBuffer (color-splash effect).
///
/// Pixels whose HSB values match the selected HueFamily are written to the output
/// buffer unchanged. All other pixels are converted to grayscale using the
/// standard luminance formula (ITU-R BT.601).
///
/// Threading: safe to call from any thread. The caller is responsible for ensuring
/// the input and output buffers are not accessed concurrently from another thread
/// while process() is running.
final class HueIsolationService: @unchecked Sendable {

    // CIContext is thread-safe per Apple documentation. Holding one instance
    // avoids the cost of Metal device/queue allocation on every frame.
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Buffer management

    /// Allocates an output pixel buffer with the same dimensions and pixel format
    /// as `input`. Call once at session start and reuse the result across frames.
    static func makeOutputBuffer(matchingFormat input: CVPixelBuffer) -> CVPixelBuffer? {
        let width  = CVPixelBufferGetWidth(input)
        let height = CVPixelBufferGetHeight(input)
        let format = CVPixelBufferGetPixelFormatType(input)

        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, format,
            nil, &outputBuffer
        )
        return status == kCVReturnSuccess ? outputBuffer : nil
    }

    // MARK: - Processing

    /// Applies hue isolation to `input`, writing the result into `output`,
    /// then returns a UIImage built from the processed frame.
    ///
    /// - Parameters:
    ///   - input:  Source frame from AVFoundation (kCVPixelFormatType_32BGRA).
    ///   - family: Hue family whose pixels are kept in color; all others → grayscale.
    ///   - output: Caller-owned buffer; must match `input` in dimensions and format.
    ///             Create once with `makeOutputBuffer(matchingFormat:)` and reuse.
    /// - Returns: A UIImage of the processed frame, or nil on lock/dimension failure.
    func process(input: CVPixelBuffer, family: HueFamily, output: CVPixelBuffer) -> UIImage? {
        let width  = CVPixelBufferGetWidth(input)
        let height = CVPixelBufferGetHeight(input)

        guard CVPixelBufferGetWidth(output)  == width,
              CVPixelBufferGetHeight(output) == height else { return nil }

        guard CVPixelBufferLockBaseAddress(input,  [.readOnly]) == kCVReturnSuccess,
              CVPixelBufferLockBaseAddress(output, [])           == kCVReturnSuccess
        else { return nil }

        defer {
            CVPixelBufferUnlockBaseAddress(output, [])
            CVPixelBufferUnlockBaseAddress(input,  [.readOnly])
        }

        guard let srcBase = CVPixelBufferGetBaseAddress(input),
              let dstBase = CVPixelBufferGetBaseAddress(output) else { return nil }

        let srcBPR = CVPixelBufferGetBytesPerRow(input)
        let dstBPR = CVPixelBufferGetBytesPerRow(output)

        // Flat buffer pointers over the full frame. Sequential access (row-major,
        // left-to-right) is cache-friendly; the CPU prefetcher handles the rest.
        // srcBPR / dstBPR may include trailing padding bytes per row, so we index
        // with per-row offsets rather than assuming a stride of width * 4.
        let srcBuf = UnsafeRawBufferPointer(
            start: srcBase, count: height * srcBPR
        )
        let dstBuf = UnsafeMutableRawBufferPointer(
            start: dstBase, count: height * dstBPR
        )

        for row in 0..<height {
            let srcRowOffset = row * srcBPR
            let dstRowOffset = row * dstBPR

            for col in 0..<width {
                let si = srcRowOffset + col * 4   // BGRA: B=+0 G=+1 R=+2 A=+3
                let di = dstRowOffset + col * 4

                let b = srcBuf[si]
                let g = srcBuf[si + 1]
                let r = srcBuf[si + 2]

                if family.matches(r: r, g: g, b: b) {
                    dstBuf[di]     = b
                    dstBuf[di + 1] = g
                    dstBuf[di + 2] = r
                    dstBuf[di + 3] = 255
                } else {
                    // ITU-R BT.601 luma, integer-only to avoid Float promotion per pixel.
                    // Max intermediate value: 1000 * 255 = 255_000, safe in UInt32.
                    let lumaRaw: UInt32 = 299 * UInt32(r) + 587 * UInt32(g) + 114 * UInt32(b)
                    let luma = UInt8(lumaRaw / 1000)
                    dstBuf[di]     = luma
                    dstBuf[di + 1] = luma
                    dstBuf[di + 2] = luma
                    dstBuf[di + 3] = 255
                }
            }
        }

        // Convert the processed output buffer to a UIImage while it is still locked.
        // CIImage holds a reference to the locked buffer; createCGImage performs a
        // GPU-accelerated render into an independent backing store before we unlock.
        let ciImage = CIImage(cvPixelBuffer: output)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
