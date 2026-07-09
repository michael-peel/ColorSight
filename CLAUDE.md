# ColorSight — Project Context for Claude Code

> Keep this file up to date. Every architectural decision, pattern, or convention should be recorded here so Claude Code sessions start with full context, not a blank slate. Update it whenever something significant changes.

---

## What This App Does

**ColorSight** is an iPhone app for colorblind users. It identifies colors in real time using the camera or a photo, names them in plain English (e.g., "Sky blue", "Olive"), and adapts its output to the user's specific Color Vision Deficiency (CVD) profile.

Two core features:
1. **Live camera color ID** — tap to sample the pixel at the center of the live viewfinder. Sub-100ms target.
2. **Screenshot eyedropper** — import a photo or still shot, drag a magnified loupe, sample in real time.

Supporting features: color history library, VoiceOver announcements, haptic feedback, color export/share.

---

## Developer Background

- CS degree; fluent in C, Java, Python.
- New to Swift and iOS — will pick it up quickly with Claude's help.
- Role: understand all generated code, own all architectural and product decisions.
- Claude generates the majority of code; developer reviews, reasons about it, and directs.

---

## Hardware

| Device | Notes |
|--------|-------|
| MacBook Neo (2026), A18 Pro, 8GB RAM | Dedicated solely to this project |
| iPhone 15 Pro Max | Personal + test device. Dev builds are safe on personal phones. |

---

## Tech Stack

| Layer | Choice | Notes |
|-------|--------|-------|
| UI | SwiftUI | iOS 26.0 minimum, iOS 26 target |
| Architecture | MVVM | Using `@Observable` (iOS 17+), NOT `ObservableObject` |
| Camera | AVFoundation | Continuous video feed, pixel sampling from `CMSampleBuffer` on background thread |
| Photos | PhotosUI | `PhotosPicker` for library import |
| Image processing | Vision + Core Image | Dominant color extraction, color region detection, loupe zoom pipeline |
| Persistence | SwiftData | Color history, user preferences |
| Cloud sync | CloudKit | **Future** — add when paid dev account enrolled |
| Settings | UserDefaults | CVD profile, accessibility prefs |
| Color naming | Local DB (bundled) | ~1,500–2,000 named colors, ~500KB. Nearest-neighbor in HSL/LAB. No API calls. |

**Do not use `ObservableObject` or `@Published`.** Use `@Observable` (Swift 5.9 macro, iOS 17+) throughout.

**iOS deployment target: 26.0** (iPhone is on iOS 26.4.2)

---

## CVD Profiles

Users self-select one profile during onboarding. Stored in `UserDefaults` under key `"cvdProfile"`. Changeable anytime in Settings.

| Profile | Type | Notes |
|---------|------|-------|
| `deuteranopia` | Red-green (most common) | |
| `protanopia` | Red deficiency | |
| `tritanopia` | Blue-yellow | |
| `achromatopsia` | Full color blindness | |
| `custom` | User-defined | User sets their own parameters |

The CVD profile affects:
- **Color name descriptions** — phrasing adapted so the description is meaningful to that user
- **App UI colors** — use CVD-safe palettes when rendering swatches, UI chrome
- **VoiceOver announcements** — phrasing and detail level per profile

---

## Project File Structure (Target)

```
ColorSight/
├── CLAUDE.md                      ← this file (project root, not inside Xcode project)
├── ColorSight.xcodeproj/
└── ColorSight/
    ├── App/
    │   ├── ColorSightApp.swift    ← @main entry point
    │   └── ContentView.swift      ← root view / navigation shell
    ├── Features/
    │   ├── Camera/                ← Live camera color ID
    │   │   ├── CameraView.swift
    │   │   └── CameraViewModel.swift
    │   ├── Eyedropper/            ← Screenshot loupe feature
    │   │   ├── EyedropperView.swift
    │   │   └── EyedropperViewModel.swift
    │   ├── History/               ← Color history library
    │   │   ├── HistoryView.swift
    │   │   └── HistoryViewModel.swift
    │   └── Onboarding/            ← CVD profile selection
    │       ├── OnboardingView.swift
    │       └── OnboardingViewModel.swift
    ├── Services/
    │   ├── ColorEngine.swift      ← RGB → name, hex, HSL, RGB output
    │   ├── AccessibilityService.swift  ← CVD profile, VoiceOver, haptics
    │   └── ImageProcessingService.swift ← Vision/Core Image wrappers
    ├── Models/
    │   ├── ColorSwatch.swift      ← SwiftData model for history entries
    │   ├── CVDProfile.swift       ← Enum for the 5 profiles
    │   └── IdentifiedColor.swift  ← Value type: name + hex + RGB + HSL
    ├── Resources/
    │   └── ColorNames.json        ← Bundled color name database (~500KB)
    └── Support/
        ├── Info.plist
        └── ColorSight.entitlements
```

