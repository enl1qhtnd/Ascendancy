import Foundation

struct ActiveLevelDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let level: Double   // Normalized concentration (arbitrary units from dose)
}

// MARK: - Performance Cache

/// Cache key for pharmacokinetics calculations
private struct PKCacheKey: Hashable {
    let protocolId: UUID
    let logsHash: Int
    let startDate: Date
    let endDate: Date
    let resolution: Int

    init(protocol_: CompoundProtocol, logs: [DoseLog], startDate: Date, endDate: Date, resolution: Int) {
        self.protocolId = protocol_.id
        self.logsHash = logs.map { "\($0.id)-\($0.timestamp)-\($0.actualDoseAmount)" }.joined().hashValue
        self.startDate = startDate
        self.endDate = endDate
        self.resolution = resolution
    }
}

/// Simple LRU cache for PK calculations (thread-safe with NSLock)
private final class PKCache {
    private var cache: [PKCacheKey: [ActiveLevelDataPoint]] = [:]
    private var accessOrder: [PKCacheKey] = []
    private let maxSize = 20
    private let lock = NSLock()

    func get(_ key: PKCacheKey) -> [ActiveLevelDataPoint]? {
        lock.lock()
        defer { lock.unlock() }

        if let value = cache[key] {
            // Update access order
            accessOrder.removeAll { $0 == key }
            accessOrder.append(key)
            return value
        }
        return nil
    }

    func set(_ key: PKCacheKey, value: [ActiveLevelDataPoint]) {
        lock.lock()
        defer { lock.unlock() }

        cache[key] = value
        accessOrder.append(key)

        // Evict oldest if over capacity
        if accessOrder.count > maxSize {
            let oldest = accessOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }

        cache.removeAll()
        accessOrder.removeAll()
    }
}

/// Encapsulates steady-state (stable level) progress for a protocol.
struct StableLevelInfo {
    /// % of steady state reached (0–100). Steady state ≈ 97% at 5 × half-life.
    let percentage: Double
    /// Hours elapsed since the protocol's first dose
    let hoursOnProtocol: Double
    /// Number of half-lives elapsed
    let halfLivesElapsed: Double
    /// True when ≥ 5 half-lives have elapsed (clinically "stable")
    var isStable: Bool { halfLivesElapsed >= 5 }
}

/// Core pharmacokinetics engine using first-order exponential decay.
/// Each dose contributes decaying concentration; stacking occurs naturally.
enum PharmacokineticsEngine {

    // MARK: - Shared Cache

    private static let cache = PKCache()

    // MARK: - Public API

    /// Calculate active level time series for a protocol given its dose logs.
    /// - Parameters:
    ///   - protocol_: The compound protocol (provides half-life, dose amount, start date)
    ///   - logs: All dose logs for this protocol, sorted by timestamp ascending
    ///   - startDate: Display window start date
    ///   - endDate: Display window end date
    ///   - resolution: Number of data points to generate
    ///   - useCache: Whether to use caching (default: true)
    /// - Returns: Array of ActiveLevelDataPoint suitable for charting
    static func activeLevel(
        for protocol_: CompoundProtocol,
        logs: [DoseLog],
        startDate: Date? = nil,
        endDate: Date = Date(),
        resolution: Int = 120,
        useCache: Bool = true
    ) -> [ActiveLevelDataPoint] {

        let halfLifeHours = protocol_.halfLifeInHours
        guard halfLifeHours > 0 else { return [] }

        // Use protocol start date or earliest log date as display window start
        let windowStart = startDate ?? min(protocol_.startDate, endDate.addingTimeInterval(-30 * 86400))
        let windowEnd = endDate

        guard windowStart < windowEnd else { return [] }

        // Check cache
        if useCache {
            let cacheKey = PKCacheKey(protocol_: protocol_, logs: logs, startDate: windowStart, endDate: windowEnd, resolution: resolution)
            if let cached = cache.get(cacheKey) {
                return cached
            }
        }

        let totalInterval = windowEnd.timeIntervalSince(windowStart)
        let step = totalInterval / Double(resolution - 1)

        // Pre-sort logs once (avoid sorting on every call)
        let sortedLogs = logs.sorted { $0.timestamp < $1.timestamp }

        var points = [ActiveLevelDataPoint]()
        points.reserveCapacity(resolution)

        // Pre-calculate decay constant
        let kDecay = log(2) / halfLifeHours

        for i in 0..<resolution {
            let t = windowStart.addingTimeInterval(Double(i) * step)
            var totalLevel: Double = 0

            for entry in sortedLogs {
                guard entry.timestamp <= t else { break }
                let hoursSinceDose = t.timeIntervalSince(entry.timestamp) / 3600.0
                let contribution = entry.actualDoseAmount * exp(-kDecay * hoursSinceDose)
                totalLevel += contribution
            }

            points.append(ActiveLevelDataPoint(date: t, level: totalLevel))
        }

        // Cache result
        if useCache {
            let cacheKey = PKCacheKey(protocol_: protocol_, logs: logs, startDate: windowStart, endDate: windowEnd, resolution: resolution)
            cache.set(cacheKey, value: points)
        }

        return points
    }

    /// Clear the calculation cache (call when protocols or logs are modified)
    static func clearCache() {
        cache.clear()
    }
    
