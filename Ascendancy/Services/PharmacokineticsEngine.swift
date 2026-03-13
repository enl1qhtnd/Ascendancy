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
        
        let totalInterval = windowEnd.timeIntervalSince(windowStart)
        let step = totalInterval / Double(resolution - 1)
        
        // Sort logs ascending by time
        let sortedLogs = logs.sorted { $0.timestamp < $1.timestamp }
        
        var points = [ActiveLevelDataPoint]()
        
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
        
        return points
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
            let firstLog = logs.sorted { $0.timestamp < $1.timestamp }.first?.timestamp
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
    static func combinedActiveLevel(
        protocols: [(CompoundProtocol, [DoseLog])],
        startDate: Date? = nil,
        endDate: Date = Date(),
        resolution: Int = 120
    ) -> [ActiveLevelDataPoint] {
        guard !protocols.isEmpty else { return [] }
        
        // Generate per-protocol and sum
        var combined = [Double](repeating: 0, count: resolution)
        var dates = [Date](repeating: Date(), count: resolution)
        
        for (proto, logs) in protocols {
            let points = activeLevel(for: proto, logs: logs, startDate: startDate, endDate: endDate, resolution: resolution)
            for (i, point) in points.enumerated() {
                combined[i] += point.level
                dates[i] = point.date
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
        guard halfLifeHours > 0 else { return nil }
        
        let kDecay = log(2) / halfLifeHours
        var hours = 0.0
        
        while hours < halfLifeHours * 10 {
            let futureDate = Date().addingTimeInterval(hours * 3600)
            let level = logs.reduce(0.0) { total, entry in
                guard entry.timestamp <= futureDate else { return total }
                let h = futureDate.timeIntervalSince(entry.timestamp) / 3600.0
                return total + entry.actualDoseAmount * exp(-kDecay * h)
            }
            if level <= threshold { return hours }
            hours += 1
        }
        return nil
    }
}