This structure is a target, not a constraint. Add folders/files as features are built. Keep features self-contained.

---

## Architectural Patterns

### MVVM with @Observable
```swift
// ✅ Correct — iOS 17+ @Observable
@Observable
class CameraViewModel {
    var identifiedColor: IdentifiedColor?
    var isCapturing = false
}

// ❌ Wrong — do not use
class CameraViewModel: ObservableObject {
    @Published var identifiedColor: IdentifiedColor?
}
```

### Color Engine Contract
`ColorEngine` is a pure service (no UI state). It takes an `(r: UInt8, g: UInt8, b: UInt8)` tuple and returns an `IdentifiedColor`.

```swift
struct IdentifiedColor {
    let name: String           // e.g. "Sky blue"
    let hex: String            // e.g. "#87CEEB"
    let rgb: (r: Int, g: Int, b: Int)
    let hsl: (h: Double, s: Double, l: Double)
    let cvdDescription: String // adapted for user's CVD profile
}
```

Nearest-neighbor matching uses **CIELAB (LAB) color space** for perceptual accuracy. Convert RGB → LAB, find minimum Euclidean distance to database entries.

### Threading
- **Camera pixel sampling**: always on a background thread. Never block main thread in AVFoundation delegates.
- **UI updates**: always dispatch to `DispatchQueue.main` (or use `@MainActor`).
- **ColorEngine**: thread-safe, stateless — safe to call from any thread.
- **Hue Isolation display**: `AVSampleBufferDisplayLayer.enqueue()` is thread-safe — call directly on `sampleQueue`, zero `DispatchQueue.main.async` per frame.

### Hue Isolation Mode (color-splash filter)

Real-time filter that keeps pixels matching a chosen hue family in color and desaturates everything else to greyscale.

**Data flow — one camera frame:**
1. `AVCaptureVideoDataOutputSampleBufferDelegate` fires on `sampleQueue` with a `CVPixelBuffer` (BGRA, 1280×720).
2. `HueIsolationService.process(input:family:output:)` runs the Metal compute kernel:
   - Wraps `input` and `output` CVPixelBuffers as `MTLTexture`s via `CVMetalTextureCache` (zero CPU↔GPU copy).
   - Dispatches `hueIsolate` kernel — each thread classifies one pixel via HSB → writes original color or BT.601 luma greyscale.
   - `cmdBuf.waitUntilCompleted()` — GPU write to `output` CVPixelBuffer is complete on return.
   - Returns `true` on success, `false` on GPU setup failure (triggers CPU fallback).
3. Caller wraps `output` CVPixelBuffer in a `CMSampleBuffer` (host-clock timestamp) and calls `isolationDisplayLayer.enqueue(_:)` — still on `sampleQueue`, no main-thread hop.

**Key types:**
| Type | Role |
|------|------|
| `HueIsolation.metal` | `hueIsolate` compute kernel + `displayVertex`/`displayFragment` shaders (display pipeline removed — no longer used) |
| `HueIsolationService` | Owns `MTLDevice`, `MTLCommandQueue`, `MTLComputePipelineState`, `CVMetalTextureCache`; CPU fallback for non-Metal hardware |
| `CameraViewModel.isolationDisplayLayer` | `AVSampleBufferDisplayLayer` owned by the ViewModel; `videoGravity = .resizeAspectFill`; `sampleBufferRenderer.flush(removingDisplayedImage:)` clears on mode-off |
| `HueIsolationDisplayView` | `UIViewRepresentable` wrapping a `UIView` that hosts the display layer as a sublayer; `layoutSubviews` keeps the layer frame in sync (no implicit CALayer animation) |
| `CameraThreadState.isolationDisplayLayer` | `nonisolated(unsafe)` reference set on MainActor when mode activates; read on `sampleQueue` to call `enqueue()` |

