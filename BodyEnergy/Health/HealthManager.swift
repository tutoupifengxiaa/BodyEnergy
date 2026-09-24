import Foundation
import HealthKit
import OSLog

protocol HealthManaging {
    func requestAuthorization() async throws
    func fetchLatestSnapshot(now: Date) async throws -> HealthSnapshot
    func fetchTodayHourlyStress(now: Date) async throws -> [HourlyStress]
    func observeChanges(_ onChange: @escaping @MainActor () async -> Void)
    func enableBackgroundUpdates()
}

enum HealthManagerError: LocalizedError {
    case healthDataUnavailable
    case missingType(String)
    case noData(String)

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "当前设备无法使用健康数据。"
        case .missingType(let identifier):
            return "HealthKit 数据类型不可用：\(identifier)。"
        case .noData(let metric):
            return "暂未读取到\(metric)的 HealthKit 数据。"
        }
    }
}

final class HealthManager: HealthManaging {
    private let healthStore: HKHealthStore
    private let calendar: Calendar
    private var observers: [HKObserverQuery] = []
    private let logger = Logger(subsystem: "com.tutoupifengxiaa.BodyEnergy", category: "HealthUpdates")

    init(healthStore: HKHealthStore = HKHealthStore(), calendar: Calendar = .current) {
        self.healthStore = healthStore
        self.calendar = calendar
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthManagerError.healthDataUnavailable
        }

