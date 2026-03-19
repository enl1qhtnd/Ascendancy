import SwiftUI
import SwiftData

struct MetricsView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @Query(filter: #Predicate<CompoundProtocol> { $0.statusRaw == "Active" })
    private var activeProtocols: [CompoundProtocol]
    
    enum MetricPeriod: String, CaseIterable {
        case week = "7D"
        case month = "30D"
        case quarter = "90D"
    }
    
    @State private var selectedPeriod: MetricPeriod = .month
    
    var periodDays: Int {
        switch selectedPeriod {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        }
    }
    
    var weightSlice: [HealthMetricPoint] {
        Array(healthKit.bodyWeightSamples.suffix(periodDays))
    }
    var hrSlice: [HealthMetricPoint] {
        Array(healthKit.heartRateSamples.suffix(periodDays))
    }
    var stepsSlice: [HealthMetricPoint] {
        Array(healthKit.stepSamples.suffix(periodDays))
    }
    var bodyFatSlice: [HealthMetricPoint] {
        Array(healthKit.bodyFatSamples.suffix(periodDays))
    }
    var activeEnergySlice: [HealthMetricPoint] {
        Array(healthKit.activeEnergySamples.suffix(periodDays))
    }
    var heightSlice: [HealthMetricPoint] {
        Array(healthKit.heightSamples.suffix(periodDays))
    }
    var bmiSlice: [HealthMetricPoint] {
        Array(healthKit.bmiSamples.suffix(periodDays))
    }
    
    // Cached PK calculation
    @State private var combinedLevelData: [ActiveLevelDataPoint] = []
    
    private func recalculateCombinedLevels() {
        let startDate = Calendar.current.date(byAdding: .day, value: -periodDays, to: Date())
        let pairs = activeProtocols.map { ($0, $0.doseLogs) }
        combinedLevelData = PharmacokineticsEngine.combinedActiveLevel(protocols: pairs, startDate: startDate)
    }
    
    var avgSteps: Double {
        let v = stepsSlice.map(\.value)
        guard !v.isEmpty else { return 0 }
        return v.reduce(0, +) / Double(v.count)
    }
    
    var avgCalories: Double {
        let v = activeEnergySlice.map(\.value)
        guard !v.isEmpty else { return 0 }
        return v.reduce(0, +) / Double(v.count)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Period picker
                        HStack(spacing: 0) {
                            ForEach(MetricPeriod.allCases, id: \.self) { period in
                                Button {
                                    Haptics.selection()
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedPeriod = period
                                    }
                                } label: {
                                    Text(period.rawValue)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(selectedPeriod == period ? .black : .white.opacity(0.5))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(selectedPeriod == period ? Color.white : Color.clear)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(4)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                        
                        if !healthKit.isAuthorized {
                            healthKitPrompt
                        }
                        
                        // Active Levels
                        if !activeProtocols.isEmpty {
                            metricCard(title: "Active Compound Levels", icon: "waveform.path.ecg", color: Color(white: 0.85)) {
                                CompactLineChart(
                                    dataPoints: combinedLevelData,
                                    lineColor: Color(white: 0.85),
                                    showCurrentDot: true,
                                    height: 120
                                )
                                
                                // Per-compound breakdown
                                VStack(spacing: 12) {
                                    ForEach(activeProtocols) { p in
                                        let level = PharmacokineticsEngine.currentLevel(for: p, logs: p.doseLogs)
                                        let stable = PharmacokineticsEngine.stableLevelInfo(for: p, logs: p.doseLogs)
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Circle().fill(p.category.uiColor).frame(width: 6, height: 6)
                                                Text(p.name)
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundStyle(.white.opacity(0.7))
                                                Spacer()
                                                Text(level.formatted(.number.precision(.fractionLength(1))))
                                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                    .foregroundStyle(.white.opacity(0.6))
                                                Text(p.doseUnit.rawValue)
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.white.opacity(0.3))
                                            }
                                            StableLevelsRow(
                                                info: stable,
                                                color: p.category.uiColor
                                            )
                                        }
                                    }
                                }
                                .padding(.top, 8)
                            }
                        }
                        
                        // Body Weight
                        metricCard(title: "Body Weight", icon: "scalemass.fill", color: .blue) {
                            HealthMetricChart(
                                dataPoints: weightSlice,
                                title: "Weight",
                                unit: "kg",
                                lineColor: .blue,
                                days: periodDays
                            )
                        }
                        
                        // Resting Heart Rate
                        metricCard(title: "Resting Heart Rate", icon: "heart.fill", color: .red) {
                            HealthMetricChart(
                                dataPoints: hrSlice,
                                title: "HR",
                                unit: "bpm",
                                lineColor: .red,
                                days: periodDays
                            )
                        }
                        
                        // Steps
                        metricCard(title: "Steps", icon: "figure.walk", color: .green) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(avgSteps.formatted(.number.precision(.fractionLength(0))))
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text("avg/day")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                HealthMetricChart(
                                    dataPoints: stepsSlice,
                                    title: "Steps",
                                    unit: "steps",
                                    lineColor: .green,
                                    days: periodDays
                                )
                            }
                        }
                        
                        // Active Energy (Calories)
                        metricCard(title: "Active Energy", icon: "flame.fill", color: .orange) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(avgCalories.formatted(.number.precision(.fractionLength(0))))
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text("kcal avg/day")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                HealthMetricChart(
                                    dataPoints: activeEnergySlice,
                                    title: "Calories",
                                    unit: "kcal",
                                    lineColor: .orange,
                                    days: periodDays
                                )
                            }
                        }
                        
                        // Body Fat Percentage
                        metricCard(title: "Body Fat", icon: "percent", color: .cyan) {
                            HealthMetricChart(
                                dataPoints: bodyFatSlice.map { HealthMetricPoint(date: $0.date, value: $0.value * 100) }, // Convert decimal to %
                                title: "Fat",
                                unit: "%",
                                lineColor: .cyan,
                                days: periodDays
                            )
                        }
                        
                        // BMI
                        metricCard(title: "Body Mass Index", icon: "scalemass", color: .indigo) {
                            HealthMetricChart(
                                dataPoints: bmiSlice,
                                title: "BMI",
                                unit: "",
                                lineColor: .indigo,
                                days: periodDays
                            )
                        }
                        
                        // Height
                        if let h = heightSlice.last {
                            metricCard(title: "Height", icon: "arrow.up.and.down", color: .teal) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(h.value.formatted(.number.precision(.fractionLength(1))))
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text("cm")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.45))
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        
                        
                        
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Metrics")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task {
            await healthKit.requestAuthorization()
            if !healthKit.isAuthorized {
                healthKit.loadMockData()
            }
            recalculateCombinedLevels()
        }
        .onChange(of: selectedPeriod) {
            recalculateCombinedLevels()
        }
        .onChange(of: activeProtocols.count) {
            recalculateCombinedLevels()
        }
    }
    
    private func metricCard<Content: View>(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TileHeader(icon: icon, title: title, iconColor: color.opacity(0.8))
            content()
        }
        .glassCard()
    }
    
    private var healthKitPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 32))
                .foregroundStyle(.red.opacity(0.7))
            Text("Connect Apple Health")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text("Allow Ascendancy to read your health data for metrics and insights.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
            Button {
                Haptics.tap()
                Task { await healthKit.requestAuthorization() }
            } label: {
                Text("Connect Health")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.8))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}

#Preview {
    MetricsView()
        .preferredColorScheme(.dark)
        .modelContainer(for: [CompoundProtocol.self, DoseLog.self], inMemory: true)
}