**Why AVSampleBufferDisplayLayer, not MTKView:**
MTKView's insertion into the SwiftUI hierarchy blocks the main thread (~100–200 ms) regardless of when the Metal pipeline is compiled. `AVSampleBufferDisplayLayer` is a `CALayer` subclass — no layout stall, and `enqueue()` is the same buffer-to-screen path used internally by `AVCaptureVideoPreviewLayer`.

**CPU fallback** (`HueIsolationService.processCPU`): direct per-pixel BGRA loop using `HueFamily.matches(r:g:b:)`. Returns `true` so the output CVPixelBuffer is still enqueued. Never runs on iOS 26 devices (all have Metal), present for correctness.

**Metal shader — hue classification** mirrors `HueFamily.matches()` exactly. Both must be kept in sync; `HueFamilyTests.testMetalIndexMatchesCaseOrder()` guards the enum↔shader index alignment.

### High Contrast Mode (low-light visibility filter)

Boosts on-screen brightness/contrast so the preview is usable in dim environments. Mirrors Hue Isolation Mode's GPU/CPU dual-path structure and **shares its display layer** — the two modes are mutually exclusive (toggling one off the other), since only one display filter can drive `isolationDisplayLayer` at a time.

- `HighContrastService` (`HighContrastService.swift` + `HighContrast.metal`, kernel `highContrastEnhance`) boosts only the brightness (V) channel in HSB space — hue/saturation pass through untouched, so an identified color never shifts (blue never reads as purple). Constants: `contrast = 1.35`, `brightnessLift = 0.12`.
- **Display-only.** `CameraViewModel`'s color-sampling delegate always reads the original, unprocessed `CVPixelBuffer`; the filter only ever writes to the shared `isolationOutputBuffer` that feeds the display layer. Toggling it can never change what color gets identified.
- `CameraThreadState.isHighContrastActive` / `isHueIsolationActive` — setting one to `true` flips the other to `false`; `isolationDisplayLayer` is only torn down (flushed + nilled) when *both* are off.
- CPU fallback (`HighContrastService.processCPU`) exists for parity with Hue Isolation but never runs on iOS 26 devices.

### SwiftData
Use `@Model` for `ColorSwatch` (history entries). The model context lives in the App entry point and is passed down via `.modelContainer(for:)`.

```swift
@Model
class ColorSwatch {
    var id: UUID
    var name: String
    var hex: String
    var rgb: (r: Int, g: Int, b: Int)  // stored as separate Int attributes
    var timestamp: Date
    var tags: [String]
}
```

---

## Key Permissions

| Permission | Info.plist Key | Value |
|-----------|---------------|-------|
| Camera | `NSCameraUsageDescription` | `"ColorSight needs camera access to identify colors."` |
| Photo library (read) | `NSPhotoLibraryUsageDescription` | `"ColorSight reads photos so you can identify colors in them."` |

Add permissions only as the relevant feature is built.

---

## Color Name Database

- File: `ColorSight/Resources/ColorNames.json`
- Format: array of `{ "name": "Sky blue", "r": 135, "g": 206, "b": 235 }`
- Sources to merge: Crayola names, Pantone basics, CSS named colors
- Target size: 1,500–2,000 entries, ~500KB
- Matching: convert query RGB and all DB entries to LAB, find minimum ΔE (Euclidean distance)
- **No API calls.** Fully offline, fully local.

---

## Onboarding

First-launch flow:
1. Welcome screen (friendly, non-clinical tone)
2. CVD profile picker — show a test image with a visual simulator so users can self-identify
3. Store profile to `UserDefaults` immediately on selection
4. Proceed to main app

Do not gate the app on profile selection. If the user skips, default to `.normal` — we have no information about whether they have CVD, so applying the wrong adaptation is worse than none. Surface Settings so they can set a profile anytime.

