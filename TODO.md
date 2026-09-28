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

## Feature 1: Clinical profile names in menu (v2.1)

- [ ] Find where profile display strings are defined (CVDProfile enum or a displayName property) and update labels to Protanopia, Deuteranopia, Tritanopia, Achromatopsia. The data model likely already uses these names, so this may only be a UI-layer label mismatch
- [ ] Check every place the label renders: home screen CVD profile row, Settings picker, first-launch coach mark copy, VoiceOver accessibility labels
- [ ] Decide whether to keep the layman term as a subtitle, for example "Protanopia (red-green)", for users unfamiliar with clinical terms
- [ ] Confirm UserDefaults raw values and enum case names are unchanged (display strings only, no migration)
- [ ] Update Services/CVDColorContext.swift output strings if they reference the old naming
- [ ] Test that VoiceOver reads the new names correctly

## Feature 2: Custom color isolation in Hue Isolation Mode (v2.1)

- [ ] Entry point: add a "Custom" option alongside the 11 hue family buttons that opens a picker of saved colors from History
- [ ] Build a lightweight picker sheet reusing the existing History SwiftData query
- [ ] Extend HueFamily, or add a sibling IsolationTarget type, to represent either a built-in hue family or a custom color target, so downstream code has one path
- [ ] Update the Swift CPU fallback matching to accept a custom target color plus tolerance
- [ ] Update HueIsolation.metal to accept a custom target color and tolerance as a uniform, branching between "hue family bucket" and "custom color distance" modes
- [ ] Use LAB distance for custom matching (consistent with the color ID matching elsewhere in the app)
- [ ] Add a tolerance/sensitivity slider
- [ ] Persist last-used custom color in UserDefaults
- [ ] Update the camera toolbar palette icon to show which custom color is active and how to switch back to a standard hue family
- [ ] Preserve mutual exclusivity with High Contrast Mode
- [ ] Handle the empty state (zero saved colors in History)
- [ ] Update VoiceOver announcements for custom mode
- [ ] Test on device that the 30fps lock holds with the extra shader branch

## Feature 3: White balance lock / calibration (v2.1)

- [ ] Add a calibration mode: user taps a known white or gray reference, app computes a correction and applies it to sampled values
- [ ] Also offer a simple white balance lock using AVCaptureDevice white balance controls
- [ ] Keep all pixel work on sampleQueue
- [ ] Add a clear indicator when calibration is active, and a one-tap reset
- [ ] Make sure calibration applies to both live ID and Hue Isolation (and later custom isolation)
- [ ] Add a Settings toggle and a coach mark or brief explanation
- [ ] VoiceOver support for calibration states

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
