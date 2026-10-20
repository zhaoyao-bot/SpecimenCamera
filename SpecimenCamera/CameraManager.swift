@preconcurrency import AVFoundation
import UIKit
import Photos

enum CameraPermissionStatus {
    case notDetermined
    case authorized
    case denied
}

@MainActor
class CameraManager: NSObject, ObservableObject {

    @Published var permissionStatus: CameraPermissionStatus = .notDetermined
    @Published var capturedImage: UIImage?
    @Published var isCameraReady = false
    @Published var isSaving = false
    @Published var saveResult: SaveResult?
    @Published var isRAWSupported = false

    /// When false, only JPEG capture is used (e.g. calibration mode).
    /// RAW+JPEG dual capture can cause the first delegate callback (pixel buffer)
    /// to produce a dark/blank preview on some devices.
    var preferRAW = true

    /// 可选物理镜头(三摄：超广角 0.5x / 主摄 1x / 长焦 2x~3x)
    /// 注意：主摄(wide)本身就是"广角"镜头，所以第三个头标为"超广角"(ultraWide, 0.5x)以免混淆。
    enum LensType: String, CaseIterable, Identifiable {
        case ultraWide
        case wide
        case telephoto

        var id: String { rawValue }

        /// 界面显示名
        var displayName: String {
            switch self {
            case .ultraWide: return "超广角"
            case .wide: return "主摄"
            case .telephoto: return "长焦"
            }
        }

        /// 界面副标题(该镜头的特点，帮助用户选择)
        var hint: String {
            switch self {
            case .ultraWide: return "视野广·畸变大"
            case .wide: return "畸变小·弱光好"
            case .telephoto: return "填满画面"
            }
        }

        /// 对应的 AVCaptureDevice 类型
        var deviceType: AVCaptureDevice.DeviceType {
            switch self {
            case .ultraWide: return .builtInUltraWideCamera
            case .wide: return .builtInWideAngleCamera
            case .telephoto: return .builtInTelephotoCamera
            }
        }

        /// 该机型是否具备这个物理镜头(没有的机型会禁用对应选项)
        var isAvailable: Bool {
            AVCaptureDevice.default(deviceType, for: .video, position: .back) != nil
        }
    }

    /// 当前使用的镜头(UI 可切换)。显微镜目镜射出平行光(等效无穷远虚像 afocal)：
    /// 主摄(wide)畸变最小、光圈最大弱光最好；长焦(telephoto)窄视角能填满目镜视野、放大率更高；
    /// 超广角(ultraWide)视野最广但畸变最大。三者都会对焦到无穷远，可在界面上实测对比。
    @Published var currentLens: LensType = .wide

    /// 当前使用的物理摄像头设备(用于锁定对焦/曝光/变焦)
    private var currentDevice: AVCaptureDevice?
    /// 当前的输入(切换镜头时需要移除旧的)
    private var currentInput: AVCaptureDeviceInput?

    // Store photo data for saving
    var capturedJpegData: Data?
    private var capturedDngData: Data?

    struct SaveResult: Equatable {
        let success: Bool
        let message: String
    }

    let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()

    override init() {
        super.init()
        checkPermission()
    }

    // MARK: - Permission

