import SwiftUI
import AVFoundation

/// UIViewRepresentable that hosts an AVCaptureVideoPreviewLayer.
/// The session is owned by CameraViewModel; we just display it here.
struct CameraPreviewView: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // Session reference doesn't change after makeUIView, nothing to update.
    }

    // MARK: - Hosted UIView

    final class PreviewUIView: UIView {

        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // Safe: layerClass guarantees this cast
            layer as! AVCaptureVideoPreviewLayer
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
        }
    }
}
