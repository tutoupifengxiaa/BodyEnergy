import Foundation

struct StressReading: Equatable, Sendable {
    enum Level: String, Sendable {
        case low
        case moderate
        case elevated
        case high
    }

    var score: Int
    var level: Level
    var hrvStressScore: Int
    var restingHeartRateStressScore: Int
    var acuteStressScore: Int
}

struct StressAnalyzer {
    private static let heartRatePairingWindow: TimeInterval = 30 * 60

    let config: EnergyConfig

    init(config: EnergyConfig = .default) {
        self.config = config
    }

    func evaluate(snapshot: HealthSnapshot) -> StressReading {
        evaluate(
            hrvMS: snapshot.heartRateVariabilityMS,
            restingHeartRateBPM: snapshot.restingHeartRateBPM,
            currentHeartRateBPM: snapshot.heartRateBPM
        )
    }

    func evaluateAvailable(snapshot: HealthSnapshot, now: Date = .now) -> (reading: StressReading, snapshot: StressSnapshot)? {
        guard snapshot.isUsable(.hrv, at: now), let hrvDate = snapshot.sampleDates[.hrv] else { return nil }
        // Resting heart rate is a daily baseline; current heart rate must be paired with the HRV sample.
        if snapshot.isUsable(.heartRate, at: now), snapshot.isUsable(.restingHeartRate, at: now),
           let heartRateDate = snapshot.sampleDates[.heartRate],
           let restingHeartRateDate = snapshot.sampleDates[.restingHeartRate],
           abs(heartRateDate.timeIntervalSince(hrvDate)) <= Self.heartRatePairingWindow {
            let reading = evaluate(snapshot: snapshot)
            let expiry = min(hrvDate.addingTimeInterval(HealthMetric.hrv.maxAge),
                             heartRateDate.addingTimeInterval(HealthMetric.heartRate.maxAge),
                             restingHeartRateDate.addingTimeInterval(HealthMetric.restingHeartRate.maxAge))
            return (reading, StressSnapshot(score: reading.score, levelTitle: reading.level.title,
                updatedAt: max(hrvDate, heartRateDate), validUntil: expiry, basis: "HRV 与心率估算"))
        }

        let score = evaluate(hrvMS: snapshot.heartRateVariabilityMS)
        let reading = StressReading(score: score, level: level(for: score), hrvStressScore: score,
                                    restingHeartRateStressScore: 0, acuteStressScore: 0)
        return (reading, StressSnapshot(score: reading.score, levelTitle: reading.level.title,
            updatedAt: hrvDate, validUntil: hrvDate.addingTimeInterval(HealthMetric.hrv.maxAge), basis: "HRV 估算"))
    }

    func evaluate(hrvMS: Double) -> Int {
        Int((inverseRatioScore(hrvMS.clamped(to: config.hrvValidRange),
                               target: config.baselines.targetHRV, slope: 2.6) * 100).rounded()).clamped(to: 0...100)
    }

    func evaluate(hrvMS: Double, restingHeartRateBPM: Double, currentHeartRateBPM: Double) -> StressReading {
        let boundedHRV = hrvMS.clamped(to: config.hrvValidRange)
        let boundedRestingHeartRate = restingHeartRateBPM.clamped(to: config.restingHeartRateValidRange)
        let boundedCurrentHeartRate = currentHeartRateBPM.clamped(to: config.heartRateValidRange)

        let hrvStress = inverseRatioScore(
            boundedHRV,
            target: config.baselines.targetHRV,
            slope: 2.6
        )
        let restingHeartRateStress = overloadScore(
            boundedRestingHeartRate,
            threshold: config.baselines.targetRestingHeartRate + 4,
            ramp: 6
        )

        let heartRateReserve = max(0, boundedCurrentHeartRate - boundedRestingHeartRate)
        let acuteStress = overloadScore(
            heartRateReserve,
            threshold: config.baselines.heartRateReserveBufferBPM,
            ramp: config.baselines.heartRateReserveRampBPM
        )

        let overallStress = weighted(
            [hrvStress, restingHeartRateStress, acuteStress],
            [0.58, 0.20, 0.22]
        )
        let score = Int((overallStress * 100).rounded()).clamped(to: 0...100)

        return StressReading(
            score: score,
            level: level(for: score),
            hrvStressScore: Int((hrvStress * 100).rounded()).clamped(to: 0...100),
            restingHeartRateStressScore: Int((restingHeartRateStress * 100).rounded()).clamped(to: 0...100),
            acuteStressScore: Int((acuteStress * 100).rounded()).clamped(to: 0...100)
        )
    }

    private func level(for score: Int) -> StressReading.Level {
        switch score {
        case 0..<30: return .low
        case 30..<55: return .moderate
        case 55..<75: return .elevated
        default: return .high
        }
    }

    private func inverseRatioScore(_ value: Double, target: Double, slope: Double) -> Double {
        guard target > 0 else { return 0.5 }
        return sigmoid((1 - (value / target)) * slope)
            .clamped(to: 0...1)
    }

    private func overloadScore(_ value: Double, threshold: Double, ramp: Double) -> Double {
        sigmoid((value - threshold) / max(ramp, 1))
            .clamped(to: 0...1)
    }

    private func weighted(_ values: [Double], _ weights: [Double]) -> Double {
        guard values.count == weights.count, !values.isEmpty else { return 0.5 }
        let denominator = weights.reduce(0, +)
        guard denominator > 0 else { return 0.5 }

        let numerator = zip(values, weights).reduce(0.0) { partial, pair in
            partial + pair.0 * pair.1
        }
        return (numerator / denominator).clamped(to: 0...1)
    }

    private func sigmoid(_ x: Double) -> Double {
        1 / (1 + exp(-x))
    }
}

extension StressReading.Level {
    var title: String {
        switch self {
        case .low:
            return "压力较低"
        case .moderate:
            return "压力适中"
        case .elevated:
            return "压力偏高"
        case .high:
            return "压力较高"
        }
    }
}
