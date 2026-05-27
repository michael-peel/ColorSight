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

> Update this table at the end of every working session.
