import SwiftUI
import Photos

struct CaptureSetupView: View {
    @StateObject private var api = APIService.shared
    @State private var specimens: [SpecimenWithRatios] = []
    @State private var collectors: [SpecimenCollector] = []
    @State private var stacks: [SpecimenTileStacked] = []

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
    @State private var lightIntensity: Double = 100
    @State private var lightAperture: Double = 0.5
    @State private var lightField: Int = 1

    @State private var isLoadingSpecimens = false
    @State private var isLoadingCollectors = false
    @State private var isLoadingStacks = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 1. Specimen selector
                    sectionCard(title: "标本信息") {
                        specimenPicker
                    }

                    // 2. Magnification ratio
                    if selectedSpecimenIndex != nil {
                        sectionCard(title: "放大倍数") {
                            ratioPicker
                        }
                    }

                    // 3. Material pack (stack)
                    if selectedRatioIndex != nil {
                        sectionCard(title: "素材包") {
                            stackPicker
                        }
                    }

                    // 4. Light parameters (when stack selected)
                    if selectedStackIndex != nil {
                        sectionCard(title: "光学参数") {
                            lightParameters
                        }
                    }

                    // 5. Collection info
                    sectionCard(title: "采集信息") {
                        collectionInfo
                    }

                    // 6. Start capture button
                    if canStartCapture {
                        Button {
                            navigateToCapture = true
                        } label: {
                            HStack {
                                Image(systemName: "camera.fill")
                                Text("开始拍摄")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("标本录制")
            .navigationBarTitleDisplayMode(.inline)
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
                NewStackView(specimenId: currentSpecimenId ?? 0,
                             ratioId: currentRatioId ?? 0) { newStack in
                    stacks.append(newStack)
                    selectedStackIndex = stacks.count - 1
                }
            }
            .overlay {
                if isLoadingSpecimens {
                    ProgressView("加载中...")
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Computed

    private var currentSpecimenId: Int? {
        guard let idx = selectedSpecimenIndex, idx < specimens.count else { return nil }
        return specimens[idx].id
    }

    private var currentRatioId: Int? {
        guard let sIdx = selectedSpecimenIndex,
              let rIdx = selectedRatioIndex,
              let ratios = specimens[sIdx].ratios,
              rIdx < ratios.count else { return nil }
        return ratios[rIdx].id
    }

    private var currentStackId: Int? {
        guard let idx = selectedStackIndex, idx < stacks.count else { return nil }
        return stacks[idx].id
    }

    private var canStartCapture: Bool {
        currentSpecimenId != nil && currentRatioId != nil && currentStackId != nil
    }

    private var captureConfig: CaptureConfig? {
        guard let specimenId = currentSpecimenId,
              let ratioId = currentRatioId,
              let stackId = currentStackId else { return nil }
        return CaptureConfig(
            specimenId: specimenId,
            specimenName: specimens[selectedSpecimenIndex!].name,
            ratioId: ratioId,
            ratioName: specimens[selectedSpecimenIndex!].ratios?[selectedRatioIndex!].name ?? "",
            stackId: stackId,
            stackName: stacks[selectedStackIndex!].stackName ?? "Stack-\(stackId)",
            light: lightIntensity,
            lightCircle: lightAperture,
            lightField: lightField,
            collectionDate: collectionDate,
            collector: selectedCollectorIndex != nil && selectedCollectorIndex! < collectors.count
                ? collectors[selectedCollectorIndex!].collector : nil
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
        stacks = (try? await api.fetchStacks(specimenId: specimenId, ratioId: ratioId)) ?? []
        // Apply light params from stack if available
        if let idx = selectedStackIndex, idx < stacks.count {
            let stack = stacks[idx]
            lightIntensity = stack.light ?? 100
            lightAperture = stack.lightCircle ?? 0.5
            lightField = stack.lightField ?? 1
        }
        isLoadingStacks = false
    }

    // MARK: - Section Card

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            content()
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Specimen Picker

    private var specimenPicker: some View {
        VStack(spacing: 8) {
            Picker("选择标本", selection: $selectedSpecimenIndex) {
                Text("请选择标本").tag(nil as Int?)
                ForEach(Array(specimens.enumerated()), id: \.offset) { idx, specimen in
                    Text(specimen.name).tag(idx as Int?)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedSpecimenIndex) {
                selectedRatioIndex = nil
                selectedStackIndex = nil
                stacks = []
            }
        }
    }

    // MARK: - Ratio Picker

    private var ratioPicker: some View {
        VStack(spacing: 8) {
            let ratios = selectedSpecimenIndex != nil ? (specimens[selectedSpecimenIndex!].ratios ?? []) : []
            Picker("放大倍数", selection: $selectedRatioIndex) {
                Text("请选择放大倍数").tag(nil as Int?)
                ForEach(Array(ratios.enumerated()), id: \.offset) { idx, ratio in
                    Text(ratio.name).tag(idx as Int?)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedRatioIndex) {
                Task { await loadStacks() }
            }
        }
    }

    // MARK: - Stack Picker

    private var stackPicker: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("素材包", selection: $selectedStackIndex) {
                    Text("请选择素材包").tag(nil as Int?)
                    ForEach(Array(stacks.enumerated()), id: \.offset) { idx, stack in
                        Text(stack.stackName ?? "Stack-\(stack.id)").tag(idx as Int?)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                Button {
                    showNewStackSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }

            if isLoadingStacks {
                ProgressView()
                    .scaleEffect(0.8)
            }

            if let idx = selectedStackIndex, idx < stacks.count {
                let stack = stacks[idx]
                VStack(alignment: .leading, spacing: 4) {
                    infoRow(label: "光强", value: stack.light != nil ? "\(stack.light!)" : "-")
                    infoRow(label: "光圈", value: stack.lightCircle != nil ? "\(stack.lightCircle!)" : "-")
                    infoRow(label: "光场", value: stack.lightField != nil ? "\(stack.lightField!)" : "-")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Light Parameters

    private var lightParameters: some View {
        VStack(spacing: 16) {
            parameterSlider(label: "光强", value: $lightIntensity, range: 0...500, step: 1, unit: "lx")
            parameterSlider(label: "光圈", value: $lightAperture, range: 0...2, step: 0.1, unit: "")
            parameterSlider(label: "光场", value: Binding(
                get: { Double(lightField) },
                set: { lightField = Int($0) }
            ), range: 0...10, step: 1, unit: "")
        }
    }

    private func parameterSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer()
                Text("\(String(format: step < 1 ? "%.1f" : "%.0f", value.wrappedValue))\(unit)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    // MARK: - Collection Info

    private var collectionInfo: some View {
        VStack(spacing: 12) {
            // Date
            HStack {
                Text("采集日期")
                    .font(.subheadline)
                Spacer()
                Button {
                    showDatePicker.toggle()
                } label: {
                    Text(collectionDateFormatted)
                        .foregroundColor(.blue)
                }
            }

            if showDatePicker {
                DatePicker("", selection: $collectionDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
            }

            Divider()

            // Collector
            HStack {
                Text("采集人")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $selectedCollectorIndex) {
                    Text("请选择").tag(nil as Int?)
                    ForEach(Array(collectors.enumerated()), id: \.offset) { idx, collector in
                        Text(collector.collector).tag(idx as Int?)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var collectionDateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: collectionDate)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
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
    @State private var isCreating = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("素材包信息")) {
                    TextField("素材包名称", text: $stackName)
                }
            }
            .navigationTitle("新建素材包")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        Task { await createStack() }
                    }
                    .disabled(stackName.isEmpty || isCreating)
                }
            }
            .overlay {
                if isCreating {
                    ProgressView()
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
                stackName: stackName
            )
            onCreated(stack)
            dismiss()
        } catch {
            print("创建素材包失败: \(error)")
        }
        isCreating = false
    }
}
