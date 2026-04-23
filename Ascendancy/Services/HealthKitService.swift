import Foundation
import HealthKit
import Combine

final class HealthKitService: ObservableObject {

    static let shared = HealthKitService()
    private let store = HKHealthStore()

    @Published var isAuthorized = false
    @Published var bodyWeightSamples: [HealthMetricPoint] = []
    @Published var heartRateSamples: [HealthMetricPoint] = []
    @Published var stepSamples: [HealthMetricPoint] = []
    @Published var bodyFatSamples: [HealthMetricPoint] = []
    @Published var activeEnergySamples: [HealthMetricPoint] = []
    @Published var heightSamples: [HealthMetricPoint] = []
    @Published var bmiSamples: [HealthMetricPoint] = []
    @Published var latestWeight: Double? = nil
    @Published var weightUnit: String = "kg"

    // Cached computed properties
    private var cachedWeightTrend: (samplesCount: Int, trend: Double)?

    /// 7-day weight trend (cached)
    var weightTrend7Day: Double {
        let currentCount = bodyWeightSamples.count

        // Return cached value if data hasn't changed
        if let cached = cachedWeightTrend, cached.samplesCount == currentCount {
            return cached.trend
        }

        guard bodyWeightSamples.count >= 7 else {
            cachedWeightTrend = (currentCount, 0)
            return 0
        }

        let last7 = Array(bodyWeightSamples.suffix(7))
        let trend = (last7.last?.value ?? 0) - (last7.first?.value ?? 0)

        cachedWeightTrend = (currentCount, trend)
        return trend
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let readTypes: Set = [
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .height)!,
            HKObjectType.quantityType(forIdentifier: .bodyMassIndex)!
        ]

        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            await MainActor.run { isAuthorized = true }
            await fetchAll()
        } catch {
            print("HealthKit auth failed: \(error)")
        }
    }

    // MARK: - Fetch All

    /// Fetch all metrics (optimized to fetch body weight first for immediate display)
    func fetchAll() async {
        // Prioritize body weight for HomeView display
        let w = await fetchBodyWeight(days: 90)
        await MainActor.run {
            bodyWeightSamples = w
            latestWeight = w.last?.value
        }

        // Fetch remaining metrics in parallel
        async let hr = fetchHeartRate(days: 90)
        async let steps = fetchSteps(days: 90)
        async let fat = fetchBodyFat(days: 90)
        async let energy = fetchActiveEnergy(days: 90)
        async let heightData = fetchHeight(days: 90)
        async let bmiData = fetchBMI(days: 90)

        let (h, s, f, e, hd, b) = await (hr, steps, fat, energy, heightData, bmiData)
        await MainActor.run {
            heartRateSamples = h
            stepSamples = s
            bodyFatSamples = f
            activeEnergySamples = e
            heightSamples = hd
            bmiSamples = b
        }
    }

    /// Fetch specific metric lazily (can be called on demand)
    func fetchMetric(_ metric: HealthMetric) async {
        switch metric {
        case .bodyWeight:
            let samples = await fetchBodyWeight(days: 90)
            await MainActor.run {
                bodyWeightSamples = samples
                latestWeight = samples.last?.value
            }
        case .heartRate:
            let samples = await fetchHeartRate(days: 90)
            await MainActor.run { heartRateSamples = samples }
        case .steps:
            let samples = await fetchSteps(days: 90)
            await MainActor.run { stepSamples = samples }
        case .bodyFat:
            let samples = await fetchBodyFat(days: 90)
            await MainActor.run { bodyFatSamples = samples }
        case .activeEnergy:
            let samples = await fetchActiveEnergy(days: 90)
            await MainActor.run { activeEnergySamples = samples }
        case .height:
            let samples = await fetchHeight(days: 90)
            await MainActor.run { heightSamples = samples }
        case .bmi:
            let samples = await fetchBMI(days: 90)
            await MainActor.run { bmiSamples = samples }
        }
    }

    enum HealthMetric {
        case bodyWeight, heartRate, steps, bodyFat, activeEnergy, height, bmi
    }

    // MARK: - Body Weight

    private func fetchBodyWeight(days: Int) async -> [HealthMetricPoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return [] }
        let unit = HKUnit.gramUnit(with: .kilo)
        return await fetchSamples(type: type, unit: unit, days: days)
    }

    // MARK: - Heart Rate

    private func fetchHeartRate(days: Int) async -> [HealthMetricPoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let unit = HKUnit(from: "count/min")
        return await fetchSamples(type: type, unit: unit, days: days)
    }

    // MARK: - Steps

    private func fetchSteps(days: Int) async -> [HealthMetricPoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return [] }
        let unit = HKUnit.count()
        let interval = DateComponents(day: 1)
        let anchorDate = Calendar.current.startOfDay(for: Date())
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: startDate, end: Date()),
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, _ in
                guard let results else {
                    continuation.resume(returning: [])
                    return
                }
                var points: [HealthMetricPoint] = []
                results.enumerateStatistics(from: startDate, to: Date()) { stat, _ in
                    if let sum = stat.sumQuantity() {
                        points.append(HealthMetricPoint(date: stat.startDate, value: sum.doubleValue(for: unit)))
                    }
                }
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
    }

    // MARK: - Body Fat

    private func fetchBodyFat(days: Int) async -> [HealthMetricPoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) else { return [] }
        let unit = HKUnit.percent()
        return await fetchSamples(type: type, unit: unit, days: days)
    }

    // MARK: - Active Energy (Calories Burned)

    private func fetchActiveEnergy(days: Int) async -> [HealthMetricPoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return [] }
        let unit = HKUnit.kilocalorie()
        let interval = DateComponents(day: 1)
        let anchorDate = Calendar.current.startOfDay(for: Date())
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: startDate, end: Date()),
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, _ in
                guard let results else {
                    continuation.resume(returning: [])
                    return
                }
                var points: [HealthMetricPoint] = []
                results.enumerateStatistics(from: startDate, to: Date()) { stat, _ in
                    if let sum = stat.sumQuantity() {
                        points.append(HealthMetricPoint(date: stat.startDate, value: sum.doubleValue(for: unit)))
                    }
                }
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
    }

    // MARK: - Height

    private func fetchHeight(days: Int) async -> [HealthMetricPoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .height) else { return [] }
        let unit = HKUnit.meterUnit(with: .centi) // cm
        return await fetchSamples(type: type, unit: unit, days: days)
    }

    // MARK: - BMI

    private func fetchBMI(days: Int) async -> [HealthMetricPoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex) else { return [] }
        let unit = HKUnit.count()
        return await fetchSamples(type: type, unit: unit, days: days)
    }

    // MARK: - Generic Sample Fetcher

    private func fetchSamples(type: HKQuantityType, unit: HKUnit, days: Int) async -> [HealthMetricPoint] {
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let points = (samples as? [HKQuantitySample])?.map {
                    HealthMetricPoint(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
                } ?? []
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
    }
}

struct HealthMetricPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}
