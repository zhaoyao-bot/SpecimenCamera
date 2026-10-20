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

// MARK: - Lens Switch Picker (主摄 / 长焦 切换)

/// 显微镜拍摄用的物理镜头切换控件。
/// 主摄(畸变最小/弱光最好) 与 长焦(填满目镜画面/放大更高) 可实时对比。
/// 无长焦镜头的机型会自动禁用"长焦"选项。
struct LensSwitchPicker: View {
    @ObservedObject var cameraManager: CameraManager

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CameraManager.LensType.allCases) { lens in
                lensButton(lens)
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.12))
        .clipShape(Capsule())
    }

    private func lensButton(_ lens: CameraManager.LensType) -> some View {
        let isSelected = cameraManager.currentLens == lens
        // 机型没有该物理镜头时禁用该选项
        let unavailable = !lens.isAvailable

        return Button {
            cameraManager.switchLens(to: lens)
        } label: {
            VStack(spacing: 1) {
                Text(lens.displayName)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                // 机型没有该镜头时明确显示"机型不支持"，避免用户以为可点却没反应
                Text(unavailable ? "机型不支持" : lens.hint)
                    .font(.system(size: 7.5, weight: .medium))
                    .opacity(0.75)
            }
            .foregroundColor(unavailable ? .gray : (isSelected ? .white : .white.opacity(0.55)))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isSelected ? WarmTheme.accent.opacity(0.55) : Color.clear)
            )
        }
        .disabled(unavailable || isSelected)
        .opacity(unavailable ? 0.3 : 1)
    }
}
