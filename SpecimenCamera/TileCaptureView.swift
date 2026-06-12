import SwiftUI
import Photos

struct TileCaptureView: View {
    let config: CaptureConfig

    @StateObject private var cameraManager = CameraManager()
    @StateObject private var api = APIService.shared

    // Tile queue
    @State private var tileQueue: [TileQueueItem] = []
    @State private var direction: TileQueueItem.Direction = .up
    @State private var parentSeq: Int = 0
    @State private var seqId: Int = 1

    // Parent overlay
    @State private var parentImage: UIImage?

    // Upload state
    @State private var isUploading = false
    @State private var uploadMessage: String?

    // Review mode
    @State private var isReviewing = false

    // Queue sheet
    @State private var showQueueSheet = false
    @State private var remoteTiles: [SpecimenTile] = []
    @State private var isLoadingTiles = false

    // Focus state for dismissing keyboard
    @FocusState private var isFocused: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top info bar
                topBar

                // Camera preview with parent overlay
                ZStack {
                    CameraPreviewView(session: cameraManager.captureSession)
                        .aspectRatio(3/4, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipped()

                    // Parent image overlay
                    if let parentImg = parentImage {
                        Image(uiImage: parentImg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .opacity(0.4)
                            .blendMode(.screen)
                            .allowsHitTesting(false)
                    }
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
        }
        .overlay {
            if isReviewing, cameraManager.capturedImage != nil {
                reviewOverlay
            }
        }
        .sheet(isPresented: $showQueueSheet) {
            queueSheetView
        }
        .alert("上传结果", isPresented: showUploadMessage, actions: {
            Button("好") { uploadMessage = nil }
        }, message: {
            Text(uploadMessage ?? "")
        })
        .onTapGesture {
            isFocused = false
        }
    }

    private var showUploadMessage: Binding<Bool> {
        Binding(get: { uploadMessage != nil }, set: { if !$0 { uploadMessage = nil } })
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
                Text(direction.rawValue)
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
                        Text(dir.rawValue)
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

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack {
            // View parent image button
            Button {
                loadParentImage()
            } label: {
                VStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(WarmTheme.accent.opacity(parentSeq > 0 ? 0.2 : 0.05))
                            .frame(width: 48, height: 48)
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 20))
                    }
                    Text("父图")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(parentSeq > 0 ? WarmTheme.accent : .gray)
            }
            .disabled(parentSeq == 0)

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
                        Text("\(direction.rawValue) | 父:\(parentSeq) | 序:\(seqId)")
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
                                        // Seq badge
                                        ZStack {
                                            Circle()
                                                .fill(WarmTheme.accent.opacity(0.15))
                                                .frame(width: 40, height: 40)
                                            Text("\(tile.seqId)")
                                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                                .foregroundColor(WarmTheme.primary)
                                        }
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("序:\(tile.seqId) | 父:\(tile.parentSeq)")
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                .foregroundColor(WarmTheme.textPrimary)
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.right.circle")
                                                    .font(.system(size: 10))
                                                Text("方向: \(tile.direction ?? "-")")
                                                if let time = tile.updateTime {
                                                    Text(" · \(time)")
                                                        .foregroundColor(WarmTheme.textSecondary.opacity(0.6))
                                                }
                                            }
                                            .font(.system(size: 12))
                                            .foregroundColor(WarmTheme.textSecondary)
                                        }
                                        Spacer()
                                        if tile.cameraImage != nil || tile.canvasImage != nil {
                                            Image(systemName: "photo.fill")
                                                .foregroundColor(WarmTheme.primary)
                                        }
                                    }
                                    .padding(.vertical, 4)
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
                                        ZStack {
                                            Circle()
                                                .fill(WarmTheme.success.opacity(0.15))
                                                .frame(width: 40, height: 40)
                                            Text("\(item.seqId)")
                                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                                .foregroundColor(WarmTheme.success)
                                        }
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("序:\(item.seqId) | 父:\(item.parentSeq)")
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                .foregroundColor(WarmTheme.textPrimary)
                                            Text("方向: \(item.direction.rawValue)")
                                                .font(.system(size: 12))
                                                .foregroundColor(WarmTheme.textSecondary)
                                        }
                                        Spacer()
                                        if let img = item.cameraImage {
                                            Image(uiImage: img)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 40, height: 40)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(WarmTheme.accent.opacity(0.2), lineWidth: 1)
                                                )
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
                cameraImage: cameraManager.capturedJpegData
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

            uploadMessage = "瓦片 #\(tile.seqId) 上传成功"
            cameraManager.discardPhoto()
            isReviewing = false
        } catch {
            uploadMessage = "上传失败: \(error.localizedDescription)"
        }

        isUploading = false
    }

    private func saveToAlbum() {
        cameraManager.saveToAlbum()
    }

    private func loadParentImage() {
        guard parentSeq > 0 else { return }
        Task {
            do {
                let tiles = try await api.fetchTiles(
                    specimenId: config.specimenId,
                    ratioId: config.ratioId,
                    stackId: config.stackId
                )
                if let parentTile = tiles.tiles?.first(where: { $0.seqId == parentSeq }),
                   let imageUrl = parentTile.cameraImage ?? parentTile.canvasImage {
                    parentImage = try await api.fetchTileImage(urlString: imageUrl)
                }
            } catch {
                print("加载父图失败: \(error)")
            }
        }
    }

    private func loadRemoteTiles() async {
        isLoadingTiles = true
        do {
            let response = try await api.fetchTiles(
                specimenId: config.specimenId,
                ratioId: config.ratioId,
                stackId: config.stackId
            )
            remoteTiles = response.tiles ?? []
        } catch {
            print("加载瓦片列表失败: \(error)")
        }
        isLoadingTiles = false
    }
}