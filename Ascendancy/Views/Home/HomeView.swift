import SwiftUI
import SwiftData
import PhotosUI

struct HomeView: View {
    @Query(filter: #Predicate<CompoundProtocol> { $0.statusRaw == "Active" })
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
    
    private func recalculateCombinedLevels() {
        let pairs = activeProtocols.map { p in (p, p.doseLogs) }
        combinedLevelData = PharmacokineticsEngine.combinedActiveLevel(
            protocols: pairs,
            startDate: Calendar.current.date(byAdding: .day, value: -14, to: Date()),
            endDate: Date()
        )
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
                            CompactNextDoseTile(protocols: activeProtocols)
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
            if healthKit.bodyWeightSamples.isEmpty {
                healthKit.loadMockData()
            }
            recalculateCombinedLevels()
        }
        .onChange(of: activeProtocols.count) {
            recalculateCombinedLevels()
        }
        .onChange(of: allLogs.count) {
            recalculateCombinedLevels()
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
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
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
                        Text("+\(protocols.count - maxShown) more")
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
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide))
    }
}

// MARK: - Bodyweight Tile

struct BodyweightTile: View {
    @ObservedObject var healthKit: HealthKitService
    
    var trend: Double {
        guard healthKit.bodyWeightSamples.count >= 7 else { return 0 }
        let last7 = Array(healthKit.bodyWeightSamples.suffix(7))
        let first = last7.first?.value ?? 0
        let last = last7.last?.value ?? 0
        return last - first
    }
    
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
                            Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(trend >= 0 ? Color.orange : Color.green)
                            Text(String(format: "%+.1f kg (7d)", trend))
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

// MARK: - Compact Next Dose Tile (half width)

struct CompactNextDoseTile: View {
    let protocols: [CompoundProtocol]
    @State private var showDaySchedule = false

    private var nextDoseProtocol: CompoundProtocol? {
        protocols
            .compactMap { p -> (CompoundProtocol, Date)? in
                guard let next = p.nextDoseDate() else { return nil }
                return (p, next)
            }
            .sorted { $0.1 < $1.1 }
            .first?.0
    }

    private var nextDoseDay: Date? {
        nextDoseProtocol.flatMap { $0.nextDoseDate() }
            .map { Calendar.current.startOfDay(for: $0) }
    }

    private var dosesToday: [(CompoundProtocol, Date)] {
        guard let day = nextDoseDay else { return [] }
        return protocols
            .compactMap { p -> (CompoundProtocol, Date)? in
                guard let next = p.nextDoseDate(),
                      Calendar.current.startOfDay(for: next) == day else { return nil }
                return (p, next)
            }
            .sorted { $0.1 < $1.1 }
    }

    var body: some View {
        Button { showDaySchedule = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TileHeader(icon: "clock.arrow.circlepath", title: "Next Dose")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }

                if let p = nextDoseProtocol, let nextDate = p.nextDoseDate() {
                    HStack(spacing: 8) {
                        CategoryIcon(category: p.category, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name.components(separatedBy: " ").first ?? p.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("\(p.doseAmount.formatted(.number.precision(.fractionLength(0...1)))) \(p.doseUnit.rawValue)")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(nextDate, format: .dateTime.hour().minute())
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(Calendar.current.isDateInToday(nextDate) ? "today" : "tmrw")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                        if dosesToday.count > 1 {
                            Text("(+\(dosesToday.count - 1) more)")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                } else {
                    Text("–")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.25))
                    Text("No upcoming dose")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDaySchedule) {
            DayScheduleSheet(doses: dosesToday)
        }
    }
}

// MARK: - Day Schedule Sheet

struct DayScheduleSheet: View {
    let doses: [(CompoundProtocol, Date)]
    @Environment(\.dismiss) private var dismiss

    private var dayLabel: String {
        guard let date = doses.first?.1 else { return "Schedule" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
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
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.35))
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                if doses.isEmpty {
                    Spacer()
                    Text("No doses scheduled")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(Array(doses.enumerated()), id: \.offset) { _, pair in
                                let (p, date) = pair
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
                                }
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
    
    var trend: Double {
        guard healthKit.bodyWeightSamples.count >= 7 else { return 0 }
        let last7 = Array(healthKit.bodyWeightSamples.suffix(7))
        return (last7.last?.value ?? 0) - (last7.first?.value ?? 0)
    }
    
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
                    Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(trend >= 0 ? Color.orange : Color.green)
                    Text(String(format: "%+.1f kg", trend))
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
    
    var currentPeak: Double {
        dataPoints.map(\.level).max() ?? 0
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
                        Text("\(protocols.count) compounds")
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
                        let stable = PharmacokineticsEngine.stableLevelInfo(for: p, logs: p.doseLogs)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(p.category.uiColor)
                                .frame(width: 6, height: 6)
                            Text(p.name.components(separatedBy: " ").first ?? p.name)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                            Text("\(Int(stable.percentage.rounded()))%")
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
        Button { showLibrary = true } label: {
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
