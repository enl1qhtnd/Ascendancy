import SwiftUI

// MARK: - Week Dot Row

struct WeekDotRow: View {
    let logs: [DoseLog]
    let protocols: [CompoundProtocol]
    
    private let calendar = Calendar.current
    
    var weekDays: [Date] {
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today) // 1=Sun
        let startOffset = -(weekday - 1) // Sunday start
        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: startOffset + $0, to: today)
        }
    }
    
    var body: some View {
        let days = weekDays
        // Bucket the week's logs into [dayStart: Set<protocolID>] in a single O(L)
        // pass, so dayStatus answers "is this protocol logged on this day?" with a
        // set lookup instead of rebuilding a full LogIndex over every log for each
        // protocol on each of the 7 days.
        let loggedByDay = loggedProtocolIDsByDay(in: days)
        return HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                VStack(spacing: 5) {
                    Text(dayLabel(day))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))

                    let status = dayStatus(day, loggedIDs: loggedByDay[calendar.startOfDay(for: day)] ?? [])
                    Circle()
                        .fill(circleColor(status))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(isToday(day) ? 0.4 : 0), lineWidth: 1.5)
                        )
                        .overlay(
                            Group {
                                if status == .complete {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                } else if status == .partial {
                                    Image(systemName: "minus")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                } else if status == .missed {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                } else if status == .noDose {
                                    Image(systemName: "minus")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.3))
                                } else {
                                    Image(systemName: "circle.dotted")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                            }
                        )
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private enum DayStatus {
        case complete, partial, missed, noDose, future
    }
    
    /// Maps each day in the week to the set of protocol IDs that have at least one
    /// log on that day. Mirrors `DoseScheduleDayHelper.isLogged` (logged == a log
    /// exists for the protocol on that day) but computes the whole week in one pass.
    private func loggedProtocolIDsByDay(in days: [Date]) -> [Date: Set<UUID>] {
        let dayStarts = Set(days.map { calendar.startOfDay(for: $0) })
        var result: [Date: Set<UUID>] = [:]
        for log in logs {
            guard let pid = log.protocol_?.id else { continue }
            let dayStart = calendar.startOfDay(for: log.timestamp)
            guard dayStarts.contains(dayStart) else { continue }
            result[dayStart, default: []].insert(pid)
        }
        return result
    }

    private func dayStatus(_ day: Date, loggedIDs: Set<UUID>) -> DayStatus {
        let today = calendar.startOfDay(for: Date())
        let dayStart = calendar.startOfDay(for: day)

        if dayStart > today { return .future }

        let activeForDay = protocols.filter { p in
            guard p.status == .active, p.startDate <= day else { return false }
            if let end = p.endDate, calendar.startOfDay(for: end) < dayStart { return false }
            return true
        }
        if activeForDay.isEmpty { return .noDose }

        let rows = DoseScheduleDayHelper.mergedRows(protocols: activeForDay, logs: logs, on: day)
        if rows.isEmpty { return .noDose }

        let allLogged = rows.allSatisfy { loggedIDs.contains($0.0.id) }
        if allLogged { return .complete }

        if dayStart < today {
            let partiallyLogged = rows.contains { loggedIDs.contains($0.0.id) }
            if partiallyLogged { return .partial }
            return .missed
        }

        return .future
    }
    
    private func circleColor(_ status: DayStatus) -> Color {
        switch status {
        case .complete: return Color.green.opacity(0.8)
        case .partial: return Color(red: 0.45, green: 0.78, blue: 1.0).opacity(0.85)
        case .missed: return Color.red.opacity(0.5)
        case .noDose: return AscendancyTheme.surfaceRaised
        case .future: return AscendancyTheme.surfaceRaised
        }
    }
    
    private func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.narrow))
    }
    
    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }
}
