import SwiftUI
import Photos

struct CaptureSetupView: View {
    @StateObject private var api = APIService.shared
    @State private var specimens: [SpecimenWithRatios] = []
    @State private var collectors: [SpecimenCollector] = []
    @State private var stacks: [SpecimenTileStacked] = []
    @State private var ratios: [SpecimenRatio] = []

    @State private var selectedSpecimenIndex: Int?
    @State private var selectedRatioIndex: Int?
    @State private var selectedStackIndex: Int?
    @State private var selectedCollectorIndex: Int?

    @State private var collectionDate = Date()
    @State private var showDatePicker = false

    // New stack creation
    @State private var showNewStackSheet = false
    @State private var newStackName = ""

    // Navigation
    @State private var navigateToCapture = false

    // Light parameters
    @State private var lightIntensity: Double = 1
    @State private var lightAperture: Double = 0.5
    @State private var lightField: Int = 1

    @State private var isLoadingSpecimens = false
    @State private var isLoadingRatios = false
    @State private var isLoadingStacks = false

    // Picker sheet states
    @State private var showSpecimenPicker = false
    @State private var showRatioPicker = false
    @State private var showStackPicker = false
    @State private var showCollectorPicker = false

    // Search text for specimen picker
    @State private var specimenSearchText = ""

    // Focus state for dismissing keyboard
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 1. Specimen + Ratio in one card
                    sectionCard(icon: "scope", title: "标本信息") {
                        specimenRatioRow
                    }

                    // 2. Collection info
                    sectionCard(icon: "calendar.badge.clock", title: "采集信息") {
                        collectionInfo
                    }

                    // 3. Material pack (stack)
                    sectionCard(icon: "square.stack.3d.up.fill", title: "素材包") {
                        stackPicker
                    }

                    // 4. Light parameters (when stack selected) — cascade in
                    if selectedStackIndex != nil {
                        sectionCard(icon: "light.max", title: "光学参数") {
                            lightParameters
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // 5. Start capture button — cascade in
                    if canStartCapture {
                        Button {
                            isFocused = false
                            navigateToCapture = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("开始拍摄")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                LinearGradient(colors: [WarmTheme.accent, WarmTheme.deep], startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: WarmTheme.primary.opacity(0.35), radius: 8, y: 4)
                        }
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: selectedStackIndex)
                .animation(.easeInOut(duration: 0.35), value: canStartCapture)
                .animation(nil, value: lightIntensity)
                .animation(nil, value: lightAperture)
                .animation(nil, value: lightField)
                .padding(18)
            }
            .background(
                LinearGradient(colors: [WarmTheme.bgGradientTop, WarmTheme.bgGradientBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            )
            .navigationTitle("标本录制")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { isFocused = false }
                }
            }
            .task {
                await loadData()
            }
            .refreshable {
                await loadData()
            }
            .navigationDestination(isPresented: $navigateToCapture) {
                if let config = captureConfig {
                    TileCaptureView(config: config)
                }
            }
            .sheet(isPresented: $showNewStackSheet) {
                NewStackView(
                    specimenId: currentSpecimenId ?? 0,
                    ratioId: currentRatioId ?? 0
                ) { newStack in
                    stacks.append(newStack)
                    selectedStackIndex = stacks.count - 1
                }
            }
            .sheet(isPresented: $showDatePicker) {
                NavigationStack {
                    DatePicker("", selection: $collectionDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .tint(WarmTheme.primary)
                        .padding()
                        .navigationTitle("选择采集日期")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { showDatePicker = false }
                            }
                        }
                }
                .presentationDetents([.medium])
            }
            .overlay {
                if isLoadingSpecimens {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(WarmTheme.primary)
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
            .onTapGesture {
                isFocused = false
            }
        }
    }

    // MARK: - Computed

    private var currentSpecimenId: Int? {
        guard let idx = selectedSpecimenIndex, idx < specimens.count else { return nil }
        return specimens[idx].id
    }

    private var currentRatioId: Int? {
        guard let idx = selectedRatioIndex, idx < ratios.count else { return nil }
        return ratios[idx].id
    }

