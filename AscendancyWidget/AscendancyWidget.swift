import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> AscendancyWidgetEntry {
        AscendancyWidgetEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (AscendancyWidgetEntry) -> Void) {
        completion(AscendancyWidgetEntry(date: Date(), snapshot: AscendancyWidgetShared.loadSnapshot() ?? .preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AscendancyWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = AscendancyWidgetShared.loadSnapshot()
        let entry = AscendancyWidgetEntry(date: now, snapshot: snapshot)
        completion(Timeline(entries: [entry], policy: .after(nextRefreshDate(for: snapshot, from: now))))
    }

    private func nextRefreshDate(for snapshot: AscendancyWidgetSnapshot?, from now: Date) -> Date {
        let fallback = now.addingTimeInterval(snapshot == nil ? 15 * 60 : 60 * 60)
        guard let nextDoseDate = snapshot?.upcomingDoses
            .map(\.scheduledAt)
            .filter({ $0 > now })
            .min() else {
            return fallback
        }

        let afterDose = nextDoseDate.addingTimeInterval(60)
        let minimumRefresh = now.addingTimeInterval(5 * 60)
        return min(fallback, max(afterDose, minimumRefresh))
    }
}

struct AscendancyWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: AscendancyWidgetSnapshot?
}

struct AscendancyWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: AscendancyWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallDoseWidget(snapshot: entry.snapshot, now: entry.date)
            case .systemLarge:
                LargeDoseWidget(snapshot: entry.snapshot, now: entry.date)
            default:
                MediumDoseWidget(snapshot: entry.snapshot, now: entry.date)
            }
        }
        .containerBackground(for: .widget) {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.05, blue: 0.08), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color.white.opacity(0.16), Color.clear],
                    center: .topTrailing,
                    startRadius: 12,
                    endRadius: 180
                )
            }
        }
    }
}

