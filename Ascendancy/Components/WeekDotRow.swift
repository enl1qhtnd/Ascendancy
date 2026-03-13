import SwiftUI

// MARK: - Week Dot Row

struct WeekDotRow: View {
    let logs: [DoseLog]
    let protocols: [CompoundProtocol]
    
    private let calendar = Calendar.current
    
    var weekDays: [Date] {
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today) // 1=Sun
        let startOffset = -(weekday - 2) // Monday start
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
                                } else if status == .missed {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.7))
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
        case complete, missed, noDose, future
    }
    
    private func dayStatus(_ day: Date) -> DayStatus {
        let today = calendar.startOfDay(for: Date())
        let dayStart = calendar.startOfDay(for: day)
        
        if dayStart > today { return .future }
        
        // Get active protocols that should have had a dose this day
        let activeProtocols = protocols.filter { $0.status == .active && $0.startDate <= day }
        if activeProtocols.isEmpty { return .noDose }
        
        // Check if any dose was logged for any active protocol on this day
        let dayLogs = logs.filter {
            calendar.startOfDay(for: $0.timestamp) == dayStart
        }
        
        if dayLogs.isEmpty { return dayStart < today ? .missed : .future }
        return .complete
    }
    
    private func circleColor(_ status: DayStatus) -> Color {
        switch status {
        case .complete: return Color.green.opacity(0.8)
        case .missed: return Color.red.opacity(0.5)
        case .noDose: return Color.white.opacity(0.06)
        case .future: return Color.white.opacity(0.06)
        }
    }
    
    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return String(formatter.string(from: date).prefix(2))
    }
    
    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }
}
