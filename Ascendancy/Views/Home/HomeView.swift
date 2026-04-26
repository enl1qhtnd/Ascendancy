import SwiftUI
import SwiftData
import PhotosUI

struct HomeView: View {
    @Query(
        filter: #Predicate<CompoundProtocol> { $0.statusRaw == "Active" },
        sort: CompoundProtocol.listSortDescriptors
    )
    private var activeProtocols: [CompoundProtocol]

    @Query(sort: \DoseLog.timestamp, order: .reverse)
    private var allLogs: [DoseLog]

    @StateObject private var healthKit = HealthKitService.shared
    @State private var showProfile = false
    @State private var showLogSheet = false
    @State private var selectedProtocolForLog: CompoundProtocol? = nil

    @AppStorage("profileImageData") private var profileImageData: Data?

    // Cached PK calculation
    @State private var combinedLevelData: [ActiveLevelDataPoint] = []
    @State private var pkRecalcTask: Task<Void, Never>? = nil

    // Track data version to avoid unnecessary recalculations
    @State private var lastProtocolsHash: Int = 0
    @State private var lastLogsHash: Int = 0

    private func recalculateCombinedLevels() {
        let snapshots = activeProtocols.map { protocol_ in
            PKProtocolSnapshot(
                startDate: protocol_.startDate,
                halfLifeHours: protocol_.halfLifeInHours,
                logs: (protocol_.doseLogs ?? [])
                    .map { PKDoseLogSnapshot(timestamp: $0.timestamp, actualDoseAmount: $0.actualDoseAmount) }
                    .sorted { $0.timestamp < $1.timestamp }
            )
        }

        // Run in background to avoid blocking UI
        Task.detached(priority: .userInitiated) {
            let newData = PharmacokineticsEngine.combinedActiveLevel(
                snapshots: snapshots,
                startDate: Calendar.current.date(byAdding: .day, value: -14, to: Date()),
                endDate: Date()
            )
            await MainActor.run {
                combinedLevelData = newData
            }
        }
    }

    private func schedulePKRecalc() {
        // Check if data actually changed
        let protocolsHash = activeProtocols.map { "\($0.id)-\($0.doseLogs?.count ?? 0)" }.joined().hashValue
        let logsHash = allLogs.prefix(100).map { "\($0.id)-\($0.timestamp)" }.joined().hashValue

        guard protocolsHash != lastProtocolsHash || logsHash != lastLogsHash else {
            return // No change, skip recalculation
        }

        lastProtocolsHash = protocolsHash
        lastLogsHash = logsHash

        pkRecalcTask?.cancel()
        pkRecalcTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            recalculateCombinedLevels()
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        headerView
                        
                        // 1. Active Protocols Tile
                        ActiveProtocolsTile(protocols: activeProtocols)
                        
                        // 2. Next Dose + Bodyweight side-by-side
                        HStack(spacing: 12) {
                            CompactTodaysDoseTile(protocols: activeProtocols, logs: allLogs)
                            CompactBodyweightTile(healthKit: healthKit)
                        }
                        
                        // 3. Active Levels Graph Tile
                        ActiveLevelsTile(dataPoints: combinedLevelData, protocols: activeProtocols)
                        
                        // 4. This Week Tile
                        ThisWeekTile(logs: allLogs, protocols: Array(activeProtocols))
                        
                        // 5. Pictures & Documents Tile (bottom)
                        PicturesDocumentsTile()
                        
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .sheet(isPresented: $showProfile) {
                ProfileSettingsView()
            }
            .sheet(item: $selectedProtocolForLog) { p in
                LogDoseSheet(protocol_: p)
            }
        }
        .task {
            await healthKit.requestAuthorization()
            recalculateCombinedLevels()
        }
        .onChange(of: activeProtocols.count) {
            schedulePKRecalc()
        }
        .onChange(of: allLogs.count) {
            schedulePKRecalc()
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(greetingText)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            
            HStack(spacing: 16) {
                Menu {
                    Text("Log Dose For...")
                        .font(.caption)
                    
                    ForEach(activeProtocols) { p in
                        Button {
                            Haptics.selection()
                            selectedProtocolForLog = p
                        } label: {
                            Label(p.name, systemImage: "plus.circle")
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white.opacity(0.8))
                        .symbolRenderingMode(.hierarchical)
                }
                
                Button {
                    Haptics.tap()
                    showProfile = true
                } label: {
                    if let data = profileImageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 30, height: 30)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.6))
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
        .padding(.top, 8)
    }
    
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return String(localized: "Good morning")
        case 12..<17: return String(localized: "Good afternoon")
        default: return String(localized: "Good evening")
        }
    }
}

