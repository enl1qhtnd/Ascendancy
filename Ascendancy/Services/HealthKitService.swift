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

    func fetchAll() async {
        async let weight = fetchBodyWeight(days: 90)
        async let hr = fetchHeartRate(days: 90)
        async let steps = fetchSteps(days: 90)
        async let fat = fetchBodyFat(days: 90)
        async let energy = fetchActiveEnergy(days: 90)
        async let heightData = fetchHeight(days: 90)
        async let bmiData = fetchBMI(days: 90)

        let (w, h, s, f, e, hd, b) = await (weight, hr, steps, fat, energy, heightData, bmiData)
        await MainActor.run {
            bodyWeightSamples = w
            heartRateSamples = h
            stepSamples = s
            bodyFatSamples = f
            activeEnergySamples = e
            heightSamples = hd
            bmiSamples = b
            latestWeight = w.last?.value
        }
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

    // MARK: - Mock Data (for simulator / previews)

    func loadMockData() {
        let now = Date()
        let cal = Calendar.current

        // Weight samples: 90 days
        bodyWeightSamples = (0..<90).map { i in
            let date = cal.date(byAdding: .day, value: -i, to: now)!
            let base = 82.5
            let noise = Double.random(in: -0.4...0.4)
            let trend = Double(90 - i) * 0.005
            return HealthMetricPoint(date: date, value: base - trend + noise)
        }.reversed()
        latestWeight = bodyWeightSamples.last?.value

        // Heart rate samples
        heartRateSamples = (0..<90).map { i in
            let date = cal.date(byAdding: .day, value: -i, to: now)!
            return HealthMetricPoint(date: date, value: Double.random(in: 52...68))
        }.reversed()

        // Step samples
        stepSamples = (0..<90).map { i in
            let date = cal.date(byAdding: .day, value: -i, to: now)!
            return HealthMetricPoint(date: date, value: Double.random(in: 4000...14000))
        }.reversed()

        // Body fat samples
        bodyFatSamples = (0..<90).map { i in
            let date = cal.date(byAdding: .day, value: -i, to: now)!
            let base = 0.15 // 15%
            let trend = Double(90 - i) * 0.0001
            let noise = Double.random(in: -0.002...0.002)
            return HealthMetricPoint(date: date, value: base - trend + noise)
        }.reversed()

        // Active energy samples
        activeEnergySamples = (0..<90).map { i in
            let date = cal.date(byAdding: .day, value: -i, to: now)!
            return HealthMetricPoint(date: date, value: Double.random(in: 400...1200))
        }.reversed()

        // Height sample (static)
        heightSamples = [HealthMetricPoint(date: now, value: 180.0)]

        // BMI samples
        bmiSamples = bodyWeightSamples.map { wp in
            let heightMeters = 1.80
            let bmi = wp.value / (heightMeters * heightMeters)
            return HealthMetricPoint(date: wp.date, value: bmi)
        }

        isAuthorized = true
    }
}

struct HealthMetricPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}
