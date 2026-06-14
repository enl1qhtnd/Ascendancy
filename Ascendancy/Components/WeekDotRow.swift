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
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { day in
                VStack(spacing: 5) {
                    Text(dayLabel(day))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                    
                    let status = dayStatus(day)
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
    
    private func dayStatus(_ day: Date) -> DayStatus {
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

        let allLogged = rows.allSatisfy {
            DoseScheduleDayHelper.isLogged($0.0, on: dayStart, logs: logs)
        }
        if allLogged { return .complete }

        if dayStart < today {
            let partiallyLogged = rows.contains {
                DoseScheduleDayHelper.isLogged($0.0, on: dayStart, logs: logs)
            }
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