@main
struct AscendancyWidget: Widget {
    let kind: String = AscendancyWidgetShared.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AscendancyWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Next Dose")
        .description("Track your next scheduled dose, today's progress, and low inventory from the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Size tokens

private enum WidgetSize {
    case small, medium, large

    var padding: CGFloat {
        switch self {
        case .small, .medium: return 12
        case .large: return 14
        }
    }

    var heroBadge: CGFloat {
        switch self {
        case .small, .medium: return 30
        case .large: return 44
        }
    }

    var heroTime: CGFloat {
        switch self {
        case .small, .medium: return 26
        case .large: return 32
        }
    }

    var rowDot: CGFloat {
        self == .small ? 6 : 8
    }

    var blockSpacing: CGFloat {
        self == .large ? 10 : 8
    }

    var emptyIcon: CGFloat {
        switch self {
        case .small: return 22
        case .medium: return 26
        case .large: return 30
        }
    }

    var heroInnerSpacing: CGFloat {
        self == .large ? 8 : 6
    }

    var compactHero: Bool {
        self != .large
    }
}

// MARK: - Size widgets

private struct SmallDoseWidget: View {
    let snapshot: AscendancyWidgetSnapshot?
    let now: Date

    private let size = WidgetSize.small

    var body: some View {
        WidgetCard(size: size) {
            WidgetHeader(title: "Next Dose", count: snapshot?.activeProtocolCount, size: size)

            if let snapshot {
                if snapshot.activeProtocolCount == 0 {
                    EmptyWidgetState(icon: "cross.vial", title: "No active protocols", subtitle: "Add one in Ascendancy", size: size)
                } else if let dose = snapshot.nextDose {
                    NextDoseHero(dose: dose, now: now, size: size)
                    Spacer(minLength: 0)
                    if snapshot.todayDoseCount > 0 {
                        ProgressStrip(snapshot: snapshot, size: size)
                    }
                } else {
                    EmptyWidgetState(icon: "checkmark.circle.fill", title: "All caught up", subtitle: todaySummary(snapshot), size: size)
                }
            } else {
                EmptyWidgetState(icon: "arrow.triangle.2.circlepath", title: "Open Ascendancy", subtitle: "Sync widget data", size: size)
            }
        }
    }
}

private struct MediumDoseWidget: View {
    let snapshot: AscendancyWidgetSnapshot?
    let now: Date

    private let size = WidgetSize.medium

    var body: some View {
        WidgetCard(size: size) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: size.blockSpacing) {
                    WidgetHeader(title: "Next Dose", count: snapshot?.activeProtocolCount, size: size)
                    primaryContent
                    Spacer(minLength: 0)
                    if let snapshot, snapshot.activeProtocolCount > 0, snapshot.nextDose != nil, snapshot.todayDoseCount > 0 {
                        ProgressStrip(snapshot: snapshot, size: size)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 0.5)

                VStack(alignment: .leading, spacing: 8) {
                    secondaryContent
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var primaryContent: some View {
        if let snapshot, snapshot.activeProtocolCount > 0, let dose = snapshot.nextDose {
            NextDoseHero(dose: dose, now: now, size: size)
        } else if let snapshot, snapshot.activeProtocolCount == 0 {
            EmptyWidgetState(icon: "cross.vial", title: "No active protocols", subtitle: "Add one in Ascendancy", size: size)
        } else if let snapshot {
            EmptyWidgetState(icon: "checkmark.circle.fill", title: "All caught up", subtitle: todaySummary(snapshot), size: size)
        } else {
            EmptyWidgetState(icon: "arrow.triangle.2.circlepath", title: "Open Ascendancy", subtitle: "Sync widget data", size: size)
        }
    }

    @ViewBuilder
    private var secondaryContent: some View {
        if let snapshot, !snapshot.lowInventoryItems.isEmpty {
            SectionTitle(icon: "shippingbox.fill", title: "Low Stock")
            ForEach(Array(snapshot.lowInventoryItems.prefix(2))) { item in
                SecondaryRow(kind: .inventory(item), size: size)
            }
        } else if let snapshot, !snapshot.upcomingDoses.dropFirst().isEmpty {
            let remaining = Array(snapshot.upcomingDoses.dropFirst())
            let displayed = Array(remaining.prefix(3))
            SectionTitle(icon: "calendar", title: "Up Next")
            ForEach(displayed) { dose in
                SecondaryRow(kind: .dose(dose, now), size: size)
            }
            MoreTodayLabel(remaining: remaining, displayed: displayed, now: now)
        } else {
            SectionTitle(icon: "sparkles", title: "Status")
            Text(catalogKey: snapshot == nil ? "Waiting for app data" : "Schedule is clear")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(3)
        }
    }
}

private struct LargeDoseWidget: View {
    let snapshot: AscendancyWidgetSnapshot?
    let now: Date

    private let size = WidgetSize.large

    var body: some View {
        WidgetCard(size: size) {
            WidgetHeader(title: "Next Dose", count: snapshot?.activeProtocolCount, size: size)

            if let snapshot {
                if snapshot.activeProtocolCount == 0 {
                    EmptyWidgetState(icon: "cross.vial", title: "No active protocols", subtitle: "Create a protocol to populate your widget", size: size)
                    Spacer(minLength: 0)
                } else {
                    if let dose = snapshot.nextDose {
                        NextDoseHero(dose: dose, now: now, size: size)
                    } else {
                        EmptyWidgetState(icon: "checkmark.circle.fill", title: "All caught up", subtitle: todaySummary(snapshot), size: size)
                    }

                    ProgressStrip(snapshot: snapshot, size: size)

                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 0.5)
                        .padding(.vertical, 2)

                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(icon: "calendar", title: "Up Next")
                            if snapshot.upcomingDoses.dropFirst().isEmpty {
                                Text(catalogKey: "No more scheduled doses")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.45))
                            } else {
                                let remaining = Array(snapshot.upcomingDoses.dropFirst())
                                let displayed = Array(remaining.prefix(3))
                                ForEach(displayed) { dose in
                                    SecondaryRow(kind: .dose(dose, now), size: size)
                                }
                                MoreTodayLabel(remaining: remaining, displayed: displayed, now: now)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(icon: "shippingbox.fill", title: "Inventory")
                            if snapshot.lowInventoryItems.isEmpty {
                                Text(catalogKey: "No low stock items")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.45))
                            } else {
                                ForEach(Array(snapshot.lowInventoryItems.prefix(3))) { item in
                                    SecondaryRow(kind: .inventory(item), size: size)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer(minLength: 0)
                }
            } else {
                EmptyWidgetState(icon: "arrow.triangle.2.circlepath", title: "Open Ascendancy", subtitle: "The app will publish your dose summary for this widget", size: size)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Card chrome

private struct WidgetCard<Content: View>: View {
    let size: WidgetSize
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: size.blockSpacing) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(size.padding)
        .foregroundStyle(.white)
    }
}

private struct WidgetHeader: View {
    let title: String
    let count: Int?
    let size: WidgetSize

    private var titleSize: CGFloat { size == .small ? 10 : 11 }

    var body: some View {
        HStack(spacing: 6) {
            Text(catalogKey: title)
                .font(AscendancyTheme.cardLabel(size: titleSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(AscendancyTheme.labelTracking)
            Spacer(minLength: 4)
            if let count, count > 0 {
                Text("\(count)")
                    .font(AscendancyTheme.meta(size: titleSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
            }
        }
    }
}

// MARK: - Hero

private struct NextDoseHero: View {
    let dose: AscendancyWidgetDose
    let now: Date
    let size: WidgetSize

    var body: some View {
        VStack(alignment: .leading, spacing: size.heroInnerSpacing) {
            HStack(spacing: 8) {
                CategoryBadge(categoryRaw: dose.categoryRaw, size: size.heroBadge)
                StatusPill(dose: dose, now: now)
                Spacer(minLength: 0)
            }

            Text(primaryTimeLabel(for: dose.scheduledAt, now: now))
                .font(AscendancyTheme.display(size: size.heroTime, weight: .semibold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            heroSubtitle
        }
    }

    @ViewBuilder
    private var heroSubtitle: some View {
        if size.compactHero {
            Text("\(dose.protocolName) · \(dose.doseText)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(dose.protocolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Text(dose.doseText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Status pill

private struct StatusPill: View {
    let dose: AscendancyWidgetDose
    let now: Date

    private enum Style {
        case due
        case today(Color)
        case later

        var fill: Color {
            switch self {
            case .due: return .orange.opacity(0.92)
            case .today(let tint): return tint.opacity(0.18)
            case .later: return .white.opacity(0.08)
            }
        }

        var stroke: Color {
            switch self {
            case .due: return .orange
            case .today(let tint): return tint.opacity(0.55)
            case .later: return .white.opacity(0.18)
            }
        }

        var text: Color {
            switch self {
            case .due: return .white
            case .today: return .white.opacity(0.92)
            case .later: return .white.opacity(0.6)
            }
        }
    }

    private var style: Style {
        let calendar = Calendar.current
        if calendar.isDate(dose.scheduledAt, inSameDayAs: now), dose.scheduledAt <= now, !dose.isLoggedToday {
            return .due
        }
        if calendar.isDate(dose.scheduledAt, inSameDayAs: now) {
            return .today(categoryColor(for: dose.categoryRaw))
        }
        return .later
    }

    var body: some View {
        Text(LocalizedStringKey(statusLabel(for: dose, now: now)))
            .font(.system(size: 9, weight: .heavy))
            .tracking(AscendancyTheme.labelTracking)
            .foregroundStyle(style.text)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(style.fill))
            .overlay(Capsule().strokeBorder(style.stroke, lineWidth: 0.5))
    }
}

// MARK: - Progress strip

private struct ProgressStrip: View {
    let snapshot: AscendancyWidgetSnapshot
    let size: WidgetSize

    var body: some View {
        if size.compactHero {
            HStack(spacing: 8) {
                WidgetProgressBar(value: snapshot.todayProgress)
                Text(progressShort(snapshot))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .monospacedDigit()
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(catalogKey: "Today")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(AscendancyTheme.labelTracking)
                    Spacer(minLength: 4)
                    Text(todaySummary(snapshot))
                        .font(AscendancyTheme.meta(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .monospacedDigit()
                }
                WidgetProgressBar(value: snapshot.todayProgress)
            }
        }
    }
}

private struct WidgetProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.12))
                Capsule()
                    .fill(.white.opacity(0.86))
                    .frame(width: max(4, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Section + Row

private struct SectionTitle: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(catalogKey: title)
                .font(AscendancyTheme.meta(size: 10, weight: .medium))
                .tracking(AscendancyTheme.labelTracking)
        }
        .foregroundStyle(.white.opacity(0.46))
    }
}

private enum SecondaryRowKind {
    case dose(AscendancyWidgetDose, Date)
    case inventory(AscendancyWidgetInventoryItem)
}

private struct MoreTodayLabel: View {
    let remaining: [AscendancyWidgetDose]
    let displayed: [AscendancyWidgetDose]
    let now: Date

    private var extraToday: Int {
        let calendar = Calendar.current
        let displayedIDs = Set(displayed.map(\.id))
        return remaining.filter { dose in
            calendar.isDate(dose.scheduledAt, inSameDayAs: now) && !displayedIDs.contains(dose.id)
        }.count
    }

    var body: some View {
        if extraToday > 0 {
            Text(String(format: String(localized: "+%lld more today"), extraToday))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(AscendancyTheme.labelTracking)
        }
    }
}

private struct SecondaryRow: View {
    let kind: SecondaryRowKind
    let size: WidgetSize

    var body: some View {
        HStack(spacing: 8) {
            CategoryDot(categoryRaw: categoryRaw, size: size.rowDot)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                Text(meta)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(metaColor)
                    .lineLimit(1)
            }
        }
    }

    private var categoryRaw: String {
        switch kind {
        case .dose(let dose, _): return dose.categoryRaw
        case .inventory(let item): return item.categoryRaw
        }
    }

    private var title: String {
        switch kind {
        case .dose(let dose, _): return dose.protocolName
        case .inventory(let item): return item.protocolName
        }
    }

    private var meta: String {
        switch kind {
        case .dose(let dose, let now):
            return "\(secondaryDateLabel(for: dose.scheduledAt, now: now)) · \(dose.doseText)"
        case .inventory(let item):
            return item.daysRemainingText.map { "\(item.remainingText) · \($0)" } ?? item.remainingText
        }
    }

    private var metaColor: Color {
        switch kind {
        case .dose: return Color.white.opacity(0.45)
        case .inventory: return Color.orange.opacity(0.78)
        }
    }
}

private struct CategoryDot: View {
    let categoryRaw: String
    let size: CGFloat

    var body: some View {
        let color = categoryColor(for: categoryRaw)
        Circle()
            .fill(color.opacity(0.22))
            .overlay(
                Circle().strokeBorder(color.opacity(0.55), lineWidth: 0.5)
            )
            .frame(width: size, height: size)
    }
}

private struct CategoryBadge: View {
    let categoryRaw: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(categoryColor(for: categoryRaw).opacity(0.18))
            Circle()
                .strokeBorder(categoryColor(for: categoryRaw).opacity(0.45), lineWidth: 1)
            Image(systemName: categoryIcon(for: categoryRaw))
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(categoryColor(for: categoryRaw))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Empty state

private struct EmptyWidgetState: View {
    let icon: String
    let title: String
    let subtitle: String
    let size: WidgetSize

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: size.emptyIcon, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
            Text(catalogKey: title)
                .font(.system(size: size == .large ? 15 : 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(catalogKey: subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Helpers

private extension AscendancyWidgetSnapshot {
    var todayProgress: Double {
        guard todayDoseCount > 0 else { return 1 }
        return Double(todayLoggedCount) / Double(todayDoseCount)
    }
}

private func todaySummary(_ snapshot: AscendancyWidgetSnapshot) -> String {
    guard snapshot.todayDoseCount > 0 else { return String(localized: "No doses today") }
    return String(
        format: String(localized: "%1$lld/%2$lld logged"),
        snapshot.todayLoggedCount,
        snapshot.todayDoseCount
    )
}

private func progressShort(_ snapshot: AscendancyWidgetSnapshot) -> String {
    "\(snapshot.todayLoggedCount)/\(snapshot.todayDoseCount)"
}

private func statusLabel(for dose: AscendancyWidgetDose, now: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDate(dose.scheduledAt, inSameDayAs: now), dose.scheduledAt <= now, !dose.isLoggedToday {
        return String(localized: "Due")
    }
    if calendar.isDate(dose.scheduledAt, inSameDayAs: now) {
        return String(localized: "Today")
    }
    if calendar.isDateInTomorrow(dose.scheduledAt) {
        return String(localized: "Tomorrow")
    }
    return dose.scheduledAt.formatted(.dateTime.weekday(.abbreviated))
}

private func primaryTimeLabel(for date: Date, now: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDate(date, inSameDayAs: now) {
        return date.formatted(.dateTime.hour().minute())
    }
    if calendar.isDateInTomorrow(date) {
        return date.formatted(.dateTime.hour().minute())
    }
    return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
}

private func secondaryDateLabel(for date: Date, now: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDate(date, inSameDayAs: now) {
        return date.formatted(.dateTime.hour().minute())
    }
    if calendar.isDateInTomorrow(date) {
        return String(
            format: String(localized: "Tomorrow %@"),
            date.formatted(.dateTime.hour().minute())
        )
    }
    return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
}

private func categoryColor(for rawValue: String) -> Color {
    switch rawValue {
    case "Medication":
        return Color(red: 0.45, green: 0.75, blue: 1.0)
    case "Peptide":
        return Color(white: 0.92)
    case "TRT":
        return Color(red: 0.15, green: 0.30, blue: 0.70)
    case "Custom":
        return Color(red: 0.2, green: 0.8, blue: 0.75)
    default:
        return Color(white: 0.7)
    }
}

private func categoryIcon(for rawValue: String) -> String {
    switch rawValue {
    case "Medication": return "pills.fill"
    case "Peptide": return "syringe.fill"
    case "TRT": return "cross.vial.fill"
    case "Custom": return "testtube.2"
    default: return "cross.vial.fill"
    }
}

private extension Text {
    init(catalogKey string: String) {
        self.init(LocalizedStringKey(string))
    }
}