    /// Quick current level snapshot
    static func currentLevel(for protocol_: CompoundProtocol, logs: [DoseLog]) -> Double {
        let halfLifeHours = protocol_.halfLifeInHours
        guard halfLifeHours > 0 else { return 0 }
        
        let now = Date()
        let kDecay = log(2) / halfLifeHours
        
        return logs.reduce(0.0) { total, entry in
            guard entry.timestamp <= now else { return total }
            let hoursSinceDose = now.timeIntervalSince(entry.timestamp) / 3600.0
            return total + entry.actualDoseAmount * exp(-kDecay * hoursSinceDose)
        }
    }
    
    /// Calculates how close a protocol is to pharmacokinetic steady-state ("stable levels").
    ///
    /// Steady state is approached asymptotically. Using the accumulation formula:
    ///   percentage = (1 − 0.5^(t / t½)) × 100
    ///
    /// Clinical milestones:
    ///   1 × t½ → 50%    2 × t½ → 75%    3 × t½ → 87.5%
    ///   4 × t½ → 93.75%   5 × t½ → 96.9%  (considered "stable")
    static func stableLevelInfo(for protocol_: CompoundProtocol, logs: [DoseLog]) -> StableLevelInfo {
        let halfLifeHours = protocol_.halfLifeInHours

        // Use the earliest of protocol startDate or first log timestamp
        let firstEvent: Date = {
            // Find first log without sorting entire array
            let firstLog = logs.min(by: { $0.timestamp < $1.timestamp })?.timestamp
            if let fl = firstLog { return Swift.min(protocol_.startDate, fl) }
            return protocol_.startDate
        }()

        let hoursOnProtocol = Date().timeIntervalSince(firstEvent) / 3600.0
        guard halfLifeHours > 0, hoursOnProtocol > 0 else {
            return StableLevelInfo(percentage: 0, hoursOnProtocol: 0, halfLivesElapsed: 0)
        }
        let halfLivesElapsed = hoursOnProtocol / halfLifeHours
        let percentage = Swift.min(100.0, (1.0 - pow(0.5, halfLivesElapsed)) * 100.0)
        return StableLevelInfo(
            percentage: percentage,
            hoursOnProtocol: hoursOnProtocol,
            halfLivesElapsed: halfLivesElapsed
        )
    }
    
    /// Active level for multiple protocols stacked (for a combined graph)
    /// Optimized single-pass calculation instead of generating separate arrays
    static func combinedActiveLevel(
        protocols: [(CompoundProtocol, [DoseLog])],
        startDate: Date? = nil,
        endDate: Date = Date(),
        resolution: Int = 120
    ) -> [ActiveLevelDataPoint] {
        guard !protocols.isEmpty else { return [] }

        // Determine window
        let windowStart = startDate ?? protocols.map { $0.0.startDate }.min() ?? endDate.addingTimeInterval(-30 * 86400)
        let windowEnd = endDate
        guard windowStart < windowEnd else { return [] }

        let totalInterval = windowEnd.timeIntervalSince(windowStart)
        let step = totalInterval / Double(resolution - 1)

        var combined = [ActiveLevelDataPoint]()
        combined.reserveCapacity(resolution)

        // Single-pass calculation for all protocols
        for i in 0..<resolution {
            let t = windowStart.addingTimeInterval(Double(i) * step)
            var totalLevel: Double = 0

            for (proto, logs) in protocols {
                let halfLifeHours = proto.halfLifeInHours
                guard halfLifeHours > 0 else { continue }
                let kDecay = log(2) / halfLifeHours

                for entry in logs {
                    guard entry.timestamp <= t else { break }
                    let hoursSinceDose = t.timeIntervalSince(entry.timestamp) / 3600.0
                    totalLevel += entry.actualDoseAmount * exp(-kDecay * hoursSinceDose)
                }
            }

            combined.append(ActiveLevelDataPoint(date: t, level: totalLevel))
        }

        return combined
    }

    /// Estimated time until level drops below a threshold (hours from now)
    /// Uses binary search for better performance than linear search
    static func hoursUntilBelow(
        threshold: Double,
        protocol_: CompoundProtocol,
        logs: [DoseLog]
    ) -> Double? {
        let halfLifeHours = protocol_.halfLifeInHours
        guard halfLifeHours > 0 else { return nil }

        let kDecay = log(2) / halfLifeHours
        let maxHours = halfLifeHours * 10

        // Helper function to calculate level at given future hours
        func levelAtHours(_ hours: Double) -> Double {
            let futureDate = Date().addingTimeInterval(hours * 3600)
            return logs.reduce(0.0) { total, entry in
                guard entry.timestamp <= futureDate else { return total }
                let h = futureDate.timeIntervalSince(entry.timestamp) / 3600.0
                return total + entry.actualDoseAmount * exp(-kDecay * h)
            }
        }

        // Check if we're already below threshold
        let currentLevel = levelAtHours(0)
        if currentLevel <= threshold { return 0 }

        // Check if we'll never reach threshold in reasonable time
        let levelAtMax = levelAtHours(maxHours)
        if levelAtMax > threshold { return nil }

        // Binary search for the crossover point
        var low: Double = 0
        var high: Double = maxHours
        let epsilon: Double = 0.1 // 6-minute precision

        while high - low > epsilon {
            let mid = (low + high) / 2
            let level = levelAtHours(mid)

            if level > threshold {
                low = mid
            } else {
                high = mid
            }
        }

        return (low + high) / 2
    }
}