// MARK: - Active Protocols Tile

struct ActiveProtocolsTile: View {
    let protocols: [CompoundProtocol]

    private let maxShown = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TileHeader(icon: "cross.vial.fill", title: "Active Protocols")

            HStack(alignment: .top, spacing: 16) {
                StatLabel(
                    value: "\(protocols.count)",
                    label: "Active",
                    valueFont: .system(size: 32, weight: .bold, design: .rounded)
                )

                Spacer()

                let shown = Array(protocols.prefix(maxShown))
                let rows = shown.chunked(into: 2)

                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, pair in
                        HStack(spacing: 12) {
                            ForEach(pair) { p in
                                HStack(spacing: 6) {
                                    CategoryIcon(category: p.category, size: 20)
                                    Text(p.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.7))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    if protocols.count > maxShown {
                        Text(String(format: String(localized: "+%lld more"), protocols.count - maxShown))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
        }
        .glassCard()
    }
}

// MARK: - Next Dose Tile

struct NextDoseTile: View {
    let protocol_: CompoundProtocol?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TileHeader(icon: "clock.arrow.circlepath", title: "Next Dose")
            
            if let p = protocol_, let nextDate = p.nextDoseDate() {
                HStack(alignment: .center, spacing: 14) {
                    CategoryIcon(category: p.category, size: 40)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("\(p.doseAmount.formatted(.number.precision(.fractionLength(0...2)))) \(p.doseUnit.rawValue)")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(nextDate, format: .dateTime.hour().minute())
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(relativeDate(nextDate))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            } else {
                Text("No upcoming doses scheduled")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .glassCard()
    }
    
    private func relativeDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return String(localized: "Today") }
        if Calendar.current.isDateInTomorrow(date) { return String(localized: "Tomorrow") }
        return date.formatted(.dateTime.weekday(.wide))
    }
}

// MARK: - Bodyweight Tile

struct BodyweightTile: View {
    @ObservedObject var healthKit: HealthKitService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TileHeader(icon: "scalemass.fill", title: "Bodyweight")

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    if let w = healthKit.latestWeight {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(w.formatted(.number.precision(.fractionLength(1))))
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("kg")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        HStack(spacing: 3) {
                            let trend = healthKit.weightTrend7Day
                            Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(trend >= 0 ? Color.orange : Color.green)
                            Text(String(format: String(localized: "%1$+.1f kg (7d)"), locale: .current, trend))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    } else {
                        Text("–")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }

                Spacer()

                // Mini sparkline
                let recent = Array(healthKit.bodyWeightSamples.suffix(21))
                if !recent.isEmpty {
                    let levels = recent.map { point -> ActiveLevelDataPoint in
                        ActiveLevelDataPoint(date: point.date, level: point.value)
                    }
                    CompactLineChart(
                        dataPoints: levels,
                        lineColor: .blue,
                        showCurrentDot: false,
                        height: 44
                    )
                    .frame(width: 100)
                }
            }
        }
        .glassCard()
    }
}

// MARK: - Compact Today's Dose Tile (half width)

struct CompactTodaysDoseTile: View {
    let protocols: [CompoundProtocol]
    let logs: [DoseLog]
    @State private var showDaySchedule = false

