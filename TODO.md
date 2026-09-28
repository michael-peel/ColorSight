# ColorSight Roadmap (v2.1 and beyond)

Read CLAUDE.md first. Rules that always apply:
- No em dashes in code comments or user-facing strings
- Do not add Claude as co-author in git commits
- No third-party packages, no Combine, no network calls
- iOS 26 minimum, use iOS 26 APIs, not fallbacks
- MVVM with @Observable, all pixel work on sampleQueue (zero main thread pixel work)
- Commit frequently with descriptive messages

Suggested order: Feature 1, then Feature 3, then Feature 2, then the rest.
Reason: white balance calibration (Feature 3) should exist before custom color isolation (Feature 2) so custom matching runs against corrected colors.

---

## Feature 1: Clinical profile names in menu (v2.1) — DONE

- [x] Find where profile display strings are defined (CVDProfile enum or a displayName property) and update labels to Protanopia, Deuteranopia, Tritanopia, Achromatopsia. The data model likely already uses these names, so this may only be a UI-layer label mismatch — only `HomeView.swift`'s `onboardingTitle` needed fixing; Settings and the home row already used clinical names
- [x] Check every place the label renders: home screen CVD profile row, Settings picker, first-launch coach mark copy, VoiceOver accessibility labels
- [x] Decide whether to keep the layman term as a subtitle, for example "Protanopia (red-green)", for users unfamiliar with clinical terms — kept as the existing `experienceDescription` sentence below the title
- [x] Confirm UserDefaults raw values and enum case names are unchanged (display strings only, no migration)
- [x] Update Services/CVDColorContext.swift output strings if they reference the old naming — already used clinical terms, no change needed
- [x] Test that VoiceOver reads the new names correctly — confirmed on device

## Feature 2: Custom color isolation in Hue Isolation Mode (v2.1) — implemented, pending on-device perf check

- [x] Entry point: add a "Custom" option alongside the 11 hue family buttons that opens a picker of saved colors from History — a "Custom" pill in the existing `HueFamilyPickerView` row
- [x] Build a lightweight picker sheet reusing the existing History SwiftData query — `CustomColorPickerSheet.swift`, same `@Query(sort: \ColorSwatch.timestamp, order: .reverse)` as `HistoryView`
- [x] Extend HueFamily, or add a sibling IsolationTarget type, to represent either a built-in hue family or a custom color target, so downstream code has one path — sibling type, `Models/IsolationTarget.swift` (HueFamily's `CaseIterable` conformance rules out an associated-value case)
- [x] Update the Swift CPU fallback matching to accept a custom target color plus tolerance — `IsolationTarget.matches(r:g:b:)` is now the CPU fallback's sole classification authority (mirrors `HueFamily.matches()`'s role)
- [x] Update HueIsolation.metal to accept a custom target color and tolerance as a uniform, branching between "hue family bucket" and "custom color distance" modes
- [x] Use LAB distance for custom matching (consistent with the color ID matching elsewhere in the app) — extracted `ColorEngine`'s private LAB math into shared `Services/ColorMath.swift`, used by both
- [x] Add a tolerance/sensitivity slider — 5...40 ΔE, shown under the pill row while a custom color is active
- [x] Persist last-used custom color in UserDefaults — `customIsolationR/G/B/Tolerance`; Hue Isolation itself still starts on a family each session, this only remembers the custom color for quick re-selection
- [x] Update the camera toolbar palette icon to show which custom color is active and how to switch back to a standard hue family — icon tint/VoiceOver value now reads `IsolationTarget.swatchColor`/`.displayName`; "Families" button in the custom row returns to the last-selected family
- [x] Preserve mutual exclusivity with High Contrast Mode — untouched, that logic doesn't depend on what Hue Isolation isolates
- [x] Handle the empty state (zero saved colors in History) — same empty-state copy/layout as `HistoryView`
- [x] Update VoiceOver announcements for custom mode — pill accessibility labels, palette button's accessibilityValue, sensitivity slider label
- [ ] Test on device that the 30fps lock holds with the extra shader branch — not yet checked; watch the `[HueIsolation] X ms/frame` console print while Custom mode is active

## Feature 3: White balance lock / calibration (v2.1) — DONE

- [x] Add a calibration mode: user taps a known white or gray reference, app computes a correction and applies it to sampled values
- [x] Also offer a simple white balance lock using AVCaptureDevice white balance controls — combined into one "Calibrate" control rather than a second toolbar button (decided with Michael — see CLAUDE.md White Balance Calibration section)
- [x] Keep all pixel work on sampleQueue — calibration adds no per-frame work at all; it locks `AVCaptureDevice` white balance once via `sessionQueue` (same pattern as torch/zoom/refocus), so the correction happens in the ISP before frames ever reach `captureOutput`
- [x] Add a clear indicator when calibration is active, and a one-tap reset — toolbar icon tints accent color when calibrated; tapping it again resets to auto
- [x] Make sure calibration applies to both live ID and Hue Isolation (and later custom isolation) — automatic, since the ISP-level lock corrects the raw CVPixelBuffer itself; no per-service changes needed
- [x] Add a Settings toggle and a coach mark or brief explanation — "White Balance Calibration" toggle in Settings; coach mark step added to the existing camera tour
- [x] VoiceOver support for calibration states — accessibilityLabel/Value on the button plus an announcement on successful calibration

## Feature 4: App Intents for Siri

- [ ] Add App Intents: "What color is this?" (opens camera in live ID) and "Open Hue Isolation" (optionally with a hue family parameter)
- [ ] Add an App Shortcuts provider so the phrases work without user setup
- [ ] Test with Siri on iOS 27

## Maintenance and compatibility

- [ ] Brief confirmation bubble when toggling High Contrast Mode or the flashlight (e.g. "High Contrast Mode On", "Flashlight On") — reuse the transient banner style already used for the Hue Isolation instructional banner
- [ ] Add a clear-background variant of the app icon for iOS 27's Liquid Glass "clear" icon setting — currently the icon keeps a solid white background under that setting and stands out against other clear-style icons
- [ ] Liquid Glass contrast pass on the camera toolbar, coach marks, and home screen under iOS 27 (test with the new contrast and customization settings)
- [ ] iPhone Duo camera handling: build against the iOS 27.1 SDK, decide behavior when the device opens or closes and cameras switch, verify preview layout
- [ ] Optional 60fps mode for Hue Isolation on A20 Pro class devices (keep the 30fps lock as default, gate by device capability)
- [ ] Capture a fresh iPad 13" (2064x2752) screenshot via the iPad Pro 13-inch (M4) simulator if needed for the next submission

## Someday / maybe (very low priority)

- [ ] Android port (full rewrite: Compose, CameraX, Room, GPU shader path for Hue Isolation). Reusable as logic only: ColorNames.json, CVD logic, LAB matching, HSB rules

---

## Release checklist (each release)

- [ ] Bump version and build number in Xcode
- [ ] Update What's New, description, and promotional text as needed
- [ ] Re-verify screenshots still match the UI
- [ ] Archive, upload, TestFlight check, then Add for Review
