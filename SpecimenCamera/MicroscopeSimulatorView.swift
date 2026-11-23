import SwiftUI

// MARK: - 显微镜模拟器: 设置页

struct MicroscopeSetupView: View {
    @StateObject private var api = APIService.shared

    // 级联选择状态(与拍摄页一致的模式)
    @State private var specimens: [SpecimenWithRatios] = []
    @State private var selectedSpecimenIndex: Int?
    @State private var ratios: [SpecimenRatio] = []
    @State private var selectedRatioIndex: Int?
    @State private var stacks: [SpecimenTileStacked] = []
    @State private var selectedStackIndex: Int?

    // Picker sheet 状态
    @State private var showSpecimenPicker = false
    @State private var showRatioPicker = false
    @State private var showStackPicker = false
    @State private var specimenSearchText = ""

    @State private var isLoading = false
    @State private var isLoadingRatios = false
    @State private var isLoadingStacks = false
    @State private var toastMessage: String?
    @State private var navigateToObserver = false

    private var specimenId: Int? {
        guard let i = selectedSpecimenIndex, specimens.indices.contains(i) else { return nil }
        return specimens[i].id
    }
    private var specimenName: String? {
        guard let i = selectedSpecimenIndex, specimens.indices.contains(i) else { return nil }
        return specimens[i].name
    }
    private var ratioId: Int? {
        guard let i = selectedRatioIndex, ratios.indices.contains(i) else { return nil }
        return ratios[i].id
    }
    private var ratioLabel: String? {
        guard let i = selectedRatioIndex, ratios.indices.contains(i) else { return nil }
        return "\(ratios[i].ratio)x"
    }
    private var stackId: Int? {
        guard let i = selectedStackIndex, stacks.indices.contains(i) else { return nil }
        return stacks[i].id
    }
    private var stackLabel: String? {
        guard let i = selectedStackIndex, stacks.indices.contains(i) else { return nil }
        return stacks[i].stackName
    }

    private var canObserve: Bool {
        specimenId != nil && ratioId != nil && stackId != nil
    }

    var body: some View {
        // 注意: 本页已被 push 进 ContentView 的 NavigationStack,
        // 不再内嵌 NavigationStack(嵌套会导致观察页返回时退到根页面)
        ZStack {
                LinearGradient(
                    colors: [WarmTheme.bgGradientTop, WarmTheme.bgGradientBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 18) {
                    headerIcon
                    selectionCard.padding(.horizontal, 24)
                    observeButton.padding(.horizontal, 24)
                    Spacer()
                }
                .padding(.top, 60)

                if isLoading {
                    ProgressView("加载中...")
                        .padding()
                        .background(WarmTheme.cardBg.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if let toast = toastMessage {
                    Text(toast)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.7))
                        .clipShape(Capsule())
                        .padding(.bottom, 60)
                }
            }
            .navigationTitle("显微镜模拟器")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadSpecimens() }
            .animation(.easeInOut(duration: 0.3), value: toastMessage)
            .sheet(isPresented: $showSpecimenPicker) {
                SpecimenPickerSheet(
                    specimens: specimens,
                    searchText: $specimenSearchText,
                    selectedIndex: $selectedSpecimenIndex
                )
            }
            .sheet(isPresented: $showRatioPicker) {
                RatioPickerSheet(ratios: ratios, selectedIndex: $selectedRatioIndex)
            }
            .sheet(isPresented: $showStackPicker) {
                StackPickerSheet(stacks: stacks, selectedIndex: $selectedStackIndex)
            }
            // 级联: 选标本 → 重置并加载倍数; 选倍数 → 重置并加载堆叠
            .onChange(of: selectedSpecimenIndex) { _, _ in
                selectedRatioIndex = nil
                selectedStackIndex = nil
                ratios = []
                stacks = []
                if specimenId != nil { Task { await loadRatios() } }
            }
            .onChange(of: selectedRatioIndex) { _, _ in
                selectedStackIndex = nil
                stacks = []
                if ratioId != nil { Task { await loadStacks() } }
            }
            .navigationDestination(isPresented: $navigateToObserver) {
                if let sid = specimenId, let rid = ratioId, let stkId = stackId {
                    MicroscopeObserverView(specimenId: sid, ratioId: rid, stackId: stkId)
                }
            }
    }

