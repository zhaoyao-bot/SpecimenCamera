import SwiftUI
import Photos

struct TileCaptureView: View {
    let config: CaptureConfig

    @StateObject private var cameraManager = CameraManager()
    @StateObject private var api = APIService.shared

    // Tile queue
    @State private var tileQueue: [TileQueueItem] = []
    @State private var direction: TileQueueItem.Direction = .down
    @State private var parentSeq: Int = 0
    @State private var seqId: Int = 1

    // Parent overlay
    @State private var parentImage: UIImage?
    @State private var isLoadingParent = false
    @State private var showParentOverlay = false

    // Upload state
    @State private var isUploading = false
    @State private var toastMessage: String?
    @State private var toastIsSuccess = true

    // Review mode
    @State private var isReviewing = false

    // parentSeq 变化的 debounce Task(1 秒节流加载父图，避免输入过程多次触发加载)
    @State private var parentLoadTask: Task<Void, Never>?

    // Queue sheet
    @State private var showQueueSheet = false
    @State private var remoteTiles: [SpecimenTile] = []
    @State private var isLoadingTiles = false
    @State private var remoteThumbnails: [Int: UIImage] = [:]

    // Focus state for dismissing keyboard
    @FocusState private var isFocused: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top info bar
                topBar

                // 镜头切换(主摄 / 长焦)
                HStack {
                    Spacer()
                    LensSwitchPicker(cameraManager: cameraManager)
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.55))

                // Camera preview with parent overlay
                GeometryReader { geo in
                    ZStack {
                        CameraPreviewView(session: cameraManager.captureSession)
                            .aspectRatio(3/4, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipped()

                        // Parent image overlay — cropped and aligned by direction
                        if let parentImg = parentImage, showParentOverlay {
                            parentOverlayView(parentImg: parentImg, containerSize: geo.size)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }

                // Tile info panel
                tileInfoPanel

                // Direction selector
                directionSelector

                // Bottom controls
                bottomControls
            }
        }
        .statusBarHidden(true)
        .navigationBarHidden(true)
        .task {
            if cameraManager.permissionStatus == .notDetermined {
                cameraManager.requestPermission()
            }
            // Auto-load parent image if parentSeq > 0
            if parentSeq > 0 {
                await loadParentImage()
            }
        }
        .onChange(of: parentSeq) { _, newSeq in
            // 取消上一次的 debounce 任务(快速输入时只加载最后一次)
            parentLoadTask?.cancel()
            if newSeq > 0 {
                parentLoadTask = Task {
                    // 1 秒内若无新变化再加载，避免 TextField 输入过程中闪 toast
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                    await loadParentImage()
                }
            } else {
                // 显式归零时立即清空父图
                parentImage = nil
                showParentOverlay = false
            }
        }
        .onDisappear {
            // 离开页面时取消未完成的加载任务
            parentLoadTask?.cancel()
        }
        .overlay {
            if isReviewing, cameraManager.capturedImage != nil {
                reviewOverlay
            }
        }
        .sheet(isPresented: $showQueueSheet) {
            queueSheetView
        }
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
        .onTapGesture {
            isFocused = false
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }

            Spacer()

            VStack(spacing: 3) {
                Text(config.specimenName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("\(config.ratioName) | \(config.stackName)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 11))
                Text("\(tileQueue.count)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                LinearGradient(colors: [WarmTheme.accent.opacity(0.6), WarmTheme.primary.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
        )
    }

    // MARK: - Tile Info Panel

    private var tileInfoPanel: some View {
        HStack(spacing: 16) {
            // Parent seq
            VStack(spacing: 5) {
                Text("父序号")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                HStack(spacing: 4) {
                    Button { parentSeq = max(0, parentSeq - 1) } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(WarmTheme.accent)
                    }
                    TextField("0", value: $parentSeq, format: .number)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .frame(width: 44)
                        .keyboardType(.numberPad)
                        .focused($isFocused)
                    Button { parentSeq += 1 } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(WarmTheme.accent)
                    }
                }
            }

            // Divider
            Rectangle()
                .fill(WarmTheme.accent.opacity(0.3))
                .frame(width: 1, height: 40)

            // Seq ID
            VStack(spacing: 5) {
                Text("序号")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                HStack(spacing: 4) {
                    Button { seqId = max(1, seqId - 1) } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(WarmTheme.accent)
                    }
                    TextField("1", value: $seqId, format: .number)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .frame(width: 44)
                        .keyboardType(.numberPad)
                        .focused($isFocused)
                    Button { seqId += 1 } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(WarmTheme.accent)
                    }
                }
            }

            // Divider
            Rectangle()
                .fill(WarmTheme.accent.opacity(0.3))
                .frame(width: 1, height: 40)

            // Direction label
            VStack(spacing: 5) {
                Text("方向")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                Text(direction.displayName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(WarmTheme.accent)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.6), Color.black.opacity(0.4)], startPoint: .top, endPoint: .bottom)
        )
    }

    // MARK: - Direction Selector

    private var directionSelector: some View {
        HStack(spacing: 14) {
            ForEach(TileQueueItem.Direction.allCases, id: \.self) { dir in
                Button {
                    direction = dir
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: directionIcon(for: dir))
                            .font(.system(size: 16, weight: .semibold))
                        Text(dir.displayName)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(direction == dir ? WarmTheme.deep : .white.opacity(0.8))
                    .frame(width: 50, height: 42)
                    .background(
                        direction == dir
                            ? LinearGradient(colors: [WarmTheme.accent, WarmTheme.light], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.15), Color.white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(direction == dir ? WarmTheme.accent.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
            }
        }
        .padding(.vertical, 12)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.5), Color.black.opacity(0.3)], startPoint: .top, endPoint: .bottom)
        )
    }

    private func directionIcon(for dir: TileQueueItem.Direction) -> String {
        switch dir {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        }
    }

    // MARK: - Parent Overlay

    /// Crop parent image to 5/8 portion based on direction and create overlay view
    @MainActor
    private func parentOverlayView(parentImg: UIImage, containerSize: CGSize) -> some View {
        let croppedImage = cropParentImage(parentImg, direction: direction)

        // Calculate how much of the container the cropped portion should cover
        // The cropped portion is 5/8 of the original image, displayed at the same scale
        // as a full image in .fit mode, so it covers 5/8 of the preview area
        let isVertical = direction == .up || direction == .down

        return ZStack(alignment: alignmentForDirection) {
            if isVertical {
                Image(uiImage: croppedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(0.35)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                    .frame(height: containerSize.height * 5.0 / 8.0)
            } else {
                Image(uiImage: croppedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(0.35)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                    .frame(width: containerSize.width * 5.0 / 8.0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignmentForDirection)
        .allowsHitTesting(false)
    }

    private var alignmentForDirection: Alignment {
        switch direction {
        case .down: return .top
        case .up: return .bottom
        case .right: return .leading
        case .left: return .trailing
        }
    }

    /// Crop parent image: take 5/8 portion based on direction
    private func cropParentImage(_ image: UIImage, direction: TileQueueItem.Direction) -> UIImage {
        let imgW = image.size.width
        let imgH = image.size.height
        let cropRect: CGRect

        switch direction {
        case .down:
            // Bottom 5/8: from y=3/8 to y=8/8
            let startY = imgH * (3.0 / 8.0)
            cropRect = CGRect(x: 0, y: startY, width: imgW, height: imgH * (5.0 / 8.0))
        case .up:
            // Top 5/8: from y=0 to y=5/8
            cropRect = CGRect(x: 0, y: 0, width: imgW, height: imgH * (5.0 / 8.0))
        case .right:
            // Right 5/8: from x=3/8 to x=8/8
            let startX = imgW * (3.0 / 8.0)
            cropRect = CGRect(x: startX, y: 0, width: imgW * (5.0 / 8.0), height: imgH)
        case .left:
            // Left 5/8: from x=0 to x=5/8
            cropRect = CGRect(x: 0, y: 0, width: imgW * (5.0 / 8.0), height: imgH)
        }

        let renderer = UIGraphicsImageRenderer(size: cropRect.size)
        return renderer.image { ctx in
            image.draw(at: CGPoint(x: -cropRect.origin.x, y: -cropRect.origin.y))
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack {
            // View parent image button
            Button {
                if parentImage != nil {
                    // Toggle overlay visibility
                    showParentOverlay.toggle()
                } else {
                    Task { await loadParentImage() }
                }
            } label: {
                VStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(WarmTheme.accent.opacity(parentSeq > 0 ? 0.2 : 0.05))
                            .frame(width: 48, height: 48)
                        if isLoadingParent {
                            ProgressView()
                                .tint(WarmTheme.accent)
                        } else if showParentOverlay && parentImage != nil {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 20))
                        } else {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 20))
                        }
                    }
                    Text(showParentOverlay && parentImage != nil ? "隐藏父图" : "父图")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(parentSeq > 0 ? WarmTheme.accent : .gray)
            }
            .disabled(parentSeq == 0 && parentImage == nil)

            Spacer()

            // Capture button
            Button {
                isFocused = false
                cameraManager.capturePhoto()
                isReviewing = true
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
            }
            .disabled(cameraManager.permissionStatus != .authorized)

            Spacer()

            // View queue button
            Button {
                isFocused = false
                Task { await loadRemoteTiles() }
                showQueueSheet = true
            } label: {
                VStack(spacing: 5) {
                    ZStack(alignment: .topTrailing) {
                        Circle()
                            .fill(WarmTheme.accent.opacity(0.2))
                            .frame(width: 48, height: 48)
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 20))
                            .foregroundColor(WarmTheme.accent)
                        if !tileQueue.isEmpty {
                            Text("\(tileQueue.count)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(
                                    LinearGradient(colors: [WarmTheme.primary, WarmTheme.deep], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .clipShape(Circle())
                                .offset(x: 4, y: -4)
                        }
                    }
                    Text("队列")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(WarmTheme.accent)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 18)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
        )
    }

    // MARK: - Review Overlay

    private var reviewOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = cameraManager.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
            }

            VStack {
                // Tile info badge
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11))
                        Text("\(direction.displayName) | 父:\(parentSeq) | 序:\(seqId)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(colors: [WarmTheme.primary.opacity(0.7), WarmTheme.deep.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                    Spacer()
                }
                .padding(.leading, 16)
                .padding(.top, 10)

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    // Upload & add to queue
                    Button {
                        Task { await uploadCurrentTile() }
                    } label: {
                        HStack(spacing: 10) {
                            if isUploading {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "arrow.up.doc.fill")
                                    .font(.system(size: 20, weight: .semibold))
                            }
                            Text(isUploading ? "上传中" : "确认上传")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(colors: [WarmTheme.success, WarmTheme.success.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isUploading)

                    // Save to album
                    Button {
                        saveToAlbum()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "photo.badge.arrow.down")
                                .font(.system(size: 20, weight: .semibold))
                            Text("保存到相册")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(colors: [WarmTheme.accent.opacity(0.7), WarmTheme.primary.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // Retake
                    Button {
                        cameraManager.discardPhoto()
                        isReviewing = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 20, weight: .semibold))
                            Text("重拍")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
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
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
            }
        }
    }

    // MARK: - Queue Sheet

    private var queueSheetView: some View {
        NavigationStack {
            Group {
                if isLoadingTiles {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(WarmTheme.primary)
                            .scaleEffect(1.2)
                        Text("加载队列...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(WarmTheme.textSecondary)
                    }
                } else if remoteTiles.isEmpty && tileQueue.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "tray")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(WarmTheme.textSecondary.opacity(0.5))
                        Text("暂无瓦片数据")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(WarmTheme.textSecondary)
                    }
                } else {
                    List {
                        // Remote tiles (reverse order)
                        if !remoteTiles.isEmpty {
                            Section {
                                ForEach(remoteTiles.reversed(), id: \.id) { tile in
                                    HStack(spacing: 12) {
                                        // Thumbnail or seq badge
                                        if let thumb = remoteThumbnails[tile.id] {
                                            Image(uiImage: thumb)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 44, height: 44)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(WarmTheme.accent.opacity(0.2), lineWidth: 1)
                                                )
                                        } else {
                                            ZStack {
                                                Circle()
                                                    .fill(WarmTheme.accent.opacity(0.15))
                                                    .frame(width: 44, height: 44)
                                                if tile.cameraImage != nil || tile.canvasImage != nil {
                                                    ProgressView()
                                                        .scaleEffect(0.6)
                                                        .tint(WarmTheme.primary)
                                                } else {
                                                    Text("\(tile.seqId)")
                                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                                        .foregroundColor(WarmTheme.primary)
                                                }
                                            }
                                        }
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("序:\(tile.seqId) | 父:\(tile.parentSeq)")
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                .foregroundColor(WarmTheme.textPrimary)
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.right.circle")
                                                    .font(.system(size: 10))
                                                Text("方向: \(TileQueueItem.Direction(rawValue: tile.direction ?? "")?.displayName ?? tile.direction ?? "-")")
                                                if let time = tile.updateTime {
                                                    Text(" · \(time)")
                                                        .foregroundColor(WarmTheme.textSecondary.opacity(0.6))
                                                }
                                            }
                                            .font(.system(size: 12))
                                            .foregroundColor(WarmTheme.textSecondary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .onAppear {
                                        loadRemoteThumbnail(tile: tile)
                                    }
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: "cloud.fill")
                                        .font(.system(size: 12))
                                    Text("服务器瓦片（倒序）")
                                }
                                .foregroundColor(WarmTheme.textSecondary)
                            }
                        }

                        // Local queue
                        if !tileQueue.isEmpty {
                            Section {
                                ForEach(tileQueue) { item in
                                    HStack(spacing: 12) {
                                        // Image on left (same layout as remote tiles)
                                        if let img = item.cameraImage {
                                            Image(uiImage: img)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 44, height: 44)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(WarmTheme.success.opacity(0.2), lineWidth: 1)
                                                )
                                        } else {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(WarmTheme.success.opacity(0.15))
                                                    .frame(width: 44, height: 44)
                                                Text("\(item.seqId)")
                                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                                    .foregroundColor(WarmTheme.success)
                                            }
                                        }
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("序:\(item.seqId) | 父:\(item.parentSeq)")
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                .foregroundColor(WarmTheme.textPrimary)
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.right.circle")
                                                    .font(.system(size: 10))
                                                Text("方向: \(item.direction.displayName)")
                                            }
                                            .font(.system(size: 12))
                                            .foregroundColor(WarmTheme.textSecondary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: "iphone")
                                        .font(.system(size: 12))
                                    Text("本次拍摄")
                                }
                                .foregroundColor(WarmTheme.textSecondary)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(WarmTheme.bgGradientTop)
                }
            }
            .navigationTitle("瓦片队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showQueueSheet = false }
                        .fontWeight(.bold)
                        .foregroundColor(WarmTheme.primary)
                }
            }
        }
    }

    // MARK: - Actions

    private func uploadCurrentTile() async {
        guard let image = cameraManager.capturedImage else { return }
        isUploading = true

        // Use same JPEG data for both canvasImage and cameraImage (compatible with old logic)
        let jpegData = image.jpegData(compressionQuality: 0.9)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        // Save current seqId as parentSeq for next tile
        let currentSeqId = seqId
        let currentParentSeq = parentSeq

        do {
            let tile = try await api.uploadTile(
                specimenId: config.specimenId,
                ratioId: config.ratioId,
                seqId: currentSeqId,
                parentSeq: currentParentSeq,
                direction: direction.rawValue,
                stackId: config.stackId,
                collectionDate: dateFormatter.string(from: config.collectionDate),
                collector: config.collector,
                canvasImage: jpegData,
                cameraImage: jpegData
            )

            // Add to local queue
            let item = TileQueueItem(
                direction: direction,
                parentSeq: currentParentSeq,
                seqId: currentSeqId,
                image: image,
                cameraImage: cameraManager.capturedImage,
                timestamp: Date()
            )
            tileQueue.append(item)

            // Auto-increment: next tile's parentSeq = current seqId
            parentSeq = currentSeqId
            seqId += 1

            toastIsSuccess = true
            toastMessage = "瓦片 #\(tile.seqId) 上传成功"
            cameraManager.discardPhoto()
            isReviewing = false
        } catch {
            toastIsSuccess = false
            toastMessage = "上传失败: \(error.localizedDescription)"
        }

        isUploading = false
    }

    private func saveToAlbum() {
        cameraManager.saveToAlbum()
        // Observe save result via onChange
    }

    private func loadParentImage() async {
        guard parentSeq > 0 else { return }
        isLoadingParent = true

        do {
            // Find parent tile and get image URL directly from list data
            var parentTile: SpecimenTile?
            if let pt = remoteTiles.first(where: { $0.seqId == parentSeq }) {
                parentTile = pt
            } else {
                // Fetch tiles list to find parent
                let response = try await api.fetchTiles(
                    specimenId: config.specimenId,
                    ratioId: config.ratioId,
                    stackId: config.stackId
                )
                remoteTiles = response.tiles ?? []
                parentTile = remoteTiles.first(where: { $0.seqId == parentSeq })
            }

            if let pt = parentTile {
                let imageUrl = pt.cameraImage ?? pt.canvasImage
                if let imageUrl = imageUrl {
                    print("🔍 Found parent image URL: \(imageUrl)")
                    // 记录加载前是否已有图：首次加载自动显示，已有图则尊重用户当前的显示/隐藏选择
                    let wasEmpty = (parentImage == nil)
                    parentImage = try await api.fetchTileImage(urlString: imageUrl)
                    if wasEmpty { showParentOverlay = true }
                } else {
                    print("❌ Parent tile has no image URL")
                    toastIsSuccess = false
                    toastMessage = "父图 #\(parentSeq) 无图片数据"
                }
            } else {
                toastIsSuccess = false
                toastMessage = "找不到父图 #\(parentSeq)"
            }
        } catch {
            print("❌ 加载父图失败: \(error)")
            toastIsSuccess = false
            toastMessage = "加载父图失败: \(error.localizedDescription)"
        }

        isLoadingParent = false
    }

    private func loadRemoteTiles() async {
        isLoadingTiles = true
        remoteThumbnails = [:]
        do {
            let response = try await api.fetchTiles(
                specimenId: config.specimenId,
                ratioId: config.ratioId,
                stackId: config.stackId
            )
            remoteTiles = response.tiles ?? []
            print("✅ Loaded \(remoteTiles.count) remote tiles")

            // Batch-load thumbnails concurrently from tile image URLs
            var loadedThumbnails: [Int: UIImage] = [:]
            await withTaskGroup(of: (Int, UIImage?).self) { group in
                for tile in remoteTiles {
                    group.addTask {
                        let imageUrl = tile.cameraImage ?? tile.canvasImage
                        if let imageUrl = imageUrl {
                            do {
                                let thumb = try await APIService.shared.fetchTileThumbnail(urlString: imageUrl)
                                return (tile.id, thumb)
                            } catch {
                                print("  ⚠️ thumbnail load failed for tile #\(tile.seqId) (id:\(tile.id)): \(error)")
                                return (tile.id, nil)
                            }
                        } else {
                            print("  ⚠️ tile #\(tile.seqId) (id:\(tile.id)) has no image URL")
                            return (tile.id, nil)
                        }
                    }
                }
                for await (id, thumb) in group {
                    if let img = thumb {
                        loadedThumbnails[id] = img
                    }
                }
            }
            remoteThumbnails = loadedThumbnails
            print("✅ Loaded \(remoteThumbnails.count) thumbnails out of \(remoteTiles.count) tiles")
        } catch {
            print("❌ 加载瓦片列表失败: \(error)")
        }
        isLoadingTiles = false
    }

    private func loadRemoteThumbnail(tile: SpecimenTile) {
        // No longer needed — thumbnails are batch-loaded in loadRemoteTiles
    }
}