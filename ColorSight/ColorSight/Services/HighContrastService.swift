import CoreVideo
import Metal

/// Per-frame brightness/contrast enhancement for visibility in low light.
///
/// Boosts only the brightness (V) channel in HSB space — hue and saturation pass
/// through unchanged, so a color's identity never shifts (blue never reads as purple).
/// This is a display-only filter: CameraViewModel's color-sampling delegate always
/// reads the original, unprocessed CVPixelBuffer — this service only ever writes to a
/// separate output buffer wrapped for AVSampleBufferDisplayLayer.
///
/// Mirrors HueIsolationService's GPU/CPU dual-path structure.
final class HighContrastService: @unchecked Sendable {

    // MARK: - Metal objects (nil → CPU fallback active)

    private let metalDevice:   MTLDevice?
    private let commandQueue:  MTLCommandQueue?
    private let pipelineState: MTLComputePipelineState?
    private let textureCache:  CVMetalTextureCache?

    /// Multiplier applied around the midpoint of brightness; >1 increases contrast.
    private let contrast: Float = 1.35
    /// Flat additive lift to brightness — helps genuinely dark scenes read as more than
    /// a black screen, without touching the sensor's own exposure/gain (which would
    /// alter the raw pixel values the color sampler reads).
    private let brightnessLift: Float = 0.12

    // MARK: - Init

    init() {
        guard
            let device  = MTLCreateSystemDefaultDevice(),
            let cq      = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary(),
            let fn      = library.makeFunction(name: "highContrastEnhance"),
            let ps      = try? device.makeComputePipelineState(function: fn)
        else {
            (metalDevice, commandQueue, pipelineState, textureCache) = (nil, nil, nil, nil)
            return
        }
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess,
              let cache
        else {
            (metalDevice, commandQueue, pipelineState, textureCache) = (nil, nil, nil, nil)
            return
        }
        metalDevice   = device
        commandQueue  = cq
        pipelineState = ps
        textureCache  = cache
    }

    // MARK: - Public entry point

    /// Applies the contrast/brightness boost to `input` and writes the result into
    /// `output`. Returns true if output was written successfully (GPU or CPU path).
    /// The caller wraps `output` in a CMSampleBuffer and enqueues it for display.
    nonisolated func process(input: CVPixelBuffer, output: CVPixelBuffer) -> Bool {
        if let device = metalDevice, let cq = commandQueue,
           let ps = pipelineState, let tc = textureCache {
            return processGPU(input: input, output: output, device: device, cq: cq, ps: ps, tc: tc)
        }
        processCPU(input: input, output: output)
        return true
    }

    // MARK: - GPU path

    nonisolated private func processGPU(
        input: CVPixelBuffer, output: CVPixelBuffer,
        device: MTLDevice, cq: MTLCommandQueue,
        ps: MTLComputePipelineState, tc: CVMetalTextureCache
    ) -> Bool {
        let w = CVPixelBufferGetWidth(input)
        let h = CVPixelBufferGetHeight(input)

        var inRef: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, tc, input, nil, .bgra8Unorm, w, h, 0, &inRef
        ) == kCVReturnSuccess, let inRef else { return false }