    func checkPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            permissionStatus = .authorized
            setupCamera()
        case .notDetermined:
            permissionStatus = .notDetermined
        default:
            permissionStatus = .denied
        }
    }

    func requestPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in
                if granted {
                    self?.permissionStatus = .authorized
                    self?.setupCamera()
                } else {
                    self?.permissionStatus = .denied
                }
            }
        }
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Camera Setup

    private func setupCamera() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        // 建立默认镜头(主摄)的输入
        guard configureInput(for: currentLens) else {
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        isRAWSupported = !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty

        captureSession.commitConfiguration()

        let session = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
            Task { @MainActor [weak self] in
                self?.isCameraReady = true
            }
            // 等自动曝光/白平衡收敛稳定后再锁定，避免锁在不佳的值上
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
                Task { @MainActor [weak self] in
                    self?.lockFocusInfinityAndExposure()
                }
            }
        }
    }

    // MARK: - Lens Switching (主摄 / 长焦)

    /// 建立(或切换)指定镜头的输入。成功返回 true。
    /// 会移除旧输入、加入新设备输入，并锁最小变焦(1x)防止视角/畸变变化。
    /// 注意：调用方需自行包裹 beginConfiguration / commitConfiguration。
    @discardableResult
    private func configureInput(for lens: LensType) -> Bool {
        // 先准备好新设备与输入，成功后才移除旧的 —— 避免切换失败时 session 没有输入导致黑屏
        guard let device = AVCaptureDevice.default(lens.deviceType, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return false
        }

        let oldInput = currentInput
        if let oldInput {
            captureSession.removeInput(oldInput)
        }

        guard captureSession.canAddInput(input) else {
            // 无法加入新输入(极少发生)，把旧的放回去保持可用
            if let oldInput, captureSession.canAddInput(oldInput) {
                captureSession.addInput(oldInput)
            }
            return false
        }

        captureSession.addInput(input)
        currentDevice = device
        currentInput = input

        // 锁最小变焦(1x)：杜绝变焦导致视角/畸变变化(尤其避免多摄机型自动切镜)
        configureDevice { dev in
            dev.videoZoomFactor = dev.minAvailableVideoZoomFactor
        }
        return true
    }

    /// 切换物理镜头(主摄 ⇄ 长焦)。切换后重新锁定无穷远对焦与曝光。
    /// 只有真正切换成功才更新 currentLens，保证 UI 状态与真实硬件一致。
    func switchLens(to lens: LensType) {
        guard lens != currentLens else { return }
        // 机型没有该物理镜头时不允许切换
        guard lens.isAvailable else { return }

        captureSession.beginConfiguration()
        let ok = configureInput(for: lens)
        captureSession.commitConfiguration()

        guard ok else { return } // 切换失败则保持原镜头
        currentLens = lens
        isRAWSupported = !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty

        // 切换镜头后等曝光重新收敛，再锁无穷远对焦 + 曝光
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
            Task { @MainActor in
                self?.lockFocusInfinityAndExposure()
            }
        }
    }

    // MARK: - Device Configuration (显微镜拍摄: 锁变焦 / 锁无穷远对焦 / 锁曝光)

    /// 显微镜目镜射出的是平行光(等效"无穷远"的虚像, afocal)，
    /// 因此相机必须对焦在无穷远(lensPosition = 1.0)，而不是对焦到眼前的物理目镜。
    /// 自动对焦很容易被近处的目镜镜片迷惑而对到近处 → 标本模糊，
    /// 所以这里锁定对焦到无穷远。同时锁定曝光，保证每张图亮度一致(标定/批量采集需要可复现)。
    func lockFocusInfinityAndExposure() {
        configureDevice { dev in
            // 1.0 = 对焦在无穷远(平行光/显微镜目镜像)
            if dev.isFocusModeSupported(.locked) {
                dev.setFocusModeLocked(lensPosition: 1.0)
            }
            // 锁定曝光(锁的是已经由自动曝光稳定下来的当前值，不会更暗)
            if dev.isExposureModeSupported(.locked) {
                dev.exposureMode = .locked
            }
        }
    }

    /// 解锁曝光(回到自动)，用于换标本/光源变化后重新测光
    func unlockExposure() {
        configureDevice { dev in
            if dev.isExposureModeSupported(.continuousAutoExposure) {
                dev.exposureMode = .continuousAutoExposure
            }
        }
    }

    /// 安全的 lockForConfiguration / unlockForConfiguration 封装
    private func configureDevice(_ block: (AVCaptureDevice) -> Void) {
        guard let device = currentDevice else { return }
        do {
            try device.lockForConfiguration()
            block(device)
            device.unlockForConfiguration()
        } catch {
            print("相机参数配置失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Capture

    func capturePhoto() {
        let settings: AVCapturePhotoSettings

        if preferRAW, let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first {
            // RAW + JPEG capture: delegate will be called twice
            // - Once with isRawPhoto=true (fileDataRepresentation returns DNG)
            // - Once with isRawPhoto=false (fileDataRepresentation returns JPEG)
            settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat,
                                               processedFormat: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        } else {
            settings = AVCapturePhotoSettings()
        }

        settings.flashMode = .auto
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - Discard

    func discardPhoto() {
        capturedImage = nil
        capturedJpegData = nil
        capturedDngData = nil
    }

    var hasCapturedPhoto: Bool {
        capturedImage != nil
    }

    // MARK: - Save to Album

    func saveToAlbum() {
        guard capturedImage != nil else { return }
        isSaving = true
        saveResult = nil

        // Capture data values before leaving main actor
        let dngData = capturedDngData
        let jpegData = capturedJpegData

        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            performSaveNonisolated(dngData: dngData, jpegData: jpegData)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] newStatus in
                guard let self else { return }
                if newStatus == .authorized || newStatus == .limited {
                    self.performSaveNonisolated(dngData: dngData, jpegData: jpegData)
                } else {
                    Task { @MainActor in
                        self.isSaving = false
                        self.saveResult = SaveResult(success: false, message: "相册权限被拒绝")
                    }
                }
            }
        default:
            isSaving = false
            saveResult = SaveResult(success: false, message: "相册权限被拒绝，请在设置中开启")
        }
    }

    nonisolated private func performSaveNonisolated(dngData: Data?, jpegData: Data?) {
        if let dng = dngData {
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                let rawOptions = PHAssetResourceCreationOptions()
                rawOptions.uniformTypeIdentifier = "com.adobe.raw-image"
                request.addResource(with: .photo, data: dng, options: rawOptions)
            }) { [weak self] success, error in
                Task { @MainActor in
                    self?.handleSaveResult(success: success, error: error, isRaw: true)
                }
            }
        } else if let jpeg = jpegData {
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: jpeg, options: nil)
            }) { [weak self] success, error in
                Task { @MainActor in
                    self?.handleSaveResult(success: success, error: error, isRaw: false)
                }
            }
        } else {
            Task { @MainActor [weak self] in
                self?.isSaving = false
                self?.saveResult = SaveResult(success: false, message: "没有可保存的数据")
            }
        }
    }

    private func handleSaveResult(success: Bool, error: Error?, isRaw: Bool) {
        isSaving = false
        if success {
            saveResult = SaveResult(success: true, message: isRaw ? "RAW照片已保存到相册" : "照片已保存到相册")
        } else {
            saveResult = SaveResult(success: false, message: "保存失败: \(error?.localizedDescription ?? "未知错误")")
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        guard error == nil else {
            print("照片处理失败: \(error?.localizedDescription ?? "")")
            return
        }

        if photo.isRawPhoto {
            // RAW photo: fileDataRepresentation() returns DNG data
            let dngData = photo.fileDataRepresentation()

            // Create preview from pixel buffer
            var previewImage: UIImage?
            if let pixelBuffer = photo.pixelBuffer {
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                let context = CIContext()
                if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                    previewImage = UIImage(cgImage: cgImage)
                }
            }

            Task { @MainActor in
                self.capturedDngData = dngData
                if let preview = previewImage, self.capturedImage == nil {
                    self.capturedImage = preview
                }
            }
        } else {
            // Processed JPEG photo
            guard let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else { return }

            Task { @MainActor in
                self.capturedImage = image
                self.capturedJpegData = data
            }
        }
    }
}
