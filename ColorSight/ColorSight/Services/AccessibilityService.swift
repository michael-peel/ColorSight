import AVFoundation
import UIKit

/// Centralised service for haptic feedback and voice announcements.
///
/// All methods must be called from the MainActor. The singleton is safe to use
/// from `CameraViewModel`, `EyedropperViewModel`, and any future feature that
/// identifies a color and wants to announce it.
@MainActor
final class AccessibilityService {

    static let shared = AccessibilityService()

    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let synthesizer     = AVSpeechSynthesizer()

    private init() {
        // Pre-warm the haptic engine so the very first call has no latency.
        impactGenerator.prepare()
    }

    // MARK: - Public API

    /// Triggers haptics and/or speaks the color name based on the user's preferences.
    ///
    /// - `haptics`: Impact feedback with intensity mapped to the color's lightness —
    ///   very dark colors produce a lighter pulse; bright/light colors produce a heavier one.
    /// - `voice`: Speaks "\(simpleName). \(hex)" via VoiceOver's announcement API when
    ///   VoiceOver is active, otherwise via `AVSpeechSynthesizer` for sighted users who
    ///   enabled the "Voice Feedback" toggle.
    func announceColor(_ color: IdentifiedColor, haptics: Bool, voice: Bool) {
        if haptics {
            // Map lightness 0–1 → intensity 0.2–1.0 so very dark colors still pulse.
            let intensity = CGFloat(0.2 + color.hsl.l * 0.8)
            impactGenerator.impactOccurred(intensity: max(0.2, min(1.0, intensity)))
            impactGenerator.prepare()   // pre-warm for the next call
        }

        if voice {
            if UIAccessibility.isVoiceOverRunning {
                // VoiceOver is active — speak the full CVD description so the user
                // gets colour name + profile-adapted context in one announcement.
                let text = "\(color.simpleName). \(color.cvdDescription) Hex: \(color.hex)."
                UIAccessibility.post(notification: .announcement, argument: text)
            } else {
                // Plain speech for sighted users who enabled Voice Feedback.
                // Keep it short: name + hex only (description is visible on screen).
                let text = "\(color.simpleName). \(color.hex)"
                let utterance      = AVSpeechUtterance(string: text)
                utterance.rate     = AVSpeechUtteranceDefaultSpeechRate
                utterance.pitchMultiplier = 1.0
                synthesizer.stopSpeaking(at: .immediate)
                synthesizer.speak(utterance)
            }
        }
    }
}