    private var dayStart: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var rows: [(CompoundProtocol, Date)] {
        DoseScheduleDayHelper.mergedRows(protocols: protocols, logs: logs, on: dayStart)
    }

    private var doneCount: Int {
        rows.filter { DoseScheduleDayHelper.isLogged($0.0, on: dayStart, logs: logs) }.count
    }

    private var nextIncomplete: (CompoundProtocol, Date)? {
        rows.first { !DoseScheduleDayHelper.isLogged($0.0, on: dayStart, logs: logs) }
    }

    private var moreIncompleteCount: Int {
        guard nextIncomplete != nil else { return 0 }
        return rows.filter { !DoseScheduleDayHelper.isLogged($0.0, on: dayStart, logs: logs) }.count - 1
    }

    var body: some View {
        Button {
            Haptics.tap()
            showDaySchedule = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TileHeader(icon: "calendar", title: "Today's Dose")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }

                if rows.isEmpty {
                    Text("–")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.25))
                    Text("No doses today")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                } else if let (p, time) = nextIncomplete {
                    HStack(spacing: 8) {
                        CategoryIcon(category: p.category, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name.components(separatedBy: " ").first ?? p.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(String(
                                format: String(localized: "%@ · %lld/%lld"),
                                "\(p.doseAmount.formatted(.number.precision(.fractionLength(0...1)))) \(p.doseUnit.rawValue)",
                                doneCount,
                                rows.count
                            ))
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(time, format: .dateTime.hour().minute())
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("next")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                        if moreIncompleteCount > 0 {
                            Text(String(format: String(localized: "(+%lld more)"), moreIncompleteCount))
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Color.green.opacity(0.85))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All caught up")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(String(format: String(localized: "%lld/%lld today"), rows.count, rows.count))
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("Done")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(String(localized: "today"))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDaySchedule) {
            DayScheduleSheet(protocols: protocols, logs: logs, initialDay: dayStart)
        }
    }
}

// MARK: - Day Schedule Sheet

struct DayScheduleSheet: View {
    let protocols: [CompoundProtocol]
    let logs: [DoseLog]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDay: Date

    init(protocols: [CompoundProtocol], logs: [DoseLog], initialDay: Date) {
        self.protocols = protocols
        self.logs = logs
        _selectedDay = State(initialValue: Calendar.current.startOfDay(for: initialDay))
    }

    private var doses: [(CompoundProtocol, Date)] {
        DoseScheduleDayHelper.mergedRows(protocols: protocols, logs: logs, on: selectedDay)
    }

    private var dayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDay) { return String(localized: "Today") }
        if cal.isDateInTomorrow(selectedDay) { return String(localized: "Tomorrow") }
        if cal.isDateInYesterday(selectedDay) { return String(localized: "Yesterday") }
        return selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Handle
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dose Schedule")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Text(dayLabel)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .animation(.easeInOut(duration: 0.15), value: dayLabel)
                    }
                    Spacer()
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.35))
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                // Day selector
                HStack(spacing: 0) {
                    Button {
                        Haptics.selection()
                        selectedDay = Calendar.current.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 44, height: 36)
                            .contentShape(Rectangle())
                    }

                    Text(selectedDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .animation(.easeInOut(duration: 0.15), value: selectedDay)

                    Button {
                        Haptics.selection()
                        selectedDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 44, height: 36)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)

                if doses.isEmpty {
                    Spacer()
                    Text("Nothing on this day")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(doses, id: \.0.id) { pair in
                                let (p, date) = pair
                                let done = DoseScheduleDayHelper.isLogged(p, on: selectedDay, logs: logs)
                                HStack(spacing: 14) {
                                    CategoryIcon(category: p.category, size: 38)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(p.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.white)
                                        Text("\(p.doseAmount.formatted(.number.precision(.fractionLength(0...2)))) \(p.doseUnit.rawValue)")
                                            .font(.system(size: 12, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }

                                    Spacer()

                                    Text(date, format: .dateTime.hour().minute())
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)

                                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22))
                                        .foregroundStyle(done ? Color.green.opacity(0.9) : .white.opacity(0.2))
                                        .symbolRenderingMode(.hierarchical)
                                }
                                .opacity(done ? 0.55 : 1)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color.black)
    }
}

