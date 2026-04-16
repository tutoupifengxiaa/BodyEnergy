import Foundation
import HealthKit

protocol HealthManaging {
    func requestAuthorization() async throws
    func fetchLatestSnapshot(now: Date) async throws -> HealthSnapshot
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
    }

    func fetchLatestSnapshot(now: Date = .now) async throws -> HealthSnapshot {
        async let heartRate = fetchLatestHeartRateBPM()
        async let hrv = fetchLatestHRV()
        async let restingHeartRate = fetchLatestRestingHeartRateBPM()
        async let sleepHours = fetchSleepDurationHours(referenceDate: now)
        async let activeEnergy = fetchTodayActiveEnergyKcal(referenceDate: now)

        return try await HealthSnapshot(
            heartRateBPM: heartRate,
            heartRateVariabilityMS: hrv,
            restingHeartRateBPM: restingHeartRate,
            sleepHours: sleepHours,
            activeEnergyKcal: activeEnergy
        )
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

    private func fetchLatestHeartRateBPM() async throws -> Double {
        let samples = try await latestQuantitySamples(identifier: .heartRate, limit: 1)
        guard let sample = samples.first else {
            throw HealthManagerError.noData("心率")
        }
        return sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }

    private func fetchLatestHRV() async throws -> Double {
        let samples = try await latestQuantitySamples(identifier: .heartRateVariabilitySDNN, limit: 1)
        guard let sample = samples.first else {
            throw HealthManagerError.noData("HRV")
        }
        return sample.quantity.doubleValue(for: .secondUnit(with: .milli))
    }

    private func fetchLatestRestingHeartRateBPM() async throws -> Double {
        let samples = try await latestQuantitySamples(identifier: .restingHeartRate, limit: 1)
        guard let sample = samples.first else {
            throw HealthManagerError.noData("静息心率")
        }
        return sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }

    private func fetchTodayActiveEnergyKcal(referenceDate: Date) async throws -> Double {
        let type = try quantityType(.activeEnergyBurned)
        let startOfDay = calendar.startOfDay(for: referenceDate)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: referenceDate, options: .strictStartDate)
        let samples = try await quantitySamples(type: type, predicate: predicate, limit: HKObjectQueryNoLimit)

        let kcalUnit = HKUnit.kilocalorie()
        return samples.reduce(0) { partialResult, sample in
            partialResult + sample.quantity.doubleValue(for: kcalUnit)
        }
    }

    private func fetchSleepDurationHours(referenceDate: Date) async throws -> Double {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthManagerError.missingType("sleepAnalysis")
        }

        let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
        let predicate = HKQuery.predicateForSamples(withStart: start, end: referenceDate, options: .strictStartDate)
        let samples = try await categorySamples(type: type, predicate: predicate, limit: HKObjectQueryNoLimit)

        let totalSeconds = samples.reduce(0.0) { partial, sample in
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            return partial + max(0, duration)
        }

        let hours = totalSeconds / 3600
        guard hours > 0 else {
            throw HealthManagerError.noData("睡眠")
        }
        return hours
    }

    private func latestQuantitySamples(identifier: HKQuantityTypeIdentifier, limit: Int) async throws -> [HKQuantitySample] {
        let type = try quantityType(identifier)
        return try await quantitySamples(
            type: type,
            predicate: nil,
            sort: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)],
            limit: limit
        )
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
