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

    // Store photo data for saving
    var capturedJpegData: Data?
    private var capturedDngData: Data?

    struct SaveResult {
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
            DispatchQueue.main.async {
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

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        isRAWSupported = !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty

        captureSession.commitConfiguration()

        let session = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
            DispatchQueue.main.async { [weak self] in
                self?.isCameraReady = true
            }
        }
    }

    // MARK: - Capture

    func capturePhoto() {
        let settings: AVCapturePhotoSettings

        if let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first {
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

        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            performSave()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        self?.performSave()
                    } else {
                        self?.isSaving = false
                        self?.saveResult = SaveResult(success: false, message: "相册权限被拒绝")
                    }
                }
            }
        default:
            isSaving = false
            saveResult = SaveResult(success: false, message: "相册权限被拒绝，请在设置中开启")
        }
    }

    private func performSave() {
        // Capture data on main thread before dispatching
        let dngData = capturedDngData
        let jpegData = capturedJpegData

        if let dng = dngData {
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                let rawOptions = PHAssetResourceCreationOptions()
                rawOptions.uniformTypeIdentifier = "com.adobe.raw-image"
                request.addResource(with: .photo, data: dng, options: rawOptions)
            }) { success, error in
                DispatchQueue.main.async { [weak self] in
                    self?.isSaving = false
                    if success {
                        self?.saveResult = SaveResult(success: true, message: "RAW照片已保存到相册")
                    } else {
                        self?.saveResult = SaveResult(success: false, message: "保存失败: \(error?.localizedDescription ?? "未知错误")")
                    }
                }
            }
        } else if let jpeg = jpegData {
            // Fallback: no DNG available, save JPEG
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: jpeg, options: nil)
            }) { success, error in
                DispatchQueue.main.async { [weak self] in
                    self?.isSaving = false
                    if success {
                        self?.saveResult = SaveResult(success: true, message: "照片已保存到相册")
                    } else {
                        self?.saveResult = SaveResult(success: false, message: "保存失败: \(error?.localizedDescription ?? "未知错误")")
                    }
                }
            }
        } else {
            isSaving = false
            saveResult = SaveResult(success: false, message: "没有可保存的数据")
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

            DispatchQueue.main.async { [weak self] in
                self?.capturedDngData = dngData
                if let preview = previewImage, self?.capturedImage == nil {
                    self?.capturedImage = preview
                }
            }
        } else {
            // Processed JPEG photo
            guard let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else { return }

            DispatchQueue.main.async { [weak self] in
                self?.capturedImage = image
                self?.capturedJpegData = data
            }
        }
    }
}
