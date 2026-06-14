import Foundation

// MARK: - Dose schedule rows (tile + sheet + week dots)

enum DoseScheduleDayHelper {

    // MARK: - Cache

    private struct ProtocolFingerprint: Hashable {
        let id: UUID
        let scheduleData: Data?
        let startDate: Date
        let endDate: Date?
        let statusRaw: String

        init(_ protocol_: CompoundProtocol) {
            self.id = protocol_.id
            self.scheduleData = protocol_.scheduleData
            self.startDate = protocol_.startDate
            self.endDate = protocol_.endDate
            self.statusRaw = protocol_.statusRaw
        }
    }

    private struct CacheKey: Hashable {
        let protocols: [ProtocolFingerprint]
        let logsHash: Int
        let dayStart: Date

        init(protocols: [CompoundProtocol], logs: [DoseLog], day: Date) {
            self.protocols = protocols
                .map(ProtocolFingerprint.init)
                .sorted { $0.id.uuidString < $1.id.uuidString }

            let cal = Calendar.current
            let dayStart = cal.startOfDay(for: day)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            var hasher = Hasher()
            let dayLogs = logs
                .filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
                .sorted { $0.id.uuidString < $1.id.uuidString }

            for log in dayLogs {
                hasher.combine(log.id)
                hasher.combine(log.protocol_?.id)
                hasher.combine(log.timestamp)
            }
            self.logsHash = hasher.finalize()
            self.dayStart = dayStart
        }
    }

    private static var scheduledCache: [CacheKey: [(CompoundProtocol, Date)]] = [:]
    private static var mergedCache: [CacheKey: [(CompoundProtocol, Date)]] = [:]
    private static let maxCacheSize = 10

    private static func evictOldestIfNeeded<T>(_ cache: inout [CacheKey: T]) {
        if cache.count > maxCacheSize {
            // Simple eviction: remove first key (Swift dictionaries maintain insertion order in recent versions)
            if let firstKey = cache.keys.first {
                cache.removeValue(forKey: firstKey)
            }
        }
    }

    // MARK: - Log index

    /// Pre-buckets logs by (protocolId, day) so callers can answer
    /// "is this protocol logged on this day?" in O(1) instead of O(L).
    private struct LogIndex {
        /// protocolId → sorted timestamps of logs on the target day
        let byProtocolAndDay: [UUID: [Date]]

        init(logs: [DoseLog], on day: Date) {
            let cal = Calendar.current
            let dayStart = cal.startOfDay(for: day)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

            var bucketed: [UUID: [Date]] = [:]
            for log in logs where log.timestamp >= dayStart && log.timestamp < dayEnd {
                guard let pid = log.protocol_?.id else { continue }
                bucketed[pid, default: []].append(log.timestamp)
            }
            for key in bucketed.keys {
                bucketed[key]?.sort()
            }
            self.byProtocolAndDay = bucketed
        }
    }

    // MARK: - Public API

    static func scheduledRows(protocols: [CompoundProtocol], on day: Date) -> [(CompoundProtocol, Date)] {
        let cacheKey = CacheKey(protocols: protocols, logs: [], day: day)

        if let cached = scheduledCache[cacheKey] {
            return cached
        }

        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let justBefore = start.addingTimeInterval(-1)

        let result = protocols.compactMap { p -> (CompoundProtocol, Date)? in
            guard let next = p.nextDoseDate(from: justBefore),
                  next >= start, next < end else { return nil }
            return (p, next)
        }.sorted { $0.1 < $1.1 }

        scheduledCache[cacheKey] = result
        evictOldestIfNeeded(&scheduledCache)

        return result
    }

    static func mergedRows(protocols: [CompoundProtocol], logs: [DoseLog], on day: Date) -> [(CompoundProtocol, Date)] {
        let cacheKey = CacheKey(protocols: protocols, logs: logs, day: day)

        if let cached = mergedCache[cacheKey] {
            return cached
        }

        let scheduled = scheduledRows(protocols: protocols, on: day)
        let scheduledIds = Set(scheduled.map { $0.0.id })

        // Pre-bucket logs by (protocolId, day) so the extras loop is O(P) instead of O(P×L).
        let index = LogIndex(logs: logs, on: day)

        let extras: [(CompoundProtocol, Date)] = protocols.compactMap { p in
            guard !scheduledIds.contains(p.id) else { return nil }
            guard let latest = index.byProtocolAndDay[p.id]?.last else { return nil }
            return (p, latest)
        }

        let result = (scheduled + extras).sorted { $0.1 < $1.1 }
        mergedCache[cacheKey] = result
        evictOldestIfNeeded(&mergedCache)

        return result
    }

    static func isLogged(_ p: CompoundProtocol, on day: Date, logs: [DoseLog]) -> Bool {
        let index = LogIndex(logs: logs, on: day)
        return index.byProtocolAndDay[p.id] != nil
    }

    /// Clear all caches (call when protocols or logs are modified)
    static func clearCache() {
        scheduledCache.removeAll()
        mergedCache.removeAll()
    }
}
