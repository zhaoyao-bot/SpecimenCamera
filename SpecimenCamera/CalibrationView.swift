import SwiftUI

// MARK: - Calibration Setup View (选择放大倍数 → 开始标定)

struct CalibrationSetupView: View {
    @StateObject private var api = APIService.shared
    @State private var ratios: [SpecimenRatio] = []
    @State private var selectedRatioIndex: Int?
    @State private var isLoadingRatios = false
    @State private var showRatioPicker = false
    @State private var navigateToCalibration = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Ratio selection card
                    sectionCard(icon: "magnifyingglass", title: "放大倍数") {
                        ratioPickerRow
                    }

                    // Start calibration button
                    if selectedRatioIndex != nil {
                        Button {
                            navigateToCalibration = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("开始标定")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                LinearGradient(colors: [WarmTheme.success, Color(red: 0.40, green: 0.60, blue: 0.20)], startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: WarmTheme.success.opacity(0.35), radius: 8, y: 4)
                        }
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: selectedRatioIndex != nil)
                .padding(18)
            }
            .background(
                LinearGradient(colors: [WarmTheme.bgGradientTop, WarmTheme.bgGradientBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            )
            .navigationTitle("标定")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadRatios()
            }
            .refreshable {
                await loadRatios()
            }
            .overlay {
                if isLoadingRatios {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(WarmTheme.success)
                            .scaleEffect(1.2)
                        Text("加载中...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(WarmTheme.textSecondary)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                }
            }
            .navigationDestination(isPresented: $navigateToCalibration) {
                if let rIdx = selectedRatioIndex {
                    CalibrationCameraView(ratioId: ratios[rIdx].id, ratioName: ratios[rIdx].ratio)
                }
            }
        }
    }

    // MARK: - Section Card

    private func sectionCard<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(WarmTheme.success)
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(WarmTheme.textPrimary)
            }
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(WarmTheme.cardBg)
                .shadow(color: WarmTheme.deep.opacity(0.06), radius: 6, y: 3)
        )
    }

    // MARK: - Ratio Picker

    private var ratioPickerRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("放大倍数")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(WarmTheme.textSecondary)
            Button {
                if !ratios.isEmpty { showRatioPicker = true }
            } label: {
                HStack {
                    Text(ratios.isEmpty ? "暂无数据" : (selectedRatioIndex != nil ? "\(ratios[selectedRatioIndex!].ratio)x" : "请选择"))
                        .font(.system(size: 15))
                        .foregroundColor(ratios.isEmpty ? WarmTheme.textSecondary.opacity(0.5) : (selectedRatioIndex != nil ? WarmTheme.textPrimary : WarmTheme.textSecondary.opacity(0.5)))
                    Spacer()
                    if !ratios.isEmpty {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(WarmTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(WarmTheme.light)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .confirmationDialog("选择放大倍数", isPresented: $showRatioPicker, titleVisibility: .visible) {
                ForEach(Array(ratios.enumerated()), id: \.offset) { idx, ratio in
                    Button("\(ratio.ratio)x") { selectedRatioIndex = idx }
                }
            }

            // Selected ratio info
            if let rIdx = selectedRatioIndex {
                let ratio = ratios[rIdx]
                HStack(spacing: 12) {
                    infoRow(icon: "ruler", label: "当前标尺", value: ratio.ruler != nil ? String(format: "%.2f px/μm", ratio.ruler!) : "未标定")
                }
                .font(.caption)
                .foregroundColor(ratio.ruler != nil ? WarmTheme.success : WarmTheme.textSecondary)
                .padding(.top, 4)
            }
        }
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text("\(label):")
            Text(value)
        }
    }

    // MARK: - Data Loading

    private func loadRatios() async {
        isLoadingRatios = true
        if let allRatios = try? await api.fetchAllRatios() {
            ratios = allRatios
        }
        isLoadingRatios = false
    }
}

// MARK: - Calibration Camera View (拍照 + 标定)

struct CalibrationCameraView: View {
    let ratioId: Int
    let ratioName: String

    @StateObject private var cameraManager: CameraManager = {
        let mgr = CameraManager()
        mgr.preferRAW = false  // calibration only needs JPEG
        return mgr
    }()
    @StateObject private var api = APIService.shared

    // Calibration state
    @State private var capturedImage: UIImage?
    @State private var pointA: CGPoint?
    @State private var pointB: CGPoint?
    @State private var realDistance: Double = 0
    @State private var isUpdatingRuler = false
    @State private var toastMessage: String?
    @State private var toastIsSuccess = true
    @State private var adjustStep: CGFloat = 1