---

## Accessibility

- **VoiceOver**: every identified color is announced as `"\(color.name), \(color.hex)"`. Phrasing is adapted per CVD profile (e.g., avoid saying "reddish" to a protanopia user; use brightness/warmth terms instead).
- **Haptics**: use `UIImpactFeedbackGenerator`. Encode brightness as pulse intensity (brighter = stronger).
- **UI colors**: all swatches and UI chrome use CVD-safe palettes. Do not rely on red/green contrast anywhere in the UI.

---

## Developer Account Status

Currently: **Paid Apple Developer account** (upgraded 2026-05-27)
- Team ID: `P3G2MZK5K4` (same Apple ID as before)
- Bundle ID: `com.michaelpeel.ColorSight`
- TestFlight: unlocked ✅
- CloudKit: unlocked — implement when ready, no `#if PAID_TIER` gate needed
- App Store: unlocked ✅
- Device provisioning: no longer expires every 7 days ✅

---

## Version Control

- **Remote**: GitHub — michael-peel/ColorSight
- **Local path**: `/Users/michael/Documents/ColorSight`
- **Local client**: GitHub Desktop
- **Commit discipline**: commit every time a feature works or a bug is resolved. Small, frequent commits. Descriptive messages.
- **Branch strategy**: `main` is always buildable. Feature branches for anything non-trivial.

---

## Claude Code Usage Notes

- Use Claude Code (terminal) for all hands-on coding: generating files, editing code, running builds
- Use claude.ai chat (Cowork) for: architecture decisions, design questions, getting unstuck at a high level
- When generating code, always match the patterns in this file
- When something is architecturally ambiguous, **flag it** rather than assuming — the developer wants to own all architectural decisions
- After each significant change, suggest a commit message

---

## Session Log

| Date | What was done |
|------|--------------|
| 2026-05-21 | Project initialized. GitHub repo created. Xcode project scaffolded. Camera permission screen working on device. First commit pushed. CLAUDE.md added to repo root. |
| 2026-05-27 | Removed custom CVD profile (unimplemented). Upgraded to paid Apple Developer account. TestFlight setup in progress. |
| 2026-06-10 | Implemented Hue Isolation Mode (color-splash filter): Metal compute kernel in HueIsolation.metal, HueIsolationService GPU/CPU pipeline, AVSampleBufferDisplayLayer display path with zero main-thread dispatch per frame. Added ColorSightTests target (30 unit tests, all passing on device). |
| 2026-06-11 | Redesigned home screen; replaced camera tooltip with step-by-step coach marks (feature tour), then fixed several tour bugs (touch passthrough/camera freeze on save, DragGesture conflict while overlay visible, tooltip not showing on replay). Added hue isolation card + profile picker to home screen; tapping a swatch now shows its color name. Fixed pulsing ring animation. Removed black/white/gray from the hue isolation picker; bumped version to 1.2. Replaced app icon and welcome-screen logo with new brand image; added branded splash screen on cold launch; added light/dark logo variants and fixed dark-mode logo display; bumped build number to 2. |
| 2026-07-07 | Replaced app icon and in-app logo with professional designer assets (new C-arc camera mark, light/white-bg + dark/navy-bg `AppLogoImage` variants); removed old placeholder logo files. |
| 2026-07-08 | Defaulted Sample Region to ON for better accuracy on textured surfaces. Added splash screen color waves (light/dark `SplashWaveImage`) and fixed a dark-mode logo size mismatch. Added pinch-to-zoom to the camera view (`AVCaptureDevice.videoZoomFactor` driven directly, so sampling stays accurate at any zoom). Moved the flashlight toggle to top-right stacked under Settings, with History/Settings/Torch icons normalized to a fixed 20×20 frame. Implemented High Contrast Mode (low-light visibility filter) — see architecture section above; mutually exclusive with Hue Isolation, shares its display layer. Changed the menu screen's Eyedropper icon from `drop.fill` to `eyedropper.halffull` to match the camera screen. Verified the icon change by building and running on device via `devicectl`. |

> Update this table at the end of every working session.
