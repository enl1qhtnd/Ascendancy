import SwiftUI
import SwiftData
import PhotosUI

struct HomeView: View {
    @Query(
        filter: #Predicate<CompoundProtocol> { $0.statusRaw == "Active" },
        sort: CompoundProtocol.listSortDescriptors
    )
    private var activeProtocols: [CompoundProtocol]

    // Protocols contributing to the PK global active levels graph.
    // Includes active, paused, and completed — only archived is excluded,
    // so recently paused/completed compounds still appear in the decay curve.
    @Query(
        filter: #Predicate<CompoundProtocol> { $0.statusRaw != "Archived" },
        sort: CompoundProtocol.listSortDescriptors
    )
    private var levelProtocols: [CompoundProtocol]

    @Query private var recentLogs: [DoseLog]

    @StateObject private var healthKit = HealthKitService.shared
    @State private var showProfile = false

    @AppStorage("profileImageData") private var profileImageData: Data?
    @AppStorage("userName") private var userName: String = ""

    // Cached PK calculation
    @State private var combinedLevelData: [ActiveLevelDataPoint] = []
    @State private var pkRecalcTask: Task<Void, Never>? = nil

    // Track data version to avoid unnecessary recalculations
    @State private var lastPKDataFingerprint: Int? = nil

    init() {
        let logStartDate = Self.homeLogFetchStartDate()
        _recentLogs = Query(
            filter: #Predicate<DoseLog> { log in
                log.timestamp >= logStartDate
            },
            sort: \DoseLog.timestamp,
            order: .reverse
        )
    }

    private var pkDataFingerprint: Int {
        PKDataFingerprint.combined(protocols: levelProtocols)
    }

    private func recalculateCombinedLevels() {
        let snapshots = levelProtocols.map { protocol_ in
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

    private func schedulePKRecalc(delay: Duration = .milliseconds(300)) {
        let fingerprint = pkDataFingerprint
        guard fingerprint != lastPKDataFingerprint else {
            return // No change, skip recalculation
        }

        lastPKDataFingerprint = fingerprint

        pkRecalcTask?.cancel()
        pkRecalcTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            recalculateCombinedLevels()
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                headerBackground
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Top summary section: greeting + at-a-glance vitals
                        VStack(spacing: 20) {
                            headerView
                                .padding(.horizontal, 16)

                            HomeVitalsRow(
                                healthKit: healthKit,
                                protocolCount: activeProtocols.count
                            )
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 44)

                        // Cards — a black panel with rounded top corners, lifted to sit
                        // "above" the gradient header for a smooth transition.
                        VStack(spacing: 12) {
                            // 1. Active Protocols Tile
                            ActiveProtocolsTile(protocols: activeProtocols)

                            // 2. Next Dose + Bodyweight side-by-side
                            HStack(spacing: 12) {
                                CompactTodaysDoseTile(protocols: activeProtocols, logs: recentLogs)
                                CompactBodyweightTile(healthKit: healthKit)
                            }

                            // 3. Active Levels Graph Tile
                            ActiveLevelsTile(dataPoints: combinedLevelData, protocols: levelProtocols)

                            // 4. This Week Tile
                            ThisWeekTile(logs: recentLogs, protocols: Array(activeProtocols))

                            // 5. Pictures & Documents Tile (bottom)
                            PicturesDocumentsTile()

                            Spacer(minLength: 24)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity)
                        .background(Color.black)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 28,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 28,
                                style: .continuous
                            )
                        )
                        // Seam lift: only a short top cap casts the shadow (the opaque
                        // panel covers it), so the blur pass stays small instead of
                        // rasterizing the full-height panel silhouette every layout.
                        .background(alignment: .top) {
                            UnevenRoundedRectangle(
                                topLeadingRadius: 28,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 28,
                                style: .continuous
                            )
                            .fill(Color.black)
                            .frame(height: 60)
                            .shadow(color: .black.opacity(0.45), radius: 14, y: -2)
                        }
                        .padding(.top, -28)
                    }
                }
            }
            .sheet(isPresented: $showProfile) {
                ProfileSettingsView()
            }
        }
        .task {
            await healthKit.requestAuthorization()
            schedulePKRecalc(delay: .zero)
        }
        .onChange(of: pkDataFingerprint) {
            schedulePKRecalc()
        }
        .onDisappear {
            pkRecalcTask?.cancel()
        }
    }

    private static func homeLogFetchStartDate(referenceDate: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: referenceDate)
        return calendar.date(byAdding: .day, value: -8, to: today) ?? today
    }
    
    private var headerBackground: some View {
        ZStack(alignment: .top) {
            Color.black

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.12, blue: 0.46),
                        Color(red: 0.02, green: 0.05, blue: 0.18),
                        .black
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [
                        Color(red: 0.08, green: 0.26, blue: 0.70).opacity(0.6),
                        .clear
                    ],
                    center: UnitPoint(x: 0.22, y: -0.06),
                    startRadius: 0,
                    endRadius: 330
                )

                RadialGradient(
                    colors: [
                        Color(red: 0.08, green: 0.16, blue: 0.58).opacity(0.48),
                        .clear
                    ],
                    center: UnitPoint(x: 1.04, y: 0.02),
                    startRadius: 0,
                    endRadius: 350
                )

                RadialGradient(
                    colors: [
                        Color(red: 0.03, green: 0.18, blue: 0.45).opacity(0.32),
                        .clear
                    ],
                    center: UnitPoint(x: 0.52, y: 0.42),
                    startRadius: 0,
                    endRadius: 310
                )
            }
            .frame(height: 380)
            .clipped()
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .ascendancyFieldLabel()
                    .foregroundStyle(.white.opacity(0.4))
                Text(greetingText)
                    .font(AscendancyTheme.display(size: 28))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()

            Button {
                Haptics.tap()
                showProfile = true
            } label: {
                ZStack {
                    Circle()
                        .fill(AscendancyTheme.surfaceRaised)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
                        )

                    if let data = profileImageData {
                        ImageDataThumbnail(
                            id: profileImageThumbnailID(for: data),
                            data: data,
                            size: CGSize(width: 40, height: 40),
                            cornerRadius: 20
                        ) {
                            Color.clear
                        }
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }
    
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let base: String
        switch hour {
        case 0..<12: base = String(localized: "Good Morning")
        case 12..<17: base = String(localized: "Good Afternoon")
        default: base = String(localized: "Good Evening")
        }
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? base : "\(base), \(name)"
    }

    private func profileImageThumbnailID(for data: Data) -> Int {
        var hasher = Hasher()
        hasher.combine(data.count)
        for byte in data.prefix(16) {
            hasher.combine(byte)
        }
        for byte in data.suffix(16) {
            hasher.combine(byte)
        }
        return hasher.finalize()
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
                    valueFont: AscendancyTheme.dataValue(size: 32)
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

    var body: some View {
        let summary = todaySummary()

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

                if summary.rows.isEmpty {
                    Text("–")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.25))
                    Text("No doses today")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                } else if let (p, time) = summary.nextIncomplete {
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
                                summary.doneCount,
                                summary.rows.count
                            ))
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(time, format: .dateTime.hour().minute())
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("next")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                        if summary.moreIncompleteCount > 0 {
                            Text(String(format: String(localized: "(+%lld more)"), summary.moreIncompleteCount))
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
                            Text(String(format: String(localized: "%lld/%lld today"), summary.rows.count, summary.rows.count))
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("Done")
                            .font(.system(size: 22, weight: .semibold))
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
            DayScheduleSheet(protocols: protocols, initialDay: dayStart)
        }
    }

    private func todaySummary() -> TodaysDoseSummary {
        let currentRows = rows
        var doneCount = 0
        var incompleteCount = 0
        var nextIncomplete: (CompoundProtocol, Date)?

        for row in currentRows {
            if DoseScheduleDayHelper.isLogged(row.0, on: dayStart, logs: logs) {
                doneCount += 1
            } else {
                incompleteCount += 1
                if nextIncomplete == nil {
                    nextIncomplete = row
                }
            }
        }

        return TodaysDoseSummary(
            rows: currentRows,
            doneCount: doneCount,
            nextIncomplete: nextIncomplete,
            moreIncompleteCount: max(0, incompleteCount - 1)
        )
    }

    private struct TodaysDoseSummary {
        let rows: [(CompoundProtocol, Date)]
        let doneCount: Int
        let nextIncomplete: (CompoundProtocol, Date)?
        let moreIncompleteCount: Int
    }
}