    private var currentStackId: Int? {
        guard let idx = selectedStackIndex, idx < stacks.count else { return nil }
        return stacks[idx].id
    }

    private var canStartCapture: Bool {
        selectedSpecimenIndex != nil && selectedRatioIndex != nil && selectedStackIndex != nil && selectedCollectorIndex != nil
    }

    private var captureConfig: CaptureConfig? {
        guard let sIdx = selectedSpecimenIndex, sIdx < specimens.count,
              let rIdx = selectedRatioIndex, rIdx < ratios.count,
              let stIdx = selectedStackIndex, stIdx < stacks.count else { return nil }
        let specimen = specimens[sIdx]
        let ratio = ratios[rIdx]
        let stack = stacks[stIdx]
        return CaptureConfig(
            specimenId: specimen.id,
            specimenName: specimen.name,
            ratioId: ratio.id,
            ratioName: ratio.ratio,
            stackId: stack.id,
            stackName: stack.stackName ?? "Stack-\(stack.id)",
            light: lightIntensity,
            lightCircle: lightAperture,
            lightField: lightField,
            collectionDate: collectionDate,
            collector: selectedCollectorIndex != nil && selectedCollectorIndex! < collectors.count
                ? collectors[selectedCollectorIndex!].name : nil
        )
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoadingSpecimens = true
        async let specimensTask = try? api.fetchSpecimensWithMagnifications()
        async let collectorsTask = try? api.fetchCollectors()

        if let resp = await specimensTask {
            specimens = resp.specimens ?? []
        }
        if let cols = await collectorsTask {
            collectors = cols
        }
        isLoadingSpecimens = false
    }

    private func loadStacks() async {
        guard let specimenId = currentSpecimenId, let ratioId = currentRatioId else { return }
        isLoadingStacks = true
        selectedStackIndex = nil
        do {
            stacks = try await api.fetchStacks(specimenId: specimenId, ratioId: ratioId)
        } catch {
            stacks = []
        }
        isLoadingStacks = false
    }

    private func loadRatios() async {
        guard let specimenId = currentSpecimenId else { return }
        isLoadingRatios = true
        selectedRatioIndex = nil
        selectedStackIndex = nil
        stacks = []
        ratios = (try? await api.fetchRatios(specimenId: specimenId)) ?? []
        isLoadingRatios = false
    }

    // MARK: - Section Card

    private func sectionCard<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(WarmTheme.primary)
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

    // MARK: - Specimen + Ratio Row

