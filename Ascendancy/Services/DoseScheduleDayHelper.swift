import Foundation

// MARK: - Dose schedule rows (tile + sheet + week dots)

enum DoseScheduleDayHelper {
    static func scheduledRows(protocols: [CompoundProtocol], on day: Date) -> [(CompoundProtocol, Date)] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let justBefore = start.addingTimeInterval(-1)
        return protocols.compactMap { p -> (CompoundProtocol, Date)? in
            guard let next = p.nextDoseDate(from: justBefore),
                  next >= start, next < end else { return nil }
            return (p, next)
        }.sorted { $0.1 < $1.1 }
    }

    static func mergedRows(protocols: [CompoundProtocol], logs: [DoseLog], on day: Date) -> [(CompoundProtocol, Date)] {
        let scheduled = scheduledRows(protocols: protocols, on: day)
        let scheduledIds = Set(scheduled.map { $0.0.id })
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let extras: [(CompoundProtocol, Date)] = protocols.compactMap { p in
            guard !scheduledIds.contains(p.id) else { return nil }
            guard let latest = logs
                .filter({ $0.protocol_?.id == p.id && cal.isDate($0.timestamp, inSameDayAs: dayStart) })
                .map(\.timestamp)
                .max() else { return nil }
            return (p, latest)
        }
        return (scheduled + extras).sorted { $0.1 < $1.1 }
    }

    static func isLogged(_ p: CompoundProtocol, on day: Date, logs: [DoseLog]) -> Bool {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        return logs.contains { log in
            log.protocol_?.id == p.id && cal.isDate(log.timestamp, inSameDayAs: dayStart)
        }
    }
}
