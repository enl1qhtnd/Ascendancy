import Foundation

// MARK: - Dose schedule rows (tile + sheet + week dots)

enum DoseScheduleDayHelper {

    // MARK: - Cache

    private struct CacheKey: Hashable {
        let protocolIds: Set<UUID>
        let logsHash: Int
        let dayStart: Date

        init(protocols: [CompoundProtocol], logs: [DoseLog], day: Date) {
            self.protocolIds = Set(protocols.map { $0.id })
            self.logsHash = logs.map { "\($0.id)-\($0.timestamp)" }.joined().hashValue
            self.dayStart = Calendar.current.startOfDay(for: day)
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
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)

        // Pre-filter logs to only those on the target day
        let relevantLogs = logs.filter { cal.isDate($0.timestamp, inSameDayAs: dayStart) }

        let extras: [(CompoundProtocol, Date)] = protocols.compactMap { p in
            guard !scheduledIds.contains(p.id) else { return nil }
            guard let latest = relevantLogs
                .filter({ $0.protocol_?.id == p.id })
                .map(\.timestamp)
                .max() else { return nil }
            return (p, latest)
        }

        let result = (scheduled + extras).sorted { $0.1 < $1.1 }
        mergedCache[cacheKey] = result
        evictOldestIfNeeded(&mergedCache)

        return result
    }

    static func isLogged(_ p: CompoundProtocol, on day: Date, logs: [DoseLog]) -> Bool {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        return logs.contains { log in
            log.protocol_?.id == p.id && cal.isDate(log.timestamp, inSameDayAs: dayStart)
        }
    }

    /// Clear all caches (call when protocols or logs are modified)
    static func clearCache() {
        scheduledCache.removeAll()
        mergedCache.removeAll()
    }
}