    private var headerIcon: some View {
        ZStack {
            Circle()
                .fill(WarmTheme.accent.opacity(0.15))
                .frame(width: 90, height: 90)
            Circle()
                .strokeBorder(WarmTheme.accent.opacity(0.4), lineWidth: 6)
                .frame(width: 90, height: 90)
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.9), WarmTheme.accent.opacity(0.3)],
                                     center: .center, startRadius: 2, endRadius: 30))
                .frame(width: 52, height: 52)
        }
    }

    // MARK: 级联选择卡片

    private var selectionCard: some View {
        VStack(spacing: 16) {
            cascadeRow(icon: "leaf.fill",
                       label: "标本",
                       value: specimenName,
                       placeholder: "请选择",
                       enabled: !specimens.isEmpty,
                       loading: false) {
                showSpecimenPicker = true
            }

            Divider()

            cascadeRow(icon: "arrow.up.left.and.arrow.down.right",
                       label: "放大倍数",
                       value: ratioLabel,
                       placeholder: specimenId == nil ? "请先选择标本" : (ratios.isEmpty ? "暂无倍数" : "请选择"),
                       enabled: specimenId != nil && !ratios.isEmpty,
                       loading: isLoadingRatios) {
                showRatioPicker = true
            }

            Divider()

            cascadeRow(icon: "square.stack.3d.up.fill",
                       label: "堆叠",
                       value: stackLabel,
                       placeholder: ratioId == nil ? "请先选择倍数" : (stacks.isEmpty ? "暂无堆叠" : "请选择"),
                       enabled: ratioId != nil && !stacks.isEmpty,
                       loading: isLoadingStacks) {
                showStackPicker = true
            }
        }
        .padding(18)
        .background(WarmTheme.cardBg.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(WarmTheme.accent.opacity(0.25), lineWidth: 1))
    }

    private func cascadeRow(icon: String, label: String, value: String?, placeholder: String,
                            enabled: Bool, loading: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(WarmTheme.accent)
                .frame(width: 22)

            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(WarmTheme.textPrimary)
                .frame(width: 62, alignment: .leading)

            Spacer()

            if loading {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(WarmTheme.primary)
            } else {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(value ?? placeholder)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(value != nil ? WarmTheme.textPrimary : WarmTheme.textSecondary.opacity(0.6))
                            .lineLimit(1)
                        if enabled {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(WarmTheme.textSecondary)
                        }
                    }
                }
                .disabled(!enabled)
            }
        }
    }

    private var observeButton: some View {
        Button {
            guard canObserve else {
                showToast("请先选择标本、放大倍数和堆叠")
                return
            }
            navigateToObserver = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "eye.fill")
                Text("开始观察")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(LinearGradient(
                colors: canObserve
                    ? [WarmTheme.primary, WarmTheme.deep]
                    : [Color.gray.opacity(0.5), Color.gray.opacity(0.4)],
                startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(isLoading)
    }

    // MARK: - Data

    private func loadSpecimens() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await api.fetchSpecimensWithMagnifications()
            specimens = response.specimens ?? []
            if specimens.isEmpty { showToast("暂无标本数据") }
        } catch {
            showToast("加载标本失败: \(error.localizedDescription)")
        }
    }

    private func loadRatios() async {
        guard let sid = specimenId else { return }
        isLoadingRatios = true
        defer { isLoadingRatios = false }
        do {
            ratios = try await api.fetchRatios(specimenId: sid)
        } catch {
            showToast("加载倍数失败: \(error.localizedDescription)")
        }
    }

    private func loadStacks() async {
        guard let sid = specimenId, let rid = ratioId else { return }
        isLoadingStacks = true
        defer { isLoadingStacks = false }
        do {
            stacks = try await api.fetchStacks(specimenId: sid, ratioId: rid)
        } catch {
            showToast("加载堆叠失败: \(error.localizedDescription)")
        }
    }

    private func showToast(_ text: String) {
        toastMessage = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            toastMessage = nil
        }
    }
}

