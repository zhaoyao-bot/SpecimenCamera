import SwiftUI

struct ContentView: View {

    @StateObject private var cameraManager = CameraManager()
    @State private var isPressed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch cameraManager.permissionStatus {
            case .notDetermined:
                permissionView(message: "需要相机权限才能使用此应用")
            case .denied:
                permissionView(message: "相机权限被拒绝，请在设置中开启")
            case .authorized:
                cameraView
            }
        }
        .statusBarHidden(true)
        .alert("保存结果", isPresented: showSaveResult, actions: {
            Button("好") {
                cameraManager.saveResult = nil
            }
        }, message: {
            Text(cameraManager.saveResult?.message ?? "")
        })
    }

    private var showSaveResult: Binding<Bool> {
        Binding(
            get: { cameraManager.saveResult != nil },
            set: { if !$0 { cameraManager.saveResult = nil } }
        )
    }

    // MARK: - Permission View

    @ViewBuilder
    private func permissionView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text(message)
                .font(.body)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if cameraManager.permissionStatus == .notDetermined {
                Button("授权相机") {
                    cameraManager.requestPermission()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            } else {
                Button("去设置") {
                    cameraManager.openSettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
    }

    // MARK: - Camera View

    private var cameraView: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Camera preview — 4:3 aspect ratio like system camera
                CameraPreviewView(session: cameraManager.captureSession)
                    .aspectRatio(3/4, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipped()

                Spacer()

                // Bottom controls
                VStack(spacing: 16) {
                    // RAW indicator
                    if cameraManager.isRAWSupported {
                        Text("RAW")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }

                    captureButton
                }
                .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 20 : 40)
            }
        }
        .overlay {
            // Captured image review overlay
            if cameraManager.capturedImage != nil {
                photoReviewOverlay
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Capture Button

    private var captureButton: some View {
        Button {
            cameraManager.capturePhoto()
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = false
                }
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
                    .frame(width: 70, height: 70)

                Circle()
                    .fill(Color.white)
                    .frame(width: 58, height: 58)
            }
            .scaleEffect(isPressed ? 0.9 : 1.0)
        }
    }

    // MARK: - Photo Review Overlay

    private var photoReviewOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Photo preview
            if let image = cameraManager.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
            }

            // RAW badge
            if cameraManager.isRAWSupported && cameraManager.hasCapturedPhoto {
                VStack {
                    HStack {
                        Text("RAW")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange)
                            .clipShape(Capsule())
                            .padding(.leading, 16)
                            .padding(.top, 8)
                        Spacer()
                    }
                    Spacer()
                }
            }

            // Action buttons: Retake & Save
            VStack {
                Spacer()

                HStack(spacing: 0) {
                    // Retake (discard)
                    Button {
                        cameraManager.discardPhoto()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 18, weight: .semibold))
                            Text("重拍")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Spacer()
                        .frame(width: 16)

                    // Save to album
                    Button {
                        cameraManager.saveToAlbum()
                    } label: {
                        HStack(spacing: 6) {
                            if cameraManager.isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            Text(cameraManager.isSaving ? "保存中" : "保存")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(cameraManager.isSaving)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .animation(.easeOut(duration: 0.3), value: cameraManager.capturedImage != nil)
    }
}

#Preview("Camera UI") {
    ContentView()
}
