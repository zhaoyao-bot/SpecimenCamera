import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        view.contentMode = .scaleAspectFit
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.previewLayer.frame = uiView.bounds
    }

    static func dismantleUIView(_ uiView: PreviewUIView, coordinator: ()) {
        uiView.previewLayer.session = nil
    }
}

class PreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSublayers(of layer: CALayer) {
        super.layoutSublayers(of: layer)
        previewLayer.frame = bounds
    }
}