// MARK: - 显微镜模拟器: 观察页(按需加载视口瓦片)

struct MicroscopeObserverView: View {
    let specimenId: Int
    let ratioId: Int
    let stackId: Int

    @StateObject private var api = APIService.shared

    private enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    /// 瓦片元数据: tx/ty 网格索引(缓存 key), px/py 源图绝对像素(拼合定位)
    /// 三焦面 URL: mid 恒有; top/bottom 可能为空(该块无此焦面)
    private struct TileMeta: Sendable {
        let tx: Int
        let ty: Int
        let px: CGFloat
        let py: CGFloat
        let url: String
        let urlTop: String?
        let urlBottom: String?

        func url(for layer: String) -> String? {
            switch layer {
            case "top": return urlTop
            case "bottom": return urlBottom
            default: return url
            }
        }
    }

    /// 参与拼合的单块瓦片
    private struct RegionTile: Sendable {
        let px: CGFloat
        let py: CGFloat
        let image: UIImage
    }

    @State private var phase: Phase = .loading
    @State private var progressText = ""
    @State private var metaByCoord: [String: TileMeta] = [:]

    @State private var tileW: CGFloat = 512
    @State private var tileH: CGFloat = 512
    @State private var gridWidth: CGFloat = 512
    @State private var gridHeight: CGFloat = 512

    @State private var windowSize: CGSize = .zero
    @State private var center: CGPoint = .zero
    @State private var viewportImage: UIImage?
    @State private var viewportOrigin: CGPoint = .zero
    @State private var viewportTiles: (x0: Int, y0: Int, x1: Int, y1: Int) = (0, 0, -1, -1)
    @State private var viewportSignature = ""
    @State private var viewportTask: Task<Void, Never>?
    @State private var reloadTask: Task<Void, Never>?   // 移动/调焦防抖
    @State private var loadingViewport = false
    @State private var tileCache: [String: UIImage] = [:]
    @State private var focus: Float = 0

    // 三焦面: 底层恒为 mid 拼合图; top/bottom 按需拼合为顶层, 透明底,
    // 五焦面帐篷插值(focus 两端为 blank 纯色层, 见 eyepieceView)
    @State private var viewportImageAlt: UIImage?
    @State private var viewportOriginAlt: CGPoint = .zero
    @State private var altLayerName = ""                // 已拼合的顶层名("top"/"bottom"/"")
    @State private var viewportAltSignature = ""
    @State private var viewportAltTask: Task<Void, Never>?

    // blank 层: (0,0) 空白占位瓦片的平均色, 视场完全离焦时的空白背景
    @State private var blankColor: Color?

    /// 源图像素 → 显示 pt 比例: 视野约覆盖 1.3 块瓦片
    private let viewScale: CGFloat = 0.5
    private let panStepPx: CGFloat = 90
    private let tileCacheLimit = 150

