import Foundation

struct HRVBaseline: Codable, Equatable, Sendable {
    static let minimumLogSpread = 0.15
    static let fallbackLogSpread = 0.25

    var medianMS: Double
    var logSpread: Double
    var dayCount: Int
    var hrvMetric: HRVMetric? = nil

    var metric: HRVMetric { hrvMetric ?? .sdnn }

    var usualRangeMS: ClosedRange<Double> {
        let spread = max(Self.minimumLogSpread, logSpread)
        let center = log(0.4 / 0.6)
        let lower = medianMS * exp(spread * (center - log(0.55 / 0.45)))
        let upper = medianMS * exp(spread * (center - log(0.3 / 0.7)))
        return lower...upper
    }
}

struct HRVTrend: Codable, Equatable, Sendable {
    var recentMedianMS: Double
    var referenceMedianMS: Double
}

struct RMSSDQuality: Codable, Equatable, Sendable {
    var version: Int
    var intervalCount: Int
    var rejectedIntervalCount: Int
    var usableDurationSeconds: Double
}

struct PressureMeasurement: Codable, Equatable, Sendable {
    var hrvMS: Double
    var baseline: HRVBaseline
    var sampledAt: Date
    var heartRateBPM: Double?
    var restingHeartRateBPM: Double?
    var restingHeartRateBaselineBPM: Double?
    var isSleeping: Bool
    var trend: HRVTrend? = nil
    var hrvMetric: HRVMetric? = nil
    var sourceIdentifier: String? = nil
    var effectiveDurationSeconds: Double? = nil
    var differenceCount: Int? = nil
    var rmssdQuality: RMSSDQuality? = nil

    var metric: HRVMetric { hrvMetric ?? .sdnn }
}

struct HealthSnapshot: Codable, Equatable, Sendable {
    var heartRateBPM: Double
    var heartRateVariabilityMS: Double
    var restingHeartRateBPM: Double
    var sleepHours: Double
    var activeEnergyKcal: Double
    var heartRateIsSedentary: Bool? = nil
    var hrvBaselineMS: Double? = nil
    var restingHeartRateBaselineBPM: Double? = nil
    var hrvBaselineLogSpread: Double? = nil
    var hrvBaselineDayCount: Int? = nil
    var pressureMeasurement: PressureMeasurement? = nil
    var pressureContextPrepared: Bool? = nil
    var hrvTrend: HRVTrend? = nil
    var pressureAlgorithmVersion: Int? = StressSnapshot.algorithmVersion
    var sleepDetails: SleepDetails? = nil
    var fitnessContext: FitnessContext? = nil
    var morningRecovery: MorningRecovery? = nil
    var sleepHistory: SleepHistorySummary? = nil
    var trainingLoad: TrainingLoad? = nil
    var cycleBattery: BatteryAssessment? = nil
    var scoringVersion: Int? = nil
    var scoredAt: Date? = nil

    var sampleDates: [HealthMetric: Date] = [:]
    var missingMetrics: Set<HealthMetric> = []

    static let empty = HealthSnapshot(
        heartRateBPM: 0, heartRateVariabilityMS: 0, restingHeartRateBPM: 0,
        sleepHours: 0, activeEnergyKcal: 0, missingMetrics: Set(HealthMetric.allCases)
    )

    var measuredAt: Date? { scoredAt ?? sampleDates.values.max() }
    var validUntil: Date? {
        if let scoringVersion, scoringVersion != BodyBatteryScorer.algorithmVersion { return nil }
        if scoringVersion == BodyBatteryScorer.algorithmVersion {
            guard let morningRecovery, cycleBattery?.isValid == true,
                  let energyDate = sampleDates[.activeEnergy], let heartDate = sampleDates[.heartRate] else { return nil }
            return min(morningRecovery.validUntil, energyDate.addingTimeInterval(HealthMetric.activeEnergy.maxAge),
                       heartDate.addingTimeInterval(HealthMetric.heartRate.maxAge))
        }
        guard missingMetrics.isEmpty, sampleDates.count == HealthMetric.allCases.count else { return nil }
        return sampleDates.map { $0.value.addingTimeInterval($0.key.maxAge) }.min()
    }

