import SwiftUI
import SwiftData
import Charts

struct ProtocolDetailView: View {
    let protocol_: CompoundProtocol
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showLogDose = false
    @State private var showEditProtocol = false
    @State private var showReconCalc = false
    @State private var showRestockInventory = false
    @State private var doseTime: Date = Date()
    
    var activeLevelData: [ActiveLevelDataPoint] {
        PharmacokineticsEngine.activeLevel(
            for: protocol_,
            logs: protocol_.sortedLogs,
            startDate: Calendar.current.date(byAdding: .day, value: -30, to: Date()),
            endDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(),
            resolution: 200
        )
    }
    
    var currentLevel: Double {
        PharmacokineticsEngine.currentLevel(for: protocol_, logs: protocol_.doseLogs)
    }
    
    var stableInfo: StableLevelInfo {
        PharmacokineticsEngine.stableLevelInfo(for: protocol_, logs: protocol_.doseLogs)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Hero header
                    heroSection
                    
                    // Schedule & Inventory row
                    HStack(spacing: 12) {
                        scheduleCard
                        inventoryCard
                    }
                    
                    // Active Levels Graph
                    activeLevelsSection
                    
                    // Dose Logs
                    doseLogsSection
                    
                    // Notes
                    if !protocol_.notes.isEmpty {
                        notesSection
                    }
                    
                    // Action buttons
                    actionButtons
                    
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(protocol_.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Edit Protocol") { showEditProtocol = true }
                    Button("PepCalc") { showReconCalc = true }
                    Divider()
                    if protocol_.status == .archived {
                        Button("Delete Permanently", role: .destructive) { deleteProtocol() }
                    } else {
                        Button("Pause") { updateStatus(.paused) }
                        Button("Complete") { updateStatus(.completed) }
                        Button("Archive", role: .destructive) { updateStatus(.archived) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showLogDose) {
            LogDoseSheet(protocol_: protocol_)
        }
        .sheet(isPresented: $showReconCalc) {
            ReconstitutionCalculatorView(prefillName: protocol_.name)
        }
        .sheet(isPresented: $showEditProtocol) {
            NewProtocolView(protocol_: protocol_)
        }
        .sheet(isPresented: $showRestockInventory) {
            RestockInventorySheet(protocol_: protocol_)
        }
        .onAppear {
            let fallback = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
            doseTime = protocol_.schedule.timesOfDay.first ?? fallback
        }
        .onChange(of: doseTime) { _, newTime in
            var sched = protocol_.schedule
            sched.timesOfDay = [newTime]
            protocol_.schedule = sched
            try? context.save()
            Task { await NotificationService.shared.scheduleReminders(for: protocol_) }
        }
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        HStack(spacing: 14) {
            CategoryIcon(category: protocol_.category, size: 56)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(protocol_.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    StatusBadge(status: protocol_.status)
                    PillTag(text: protocol_.category.rawValue)
                    PillTag(text: protocol_.administrationForm.rawValue)
                }
                Text("Started \(protocol_.startDate.formatted(.dateTime.month(.wide).day().year()))")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
            
            Spacer()
        }
        .glassCard()
    }
    
    // MARK: - Schedule Card
    
    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TileHeader(icon: "calendar.badge.clock", title: "Schedule")
            
            Text(protocol_.schedule.description)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            
            AscendancyDivider()
            
            VStack(alignment: .leading, spacing: 4) {
                InfoRow(label: "Dose", value: "\(protocol_.doseAmount.formatted(.number.precision(.fractionLength(0...2)))) \(protocol_.doseUnit.rawValue)")
                InfoRow(label: "Half-life", value: "\(protocol_.halfLifeValue.formatted(.number.precision(.fractionLength(0...1)))) \(protocol_.halfLifeUnit.rawValue)")
                if let end = protocol_.endDate {
                    InfoRow(label: "End date", value: end.formatted(.dateTime.month(.abbreviated).day().year()))
                }
            }

            AscendancyDivider()

            HStack {
                Text("Dose Time")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                DatePicker("", selection: $doseTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(.white)
                    .colorScheme(.dark)
            }
        }
        .glassCardFilling(cornerRadius: 16, padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
    }
    
    // MARK: - Inventory Card
    
    private var inventoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TileHeader(icon: "shippingbox.fill", title: "Inventory",
                       iconColor: protocol_.isLowInventory ? .orange : .white.opacity(0.5))
            
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(protocol_.inventoryCount.formatted(.number.precision(.fractionLength(0...2))))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(protocol_.isLowInventory ? .orange : .white)
                
                Text(protocol_.inventoryDisplayUnitLabel + (protocol_.formDosage > 0 ? " (\(protocol_.formDosage.formatted(.number.precision(.fractionLength(0...2)))) \(protocol_.doseUnit.rawValue) per \(protocol_.administrationForm.inventorySingularLabel))" : ""))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }
            
            InventoryBar(current: protocol_.inventoryCount, maxValue: protocol_.inventoryCount + protocol_.inventoryLowThreshold * 3)
            
            if protocol_.isLowInventory {
                Label("Low stock", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            
            if let days = InventoryService.shared.daysOfSupply(for: protocol_) {
                Text("\(Int(days)) days remaining")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Button {
                showRestockInventory = true
            } label: {
                Label(protocol_.restockButtonTitle, systemImage: "shippingbox.badge.plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .glassCardFilling(cornerRadius: 16, padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
    }
    
    // MARK: - Active Levels Graph
    
    private var activeLevelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TileHeader(icon: "waveform.path.ecg", title: "Active Levels")
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentLevel.formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Current estimated level")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("±30d view")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            
            // Stable Levels indicator
            StableLevelsRow(
                info: stableInfo,
                color: protocol_.category.uiColor
            )
            
            if activeLevelData.isEmpty {
                Text("Log doses to see active level graph")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                Chart {
                    ForEach(activeLevelData) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Level", point.level)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [categoryChartColor.opacity(0.3), Color.clear],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                        
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Level", point.level)
                        )
                        .foregroundStyle(categoryChartColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                    }
                    
                    // "Now" annotation
                    RuleMark(x: .value("Now", Date()))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.white.opacity(0.2))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { v in
                        if let date = v.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: .dateTime.month(.abbreviated).day())
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3, dash: [3]))
                            .foregroundStyle(Color.white.opacity(0.05))
                    }
                }
                .chartYAxis {
                    AxisMarks { v in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3, dash: [3]))
                            .foregroundStyle(Color.white.opacity(0.05))
                    }
                }
                .frame(height: 140)
            }
        }
        .glassCard()
    }
    
    private var categoryChartColor: Color {
        protocol_.category.uiColor
    }
    
    // MARK: - Dose Logs Section
    
    private var doseLogsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Dose History")
            
            if protocol_.doseLogs.isEmpty {
                Text("No doses logged yet")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                    .glassCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(protocol_.sortedLogs.prefix(8)) { log in
                        LogEntryRow(log: log)
                        if log.id != protocol_.sortedLogs.prefix(8).last?.id {
                            AscendancyDivider().padding(.leading, 44)
                        }
                    }
                }
                .glassCard()
                
                if protocol_.doseLogs.count > 8 {
                    Text("View all \(protocol_.doseLogs.count) entries in Logs tab")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }
    
    // MARK: - Notes Section
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Notes")
            Text(protocol_.notes)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .glassCard()
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                showLogDose = true
            } label: {
                Label("Log Dose", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            
            if protocol_.category == .peptide {
                Button {
                    showReconCalc = true
                } label: {
                    Label("Reconstitution Calculator", systemImage: "flask.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }
    
    private func updateStatus(_ status: ProtocolStatus) {
        protocol_.status = status
        try? context.save()
    }
    
    private func deleteProtocol() {
        context.delete(protocol_)
        try? context.save()
        dismiss()
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

private struct RestockInventorySheet: View {
    let protocol_: CompoundProtocol

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var adjustment: Int = 0

    private var projectedStock: Double {
        max(0, protocol_.inventoryCount + Double(adjustment))
    }

    private var isDepletion: Bool { adjustment < 0 }
    private var hasChange: Bool { adjustment != 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 20) {

                    // Current stock
                    VStack(spacing: 6) {
                        Text("Current Stock")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                            .textCase(.uppercase)
                            .tracking(0.8)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(protocol_.inventoryCount.formatted(.number.precision(.fractionLength(0...2))))
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text(protocol_.inventoryDisplayUnitLabel)
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .glassCard()

                    // Stepper selector
                    VStack(spacing: 12) {
                        Text("Adjust Quantity")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                            .textCase(.uppercase)
                            .tracking(0.8)

                        HStack(spacing: 0) {
                            Button {
                                if Double(adjustment - 1) + protocol_.inventoryCount >= 0 {
                                    adjustment -= 1
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 42))
                                    .foregroundStyle(
                                        Double(adjustment - 1) + protocol_.inventoryCount >= 0
                                            ? Color.white.opacity(0.85)
                                            : Color.white.opacity(0.18)
                                    )
                            }
                            .disabled(Double(adjustment - 1) + protocol_.inventoryCount < 0)

                            Spacer()

                            VStack(spacing: 3) {
                                Text(adjustment > 0 ? "+\(adjustment)" : "\(adjustment)")
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
                                    .foregroundStyle(
                                        adjustment > 0 ? Color.green
                                        : adjustment < 0 ? Color.orange
                                        : Color.white.opacity(0.3)
                                    )
                                    .monospacedDigit()
                                    .contentTransition(.numericText(value: Double(adjustment)))
                                    .animation(.spring(response: 0.25), value: adjustment)
                                Text(protocol_.administrationForm.inventoryPluralLabel)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            .frame(minWidth: 100)

                            Spacer()

                            Button {
                                adjustment += 1
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 42))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .glassCard()

                    // Projected change
                    if hasChange {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(isDepletion ? "Depletion" : "Restock")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(isDepletion ? .orange : .green)
                                    .textCase(.uppercase)
                                    .tracking(0.8)
                                HStack(spacing: 6) {
                                    Text(protocol_.inventoryCount.formatted(.number.precision(.fractionLength(0...2))))
                                        .foregroundStyle(.white.opacity(0.45))
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.3))
                                    Text(projectedStock.formatted(.number.precision(.fractionLength(0...2))))
                                        .foregroundStyle(isDepletion ? .orange : .green)
                                        .fontWeight(.semibold)
                                    Text(protocol_.inventoryDisplayUnitLabel)
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                .font(.system(size: 16, design: .rounded))
                            }
                            Spacer()
                        }
                        .glassCard()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .animation(.spring(response: 0.3), value: hasChange)
                    }

                    Spacer()

                    Button {
                        applyAdjustment()
                    } label: {
                        Label(
                            isDepletion
                                ? "Apply Depletion"
                                : "Restock \(protocol_.administrationForm.inventoryPluralLabel.capitalized)",
                            systemImage: isDepletion ? "minus.circle.fill" : "shippingbox.badge.plus"
                        )
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(hasChange ? .black : .white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(hasChange ? Color.white : Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(!hasChange)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Adjust Inventory")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private func applyAdjustment() {
        guard hasChange else { return }

        if protocol_.inventoryUnitLabel.isEmpty {
            protocol_.refreshInventoryUnitLabel()
        }

        let delta = Double(adjustment)
        if delta > 0 {
            InventoryService.shared.addInventory(to: protocol_, amount: delta)
        } else {
            protocol_.inventoryCount = max(0, protocol_.inventoryCount + delta)
        }
        try? context.save()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        ProtocolDetailView(protocol_: SampleData.makeSampleProtocols()[0])
    }
    .preferredColorScheme(.dark)
    .modelContainer(for: [CompoundProtocol.self, DoseLog.self], inMemory: true)
}
