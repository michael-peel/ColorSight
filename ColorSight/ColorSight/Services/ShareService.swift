import SwiftUI
import UIKit

// MARK: - Activity view (UIKit share sheet wrapper)

/// Thin SwiftUI wrapper around UIActivityViewController.
/// Present via `.sheet(item: $sharePayload) { payload in ActivityView(items: payload.items) }`.
struct ActivityView: UIViewControllerRepresentable {
    let items:       [Any]
    var subject:     String = ""
    var activities:  [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: activities)
        if !subject.isEmpty {
            vc.setValue(subject, forKey: "subject")
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Share payload

/// Identifiable wrapper used with `.sheet(item:)` to drive the ActivityView sheet.
struct SharePayload: Identifiable {
    let id      = UUID()
    let items:  [Any]
    let subject: String
}
