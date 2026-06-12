import SwiftUI

// MARK: - Warm Theme Colors

struct WarmTheme {
    static let primary = Color(red: 0.85, green: 0.55, blue: 0.25)      // Amber brown
    static let accent = Color(red: 0.92, green: 0.65, blue: 0.30)      // Warm amber
    static let deep = Color(red: 0.60, green: 0.35, blue: 0.15)        // Deep brown
    static let light = Color(red: 0.98, green: 0.92, blue: 0.85)       // Warm cream
    static let bgGradientTop = Color(red: 0.96, green: 0.88, blue: 0.78)
    static let bgGradientBottom = Color(red: 0.92, green: 0.82, blue: 0.70)
    static let cardBg = Color(red: 1.0, green: 0.97, blue: 0.93)
    static let textPrimary = Color(red: 0.35, green: 0.20, blue: 0.10)
    static let textSecondary = Color(red: 0.55, green: 0.40, blue: 0.25)
    static let success = Color(red: 0.55, green: 0.75, blue: 0.35)
}

struct ContentView: View {
    @State private var showSpecimenCapture = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Warm gradient background
                LinearGradient(
                    colors: [WarmTheme.bgGradientTop, WarmTheme.bgGradientBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // App title area
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(WarmTheme.accent.opacity(0.15))
                                .frame(width: 120, height: 120)
                            Circle()
                                .fill(WarmTheme.accent.opacity(0.08))
                                .frame(width: 160, height: 160)
                            Image(systemName: "camera.metering.matrix")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 50, height: 50)
                                .foregroundColor(WarmTheme.deep)
                        }

                        Text("标本相机")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(WarmTheme.textPrimary)

                        Text("微观世界，尽在掌握")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(WarmTheme.textSecondary)
                    }
                    .padding(.top, 80)

                    Spacer()

                    // Main features
                    VStack(spacing: 18) {
                        NavigationLink {
                            CaptureSetupView()
                        } label: {
                            featureCard(icon: "binoculars.fill",
                                        title: "标本录制",
                                        subtitle: "选择标本 · 配置参数 · 拍摄瓦片",
                                        gradient: [WarmTheme.primary, WarmTheme.deep])
                        }

                        NavigationLink {
                            QuickCameraView()
                        } label: {
                            featureCard(icon: "camera.fill",
                                        title: "快速拍照",
                                        subtitle: "RAW+JPEG 拍摄 · 保存到相册",
                                        gradient: [WarmTheme.accent, WarmTheme.primary])
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    // API settings
                    NavigationLink {
                        APISettingsView()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 13))
                            Text("API 设置")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(WarmTheme.textSecondary)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(WarmTheme.cardBg.opacity(0.6))
                        .clipShape(Capsule())
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("")
        }
    }

    private func featureCard(icon: String, title: String, subtitle: String, gradient: [Color]) -> some View {
        HStack(spacing: 18) {
            // Icon with gradient background
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 60, height: 60)
                    .shadow(color: gradient.first!.opacity(0.3), radius: 6, y: 3)

                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(WarmTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(WarmTheme.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(WarmTheme.textSecondary.opacity(0.6))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(WarmTheme.cardBg)
                .shadow(color: WarmTheme.deep.opacity(0.08), radius: 8, y: 4)
        )
    }
}

// MARK: - Quick Camera View

struct QuickCameraView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var isPressed = false
    @State private var toastMessage: String?
    @State private var toastIsSuccess = true

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
        .overlay(alignment: .top) {
            if let msg = toastMessage {
                HStack(spacing: 8) {
                    Image(systemName: toastIsSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(msg)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(toastIsSuccess ? WarmTheme.success.opacity(0.9) : Color.red.opacity(0.85))
                )
                .padding(.top, 50)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            toastMessage = nil
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: toastMessage)
        .onChange(of: cameraManager.saveResult) { _, newValue in
            if let result = newValue {
                toastIsSuccess = result.success
                toastMessage = result.message
            }
        }
    }

    @ViewBuilder
    private func permissionView(message: String) -> some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(WarmTheme.accent.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: "camera.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(WarmTheme.accent)
            }
            Text(message)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if cameraManager.permissionStatus == .notDetermined {
                Button("授权相机") { cameraManager.requestPermission() }
                    .buttonStyle(.borderedProminent)
                    .tint(WarmTheme.primary)
            } else {
                Button("去设置") { cameraManager.openSettings() }
                    .buttonStyle(.borderedProminent)
                    .tint(WarmTheme.primary)
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
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                LinearGradient(colors: [WarmTheme.accent, WarmTheme.primary], startPoint: .leading, endPoint: .trailing)
                            )
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
                    .strokeBorder(WarmTheme.accent, lineWidth: 4)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(
                        LinearGradient(colors: [.white, WarmTheme.light], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 60, height: 60)
                    .shadow(color: WarmTheme.accent.opacity(0.3), radius: 4, y: 2)
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
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                LinearGradient(colors: [WarmTheme.accent, WarmTheme.primary], startPoint: .leading, endPoint: .trailing)
                            )
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
                HStack(spacing: 14) {
                    Button {
                        cameraManager.discardPhoto()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 20, weight: .semibold))
                            Text("重拍")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }

                    Button {
                        cameraManager.saveToAlbum()
                    } label: {
                        HStack(spacing: 8) {
                            if cameraManager.isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 20, weight: .semibold))
                            }
                            Text(cameraManager.isSaving ? "保存中" : "保存到相册")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(colors: [WarmTheme.success, WarmTheme.success.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(cameraManager.isSaving)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
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
            Section(header:
                Text("服务器地址")
                    .foregroundColor(WarmTheme.textSecondary)
            ) {
                TextField("https://specimen.example.com", text: $inputURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                Button("保存到相册") {
                    let trimmed = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        baseURL = trimmed
                    }
                    testResult = "已保存到相册"
                }
                .disabled(inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .tint(WarmTheme.primary)
            }

            Section(header:
                Text("连接测试")
                    .foregroundColor(WarmTheme.textSecondary)
            ) {
                Button("测试连接") {
                    Task { await testConnection() }
                }
                .tint(WarmTheme.primary)

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(result.contains("成功") ? WarmTheme.success : .red)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(WarmTheme.bgGradientTop)
        .navigationTitle("API 设置")
        .navigationBarTitleDisplayMode(.inline)
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