    /// 调焦步进: focus 全程 [-1,1], 0.05 × 40 步(可调)
    private let focusStep: Float = 0.05

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.08, blue: 0.06),
                         Color(red: 0.02, green: 0.02, blue: 0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                infoBar
                Spacer()

                switch phase {
                case .loading:
                    VStack(spacing: 14) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(WarmTheme.accent)
                        Text(progressText.isEmpty ? "正在加载瓦片产品..." : progressText)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.75))
                    }
                case .failed(let message):
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.yellow.opacity(0.8))
                        Text(message)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                        Button("重试") {
                            phase = .loading
                            Task { await load() }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(WarmTheme.accent)
                    }
                case .ready:
                    if let vp = viewportImage {
                        eyepieceView(vp)
                    } else {
                        eyepiecePlaceholder
                    }
                }

                Spacer()
                controls
            }
            .padding(.vertical, 12)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black.opacity(0.55), for: .navigationBar)
        .task { await load() }
        // 窗口尺寸就绪/变化后按需拼视口(初始由 placeholder 的 GeometryReader 触发)
        .onChange(of: windowSize) { _, _ in
            if phase == .ready { ensureViewport() }
        }
        .onDisappear {
            viewportTask?.cancel()
            reloadTask?.cancel()
        }
    }

    /// 视口图未就绪时的占位: 同样包含 GeometryReader 以便尽早获得窗口尺寸
    private var eyepiecePlaceholder: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Color.black
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.1)
                        .tint(WarmTheme.accent)
                    Text(progressText.isEmpty ? "加载视口瓦片..." : progressText)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            .frame(width: s, height: s)
            .clipShape(Circle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                if windowSize != geo.size { windowSize = geo.size }
            }
            .onChange(of: geo.size) { _, newSize in
                windowSize = newSize
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var infoBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 12))
                Text("模拟观察 · stack \(stackId)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white.opacity(0.9))
            Spacer()
            Text("方向键移动视野寻找标本")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(.horizontal, 16)
    }

    /// shader 调用结构必须保留(实验证实: 摘除 layerEffect 结构会导致圆窗黑屏,
    /// 机制不明)。开关 false = shader 不执行, 无暗角/色差/噪点计算, 仅为占位。
    private let useMicroscopeShader = false

    /// 三焦面单层图: 按视口原点居中偏移 + 混合权重
    private func layerImage(_ img: UIImage, _ origin: CGPoint, opacity: Double) -> some View {
        Image(uiImage: img)
            .resizable()
            .interpolation(.medium)
            .frame(width: img.size.width * viewScale,
                   height: img.size.height * viewScale)
            // Image 在 ZStack 中已居中(图中心 = 源图 origin+vpSize/2 处),
            // 需要移动量 = 把"源图 center 点"对到视图中心:
            // offset = (origin + vpSize/2 - center) * viewScale
            .offset(x: (origin.x + img.size.width / 2 - center.x) * viewScale,
                    y: (origin.y + img.size.height / 2 - center.y) * viewScale)
            .opacity(opacity)
    }

    @ViewBuilder
    private func eyepieceView(_ vp: UIImage) -> some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)

            // 五层帐篷插值: blank → bottom → mid → top → blank (从下到上)
            // 节点位置 n: blank=0/4, bottom=1, mid=2, top=3; n=(focus+1)*2 ∈ [0,4]
            // 帐篷函数 max(0, 1-|n-k|): 任意时刻只有相邻两层权重>0, 之和恒为 1
            let n = min(max((focus + 1) * 2, 0), 4)
            let wBlank = max(0, 1 - n) + max(0, 1 - abs(n - 4))
            let wBottom = max(0, 1 - abs(n - 1))
            let wMid = max(0, 1 - abs(n - 2))
            let wTop = max(0, 1 - abs(n - 3))

            let content = ZStack {
                Color.black
                if wBlank > 0, let bc = blankColor {
                    bc.opacity(Double(wBlank))
                }
                if wBottom > 0, altLayerName == "bottom", let alt = viewportImageAlt {
                    layerImage(alt, viewportOriginAlt, opacity: Double(wBottom))
                }
                layerImage(vp, viewportOrigin, opacity: Double(wMid))
                if wTop > 0, altLayerName == "top", let alt = viewportImageAlt {
                    layerImage(alt, viewportOriginAlt, opacity: Double(wTop))
                }
            }
            .frame(width: s, height: s)
            .clipped()

            // 结构占位: 此 Group+layerEffect 不可删除(删除即黑屏), 开关 false 时不执行
            Group {
                if useMicroscopeShader {
                    content.layerEffect(
                        ShaderLibrary.microscopeView(
                            .float2(CGSize(width: s, height: s))
                        ),
                        maxSampleOffset: CGSize(width: 8, height: 8)
                    )
                } else {
                    content
                }
            }
            .clipShape(Circle())
            .animation(.easeOut(duration: 0.1), value: center)
            .animation(.easeOut(duration: 0.08), value: focus)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 圆窗边缘内氲: 外缘 6% 半径由透明渐变到黑, 柔化硬边
            .overlay(
                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: .clear, location: 0.94),
                                .init(color: .black, location: 1.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: s / 2
                        )
                    )
                    .frame(width: s, height: s)
                    .allowsHitTesting(false)
            )
            .overlay(alignment: .bottom) {
                viewportBadge.padding(.bottom, 6)
            }
            .onAppear {
                if windowSize != geo.size { windowSize = geo.size }
            }
            .onChange(of: geo.size) { _, newSize in
                windowSize = newSize
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var viewportBadge: some View {
        if loadingViewport {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(.white)
                Text(progressText.isEmpty ? "加载邻近瓦片..." : progressText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.55))
            .clipShape(Capsule())
        } else {
            focusIndicator
        }
    }

    private var focusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(focus == 0 ? Color.green : Color.yellow)
                .frame(width: 7, height: 7)
            Text(focus == 0 ? "合焦" : (focus > 0
                ? "前离焦 \(String(format: "%.1f", focus))"
                : "后离焦 \(String(format: "%.1f", -focus))"))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.55))
        .clipShape(Capsule())
    }

    private var controls: some View {
        HStack(spacing: 22) {
            directionPad
            Divider()
                .frame(height: 130)
                .background(Color.white.opacity(0.2))
            focusPad
        }
        .padding(.vertical, 10)
    }

    private func padButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 46, height: 38)
                .background(Color.white.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }

    private var directionPad: some View {
        VStack(spacing: 4) {
            padButton(icon: "arrow.up") { pan(dx: 0, dy: -1) }
            HStack(spacing: 4) {
                padButton(icon: "arrow.left") { pan(dx: -1, dy: 0) }
                padButton(icon: "arrow.down") { pan(dx: 0, dy: 1) }
                padButton(icon: "arrow.right") { pan(dx: 1, dy: 0) }
            }
        }
    }

    private var focusPad: some View {
        VStack(spacing: 4) {
            Text("焦距")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            HStack(spacing: 4) {
                padButton(icon: "plus") { setFocus(min(1, focus + focusStep)) }
                padButton(icon: "minus") { setFocus(max(-1, focus - focusStep)) }
            }
            Button("合焦") { setFocus(0) }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(WarmTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    /// 平移视野: dx/dy 为方向(-1/0/1), 视野中心在源图内移动并 clamp 到网格边界
    private func pan(dx: CGFloat, dy: CGFloat) {
        guard phase == .ready else { return }
        let half = max(windowSize.width, 1) / viewScale / 2
        withAnimation(.easeOut(duration: 0.1)) {
            center.x = min(max(center.x + dx * panStepPx, min(half, gridWidth / 2)),
                           max(gridWidth - half, gridWidth / 2))
            center.y = min(max(center.y + dy * panStepPx, min(half, gridHeight / 2)),
                           max(gridHeight - half, gridHeight / 2))
        }
        // 防抖: 连续按键只在停顿 250ms 后重拼视口, 避免下载风暴和取消浪费
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled { ensureViewport() }
        }
    }

    // MARK: - 按需视口加载

    /// 调焦: 立即更新显示(顶层 opacity), 防抖后按需拼合顶层焦面
    private func setFocus(_ v: Float) {
        focus = v
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            if !Task.isCancelled { ensureViewport() }
        }
    }

    /// 视野中心变化后计算所需瓦片范围。
    /// 调试模式(只拼视野中心所在的单块瓦片, 隔离验证"一块能否看到标本"):
    /// autoLocate = true → 拼合范围恒为 center 所在的 1×1 块;
    /// false → 拼视野覆盖的块(2×2 左右)
    private let onlyCenterTile = false

    private func ensureViewport() {
        // 窗口尺寸未知(placeholder 尚未渲染)时不拼, 等 onChange(windowSize) 再触发
        guard windowSize.width > 10 else { return }

        let x0: Int, y0: Int, x1: Int, y1: Int
        if onlyCenterTile {
            x0 = max(Int(center.x / tileW), 0)
            y0 = max(Int(center.y / tileH), 0)
            x1 = x0
            y1 = y0
        } else {
            let span = max(windowSize.width, 1) / viewScale
            let half = span / 2
            x0 = max(Int(floor((center.x - half) / tileW)), 0)
            y0 = max(Int(floor((center.y - half) / tileH)), 0)
            x1 = max(Int(floor((center.x + half - 0.001) / tileW)), 0)
            y1 = max(Int(floor((center.y + half - 0.001) / tileH)), 0)
        }

        let signature = "\(x0),\(y0),\(x1),\(y1)"
        if !(viewportTiles.x0 <= x0 && viewportTiles.x1 >= x1 &&
             viewportTiles.y0 <= y0 && viewportTiles.y1 >= y1),
           signature != viewportSignature {
            viewportSignature = signature
            // 不取消旧任务: 旧任务靠签名守卫自行退出, 已完成的下载仍会入缓存
            viewportTask = Task { await buildViewport(layer: "mid", x0: x0, y0: y0, x1: x1, y1: y1, signature: signature) }
        }

        // ---- 五层插值的 alt 层(blank→bottom→mid→top→blank, 从下到上) ----
        // + (向上调焦) → top, − (向下调焦) → bottom
        // 接近合焦(|focus| ≤ 0.05)时 alt 权重很小(≤0.1), 不需要拼合
        let wantAlt = focus > 0.05 ? "top" : (focus < -0.05 ? "bottom" : "")
        guard wantAlt.isEmpty == false else { return }
        let altSignature = "\(wantAlt)|\(x0),\(y0),\(x1),\(y1)"
        guard altSignature != viewportAltSignature else { return }
        viewportAltSignature = altSignature
        viewportAltTask = Task { await buildViewport(layer: wantAlt, x0: x0, y0: y0, x1: x1, y1: y1, signature: altSignature) }
    }

    private func buildViewport(layer: String, x0: Int, y0: Int, x1: Int, y1: Int, signature: String) async {
        // 签名已变(期间又有新的视口请求) → 本次作废, 不下载
        guard signature == (layer == "mid" ? viewportSignature : viewportAltSignature) else { return }
        loadingViewport = true
        defer { loadingViewport = false }

        // 1. 下载缺失瓦片(已缓存的复用)。非 throwing group: 即使任务被取消,
        //    已完成的下载结果也全部入缓存, 不浪费
        var needed: [TileMeta] = []
        for ty in y0...y1 {
            for tx in x0...x1 {
                let key = "\(layer)|\(tx),\(ty)"
                guard tileCache[key] == nil,
                      let m = metaByCoord["\(tx),\(ty)"],
                      m.url(for: layer)?.isEmpty == false else { continue }
                needed.append(m)
            }
        }
        if !needed.isEmpty {
            var fetched = 0
            await withTaskGroup(of: (Int, UIImage?).self) { group in
                for (i, m) in needed.enumerated() {
                    group.addTask {
                        do {
                            let data = try await api.fetchTileImageData(urlString: m.url(for: layer)!)
                            return (i, UIImage(data: data))
                        } catch {
                            return (i, nil)
                        }
                    }
                }
                for await (i, img) in group {
                    fetched += 1
                    progressText = "加载瓦片 \(fetched)/\(needed.count)"
                    if let img {
                        let m = needed[i]
                        tileCache["\(layer)|\(m.tx),\(m.ty)"] = img
                    }
                }
            }
        }

        // 2. 期间签名又变了 → 只攒缓存, 不更新 UI(不清理缓存)
        guard signature == (layer == "mid" ? viewportSignature : viewportAltSignature) else { return }

        // 3. 收集本视口区域内的瓦片(清理缓存前取出)
        //    px/py 必须是"相对区域原点"的画布坐标:
        //    m.px/py 是网格绝对坐标(如 (2,3) 块 → 1024,1536), 直接画会超出画布 → 全黑
        let originPx = CGFloat(x0) * tileW
        let originPy = CGFloat(y0) * tileH
        var region: [RegionTile] = []
        for ty in y0...y1 {
            for tx in x0...x1 {
                if let img = tileCache["\(layer)|\(tx),\(ty)"],
                   let m = metaByCoord["\(tx),\(ty)"] {
                    region.append(RegionTile(px: m.px - originPx,
                                             py: m.py - originPy,
                                             image: img))
                }
            }
        }
        if tileCache.count > tileCacheLimit { tileCache.removeAll() }
        // 顶层焦面允许部分块缺失(该块无此焦面) → 拼合图对应区域透明, 露出底层 mid。
        // 但整层一块都没有时不更新 UI: 显示一张全透明顶层会把 mid 权重压低 → 露黑底
        if region.isEmpty {
            if layer == "mid" { return }
            return
        }

        // 4. 后台拼合局部图
        let width = CGFloat(x1 - x0 + 1) * tileW
        let height = CGFloat(y1 - y0 + 1) * tileH
        let image = await Task.detached(priority: .userInitiated) {
            Self.renderRegion(tiles: region, width: width, height: height,
                              opaque: layer == "mid")
        }.value
        guard signature == (layer == "mid" ? viewportSignature : viewportAltSignature) else { return }

        if layer == "mid" {
            viewportImage = image
            viewportOrigin = CGPoint(x: CGFloat(x0) * tileW, y: CGFloat(y0) * tileH)
            viewportTiles = (x0, y0, x1, y1)
        } else {
            viewportImageAlt = image
            viewportOriginAlt = CGPoint(x: CGFloat(x0) * tileW, y: CGFloat(y0) * tileH)
            altLayerName = layer
        }
    }

    /// 取瓦片图像的平均颜色(缩到 1×1 采样), 用于 blank 层纯色
    nonisolated private static func averageColor(from data: Data) async -> Color? {
        guard let img = UIImage(data: data), let cg = img.cgImage else { return nil }
        return await Task.detached(priority: .utility) {
            var pixel = [UInt8](repeating: 0, count: 4)
            let ctx = CGContext(data: &pixel, width: 1, height: 1,
                                bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return Color(red: Double(pixel[0]) / 255.0,
                         green: Double(pixel[1]) / 255.0,
                         blue: Double(pixel[2]) / 255.0)
        }.value
    }

    /// 拼合局部区域(scale=1: UIImage.size 即源图像素)
    /// 注意: UIImage.draw 依赖 UIKit 当前上下文, 必须用 UIGraphicsImageRenderer 包裹
    nonisolated private static func renderRegion(
        tiles: [RegionTile],
        width: CGFloat, height: CGFloat,
        opaque: Bool = true
    ) -> UIImage {
        let size = CGSize(width: max(width, 1), height: max(height, 1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            if opaque {
                UIColor.black.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            for t in tiles {
                t.image.draw(in: CGRect(origin: CGPoint(x: t.px, y: t.py),
                                        size: t.image.size))
            }
        }
    }

    // MARK: - 数据加载

    private func load() async {
        progressText = "正在获取瓦片产品..."
        do {
            let products = try await api.fetchTileProducts(
                specimenId: specimenId, ratioId: ratioId, stackId: stackId
            )

            // 只保留有 loc_mid 图的记录; 同坐标多条时保留最后一条
            var byCoord: [String: SpecimenTileProduct] = [:]
            for p in products where (p.locMid ?? "").isEmpty == false {
                byCoord["\(p.locX ?? -1),\(p.locY ?? -1)"] = p
            }
            guard !byCoord.isEmpty else {
                phase = .failed("该堆叠还没有瓦片产品(loc_mid 为空)。\n请先在后台对堆叠执行「拆分堆叠到地图」。")
                return
            }

            // 坐标单位启发式: 索引坐标的最大值 = 网格块数(几十以内),
            // 像素坐标的有效值必然 ≥512。上一版用"跨度≤8"误判了 14×11 网格。
            let rawX = byCoord.values.map { $0.locX ?? 0 }
            let rawY = byCoord.values.map { $0.locY ?? 0 }
            let isIndex = (rawX.max() ?? 0) < 256 && (rawY.max() ?? 0) < 256

            var metas: [TileMeta] = []
            var maxRight: CGFloat = 0
            var maxBottom: CGFloat = 0
            for p in byCoord.values {
                let rx = CGFloat(p.locX ?? 0)
                let ry = CGFloat(p.locY ?? 0)
                let tx = isIndex ? Int(rx) : Int(floor(rx / tileW))
                let ty = isIndex ? Int(ry) : Int(floor(ry / tileH))
                let px = isIndex ? rx * tileW : rx
                let py = isIndex ? ry * tileH : ry
                metas.append(TileMeta(tx: tx, ty: ty, px: px, py: py,
                                      url: p.locMid!, urlTop: p.locTop, urlBottom: p.locBottom))
                maxRight = max(maxRight, px + tileW)
                maxBottom = max(maxBottom, py + tileH)
            }

            metaByCoord = Dictionary(metas.map { ("\($0.tx),\($0.ty)", $0) },
                                     uniquingKeysWith: { a, _ in a })
            gridWidth = maxRight
            gridHeight = maxBottom

            // 自动定位: HEAD 扫描各瓦片字节数, 跳过空白占位, 初始视野对准内容最大的瓦片
            progressText = "定位标本区域..."
            await locateSpecimen()

            phase = .ready
            ensureViewport()

            // blank 层: 异步取 (0,0) 空白占位瓦片的平均色(不阻塞进入观察)
            if let m0 = metaByCoord["0,0"], let u = m0.url(for: "mid") {
                Task {
                    if let data = try? await api.fetchTileImageData(urlString: u) {
                        blankColor = await Self.averageColor(from: data)
                    }
                }
            }
        } catch {
            phase = .failed("加载失败: \(error.localizedDescription)")
        }
    }

    /// 用 HEAD 请求的 content-length 找出有内容的瓦片, 把初始视野中心对准它。
    /// 空白占位 PNG 约 1.7KB, 有内容的瓦片明显更大。
    private func locateSpecimen() async {
        let all = Array(metaByCoord.values)
        guard !all.isEmpty else { return }

        var best: TileMeta?
        var bestSize = 0
        await withTaskGroup(of: (TileMeta, Int).self) { group in
            for m in all {
                group.addTask {
                    let len = await api.fetchTileContentLength(urlString: m.url)
                    return (m, len)
                }
            }
            for await (m, len) in group where len > bestSize {
                bestSize = len
                best = m
            }
        }

        if let m = best, bestSize > 8000 {
            center = CGPoint(x: m.px + tileW / 2, y: m.py + tileH / 2)
        } else {
            center = CGPoint(x: gridWidth / 2, y: gridHeight / 2)
        }
    }
}

// MARK: - 放大倍数选择 Sheet

struct RatioPickerSheet: View {
    let ratios: [SpecimenRatio]
    @Binding var selectedIndex: Int?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(ratios.enumerated()), id: \.element.id) { idx, ratio in
                    Button {
                        selectedIndex = idx
                        dismiss()
                    } label: {
                        HStack {
                            Text("\(ratio.ratio)x")
                                .font(.system(size: 15))
                                .foregroundColor(WarmTheme.textPrimary)
                            Spacer()
                            if selectedIndex == idx {
                                Image(systemName: "checkmark")
                                    .foregroundColor(WarmTheme.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择放大倍数")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 堆叠选择 Sheet

struct StackPickerSheet: View {
    let stacks: [SpecimenTileStacked]
    @Binding var selectedIndex: Int?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(stacks.enumerated()), id: \.element.id) { idx, stack in
                    Button {
                        selectedIndex = idx
                        dismiss()
                    } label: {
                        HStack {
                            Text(stack.stackName ?? "堆叠 \(stack.id)")
                                .font(.system(size: 15))
                                .foregroundColor(WarmTheme.textPrimary)
                            Spacer()
                            if selectedIndex == idx {
                                Image(systemName: "checkmark")
                                    .foregroundColor(WarmTheme.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择堆叠")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