        let outAttrs = [kCVMetalTextureUsage:
            NSNumber(value: MTLTextureUsage([.shaderRead, .shaderWrite]).rawValue)
        ] as CFDictionary
        var outRef: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, tc, output, outAttrs, .bgra8Unorm, w, h, 0, &outRef
        ) == kCVReturnSuccess, let outRef else { return false }

        guard let inTex  = CVMetalTextureGetTexture(inRef),
              let outTex = CVMetalTextureGetTexture(outRef) else { return false }

        guard let cmdBuf  = cq.makeCommandBuffer(),
              let encoder = cmdBuf.makeComputeCommandEncoder() else { return false }

        encoder.setComputePipelineState(ps)
        encoder.setTexture(inTex,  index: 0)
        encoder.setTexture(outTex, index: 1)

        var params = HighContrastParams(contrast: contrast, brightnessLift: brightnessLift)
        encoder.setBytes(&params, length: MemoryLayout<HighContrastParams>.size, index: 0)

        encoder.dispatchThreads(
            MTLSize(width: w, height: h, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        // Flush the cache so the output CVPixelBuffer's IOSurface is up to date
        // and safe to wrap in a CMSampleBuffer for AVSampleBufferDisplayLayer.
        CVMetalTextureCacheFlush(tc, 0)

        return true
    }

    // MARK: - CPU fallback path

    // Writes processed pixels to `output` but returns no display artifact.
    // Called only on non-Metal hardware; all iOS 26 devices have Metal.
    nonisolated private func processCPU(input: CVPixelBuffer, output: CVPixelBuffer) {
        let width  = CVPixelBufferGetWidth(input)
        let height = CVPixelBufferGetHeight(input)

        guard CVPixelBufferGetWidth(output)  == width,
              CVPixelBufferGetHeight(output) == height else { return }

        guard CVPixelBufferLockBaseAddress(input,  [.readOnly]) == kCVReturnSuccess,
              CVPixelBufferLockBaseAddress(output, [])           == kCVReturnSuccess
        else { return }
        defer {
            CVPixelBufferUnlockBaseAddress(output, [])
            CVPixelBufferUnlockBaseAddress(input,  [.readOnly])
        }

        guard let srcBase = CVPixelBufferGetBaseAddress(input),
              let dstBase = CVPixelBufferGetBaseAddress(output) else { return }

        let srcBPR = CVPixelBufferGetBytesPerRow(input)
        let dstBPR = CVPixelBufferGetBytesPerRow(output)
        let srcBuf = UnsafeRawBufferPointer(start: srcBase, count: height * srcBPR)
        let dstBuf = UnsafeMutableRawBufferPointer(start: dstBase, count: height * dstBPR)

        let contrastD       = Double(contrast)
        let brightnessLiftD = Double(brightnessLift)

        for row in 0..<height {
            let so = row * srcBPR
            let do_ = row * dstBPR
            for col in 0..<width {
                let si = so + col * 4
                let di = do_ + col * 4
                let b = Double(srcBuf[si])   / 255.0
                let g = Double(srcBuf[si+1]) / 255.0
                let r = Double(srcBuf[si+2]) / 255.0

                let (h, s, v) = Self.rgbToHSB(r: r, g: g, b: b)
                let v2 = min(max((v - 0.5) * contrastD + 0.5 + brightnessLiftD, 0), 1)
                let (r2, g2, b2) = Self.hsbToRGB(h: h, s: s, v: v2)

                dstBuf[di]   = UInt8(clamping: Int((b2 * 255).rounded()))
                dstBuf[di+1] = UInt8(clamping: Int((g2 * 255).rounded()))
                dstBuf[di+2] = UInt8(clamping: Int((r2 * 255).rounded()))
                dstBuf[di+3] = 255
            }
        }
    }

    nonisolated private static func rgbToHSB(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let maxC  = max(r, max(g, b))
        let minC  = min(r, min(g, b))
        let delta = maxC - minC
        let brightness = maxC
        let saturation = maxC > 0.001 ? delta / maxC : 0

        var hue = 0.0
        if delta > 0.001 {
            if maxC == r {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) * 60
            } else if maxC == g {
                hue = ((b - r) / delta + 2) * 60
            } else {
                hue = ((r - g) / delta + 4) * 60
            }
            if hue < 0 { hue += 360 }
        }
        return (hue, saturation, brightness)
    }

    nonisolated private static func hsbToRGB(h: Double, s: Double, v: Double) -> (r: Double, g: Double, b: Double) {
        let c  = v * s
        let hp = h / 60
        let x  = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))

        let rgb1: (Double, Double, Double)
        switch hp {
        case ..<1:  rgb1 = (c, x, 0)
        case ..<2:  rgb1 = (x, c, 0)
        case ..<3:  rgb1 = (0, c, x)
        case ..<4:  rgb1 = (0, x, c)
        case ..<5:  rgb1 = (x, 0, c)
        default:    rgb1 = (c, 0, x)
        }
        let m = v - c
        return (rgb1.0 + m, rgb1.1 + m, rgb1.2 + m)
    }
}

// MARK: - GPU constants (layout must match HighContrastParams in HighContrast.metal)

private struct HighContrastParams {
    var contrast: Float
    var brightnessLift: Float
}