// MARK: - Compact Bodyweight Tile (half width)

struct CompactBodyweightTile: View {
    @ObservedObject var healthKit: HealthKitService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TileHeader(icon: "scalemass.fill", title: "Weight")

            if let w = healthKit.latestWeight {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(w.formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("kg")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }

                HStack(spacing: 4) {
                    let trend = healthKit.weightTrend7Day
                    Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(trend >= 0 ? Color.orange : Color.green)
                    Text(String(format: String(localized: "%1$+.1f kg"), locale: .current, trend))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                    Text("7d")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
            } else {
                Text("–")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.25))
                Text("No data")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
    }
}

// MARK: - Active Levels Tile

struct ActiveLevelsTile: View {
    let dataPoints: [ActiveLevelDataPoint]
    let protocols: [CompoundProtocol]

    private func percentText(_ percentage: Double) -> String {
        (percentage / 100.0).formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TileHeader(icon: "waveform.path.ecg", title: "Active Levels")

            if protocols.isEmpty {
                Text("No active protocols")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Combined")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                            .textCase(.uppercase)
                            .tracking(0.4)
                        Text(String(format: String(localized: "%lld compounds"), protocols.count))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                }

                CompactLineChart(
                    dataPoints: dataPoints,
                    lineColor: Color(white: 0.85),
                    showCurrentDot: true,
                    height: 72
                )

                // Protocol level dots with stable %
                HStack(spacing: 8) {
                    ForEach(protocols.prefix(4)) { p in
                        let stable = p.cachedStableLevelInfo()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(p.category.uiColor)
                                .frame(width: 6, height: 6)
                            Text(p.name.components(separatedBy: " ").first ?? p.name)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                            Text(percentText(stable.percentage))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(stable.isStable ? p.category.uiColor.opacity(0.8) : .white.opacity(0.35))
                        }
                    }
                    Spacer()
                }
            }
        }
        .glassCard()
    }

}

// MARK: - This Week Tile

struct ThisWeekTile: View {
    let logs: [DoseLog]
    let protocols: [CompoundProtocol]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TileHeader(icon: "calendar.badge.checkmark", title: "This Week")
            WeekDotRow(logs: logs, protocols: protocols)
        }
        .glassCard()
    }
}

// MARK: - Pictures & Documents Tile

struct PicturesDocumentsTile: View {
    @Query(sort: \MediaDocument.dateAdded, order: .reverse) private var documents: [MediaDocument]
    @State private var showLibrary = false
    
    var body: some View {
        Button {
            Haptics.tap()
            showLibrary = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TileHeader(icon: "photo.on.rectangle.angled", title: "Pictures & Documents")
                    Spacer()
                    HStack(spacing: 4) {
                        if !documents.isEmpty {
                            Text("\(documents.count)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                
                HStack(spacing: 8) {
                    ForEach(documents.prefix(4)) { doc in
                        if let data = doc.imageData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 54, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    
                    if documents.count < 4 {
                        ForEach(0..<(4 - min(documents.count, 4)), id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.04))
                                .frame(width: 54, height: 54)
                                .overlay(
                                    Image(systemName: "doc.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white.opacity(0.08))
                                )
                        }
                    }
                    
                    Spacer()
                }
                
                Text(documents.isEmpty
                     ? "Tap to add protocol photos, bloodwork & documents"
                     : "Tap to view & manage all files")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .glassCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showLibrary) {
            MediaLibraryView()
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

#Preview {
    HomeView()
        .preferredColorScheme(.dark)
        .modelContainer(for: [CompoundProtocol.self, DoseLog.self, MediaDocument.self], inMemory: true)
}
