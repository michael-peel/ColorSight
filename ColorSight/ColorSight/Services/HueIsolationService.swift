import CoreVideo
import CoreImage
import Metal
import UIKit

/// Per-frame hue isolation filter (color-splash effect).
///
/// Primary path — Metal GPU compute:
///   CVPixelBuffers are wrapped as MTLTextures via CVMetalTextureCache (zero copy).
///   The `hueIsolate` kernel (HueIsolation.metal) classifies pixels entirely on the
///   GPU; the processed buffer is then rendered to UIImage via a GPU-accelerated
///   CIContext. Zero CPU pixel work per frame.
///
/// Fallback path — CPU per-pixel loop:
///   Used automatically if Metal initialisation fails (simulator, unusual hardware).
///
/// Threading: all methods are safe to call from any thread.
final class HueIsolationService: @unchecked Sendable {

    // MARK: - Metal objects (nil → CPU fallback active)

    private let metalDevice:   MTLDevice?
    private let commandQueue:  MTLCommandQueue?
    private let pipelineState: MTLComputePipelineState?
    private let textureCache:  CVMetalTextureCache?

    // GPU-accelerated CIContext — shared by both paths for UIImage conversion.
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

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
    /// the dimensions and format of `input`. Call once at session start and reuse.
    ///
    /// Both attributes are required:
    ///   • IOSurface: CIContext renders GPU-side without a CPU readback.
    ///   • MetalCompatibility: CVMetalTextureCache can wrap the buffer as MTLTexture.
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

    /// Applies hue isolation to `input`, writes the result into `output`,
    /// and returns a UIImage for display.
    nonisolated func process(input: CVPixelBuffer, family: HueFamily, output: CVPixelBuffer) -> UIImage? {
        if let device = metalDevice, let cq = commandQueue,
           let ps = pipelineState, let tc = textureCache {
            return processGPU(input: input, family: family, output: output,
                              device: device, cq: cq, ps: ps, tc: tc)
        }
        return processCPU(input: input, family: family, output: output)
    }

    // MARK: - GPU path

    nonisolated private func processGPU(
        input:  CVPixelBuffer, family: HueFamily, output: CVPixelBuffer,
        device: MTLDevice, cq: MTLCommandQueue,
        ps:     MTLComputePipelineState, tc: CVMetalTextureCache
    ) -> UIImage? {
        let w = CVPixelBufferGetWidth(input)
        let h = CVPixelBufferGetHeight(input)

        // Wrap CVPixelBuffers as MTLTextures via the cache — zero CPU-GPU copy.
        var inRef: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, tc, input, nil, .bgra8Unorm, w, h, 0, &inRef
        ) == kCVReturnSuccess, let inRef else { return nil }

        // Output texture needs shaderWrite so the kernel can write to it.
        let outAttrs = [kCVMetalTextureUsage:
            NSNumber(value: MTLTextureUsage([.shaderRead, .shaderWrite]).rawValue)
        ] as CFDictionary
        var outRef: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, tc, output, outAttrs, .bgra8Unorm, w, h, 0, &outRef
        ) == kCVReturnSuccess, let outRef else { return nil }

        guard let inTex  = CVMetalTextureGetTexture(inRef),
              let outTex = CVMetalTextureGetTexture(outRef) else { return nil }

        guard let cmdBuf  = cq.makeCommandBuffer(),
              let encoder = cmdBuf.makeComputeCommandEncoder() else { return nil }

        encoder.setComputePipelineState(ps)
        encoder.setTexture(inTex,  index: 0)
        encoder.setTexture(outTex, index: 1)

        var params = HueIsolationParams(family: UInt32(family.metalIndex))
        encoder.setBytes(&params, length: MemoryLayout<HueIsolationParams>.size, index: 0)

        // 16×16 threadgroup is cache-efficient for 2-D image processing on Apple GPUs.
        // dispatchThreads handles non-multiple-of-16 image dimensions automatically.
        encoder.dispatchThreads(
            MTLSize(width: w, height: h, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()   // sampleQueue thread; GPU completes in <5 ms on A18 Pro

        CVMetalTextureCacheFlush(tc, 0)

        // Convert to UIImage — CIContext reads from the IOSurface GPU-side, no CPU pixel copy.
        let ci = CIImage(cvPixelBuffer: output)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - CPU fallback path

    nonisolated private func processCPU(input: CVPixelBuffer, family: HueFamily, output: CVPixelBuffer) -> UIImage? {
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

        let ci = CIImage(cvPixelBuffer: output)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - GPU constants (layout must match HueIsolationParams in HueIsolation.metal)

private struct HueIsolationParams {
    var family: UInt32
}