    func isUsable(at date: Date) -> Bool {
        guard let validUntil, validUntil >= date else { return false }
        if scoringVersion == BodyBatteryScorer.algorithmVersion {
            return morningRecovery?.isValid(at: date) == true && cycleBattery?.isValid == true
                && (scoredAt.map { $0 <= date.addingTimeInterval(300) } ?? false)
                && isUsable(.heartRate, at: date) && isUsable(.activeEnergy, at: date)
        }
        return HealthMetric.allCases.allSatisfy { isUsable($0, at: date) }
    }

    func isUsable(_ metric: HealthMetric, at date: Date) -> Bool {
        guard !missingMetrics.contains(metric), let sampledAt = sampleDates[metric],
              sampledAt <= date.addingTimeInterval(300), sampledAt.addingTimeInterval(metric.maxAge) >= date else { return false }
        let value: Double
        switch metric {
        case .heartRate: value = heartRateBPM
        case .hrv: value = heartRateVariabilityMS
        case .restingHeartRate: value = restingHeartRateBPM
        case .sleep: value = sleepHours
        case .activeEnergy: value = activeEnergyKcal
        }
        return value.isFinite && (metric == .activeEnergy ? value >= 0 : value > 0)
    }

    static let baseline = HealthSnapshot(
        heartRateBPM: 72,
        heartRateVariabilityMS: 55,
        restingHeartRateBPM: 58,
        sleepHours: 7.5,
        activeEnergyKcal: 520,
        hrvBaselineMS: 55
    )
}

enum BodyBatteryState: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low

    init(energyScore: Int) {
        switch energyScore {
        case 70...100:
            self = .high
        case 40..<70:
            self = .medium
        default:
            self = .low
        }
    }

    var title: String {
        switch self {
        case .high:
            return "状态良好"
        case .medium:
            return "状态平稳"
        case .low:
            return "需要恢复"
        }
    }
}

struct BodyStatusDescriptor: Codable, Equatable, Sendable {
    var state: BodyBatteryState
    var title: String
    var detail: String
    var action: String

    static func make(energyScore: Int) -> BodyStatusDescriptor {
        let state = BodyBatteryState(energyScore: energyScore)
        switch state {
        case .high:
            return BodyStatusDescriptor(
                state: state,
                title: "身体储备充足",
                detail: "恢复和自主神经状态都比较在线，今天更适合安排完整训练，或者把重点项目做得更扎实。",
                action: "建议优先完成计划内主训练，训练后注意补水和放松。"
            )
        case .medium:
            return BodyStatusDescriptor(
                state: state,
                title: "身体状态平稳",
                detail: "当前恢复基础比较稳定，但训练储备还没到峰值，更适合中等强度、可持续的节奏。",
                action: "建议以稳态有氧、轻力量或技术训练为主。"
            )
        case .low:
            return BodyStatusDescriptor(
                state: state,
                title: "身体更需要恢复",
                detail: "当前身体电量偏低，通常意味着睡眠、压力或近期活动负荷还没有完全回到舒适区间。",
                action: "建议减少刺激，优先步行、拉伸、补水和提早休息。"
            )
        }
    }
}

// Display freshness limits, not medical thresholds.
enum HealthMetric: String, Codable, CaseIterable, Sendable {
    case heartRate, hrv, restingHeartRate, sleep, activeEnergy

    var title: String {
        switch self {
        case .heartRate: return "最近心率"
        case .hrv: return "HRV"
        case .restingHeartRate: return "静息心率"
        case .sleep: return "睡眠"
        case .activeEnergy: return "活动消耗"
        }
    }

    var maxAge: TimeInterval {
        switch self {
        case .heartRate: return 6 * 3600
        case .hrv, .sleep: return 36 * 3600
        case .restingHeartRate: return 48 * 3600
        case .activeEnergy: return 24 * 3600
        }
    }
}
