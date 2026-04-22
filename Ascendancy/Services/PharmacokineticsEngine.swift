import Foundation

struct ActiveLevelDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let level: Double   // Normalized concentration (arbitrary units from dose)
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
    
    // MARK: - Public API
    
    /// Calculate active level time series for a protocol given its dose logs.
    /// - Parameters:
    ///   - protocol_: The compound protocol (provides half-life, dose amount, start date)
    ///   - logs: All dose logs for this protocol, sorted by timestamp ascending
    ///   - startDate: Display window start date
    ///   - endDate: Display window end date
    ///   - resolution: Number of data points to generate
    /// - Returns: Array of ActiveLevelDataPoint suitable for charting
    static func activeLevel(
        for protocol_: CompoundProtocol,
        logs: [DoseLog],
        startDate: Date? = nil,
        endDate: Date = Date(),
        resolution: Int = 120
    ) -> [ActiveLevelDataPoint] {

        let halfLifeHours = protocol_.halfLifeInHours
        guard halfLifeHours > 0 else { return [] }

        // Use protocol start date or earliest log date as display window start
        let windowStart = startDate ?? min(protocol_.startDate, endDate.addingTimeInterval(-30 * 86400))
        let windowEnd = endDate

        guard windowStart < windowEnd else { return [] }

        // Pre-sort logs once (instead of sorting on every call)
        let sortedLogs = logs.sorted { $0.timestamp < $1.timestamp }
        guard !sortedLogs.isEmpty else { return [] }

        let totalInterval = windowEnd.timeIntervalSince(windowStart)
        let step = totalInterval / Double(resolution - 1)

        var points = [ActiveLevelDataPoint]()
        points.reserveCapacity(resolution)

        let kDecay = log(2) / halfLifeHours

        // Pre-calculate decay threshold (5-7 half-lives is effectively zero contribution)
        let significantHours = halfLifeHours * 7.0

        for i in 0..<resolution {
            let t = windowStart.addingTimeInterval(Double(i) * step)
            var totalLevel: Double = 0

            // Use binary search to find first relevant log instead of iterating from start
            let tTimestamp = t.timeIntervalSinceReferenceDate

            for entry in sortedLogs {
                let entryTimestamp = entry.timestamp.timeIntervalSinceReferenceDate

                // Early termination: skip logs after current time
                guard entryTimestamp <= tTimestamp else { break }

                let hoursSinceDose = (tTimestamp - entryTimestamp) / 3600.0

                // Skip doses that have decayed to insignificant levels
                guard hoursSinceDose <= significantHours else { continue }

                let contribution = entry.actualDoseAmount * exp(-kDecay * hoursSinceDose)
                totalLevel += contribution
            }

            points.append(ActiveLevelDataPoint(date: t, level: totalLevel))
        }

        return points
    }
    
    /// Quick current level snapshot
    static func currentLevel(for protocol_: CompoundProtocol, logs: [DoseLog]) -> Double {
        let halfLifeHours = protocol_.halfLifeInHours
        guard halfLifeHours > 0, !logs.isEmpty else { return 0 }

        let now = Date()
        let nowTimestamp = now.timeIntervalSinceReferenceDate
        let kDecay = log(2) / halfLifeHours
        let significantHours = halfLifeHours * 7.0

        var total: Double = 0

        for entry in logs {
            guard entry.timestamp.timeIntervalSinceReferenceDate <= nowTimestamp else { continue }
            let hoursSinceDose = (nowTimestamp - entry.timestamp.timeIntervalSinceReferenceDate) / 3600.0

            // Skip doses that have decayed to insignificant levels
            guard hoursSinceDose <= significantHours else { continue }

            total += entry.actualDoseAmount * exp(-kDecay * hoursSinceDose)
        }

        return total
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
        // Optimize: Only find min if logs exist, avoid sorting
        let firstEvent: Date = {
            if logs.isEmpty {
                return protocol_.startDate
            }
            let firstLog = logs.min(by: { $0.timestamp < $1.timestamp })?.timestamp
            if let fl = firstLog {
                return Swift.min(protocol_.startDate, fl)
            }
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
    static func combinedActiveLevel(
        protocols: [(CompoundProtocol, [DoseLog])],
        startDate: Date? = nil,
        endDate: Date = Date(),
        resolution: Int = 120
    ) -> [ActiveLevelDataPoint] {
        guard !protocols.isEmpty else { return [] }

        // Optimize: Compute window dates once
        let firstProtocol = protocols[0].0
        let windowStart = startDate ?? min(firstProtocol.startDate, endDate.addingTimeInterval(-30 * 86400))
        let windowEnd = endDate
        guard windowStart < windowEnd else { return [] }

        let totalInterval = windowEnd.timeIntervalSince(windowStart)
        let step = totalInterval / Double(resolution - 1)

        // Pre-allocate arrays
        var combined = [Double](repeating: 0, count: resolution)
        var dates = [Date]()
        dates.reserveCapacity(resolution)

        // Pre-calculate time points
        for i in 0..<resolution {
            dates.append(windowStart.addingTimeInterval(Double(i) * step))
        }

        // For each protocol, calculate contribution and accumulate
        for (proto, logs) in protocols {
            let halfLifeHours = proto.halfLifeInHours
            guard halfLifeHours > 0, !logs.isEmpty else { continue }

            let sortedLogs = logs.sorted { $0.timestamp < $1.timestamp }
            let kDecay = log(2) / halfLifeHours
            let significantHours = halfLifeHours * 7.0

            for (i, t) in dates.enumerated() {
                let tTimestamp = t.timeIntervalSinceReferenceDate
                var totalLevel: Double = 0

                for entry in sortedLogs {
                    let entryTimestamp = entry.timestamp.timeIntervalSinceReferenceDate
                    guard entryTimestamp <= tTimestamp else { break }

                    let hoursSinceDose = (tTimestamp - entryTimestamp) / 3600.0
                    guard hoursSinceDose <= significantHours else { continue }

                    totalLevel += entry.actualDoseAmount * exp(-kDecay * hoursSinceDose)
                }

                combined[i] += totalLevel
            }
        }

        return zip(dates, combined).map { ActiveLevelDataPoint(date: $0, level: $1) }
    }
    
    /// Estimated time until level drops below a threshold (hours from now)
    static func hoursUntilBelow(
        threshold: Double,
        protocol_: CompoundProtocol,
        logs: [DoseLog]
    ) -> Double? {
        let halfLifeHours = protocol_.halfLifeInHours
        guard halfLifeHours > 0, !logs.isEmpty else { return nil }

        let kDecay = log(2) / halfLifeHours
        let now = Date()
        let nowTimestamp = now.timeIntervalSinceReferenceDate
        let significantHours = halfLifeHours * 7.0

        // Filter to only relevant logs (within significant decay window from now)
        let relevantLogs = logs.filter {
            let hoursSince = (nowTimestamp - $0.timestamp.timeIntervalSinceReferenceDate) / 3600.0
            return hoursSince <= significantHours + (halfLifeHours * 10)
        }

        guard !relevantLogs.isEmpty else { return nil }

        var hours = 0.0
        let maxHours = halfLifeHours * 10

        while hours < maxHours {
            let futureTimestamp = nowTimestamp + (hours * 3600)
            var level: Double = 0

            for entry in relevantLogs {
                let entryTimestamp = entry.timestamp.timeIntervalSinceReferenceDate
                guard entryTimestamp <= futureTimestamp else { continue }

                let h = (futureTimestamp - entryTimestamp) / 3600.0
                guard h <= significantHours else { continue }

                level += entry.actualDoseAmount * exp(-kDecay * h)
            }

            if level <= threshold { return hours }
            hours += 1
        }
        return nil
    }
}