// MARK: - Day Schedule Sheet

struct DayScheduleSheet: View {
    let protocols: [CompoundProtocol]
    @Query(sort: \DoseLog.timestamp, order: .reverse) private var logs: [DoseLog]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDay: Date

    init(protocols: [CompoundProtocol], initialDay: Date) {
        self.protocols = protocols
        _selectedDay = State(initialValue: Calendar.current.startOfDay(for: initialDay))
    }

    private var doses: [(CompoundProtocol, Date)] {
        DoseScheduleDayHelper.mergedRows(protocols: protocols, logs: logs, on: selectedDay)
    }

    private func actualLog(for p: CompoundProtocol) -> DoseLog? {
        logs
            .filter { $0.protocol_?.id == p.id && Calendar.current.isDate($0.timestamp, inSameDayAs: selectedDay) }
            .sorted { $0.timestamp < $1.timestamp }
            .last
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
                            .ascendancySectionHeading()
                            .foregroundStyle(.white.opacity(0.4))
                        Text(dayLabel)
                            .font(.system(size: 26, weight: .semibold))
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
                                let (p, scheduledDate) = pair
                                let done = DoseScheduleDayHelper.isLogged(p, on: selectedDay, logs: logs)
                                let logEntry = done ? actualLog(for: p) : nil
                                let displayTime = logEntry?.timestamp ?? scheduledDate
                                let displayDose = logEntry.map {
                                    "\($0.actualDoseAmount.formatted(.number.precision(.fractionLength(0...2)))) \($0.doseUnit.rawValue)"
                                } ?? "\(p.doseAmount.formatted(.number.precision(.fractionLength(0...2)))) \(p.doseUnit.rawValue)"
                                HStack(spacing: 14) {
                                    CategoryIcon(category: p.category, size: 38)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(p.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.white)
                                        Text(displayDose)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }

                                    Spacer()

                                    Text(displayTime, format: .dateTime.hour().minute())
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(.white)

                                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22))
                                        .foregroundStyle(done ? Color.green.opacity(0.9) : .white.opacity(0.2))
                                        .symbolRenderingMode(.hierarchical)
                                }
                                .opacity(done ? 0.55 : 1)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(AscendancyTheme.surfaceRaised)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    Text(healthKit.displayWeight(w).formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(healthKit.weightUnitIsLbs ? "lbs" : "kg")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }

                HStack(spacing: 4) {
                    let trend = healthKit.weightTrend7DayDisplay
                    Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(trend >= 0 ? Color.orange : Color.green)
                    Text(String(format: healthKit.weightUnitIsLbs ? String(localized: "%1$+.1f lbs") : String(localized: "%1$+.1f kg"), locale: .current, trend))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                    Text("7d")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
            } else {
                Text("–")
                    .font(.system(size: 26, weight: .semibold))
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
                Text("No compounds to display")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Combined")
                            .ascendancyFieldLabel(size: 10)
                            .foregroundStyle(.white.opacity(0.35))
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
                                .font(.system(size: 10, weight: .semibold))
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
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                
                HStack(spacing: 8) {
                    ForEach(documents.prefix(4)) { doc in
                        if let data = doc.imageData {
                            ImageDataThumbnail(
                                id: "\(doc.id.uuidString)-\(data.count)",
                                data: data,
                                size: CGSize(width: 54, height: 54),
                                cornerRadius: 6
                            ) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(AscendancyTheme.surfaceInset)
                                    .overlay(
                                        Image(systemName: "doc.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(.white.opacity(0.08))
                                    )
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill((doc.fileExtension == "pdf" ? Color.red : Color.white).opacity(0.08))
                                .frame(width: 54, height: 54)
                                .overlay(
                                    Image(systemName: doc.fileExtension == "pdf" ? "doc.text.fill" : "doc.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle((doc.fileExtension == "pdf" ? Color.red : Color.white).opacity(0.45))
                                )
                        }
                    }
                    
                    if documents.count < 4 {
                        ForEach(0..<(4 - min(documents.count, 4)), id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AscendancyTheme.surfaceInset)
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
