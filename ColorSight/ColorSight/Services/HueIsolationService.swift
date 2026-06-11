import CoreVideo
import Metal

/// Per-frame hue isolation filter (color-splash effect).
///
/// Primary path — Metal GPU compute:
///   CVPixelBuffers are wrapped as MTLTextures via CVMetalTextureCache (zero copy).
///   The `hueIsolate` kernel classifies pixels entirely on the GPU and returns
///   the output MTLTexture for direct display in HueIsolationMetalView — no CPU
///   readback, no UIImage, no CIContext.
///
/// Fallback path — CPU per-pixel loop:
///   Writes processed pixels to the output CVPixelBuffer but returns nil (no
///   MTKView display) — used only on non-Metal hardware, which iOS 26 devices
///   never are.
///
/// Threading: all methods are safe to call from any thread.
final class HueIsolationService: @unchecked Sendable {

    // MARK: - Metal objects (nil → CPU fallback active)

    private let metalDevice:   MTLDevice?
    private let commandQueue:  MTLCommandQueue?
    private let pipelineState: MTLComputePipelineState?
    private let textureCache:  CVMetalTextureCache?

    // MARK: - Init

    init() {
        guard
            let device  = MTLCreateSystemDefaultDevice(),
            let cq      = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary(),
            let fn      = library.makeFunction(name: "hueIsolate"),
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

    // MARK: - Buffer management

    /// Allocates an IOSurface-backed, Metal-compatible output pixel buffer matching
    /// the dimensions and format of `input`. Call once per session and reuse.
    nonisolated static func makeOutputBuffer(matchingFormat input: CVPixelBuffer) -> CVPixelBuffer? {
        let width  = CVPixelBufferGetWidth(input)
        let height = CVPixelBufferGetHeight(input)
        let format = CVPixelBufferGetPixelFormatType(input)

        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey:  true
        ]
        var buf: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, format,
                                         attrs as CFDictionary, &buf)
        return status == kCVReturnSuccess ? buf : nil
    }

    // MARK: - Public entry point

    /// Applies hue isolation to `input` and writes the result into `output`.
    /// Returns true if output was written successfully (GPU or CPU path).
    /// The caller wraps `output` in a CMSampleBuffer and enqueues it for display.
    nonisolated func process(input: CVPixelBuffer, family: HueFamily,
                             output: CVPixelBuffer) -> Bool {
        if let device = metalDevice, let cq = commandQueue,
           let ps = pipelineState, let tc = textureCache {
            return processGPU(input: input, family: family, output: output,
                              device: device, cq: cq, ps: ps, tc: tc)
        }
        processCPU(input: input, family: family, output: output)
        return true
    }

    // MARK: - GPU path

    nonisolated private func processGPU(
        input:  CVPixelBuffer, family: HueFamily, output: CVPixelBuffer,
        device: MTLDevice, cq: MTLCommandQueue,
        ps:     MTLComputePipelineState, tc: CVMetalTextureCache
    ) -> Bool {
        let w = CVPixelBufferGetWidth(input)
        let h = CVPixelBufferGetHeight(input)

        // Wrap both CVPixelBuffers as MTLTextures via the cache — zero CPU-GPU copy.
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

        var params = HueIsolationParams(family: UInt32(family.metalIndex))
        encoder.setBytes(&params, length: MemoryLayout<HueIsolationParams>.size, index: 0)

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
    nonisolated private func processCPU(input: CVPixelBuffer, family: HueFamily,
                                        output: CVPixelBuffer) {
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

        for row in 0..<height {
            let so = row * srcBPR
            let do_ = row * dstBPR
            for col in 0..<width {
                let si = so + col * 4
                let di = do_ + col * 4
                let b = srcBuf[si]; let g = srcBuf[si+1]; let r = srcBuf[si+2]
                if family.matches(r: r, g: g, b: b) {
                    dstBuf[di]=b; dstBuf[di+1]=g; dstBuf[di+2]=r; dstBuf[di+3]=255
                } else {
                    let lumaRaw: UInt32 = 299*UInt32(r) + 587*UInt32(g) + 114*UInt32(b)
                    let luma = UInt8(lumaRaw / 1000)
                    dstBuf[di]=luma; dstBuf[di+1]=luma; dstBuf[di+2]=luma; dstBuf[di+3]=255
                }
            }
        }
    }
}

// MARK: - GPU constants (layout must match HueIsolationParams in HueIsolation.metal)

private struct HueIsolationParams {
    var family: UInt32
}
