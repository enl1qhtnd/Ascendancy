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
                    startRadius: 8,
                    endRadius: 150
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

private struct SmallDoseWidget: View {
    let snapshot: AscendancyWidgetSnapshot?
    let now: Date

    var body: some View {
        WidgetCard {
            WidgetHeader(title: "Next Dose", count: snapshot?.activeProtocolCount)

            if let snapshot {
                if snapshot.activeProtocolCount == 0 {
                    EmptyWidgetState(icon: "cross.vial", title: "No active protocols", subtitle: "Add one in Ascendancy")
                } else if let dose = snapshot.nextDose {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            CategoryBadge(categoryRaw: dose.categoryRaw, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(dose.protocolName)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(dose.doseText)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 0)

                        Text(statusLabel(for: dose, now: now))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(statusColor(for: dose, now: now))
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Text(primaryTimeLabel(for: dose.scheduledAt, now: now))
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)

                        ProgressSummary(snapshot: snapshot)
                    }
                } else {
                    EmptyWidgetState(icon: "checkmark.circle.fill", title: "All caught up", subtitle: todaySummary(snapshot))
                }
            } else {
                EmptyWidgetState(icon: "arrow.triangle.2.circlepath", title: "Open Ascendancy", subtitle: "Sync widget data")
            }
        }
    }
}

private struct MediumDoseWidget: View {
    let snapshot: AscendancyWidgetSnapshot?
    let now: Date

    var body: some View {
        WidgetCard {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    WidgetHeader(title: "Next Dose", count: snapshot?.activeProtocolCount)

                    if let snapshot, snapshot.activeProtocolCount > 0, let dose = snapshot.nextDose {
                        NextDoseHero(dose: dose, now: now)
                        Spacer(minLength: 0)
                        ProgressSummary(snapshot: snapshot)
                    } else if let snapshot, snapshot.activeProtocolCount == 0 {
                        EmptyWidgetState(icon: "cross.vial", title: "No active protocols", subtitle: "Add one in Ascendancy")
                    } else if let snapshot {
                        EmptyWidgetState(icon: "checkmark.circle.fill", title: "All caught up", subtitle: todaySummary(snapshot))
                    } else {
                        EmptyWidgetState(icon: "arrow.triangle.2.circlepath", title: "Open Ascendancy", subtitle: "Sync widget data")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    if let snapshot, !snapshot.lowInventoryItems.isEmpty {
                        SectionTitle(icon: "shippingbox.fill", title: "Low Stock")
                        ForEach(Array(snapshot.lowInventoryItems.prefix(2))) { item in
                            InventoryRow(item: item)
                        }
                    } else if let snapshot, !snapshot.upcomingDoses.dropFirst().isEmpty {
                        SectionTitle(icon: "calendar", title: "Up Next")
                        ForEach(Array(snapshot.upcomingDoses.dropFirst().prefix(2))) { dose in
                            UpcomingDoseRow(dose: dose, now: now)
                        }
                    } else {
                        SectionTitle(icon: "sparkles", title: "Status")
                        Text(snapshot == nil ? "Waiting for app data" : "Schedule is clear")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(2)
                    }
                }
                .frame(width: 118, alignment: .leading)
            }
        }
    }
}

private struct LargeDoseWidget: View {
    let snapshot: AscendancyWidgetSnapshot?
    let now: Date

    var body: some View {
        WidgetCard {
            WidgetHeader(title: "Ascendancy", count: snapshot?.activeProtocolCount)

            if let snapshot {
                if snapshot.activeProtocolCount == 0 {
                    EmptyWidgetState(icon: "cross.vial", title: "No active protocols", subtitle: "Create a protocol to populate your widget")
                    Spacer(minLength: 0)
                } else {
                    if let dose = snapshot.nextDose {
                        NextDoseHero(dose: dose, now: now)
                    } else {
                        EmptyWidgetState(icon: "checkmark.circle.fill", title: "All caught up", subtitle: todaySummary(snapshot))
                    }

                    ProgressSummary(snapshot: snapshot)

                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(icon: "calendar", title: "Upcoming")
                            ForEach(Array(snapshot.upcomingDoses.dropFirst().prefix(3))) { dose in
                                UpcomingDoseRow(dose: dose, now: now)
                            }
                            if snapshot.upcomingDoses.dropFirst().isEmpty {
                                Text("No more scheduled doses")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(icon: "shippingbox.fill", title: "Inventory")
                            if snapshot.lowInventoryItems.isEmpty {
                                Text("No low stock items")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.45))
                            } else {
                                ForEach(Array(snapshot.lowInventoryItems.prefix(3))) { item in
                                    InventoryRow(item: item)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer(minLength: 0)

                    Text("Updated \(snapshot.generatedAt, style: .time)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.32))
                }
            } else {
                EmptyWidgetState(icon: "arrow.triangle.2.circlepath", title: "Open Ascendancy", subtitle: "The app will publish your dose summary for this widget")
                Spacer(minLength: 0)
            }
        }
    }
}

private struct WidgetCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .foregroundStyle(.white)
    }
}

