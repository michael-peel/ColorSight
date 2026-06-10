import SwiftUI

/// Full-screen overlay that displays the per-pixel color-splash filtered frame
/// produced by HueIsolationService. Sits between the raw camera preview and the
/// crosshair in the ZStack so UI controls remain on top.
///
/// Hit-testing is disabled — all gestures fall through to the camera view below.
struct HueIsolationOverlayView: View {

    let image: UIImage

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
