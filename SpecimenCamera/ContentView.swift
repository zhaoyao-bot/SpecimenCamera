import SwiftUI

struct ContentView: View {
    @State private var showSpecimenCapture = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 20) {
                    // App title
                    VStack(spacing: 8) {
                        Image("Icon-1024")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .shadow(radius: 4)

                        Text("标本相机")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    .padding(.top, 60)

                    Spacer()

                    // Main features
                    VStack(spacing: 16) {
                        // Specimen recording
                        NavigationLink {
                            CaptureSetupView()
                        } label: {
                            featureCard(icon: "microscope.fill",
                                        title: "标本录制",
                                        subtitle: "选择标本、配置参数、拍摄瓦片",
                                        color: .blue)
                        }

                        // Quick camera (original function)
                        NavigationLink {
                            QuickCameraView()
                        } label: {
                            featureCard(icon: "camera.fill",
                                        title: "快速拍照",
                                        subtitle: "RAW+JPEG 拍摄，保存到相册",
                                        color: .orange)
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer()

                    // API settings
                    NavigationLink {
                        APISettingsView()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape.fill")
                                .font(.caption)
                            Text("API 设置")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("")
        }
    }

    private func featureCard(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Quick Camera View (Original)

struct QuickCameraView: View {
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
        .navigationTitle("快速拍照")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("保存结果", isPresented: showSaveResult, actions: {
            Button("好") { cameraManager.saveResult = nil }
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
                Button("授权相机") { cameraManager.requestPermission() }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
            } else {
                Button("去设置") { cameraManager.openSettings() }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
            }
        }
    }

    private var cameraView: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                CameraPreviewView(session: cameraManager.captureSession)
                    .aspectRatio(3/4, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipped()

                Spacer()

                VStack(spacing: 16) {
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
            if cameraManager.capturedImage != nil {
                photoReviewOverlay
                    .transition(.opacity)
            }
        }
    }

    private var captureButton: some View {
        Button {
            cameraManager.capturePhoto()
            withAnimation(.easeInOut(duration: 0.1)) { isPressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) { isPressed = false }
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

    private var photoReviewOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = cameraManager.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
            }

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

            VStack {
                Spacer()
                HStack(spacing: 0) {
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

                    Spacer().frame(width: 16)

                    Button {
                        cameraManager.saveToAlbum()
                    } label: {
                        HStack(spacing: 6) {
                            if cameraManager.isSaving {
                                ProgressView().tint(.white)
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

// MARK: - API Settings

struct APISettingsView: View {
    @AppStorage("api_base_url") private var baseURL = ""
    @State private var inputURL = ""
    @State private var testResult: String?

    var body: some View {
        Form {
            Section(header: Text("服务器地址")) {
                TextField("https://specimen.example.com", text: $inputURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                Button("保存") {
                    let trimmed = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        baseURL = trimmed
                    }
                    testResult = "已保存"
                }
                .disabled(inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section(header: Text("连接测试")) {
                Button("测试连接") {
                    Task { await testConnection() }
                }

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(result.contains("成功") ? .green : .red)
                }
            }
        }
        .navigationTitle("API 设置")
        .onAppear {
            inputURL = baseURL.isEmpty ? APIConfig.baseURL : baseURL
        }
    }

    private func testConnection() async {
        do {
            let specimens = try await APIService.shared.fetchSpecimens()
            testResult = "连接成功，获取到 \(specimens.count) 个标本"
        } catch {
            testResult = "连接失败: \(error.localizedDescription)"
        }
    }
}

#Preview("主页") {
    ContentView()
}