    // Brightness (SwiftUI .brightness() modifier, 0 = original)
    @State private var brightnessValue: Double = 0

    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if capturedImage == nil {
                cameraPhase
            } else {
                calibrationPhase
            }
        }
        .statusBarHidden(true)
        .navigationBarHidden(true)
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.easeOut(duration: 0.3)) { toastMessage = nil }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: toastMessage)
        .task {
            if cameraManager.permissionStatus == .notDetermined {
                cameraManager.requestPermission()
            }
        }
    }

    // MARK: - Camera Phase

    private var cameraPhase: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                Spacer()
                VStack(spacing: 3) {
                    Text("标定 · \(ratioName)x")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("拍摄标尺参考照片")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                }
                Spacer()
                Spacer().frame(width: 34)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.7))

            // 镜头切换(主摄 / 长焦)
            HStack {
                Spacer()
                LensSwitchPicker(cameraManager: cameraManager)
                Spacer()
            }
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.55))

            // Camera preview
            CameraPreviewView(session: cameraManager.captureSession)
                .aspectRatio(3/4, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()

            Spacer()

            // Capture button
            Button {
                cameraManager.capturePhoto()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(WarmTheme.accent, lineWidth: 4)
                        .frame(width: 72, height: 72)
                    Circle()
                        .fill(LinearGradient(colors: [.white, WarmTheme.light], startPoint: .top, endPoint: .bottom))
                        .frame(width: 60, height: 60)
                        .shadow(color: WarmTheme.accent.opacity(0.3), radius: 4, y: 2)
                }
            }
            .disabled(cameraManager.permissionStatus != .authorized)
            .padding(.bottom, 30)
        }
        .onChange(of: cameraManager.capturedImage) { _, newImage in
            if let img = newImage {
                capturedImage = img
                pointA = nil
                pointB = nil
                realDistance = 0
            }
        }
    }

    // MARK: - Calibration Phase

    private var calibrationPhase: some View {
        GeometryReader { geo in
            ZStack {
                // Photo display
                if let img = capturedImage {
                    imageWithPoints(img: img, containerSize: geo.size)
                        .brightness(brightnessValue)
                }

                // Info overlay
                VStack {
                    calibrationTopBar
                    Spacer()
                    calibrationResultPanel
                }
            }
        }
    }

    private var calibrationTopBar: some View {
        HStack(spacing: 8) {
            Button {
                capturedImage = nil
                pointA = nil
                pointB = nil
                realDistance = 0
                cameraManager.discardPhoto()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .semibold))
                    Text("重拍")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
            }

            Spacer()

            // Brightness
            HStack(spacing: 4) {
                Image(systemName: "sun.max")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                Slider(value: $brightnessValue, in: -0.3...0.5, step: 0.05)
                    .frame(width: 70)
                Text(String(format: "%.0f", brightnessValue * 100))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.1))
            .clipShape(Capsule())

            // Ratio label
            Text("\(ratioName)x")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(WarmTheme.accent.opacity(0.3))
                .clipShape(Capsule())

            // Clear points
            if pointA != nil || pointB != nil {
                Button {
                    pointA = nil
                    pointB = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 12))
                        Text("清除")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.3))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.7))
    }

    private var calibrationResultPanel: some View {
        VStack(spacing: 12) {
            if let a = pointA, let b = pointB {
                let pixelDist = sqrt(pow(b.x - a.x, 2) + pow(b.y - a.y, 2))
                let roundedDist = round(pixelDist * 100) / 100

                VStack(spacing: 10) {
                    Text("像素距离: \(String(format: "%.2f", roundedDist)) px")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    // Fine-tune controls
                    fineTuneControls

                    // Real distance input
                    HStack(spacing: 10) {
                        Text("实际距离:")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        TextField("μm", value: $realDistance, format: .number)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(WarmTheme.accent)
                            .multilineTextAlignment(.center)
                            .frame(width: 80)
                            .keyboardType(.decimalPad)
                            .focused($isFocused)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(Color.white.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("μm")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }

                    // Calculated ruler
                    if realDistance > 0 {
                        let ruler = roundedDist / realDistance
                        Text("标尺值: \(String(format: "%.2f", ruler)) px/μm")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(WarmTheme.success)

                        Button {
                            Task { await updateRuler(ruler: ruler) }
                        } label: {
                            HStack(spacing: 8) {
                                if isUpdatingRuler {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "arrow.up.doc.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                Text(isUpdatingRuler ? "更新中" : "更新标尺到服务器")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(colors: [WarmTheme.success, WarmTheme.success.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(isUpdatingRuler)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.85))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WarmTheme.accent.opacity(0.3), lineWidth: 1))
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            } else {
                VStack(spacing: 6) {
                    Text(pointA == nil ? "点击照片放置标记点 A" : "点击照片放置标记点 B")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(16)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.7))
                )
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Fine-tune Controls

    private var fineTuneControls: some View {
        HStack(spacing: 16) {
            // Point A
            VStack(spacing: 6) {
                Text("A 微调")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(WarmTheme.accent)
                directionPad(point: $pointA)
            }

            Divider().frame(height: 60).background(Color.white.opacity(0.2))

            // Point B
            VStack(spacing: 6) {
                Text("B 微调")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(WarmTheme.success)
                directionPad(point: $pointB)
            }

            Divider().frame(height: 60).background(Color.white.opacity(0.2))

            // Step
            VStack(spacing: 6) {
                Text("步进")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                stepControl
            }
        }
        .padding(.vertical, 8)
    }

    private func directionPad(point: Binding<CGPoint?>) -> some View {
        VStack(spacing: 3) {
            arrowButton(icon: "chevron.up", action: {
                if let p = point.wrappedValue {
                    point.wrappedValue = CGPoint(x: p.x, y: p.y - adjustStep)
                }
            }, enabled: point.wrappedValue != nil)

            HStack(spacing: 3) {
                arrowButton(icon: "chevron.left", action: {
                    if let p = point.wrappedValue {
                        point.wrappedValue = CGPoint(x: p.x - adjustStep, y: p.y)
                    }
                }, enabled: point.wrappedValue != nil)

                arrowButton(icon: "chevron.right", action: {
                    if let p = point.wrappedValue {
                        point.wrappedValue = CGPoint(x: p.x + adjustStep, y: p.y)
                    }
                }, enabled: point.wrappedValue != nil)
            }

            arrowButton(icon: "chevron.down", action: {
                if let p = point.wrappedValue {
                    point.wrappedValue = CGPoint(x: p.x, y: p.y + adjustStep)
                }
            }, enabled: point.wrappedValue != nil)
        }
    }

    private func arrowButton(icon: String, action: @escaping () -> Void, enabled: Bool) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(enabled ? .white : .white.opacity(0.3))
                .frame(width: 36, height: 30)
                .background(enabled ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .disabled(!enabled)
    }

    private var stepControl: some View {
        HStack(spacing: 2) {
            Button { adjustStep = max(1, adjustStep - 1) } label: {
                Text("-")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 28)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            Text("\(Int(adjustStep))")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 24)
            Button { adjustStep = min(10, adjustStep + 1) } label: {
                Text("+")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 28)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Image with Points

    @MainActor
    private func imageWithPoints(img: UIImage, containerSize: CGSize) -> some View {
        let imageSize = img.size
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        let fitSize: CGSize
        let offset: CGPoint
        if imageAspect > containerAspect {
            let scale = containerSize.width / imageSize.width
            fitSize = CGSize(width: containerSize.width, height: imageSize.height * scale)
            offset = CGPoint(x: 0, y: (containerSize.height - fitSize.height) / 2)
        } else {
            let scale = containerSize.height / imageSize.height
            fitSize = CGSize(width: imageSize.width * scale, height: containerSize.height)
            offset = CGPoint(x: (containerSize.width - fitSize.width) / 2, y: 0)
        }

        let displayScale = fitSize.width / imageSize.width

        return ZStack {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let a = pointA {
                pointMarker(at: CGPoint(x: a.x * displayScale + offset.x,
                                        y: a.y * displayScale + offset.y),
                            label: "A", color: WarmTheme.accent)
            }
            if let b = pointB {
                pointMarker(at: CGPoint(x: b.x * displayScale + offset.x,
                                        y: b.y * displayScale + offset.y),
                            label: "B", color: WarmTheme.success)
            }
            if let a = pointA, let b = pointB {
                lineFrom(
                    CGPoint(x: a.x * displayScale + offset.x, y: a.y * displayScale + offset.y),
                    CGPoint(x: b.x * displayScale + offset.x, y: b.y * displayScale + offset.y)
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
            let imgX = (location.x - offset.x) / displayScale
            let imgY = (location.y - offset.y) / displayScale
            let clampedX = max(0, min(imageSize.width, imgX))
            let clampedY = max(0, min(imageSize.height, imgY))

            if pointA == nil {
                pointA = CGPoint(x: clampedX, y: clampedY)
            } else if pointB == nil {
                pointB = CGPoint(x: clampedX, y: clampedY)
            } else {
                pointA = CGPoint(x: clampedX, y: clampedY)
                pointB = nil
            }
            isFocused = false
        }
    }

    private func pointMarker(at point: CGPoint, label: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 24, height: 24)
                .opacity(0.5)
            Circle()
                .stroke(color, lineWidth: 2)
                .frame(width: 24, height: 24)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .position(point)
    }

    private func lineFrom(_ p1: CGPoint, _ p2: CGPoint) -> some View {
        Path { path in
            path.move(to: p1)
            path.addLine(to: p2)
        }
        .stroke(WarmTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
    }

    // MARK: - Update Ruler

    private func updateRuler(ruler: Double) async {
        isUpdatingRuler = true
        do {
            let updated = try await api.updateRatioRuler(ratioId: ratioId, ruler: ruler)
            toastIsSuccess = true
            toastMessage = "标尺已更新: \(String(format: "%.2f", updated.ruler ?? ruler)) px/μm"
        } catch {
            toastIsSuccess = false
            toastMessage = "更新失败: \(error.localizedDescription)"
        }
        isUpdatingRuler = false
    }
}