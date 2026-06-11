import AVFoundation
import SwiftUI
import UIKit

/// Wraps an AVSampleBufferDisplayLayer in a SwiftUI view.
///
/// The display layer is created and owned by CameraViewModel so sampleQueue can
/// enqueue processed CVPixelBuffers directly — no UIImage, no CIContext, no main-
/// thread dispatch per frame. This view just adds the layer to the UIKit hierarchy
/// and keeps its frame in sync with the view bounds.
struct HueIsolationDisplayView: UIViewRepresentable {

    var displayLayer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> HueIsolationContainerView {
        HueIsolationContainerView(displayLayer: displayLayer)
    }

    func updateUIView(_ uiView: HueIsolationContainerView, context: Context) {}
}

// MARK: - Container view

final class HueIsolationContainerView: UIView {

    private let displayLayer: AVSampleBufferDisplayLayer

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init(frame: .zero)
        backgroundColor = .clear
        displayLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Disable implicit CALayer animation so the layer tracks view resizes instantly.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }
}
