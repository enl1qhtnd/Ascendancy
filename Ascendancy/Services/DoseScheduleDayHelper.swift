import Foundation

// MARK: - Dose schedule rows (tile + sheet + week dots)

enum DoseScheduleDayHelper {
    static func scheduledRows(protocols: [CompoundProtocol], on day: Date) -> [(CompoundProtocol, Date)] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let justBefore = start.addingTimeInterval(-1)

        var results: [(CompoundProtocol, Date)] = []
        results.reserveCapacity(protocols.count)

        for p in protocols {
            guard let next = p.nextDoseDate(from: justBefore),
                  next >= start, next < end else { continue }
            results.append((p, next))
        }

        return results.sorted { $0.1 < $1.1 }
    }

    static func mergedRows(protocols: [CompoundProtocol], logs: [DoseLog], on day: Date) -> [(CompoundProtocol, Date)] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)

        // Get scheduled protocols
        let scheduled = scheduledRows(protocols: protocols, on: day)
        let scheduledIds = Set(scheduled.map { $0.0.id })

        // Build a lookup map of protocol ID -> latest log timestamp for this day
        // This avoids O(n*m) complexity from filtering logs repeatedly
        var protocolToLatestLog: [UUID: Date] = [:]
        for log in logs {
            guard cal.isDate(log.timestamp, inSameDayAs: dayStart),
                  let protocolId = log.protocol_?.id else { continue }

            if let existing = protocolToLatestLog[protocolId] {
                if log.timestamp > existing {
                    protocolToLatestLog[protocolId] = log.timestamp
                }
            } else {
                protocolToLatestLog[protocolId] = log.timestamp
            }
        }

        // Find protocols with logs but no scheduled dose
        var extras: [(CompoundProtocol, Date)] = []
        extras.reserveCapacity(protocols.count - scheduledIds.count)

        for p in protocols {
            guard !scheduledIds.contains(p.id),
                  let latest = protocolToLatestLog[p.id] else { continue }
            extras.append((p, latest))
        }

        return (scheduled + extras).sorted { $0.1 < $1.1 }
    }

    static func isLogged(_ p: CompoundProtocol, on day: Date, logs: [DoseLog]) -> Bool {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)

        // Optimize: Direct iteration with early return
        for log in logs {
            if log.protocol_?.id == p.id && cal.isDate(log.timestamp, inSameDayAs: dayStart) {
                return true
            }
        }
        return false
    }
}