private struct WidgetHeader: View {
    let title: String
    let count: Int?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.62))
                .textCase(.uppercase)
                .tracking(0.7)
            Spacer(minLength: 4)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.9), in: Capsule())
            }
        }
    }
}

private struct NextDoseHero: View {
    let dose: AscendancyWidgetDose
    let now: Date

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CategoryBadge(categoryRaw: dose.categoryRaw, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusLabel(for: dose, now: now))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(statusColor(for: dose, now: now))
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(primaryTimeLabel(for: dose.scheduledAt, now: now))
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                Text("\(dose.protocolName) - \(dose.doseText)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
        }
    }
}

private struct ProgressSummary: View {
    let snapshot: AscendancyWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Today")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 4)
                Text(todaySummary(snapshot))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }
            WidgetProgressBar(value: snapshot.todayProgress)
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
        .frame(height: 5)
    }
}

private struct SectionTitle: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.55)
        }
        .foregroundStyle(.white.opacity(0.46))
    }
}

private struct UpcomingDoseRow: View {
    let dose: AscendancyWidgetDose
    let now: Date

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(categoryColor(for: dose.categoryRaw))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(dose.protocolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                Text("\(secondaryDateLabel(for: dose.scheduledAt, now: now)) - \(dose.doseText)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }
        }
    }
}

private struct InventoryRow: View {
    let item: AscendancyWidgetInventoryItem

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(categoryColor(for: item.categoryRaw))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.protocolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                Text(item.daysRemainingText.map { "\(item.remainingText) - \($0)" } ?? item.remainingText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.orange.opacity(0.76))
                    .lineLimit(1)
            }
        }
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

private struct EmptyWidgetState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(2)
            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private extension AscendancyWidgetSnapshot {
    var todayProgress: Double {
        guard todayDoseCount > 0 else { return 1 }
        return Double(todayLoggedCount) / Double(todayDoseCount)
    }
}

private func todaySummary(_ snapshot: AscendancyWidgetSnapshot) -> String {
    guard snapshot.todayDoseCount > 0 else { return "No doses today" }
    return "\(snapshot.todayLoggedCount)/\(snapshot.todayDoseCount) logged"
}

private func statusLabel(for dose: AscendancyWidgetDose, now: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDate(dose.scheduledAt, inSameDayAs: now), dose.scheduledAt <= now, !dose.isLoggedToday {
        return "Due"
    }
    if calendar.isDate(dose.scheduledAt, inSameDayAs: now) {
        return "Today"
    }
    if calendar.isDateInTomorrow(dose.scheduledAt) {
        return "Tomorrow"
    }
    return dose.scheduledAt.formatted(.dateTime.weekday(.abbreviated))
}

private func primaryTimeLabel(for date: Date, now: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDate(date, inSameDayAs: now) {
        return date.formatted(.dateTime.hour().minute())
    }
    if calendar.isDateInTomorrow(date) {
        return "Tomorrow"
    }
    return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
}

private func secondaryDateLabel(for date: Date, now: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDate(date, inSameDayAs: now) {
        return date.formatted(.dateTime.hour().minute())
    }
    if calendar.isDateInTomorrow(date) {
        return "Tomorrow " + date.formatted(.dateTime.hour().minute())
    }
    return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
}

private func statusColor(for dose: AscendancyWidgetDose, now: Date) -> Color {
    let calendar = Calendar.current
    if calendar.isDate(dose.scheduledAt, inSameDayAs: now), dose.scheduledAt <= now, !dose.isLoggedToday {
        return .orange
    }
    return .white.opacity(0.58)
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