        let types = try requiredReadTypes()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: nil, read: types) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        enableBackgroundUpdates()
    }

    func observeChanges(_ onChange: @escaping @MainActor () async -> Void) {
        guard observers.isEmpty, HKHealthStore.isHealthDataAvailable(),
              let types = try? requiredReadTypes() else { return }
        for case let type as HKSampleType in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                guard error == nil else { completion(); return }
                Task { @MainActor in
                    await onChange()
                    completion()
                }
            }
            observers.append(query)
            healthStore.execute(query)
        }
    }

    func enableBackgroundUpdates() {
        guard HKHealthStore.isHealthDataAvailable(), let types = try? requiredReadTypes() else { return }
        for type in types {
            healthStore.enableBackgroundDelivery(for: type, frequency: .immediate) { [logger] success, error in
                // Keep only registration status, never health measurements, for device verification.
                UserDefaults.standard.set(success, forKey: "health.background.enabled." + type.identifier)
                if let error {
                    logger.error("Background delivery registration failed: code \((error as NSError).code)")
                }
            }
        }
    }

    func fetchLatestSnapshot(now: Date = .now) async throws -> HealthSnapshot {
        async let heartRate = reading(.heartRate, identifier: .heartRate, unit: HKUnit.count().unitDivided(by: .minute()), now: now)
        async let hrv = reading(.hrv, identifier: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), now: now)
        async let resting = reading(.restingHeartRate, identifier: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), now: now)
        async let sleep = sleepReading(now: now)
        async let energy = energyReading(now: now)
        let readings = await [heartRate, hrv, resting, sleep, energy]
        if let error = readings.compactMap(\.error).first { throw error }
        var snapshot = HealthSnapshot.empty
        for reading in readings {
            guard let value = reading.value, let date = reading.date else { continue }
            snapshot.missingMetrics.remove(reading.metric)
            snapshot.sampleDates[reading.metric] = date
            switch reading.metric {
            case .heartRate: snapshot.heartRateBPM = value
            case .hrv: snapshot.heartRateVariabilityMS = value
            case .restingHeartRate: snapshot.restingHeartRateBPM = value
            case .sleep: snapshot.sleepHours = value
            case .activeEnergy: snapshot.activeEnergyKcal = value
            }
        }
        return snapshot
    }

    func fetchTodayHourlyStress(now: Date = .now) async throws -> [HourlyStress] {
        let type = try quantityType(.heartRateVariabilitySDNN)
        let start = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictEndDate)
        let samples = try await quantitySamples(type: type, predicate: predicate, limit: HKObjectQueryNoLimit)
        let grouped = Dictionary(grouping: samples.filter { $0.endDate >= start && $0.endDate <= now }) {
            calendar.dateInterval(of: .hour, for: $0.endDate)?.start ?? $0.endDate
        }
        let analyzer = StressAnalyzer()
        return grouped.compactMap { hour, samples in
            let values = samples.map { $0.quantity.doubleValue(for: .secondUnit(with: .milli)) }
                .filter { $0.isFinite && $0 > 0 }
            guard !values.isEmpty else { return nil }
            return HourlyStress(hour: hour, score: analyzer.evaluate(hrvMS: values.reduce(0, +) / Double(values.count)))
        }.sorted { $0.hour < $1.hour }
    }

    private struct Reading {
        let metric: HealthMetric
        var value: Double? = nil
        var date: Date? = nil
        var error: Error? = nil
    }

    private func reading(_ metric: HealthMetric, identifier: HKQuantityTypeIdentifier, unit: HKUnit, now: Date) async -> Reading {
        do {
            let type = try quantityType(identifier)
            let predicate = HKQuery.predicateForSamples(withStart: now.addingTimeInterval(-7 * 86400), end: now)
            let samples = try await quantitySamples(type: type, predicate: predicate, limit: 1)
            guard let sample = samples.first else { return Reading(metric: metric) }
            let value = sample.quantity.doubleValue(for: unit)
            guard value.isFinite, value >= 0 else { return Reading(metric: metric) }
            return Reading(metric: metric, value: value, date: sample.endDate)
        } catch { return Reading(metric: metric, error: error) }
    }

    private func energyReading(now: Date) async -> Reading {
        do {
            let type = try quantityType(.activeEnergyBurned)
            let predicate = HKQuery.predicateForSamples(withStart: calendar.startOfDay(for: now), end: now)
            let samples = try await quantitySamples(type: type, predicate: predicate, limit: 1)
            guard let sampledAt = samples.first?.endDate else { return Reading(metric: .activeEnergy) }
            return try await withCheckedThrowingContinuation { continuation in
                let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                    if let error { continuation.resume(throwing: error); return }
                    guard let total = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) else {
                        continuation.resume(returning: Reading(metric: .activeEnergy)); return
                    }
                    continuation.resume(returning: Reading(metric: .activeEnergy, value: total, date: sampledAt))
                }
                healthStore.execute(query)
            }
        } catch { return Reading(metric: .activeEnergy, error: error) }
    }

    private func sleepReading(now: Date) async -> Reading {
        do {
            guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return Reading(metric: .sleep) }
            // A noon-to-noon sleep day keeps one overnight session together.
            let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
            let start = calendar.date(byAdding: .day, value: -1, to: noon) ?? now.addingTimeInterval(-86400)
            let end = min(now, noon)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let samples = try await categorySamples(type: type, predicate: predicate, limit: HKObjectQueryNoLimit)
            let intervals = samples.filter {
                [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                 HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue].contains($0.value)
            }.compactMap { sample -> DateInterval? in
                let beginning = max(sample.startDate, start)
                let ending = min(sample.endDate, end)
                return ending > beginning ? DateInterval(start: beginning, end: ending) : nil
            }
            let hours = Self.sleepDuration(intervals) / 3600
            guard hours > 0, let measured = intervals.map(\.end).max() else { return Reading(metric: .sleep) }
            return Reading(metric: .sleep, value: hours, date: measured)
        } catch { return Reading(metric: .sleep, error: error) }
    }

    static func sleepDuration(_ intervals: [DateInterval]) -> TimeInterval {
        let sorted = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return 0 }
        var total: TimeInterval = 0
        for next in sorted.dropFirst() {
            if next.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, next.end))
            } else {
                total += current.duration
                current = next
            }
        }
        return total + current.duration
    }

    private func requiredReadTypes() throws -> Set<HKObjectType> {
        guard
            let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate),
            let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            let restingHeartRate = HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        else {
            throw HealthManagerError.missingType("必要的 HealthKit 类型")
        }

        return [heartRate, hrv, restingHeartRate, activeEnergy, sleep]
    }

    private func quantityType(_ identifier: HKQuantityTypeIdentifier) throws -> HKQuantityType {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw HealthManagerError.missingType(identifier.rawValue)
        }
        return type
    }

    private func quantitySamples(
        type: HKQuantityType,
        predicate: NSPredicate?,
        sort: [NSSortDescriptor] = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)],
        limit: Int
    ) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: sort) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let casted = (samples as? [HKQuantitySample]) ?? []
                continuation.resume(returning: casted)
            }
            healthStore.execute(query)
        }
    }

    private func categorySamples(
        type: HKCategoryType,
        predicate: NSPredicate?,
        limit: Int
    ) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }
}