    private var specimenRatioRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                // Specimen picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("标本")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(WarmTheme.textSecondary)
                    Button {
                        if !specimens.isEmpty { showSpecimenPicker = true }
                    } label: {
                        HStack {
                            Text(specimens.isEmpty ? "暂无标本" : (selectedSpecimenIndex != nil ? specimens[selectedSpecimenIndex!].name : "请选择"))
                                .font(.system(size: 15))
                                .foregroundColor(specimens.isEmpty ? WarmTheme.textSecondary.opacity(0.5) : (selectedSpecimenIndex != nil ? WarmTheme.textPrimary : WarmTheme.textSecondary.opacity(0.5)))
                            Spacer()
                            if !specimens.isEmpty {
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
                    .frame(maxWidth: .infinity)
                    .sheet(isPresented: $showSpecimenPicker) {
                        SpecimenPickerSheet(
                            specimens: specimens,
                            searchText: $specimenSearchText,
                            selectedIndex: $selectedSpecimenIndex
                        )
                    }
                }
                .frame(maxWidth: .infinity)

                // Divider
                Rectangle()
                    .fill(WarmTheme.accent.opacity(0.2))
                    .frame(width: 1, height: 36)
                    .padding(.horizontal, 8)

                // Ratio picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("放大倍数")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(WarmTheme.textSecondary)
                    if selectedSpecimenIndex != nil {
                        if isLoadingRatios {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(WarmTheme.primary)
                        } else {
                            Button {
                                if !ratios.isEmpty { showRatioPicker = true }
                            } label: {
                                HStack {
                                    Text(ratios.isEmpty ? "暂无放大倍数" : (selectedRatioIndex != nil ? "\(ratios[selectedRatioIndex!].ratio)x" : "请选择"))
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
                            .frame(maxWidth: .infinity)
                            .confirmationDialog("选择放大倍数", isPresented: $showRatioPicker, titleVisibility: .visible) {
                                ForEach(Array(ratios.enumerated()), id: \.offset) { idx, ratio in
                                    Button("\(ratio.ratio)x") { selectedRatioIndex = idx }
                                }
                            }
                        }
                    } else {
                        Text("请先选择标本")
                            .font(.system(size: 13))
                            .foregroundColor(WarmTheme.textSecondary.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: selectedSpecimenIndex) { _, newValue in
            selectedRatioIndex = nil
            selectedStackIndex = nil
            stacks = []
            if newValue != nil {
                Task { await loadRatios() }
            }
        }
    }

    // MARK: - Stack Picker

    private var stackPicker: some View {
        VStack(spacing: 8) {
            HStack {
                if selectedRatioIndex == nil {
                    Text("请先选择标本和放大倍数")
                        .font(.system(size: 13))
                        .foregroundColor(WarmTheme.textSecondary.opacity(0.5))
                } else if isLoadingStacks {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(WarmTheme.primary)
                } else {
                    Button {
                        if !stacks.isEmpty {
                            showStackPicker = true
                        }
                    } label: {
                        HStack {
                            Text(stacks.isEmpty ? "暂无素材包，请先创建" : (selectedStackIndex != nil ? stacks[selectedStackIndex!].stackName ?? "Stack-\(stacks[selectedStackIndex!].id)" : "请选择素材包"))
                                .font(.system(size: 15))
                                .foregroundColor(stacks.isEmpty ? WarmTheme.textSecondary.opacity(0.5) : (selectedStackIndex != nil ? WarmTheme.textPrimary : WarmTheme.textSecondary.opacity(0.5)))
                            Spacer()
                            if !stacks.isEmpty {
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
                    .confirmationDialog("选择素材包", isPresented: $showStackPicker, titleVisibility: .visible) {
                        ForEach(Array(stacks.enumerated()), id: \.offset) { idx, stack in
                            Button(stack.stackName ?? "Stack-\(stack.id)") { selectedStackIndex = idx }
                        }
                    }
                }

                Spacer()

                if selectedRatioIndex != nil {
                    Button {
                        showNewStackSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(WarmTheme.primary)
                    }
                }
            }

            if let idx = selectedStackIndex, idx < stacks.count {
                let stack = stacks[idx]
                VStack(alignment: .leading, spacing: 6) {
                    infoRow(icon: "sun.max.fill", label: "光强", value: stack.light != nil ? "\(Int(stack.light!))" : "-")
                    infoRow(icon: "circle.circle", label: "光圈", value: stack.lightCircle != nil ? String(format: "%.1f", stack.lightCircle!) : "-")
                    infoRow(icon: "lightbulb.fill", label: "光场", value: stack.lightField != nil ? (stack.lightField! == 1 ? "明场" : "暗场") : "-")
                }
                .font(.caption)
                .foregroundColor(WarmTheme.textSecondary)
                .padding(.top, 6)
                .padding(.horizontal, 4)
            }
        }
        .onChange(of: selectedStackIndex) { _, newValue in
            if let idx = newValue, idx < stacks.count {
                let stack = stacks[idx]
                lightIntensity = stack.light ?? 1
                lightAperture = stack.lightCircle ?? 0.5
                lightField = stack.lightField ?? 1
            }
        }
        .onChange(of: selectedRatioIndex) { _, newValue in
            selectedStackIndex = nil
            stacks = []
            if newValue != nil {
                Task { await loadStacks() }
            }
        }
    }

    // MARK: - Light Parameters

    private var lightParameters: some View {
        VStack(spacing: 20) {
            parameterSlider(icon: "sun.max.fill", label: "光强", value: $lightIntensity, range: 1...10, step: 1, unit: "")
            parameterSlider(icon: "circle.circle", label: "光圈", value: $lightAperture, range: 0...1, step: 0.1, unit: "")
            parameterSlider(icon: "lightbulb.fill", label: "光场", value: Binding(
                get: { Double(lightField) },
                set: { lightField = Int($0) }
            ), range: 0...1, step: 1, unit: "", displayMap: { v -> String in
                v == 1 ? "明场" : "暗场"
            })
        }
    }

    private func parameterSlider(icon: String, label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String, displayMap: ((Double) -> String)? = nil) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(WarmTheme.primary)
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(WarmTheme.textPrimary)
                Spacer()
                Text(displayMap != nil ? displayMap!(value.wrappedValue) : "\(String(format: step < 1 ? "%.1f" : "%.0f", value.wrappedValue))\(unit)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(WarmTheme.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(WarmTheme.accent.opacity(0.12))
                    .clipShape(Capsule())
            }
            Slider(value: value, in: range, step: step)
                .tint(WarmTheme.primary)
        }
    }

    // MARK: - Collection Info

    private var collectionInfo: some View {
        VStack(spacing: 14) {
            // Date
            HStack {
                Image(systemName: "calendar")
                    .font(.system(size: 14))
                    .foregroundColor(WarmTheme.primary)
                Text("采集日期")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(WarmTheme.textPrimary)
                Spacer()
                Button {
                    isFocused = false
                    showDatePicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(collectionDateFormatted)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(WarmTheme.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(WarmTheme.textSecondary)
                    }
                }
            }

            Divider()
                .background(WarmTheme.accent.opacity(0.2))

            // Collector
            HStack {
                Image(systemName: "person.fill")
                    .font(.system(size: 14))
                    .foregroundColor(WarmTheme.primary)
                Text("采集人")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(WarmTheme.textPrimary)
                Spacer()
                Button {
                    if !collectors.isEmpty { showCollectorPicker = true }
                } label: {
                    HStack(spacing: 4) {
                        Text(collectors.isEmpty ? "暂无采集人" : (selectedCollectorIndex != nil ? collectors[selectedCollectorIndex!].name : "请选择"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(collectors.isEmpty ? WarmTheme.textSecondary.opacity(0.5) : WarmTheme.primary)
                        if !collectors.isEmpty {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(WarmTheme.textSecondary)
                        }
                    }
                }
                .confirmationDialog("选择采集人", isPresented: $showCollectorPicker, titleVisibility: .visible) {
                    ForEach(Array(collectors.enumerated()), id: \.offset) { idx, collector in
                        Button(collector.name) { selectedCollectorIndex = idx }
                    }
                }
            }
        }
    }

    private var collectionDateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: collectionDate)
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(WarmTheme.primary)
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(WarmTheme.textPrimary)
        }
    }
}

// MARK: - Capture Config

struct CaptureConfig {
    let specimenId: Int
    let specimenName: String
    let ratioId: Int
    let ratioName: String
    let stackId: Int
    let stackName: String
    let light: Double
    let lightCircle: Double
    let lightField: Int
    let collectionDate: Date
    let collector: String?
}

// MARK: - New Stack View

struct NewStackView: View {
    let specimenId: Int
    let ratioId: Int
    let onCreated: (SpecimenTileStacked) -> Void

    @State private var stackName = ""
    @State private var lightIntensity: Double = 5
    @State private var lightAperture: Double = 0.5
    @State private var lightFieldType: Int = 1  // 1:明场, 0:暗场
    @State private var isCreating = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 素材包名称
                    VStack(alignment: .leading, spacing: 6) {
                        Label("素材包名称", systemImage: "square.stack.3d.up.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(WarmTheme.textSecondary)
                        TextField("请输入素材包名称", text: $stackName)
                            .font(.system(size: 16))
                            .padding(14)
                            .background(WarmTheme.light)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(WarmTheme.accent.opacity(0.3), lineWidth: 1)
                            )
                    }

                    // 光强
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("光强", systemImage: "sun.max.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(WarmTheme.textSecondary)
                            Spacer()
                            Text("\(Int(lightIntensity))")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(WarmTheme.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(WarmTheme.accent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        Slider(value: $lightIntensity, in: 1...10, step: 1)
                            .tint(WarmTheme.primary)
                    }

                    // 光圈
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("光圈", systemImage: "circle.circle")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(WarmTheme.textSecondary)
                            Spacer()
                            Text(String(format: "%.1f", lightAperture))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(WarmTheme.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(WarmTheme.accent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        Slider(value: $lightAperture, in: 0...1, step: 0.1)
                            .tint(WarmTheme.primary)
                    }

                    // 光场
                    VStack(alignment: .leading, spacing: 6) {
                        Label("光场", systemImage: "lightbulb.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(WarmTheme.textSecondary)
                        HStack(spacing: 12) {
                            Button {
                                lightFieldType = 1
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: lightFieldType == 1 ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(lightFieldType == 1 ? WarmTheme.primary : WarmTheme.textSecondary.opacity(0.5))
                                    Text("明场")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(lightFieldType == 1 ? WarmTheme.textPrimary : WarmTheme.textSecondary.opacity(0.5))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(lightFieldType == 1 ? WarmTheme.accent.opacity(0.15) : WarmTheme.light)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            Button {
                                lightFieldType = 0
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: lightFieldType == 0 ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(lightFieldType == 0 ? WarmTheme.primary : WarmTheme.textSecondary.opacity(0.5))
                                    Text("暗场")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(lightFieldType == 0 ? WarmTheme.textPrimary : WarmTheme.textSecondary.opacity(0.5))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(lightFieldType == 0 ? WarmTheme.accent.opacity(0.15) : WarmTheme.light)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .background(
                LinearGradient(colors: [WarmTheme.bgGradientTop, WarmTheme.bgGradientBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            )
            .navigationTitle("新建素材包")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundColor(WarmTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        Task { await createStack() }
                    }
                    .fontWeight(.bold)
                    .foregroundColor(stackName.isEmpty || isCreating ? WarmTheme.textSecondary : WarmTheme.primary)
                    .disabled(stackName.isEmpty || isCreating)
                }
            }
            .overlay {
                if isCreating {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(WarmTheme.primary)
                            .scaleEffect(1.2)
                        Text("创建中...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(WarmTheme.textSecondary)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private func createStack() async {
        isCreating = true
        do {
            let stack = try await APIService.shared.createStack(
                specimenId: specimenId,
                ratioId: ratioId,
                stackName: stackName,
                light: lightIntensity,
                lightCircle: lightAperture,
                lightField: lightFieldType
            )
            onCreated(stack)
            dismiss()
        } catch {
            print("创建素材包失败: \(error)")
        }
        isCreating = false
    }
}

// MARK: - Specimen Picker Sheet (带搜索)

struct SpecimenPickerSheet: View {
    let specimens: [SpecimenWithRatios]
    @Binding var searchText: String
    @Binding var selectedIndex: Int?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFocused: Bool

    /// 仅按名称模糊匹配（不区分大小写）
    private var filteredSpecimens: [(index: Int, specimen: SpecimenWithRatios)] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return Array(specimens.enumerated()).map { ($0.offset, $0.element) }
        }
        return specimens.enumerated().compactMap { idx, specimen in
            specimen.name.lowercased().contains(query) ? (idx, specimen) : nil
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索框
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(WarmTheme.textSecondary)
                    TextField("搜索标本名称", text: $searchText)
                        .focused($isSearchFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(WarmTheme.textSecondary.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(WarmTheme.light)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

                // 列表
                if filteredSpecimens.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 40))
                            .foregroundColor(WarmTheme.textSecondary.opacity(0.5))
                        Text(specimens.isEmpty ? "暂无标本数据" : "未找到匹配的标本")
                            .font(.system(size: 14))
                            .foregroundColor(WarmTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredSpecimens, id: \.index) { item in
                            Button {
                                selectedIndex = item.index
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "leaf.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(WarmTheme.success)
                                    Text(item.specimen.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(WarmTheme.textPrimary)
                                    Spacer()
                                    if selectedIndex == item.index {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundColor(WarmTheme.success)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(
                LinearGradient(colors: [WarmTheme.bgGradientTop, WarmTheme.bgGradientBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            )
            .navigationTitle("选择标本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                        .foregroundColor(WarmTheme.primary)
                }
            }
        }
        .onAppear {
            isSearchFocused = true
        }
    }
}
