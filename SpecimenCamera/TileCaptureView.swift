import SwiftUI
import Photos

struct TileCaptureView: View {
    let config: CaptureConfig

    @StateObject private var cameraManager = CameraManager()
    @StateObject private var api = APIService.shared

    // Tile queue
    @State private var tileQueue: [TileQueueItem] = []
    @State private var direction: TileQueueItem.Direction = .center
    @State private var parentSeq: Int = 0
    @State private var seqId: Int = 1

    // Parent overlay
    @State private var parentImage: UIImage?

    // Upload state
    @State private var isUploading = false
    @State private var uploadMessage: String?

    // Review mode
    @State private var isReviewing = false

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
                            .opacity(0.5)
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
        .alert("上传结果", isPresented: showUploadMessage, actions: {
            Button("好") { uploadMessage = nil }
        }, message: {
            Text(uploadMessage ?? "")
        })
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
                    .font(.title3)
                    .foregroundColor(.white)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(config.specimenName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                Text("\(config.ratioName) | \(config.stackName)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            Text("已拍 \(tileQueue.count)")
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.6))
    }

    // MARK: - Tile Info Panel

    private var tileInfoPanel: some View {
        HStack(spacing: 16) {
            // Parent seq
            VStack(spacing: 4) {
                Text("父序号")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                HStack(spacing: 4) {
                    Button { parentSeq = max(0, parentSeq - 1) } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                    TextField("0", value: $parentSeq, format: .number)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .frame(width: 44)
                        .keyboardType(.numberPad)
                    Button { parentSeq += 1 } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                }
            }

            Divider()
                .frame(height: 40)
                .background(Color.white.opacity(0.3))

            // Seq ID
            VStack(spacing: 4) {
                Text("序号")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                HStack(spacing: 4) {
                    Button { seqId = max(1, seqId - 1) } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                    TextField("1", value: $seqId, format: .number)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .frame(width: 44)
                        .keyboardType(.numberPad)
                    Button { seqId += 1 } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                }
            }

            Divider()
                .frame(height: 40)
                .background(Color.white.opacity(0.3))

            // Direction label
            VStack(spacing: 4) {
                Text("方向")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                Text(direction.rawValue)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.yellow)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.black.opacity(0.5))
    }

    // MARK: - Direction Selector

    private var directionSelector: some View {
        HStack(spacing: 12) {
            ForEach(TileQueueItem.Direction.allCases, id: \.self) { dir in
                Button {
                    direction = dir
                } label: {
                    Text(dir.rawValue)
                        .font(.subheadline)
                        .fontWeight(direction == dir ? .bold : .regular)
                        .foregroundColor(direction == dir ? .black : .white)
                        .frame(width: 44, height: 36)
                        .background(direction == dir ? Color.yellow : Color.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.4))
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack {
            // View parent image button
            Button {
                loadParentImage()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title2)
                    Text("父图")
                        .font(.caption2)
                }
                .foregroundColor(parentSeq > 0 ? .white : .gray)
            }
            .disabled(parentSeq == 0)

            Spacer()

            // Capture button
            Button {
                cameraManager.capturePhoto()
                isReviewing = true
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 4)
                        .frame(width: 70, height: 70)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 58, height: 58)
                }
            }
            .disabled(cameraManager.permissionStatus != .authorized)

            Spacer()

            // View queue button
            Button {
                // TODO: show queue list
            } label: {
                VStack(spacing: 4) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "square.grid.2x2")
                            .font(.title2)
                        if !tileQueue.isEmpty {
                            Text("\(tileQueue.count)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.red)
                                .clipShape(Circle())
                        }
                    }
                    Text("队列")
                        .font(.caption2)
                }
                .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.6))
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
                // Tile info
                HStack {
                    Text("\(direction.rawValue) | 父:\(parentSeq) | 序:\(seqId)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Capsule())
                    Spacer()
                }
                .padding(.leading, 16)
                .padding(.top, 8)

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    // Upload & add to queue
                    Button {
                        Task { await uploadCurrentTile() }
                    } label: {
                        HStack(spacing: 8) {
                            if isUploading {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "arrow.up.doc.fill")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            Text(isUploading ? "上传中" : "确认上传")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isUploading)

                    // Retake
                    Button {
                        cameraManager.discardPhoto()
                        isReviewing = false
                    } label: {
                        HStack(spacing: 8) {
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
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
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

        do {
            let tile = try await api.uploadTile(
                specimenId: config.specimenId,
                ratioId: config.ratioId,
                seqId: seqId,
                parentSeq: parentSeq,
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
                parentSeq: parentSeq,
                seqId: seqId,
                image: image,
                cameraImage: cameraManager.capturedImage,
                timestamp: Date()
            )
            tileQueue.append(item)

            // Auto-increment
            seqId += 1

            uploadMessage = "瓦片 #\(tile.seqId) 上传成功"
            cameraManager.discardPhoto()
            isReviewing = false
        } catch {
            uploadMessage = "上传失败: \(error.localizedDescription)"
        }

        isUploading = false
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
}
