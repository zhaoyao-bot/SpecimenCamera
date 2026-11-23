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
                    .font(.system(size: 7, weight: .medium))
                    .opacity(0.75)
            }
            .foregroundColor(unavailable ? .gray : (isSelected ? .white : .white.opacity(0.55)))
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isSelected ? WarmTheme.accent.opacity(0.55) : Color.clear)
            )
        }
        .disabled(unavailable || isSelected)
        .opacity(unavailable ? 0.3 : 1)
    }
}

// MARK: - Re-metering Button (重新测光)

/// 光源变化(换灯泡/调亮度)后，点一下重新自动测光，1 秒后重新锁死曝光。
/// 避免为了重新适应光源而重启 App 或切镜头。
struct RemeteringButton: View {
    @ObservedObject var cameraManager: CameraManager
    @State private var isMetering = false

    var body: some View {
        Button {
            guard !isMetering else { return }
            isMetering = true
            cameraManager.remeasureExposureAndLock()
            // 1 秒自动测光 + 0.3 秒缓冲后恢复可点
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                isMetering = false
            }
        } label: {
            VStack(spacing: 1) {
                if isMetering {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(WarmTheme.accent)
                        .frame(height: 12)
                } else {
                    Image(systemName: "camera.metering.center.weighted")
                        .font(.system(size: 12, weight: .bold))
                }
                Text(isMetering ? "测光中" : "测光")
                    .font(.system(size: 7, weight: .medium))
            }
            .foregroundColor(isMetering ? WarmTheme.accent : .white.opacity(0.75))
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
        }
        .disabled(isMetering)
    }
}
