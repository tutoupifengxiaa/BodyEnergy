import Foundation

struct EnergyScores: Equatable, Sendable {
    var recoveryScore: Int
    var energyScore: Int
    var trainingLoadScore: Int
}

struct EnergyScorer {
    let config: EnergyConfig

    init(config: EnergyConfig = .default) {
        self.config = config
    }

    func computeScores(input rawInput: EnergyInput) -> EnergyScores {
        let input = sanitize(rawInput)
        let recovery = recoveryScore(for: input)
        let fatigue = fatigueScore(for: input)
        // A rest day or an early morning must not lose points for low activity.
        let activityBalance = centeredScore(
            max(input.activeEnergyKcal, config.baselines.targetActiveEnergyKcal),
            target: config.baselines.targetActiveEnergyKcal,
            tolerance: config.baselines.activityBalanceToleranceKcal
        )

        let trainingLoad = weighted(
            [
                ratioScore(input.heartRateBPM, target: config.baselines.targetTrainingHeartRate, slope: 2.0),
                ratioScore(input.activeEnergyKcal, target: config.baselines.targetActiveEnergyKcal, slope: 2.1)
            ],
            [
                config.weights.trainingLoadHeartRate,
                config.weights.trainingLoadActiveEnergy
            ]
        )

        let readiness = weighted(
            [recovery, 1 - fatigue, activityBalance],
            [
                config.weights.energyRecovery,
                config.weights.energyFatigueResistance,
                config.weights.energyActivityBalance
            ]
        )
        let fatiguePenalty = max(0, fatigue - recovery) * 0.18
        let boundedEnergy = bounded(readiness - fatiguePenalty, to: 0...1)

        return EnergyScores(
            recoveryScore: bounded(Int((recovery * 100).rounded()), to: 0...100),
            energyScore: bounded(Int((boundedEnergy * 100).rounded()), to: 0...100),
            trainingLoadScore: bounded(Int((trainingLoad * 100).rounded()), to: 0...100)
        )
    }

    private func sanitize(_ input: EnergyInput) -> EnergyInput {
        EnergyInput(
            heartRateBPM: bounded(input.heartRateBPM, to: config.heartRateValidRange),
            heartRateVariabilityMS: bounded(input.heartRateVariabilityMS, to: config.hrvValidRange),
            restingHeartRateBPM: bounded(input.restingHeartRateBPM, to: config.restingHeartRateValidRange),
            sleepHours: bounded(input.sleepHours, to: config.sleepValidRange),
            activeEnergyKcal: bounded(input.activeEnergyKcal, to: config.activeEnergyValidRange),
            hrvBaselineMS: input.hrvBaselineMS,
            restingHeartRateBaselineBPM: input.restingHeartRateBaselineBPM
        )
    }

    private func recoveryScore(for input: EnergyInput) -> Double {
        let sleepQuality = sleepScore(for: input.sleepHours)
        let severeSleepShortfall = max(0, config.baselines.restorativeSleepFloorHours - input.sleepHours)
            / max(config.baselines.restorativeSleepFloorHours, 1)
        let targetScore = bounded(config.baselines.recoveryMarkerScoreAtTarget, to: 0.01...0.99)
        let recoveryBias = log(targetScore / (1 - targetScore))
        let hrvTarget = input.hrvBaselineMS.flatMap { config.hrvValidRange.contains($0) ? $0 : nil }
            ?? config.baselines.targetHRV
        let restingTarget = input.restingHeartRateBaselineBPM.flatMap {
            config.restingHeartRateValidRange.contains($0) ? $0 : nil
        } ?? config.baselines.targetRestingHeartRate
        let hrvScore = ratioScore(input.heartRateVariabilityMS, target: hrvTarget,
                                 slope: 2.0, bias: recoveryBias)
        let restingHeartRateScore = inverseRatioScore(
            input.restingHeartRateBPM,
            target: restingTarget,
            slope: 2.3,
            bias: recoveryBias
        )

        return weighted(
            // Keep reducing recovery after the usual sleep credit reaches zero.
            [sleepQuality - severeSleepShortfall, hrvScore, restingHeartRateScore],
            [config.weights.recoverySleep, config.weights.recoveryHRV, config.weights.recoveryRHR]
        )
    }

    private func fatigueScore(for input: EnergyInput) -> Double {
        let sleepDebt = sleepDebtPenalty(for: input.sleepHours)
        let heartRateReserve = max(0, input.heartRateBPM - input.restingHeartRateBPM)
        let heartRateStrain = overloadScore(
            heartRateReserve,
            threshold: config.baselines.heartRateReserveBufferBPM,
            ramp: config.baselines.heartRateReserveRampBPM
        )
        let activityOverload = overloadScore(
            input.activeEnergyKcal,
            threshold: config.baselines.overloadActiveEnergyKcal,
            ramp: config.baselines.activityBalanceToleranceKcal
        )

        return weighted(
            [heartRateStrain, sleepDebt, activityOverload],
            [
                config.weights.fatigueHeartRate,
                config.weights.fatigueSleepDebt,
                config.weights.fatigueActivity
            ]
        )
    }

    private func sleepScore(for sleepHours: Double) -> Double {
        // Duration credit saturates at the target; longer sleep adds no penalty or bonus.
        let durationScore = centeredScore(
            min(sleepHours, config.baselines.targetSleepHours),
            target: config.baselines.targetSleepHours,
            tolerance: 2.0
        )
        let sleepDebt = sleepDebtPenalty(for: sleepHours)
        return bounded(durationScore * 0.78 + (1 - sleepDebt) * 0.22, to: 0...1)
    }

    private func sleepDebtPenalty(for sleepHours: Double) -> Double {
        let restorativeWindow = max(
            config.baselines.targetSleepHours - config.baselines.restorativeSleepFloorHours,
            1
        )
        let shortfall = max(0, config.baselines.targetSleepHours - sleepHours)
        return bounded(shortfall / restorativeWindow, to: 0...1)
    }

    private func ratioScore(_ value: Double, target: Double, slope: Double, bias: Double = 0) -> Double {
        guard target > 0 else { return 0.5 }
        return sigmoid(((value / target) - 1) * slope + bias)
    }

    private func inverseRatioScore(_ value: Double, target: Double, slope: Double, bias: Double) -> Double {
        guard target > 0 else { return 0.5 }
        return sigmoid((1 - (value / target)) * slope + bias)
    }

    private func centeredScore(_ value: Double, target: Double, tolerance: Double) -> Double {
        let distance = abs(value - target)
        let normalizedDistance = bounded(distance / tolerance, to: 0...1.6)
        return bounded(1 - normalizedDistance, to: 0...1)
    }

    private func overloadScore(_ value: Double, threshold: Double, ramp: Double) -> Double {
        sigmoid((value - threshold) / max(ramp, 1))
    }

    private func sigmoid(_ x: Double) -> Double {
        1 / (1 + exp(-x))
    }

    private func weighted(_ values: [Double], _ weights: [Double]) -> Double {
        guard values.count == weights.count, !values.isEmpty else { return 0.5 }
        let denominator = weights.reduce(0, +)
        guard denominator > 0 else { return 0.5 }

        let numerator = zip(values, weights).reduce(0.0) { partial, pair in
            partial + pair.0 * pair.1
        }
        return bounded(numerator / denominator, to: 0...1)
    }
}

private func bounded(_ value: Double, to range: ClosedRange<Double>) -> Double {
    Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
}

private func bounded(_ value: Int, to range: ClosedRange<Int>) -> Int {
    Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
}

struct BatteryAssessment: Codable, Equatable, Sendable {
    var level: Double
    var previousLevel: Double?
    var sleepCharge: Double
    var restCharge: Double
    var activityDrain: Double
    var awakeDrain: Double
    var stressDrain: Double
    var resetReason: String?

    var limitAdjustment: Double {
        guard let previousLevel, resetReason == nil else { return 0 }
        return level - previousLevel - sleepCharge - restCharge + activityDrain + awakeDrain + stressDrain
    }

    var isValid: Bool {
        level.isFinite && (0...100).contains(level)
            && (previousLevel.map { $0.isFinite && (0...100).contains($0) } ?? true)
            && [sleepCharge, restCharge, activityDrain, awakeDrain, stressDrain].allSatisfy { $0.isFinite && $0 >= 0 }
    }
}

struct BodyBatteryScorer {
    func level(previous: HealthRecord?, health: HealthSnapshot, recoveryScore: Int,
               initialScore: Int, pressure: StressSnapshot?, now: Date) -> Double {
        assessment(previous: previous, health: health, recoveryScore: recoveryScore,
                   initialScore: initialScore, pressure: pressure, now: now).level
    }

    func assessment(previous: HealthRecord?, health: HealthSnapshot, recoveryScore: Int,
                    initialScore: Int, pressure: StressSnapshot?, now: Date) -> BatteryAssessment {
        guard let previous, let previousLevel = previous.batteryLevel,
              previousLevel.isFinite, (0...100).contains(previousLevel),
              let measuredAt = health.measuredAt, measuredAt <= now.addingTimeInterval(300) else {
            return BatteryAssessment(level: Double(initialScore), previousLevel: nil,
                sleepCharge: 0, restCharge: 0, activityDrain: 0, awakeDrain: 0, stressDrain: 0,
                resetReason: "从当前有效健康数据建立电量起点，尚无可比较的上一条记录。")
        }

        let elapsed = measuredAt.timeIntervalSince(previous.energy.updatedAt)
        guard elapsed >= 0 else {
            return BatteryAssessment(level: previousLevel, previousLevel: previousLevel,
                sleepCharge: 0, restCharge: 0, activityDrain: 0, awakeDrain: 0, stressDrain: 0,
                resetReason: "本次观测时间早于上一条记录，保留原电量。")
        }
        // A long gap has too little interval data to reconstruct a continuous reserve.
        guard elapsed <= 48 * 3600 else {
            return BatteryAssessment(level: Double(initialScore), previousLevel: previousLevel,
                sleepCharge: 0, restCharge: 0, activityDrain: 0, awakeDrain: 0, stressDrain: 0,
                resetReason: "观测间隔超过 48 小时，按当前数据重新建立电量起点。")
        }

        let oldSleepDate = previous.health.sampleDates[.sleep]
        let newSleepDate = health.sampleDates[.sleep]
        let newNight = oldSleepDate.flatMap { old in
            newSleepDate.map { $0.timeIntervalSince(old) > 12 * 3600 }
        } ?? false
        let sleepHours = min(12, max(0, newNight ? health.sleepHours
                                                : health.sleepHours - previous.health.sleepHours))

        let oldEnergyDate = previous.health.sampleDates[.activeEnergy]
        let newEnergyDate = health.sampleDates[.activeEnergy]
        let sameEnergyDay = oldEnergyDate.flatMap { old in
            newEnergyDate.map { Calendar.current.isDate(old, inSameDayAs: $0) }
        } ?? false
        let activeKcal = max(0, sameEnergyDay ? health.activeEnergyKcal - previous.health.activeEnergyKcal
                                              : health.activeEnergyKcal)

        let awakeHours = max(0, elapsed / 3600 - sleepHours)
        let recovery = Double(recoveryScore.clamped(to: 0...100)) / 100
        let sleepCharge = sleepHours * 7 * (0.35 + 0.65 * recovery)
        let activityDrain = activeKcal / 25
        let awakeDrain = awakeHours * 0.35

        var stressDrain = 0.0
        var restCharge = 0.0
        if let pressure, pressure.updatedAt > previous.energy.updatedAt,
           pressure.updatedAt <= measuredAt, measuredAt.timeIntervalSince(pressure.updatedAt) <= 2 * 3600 {
            let observedHours = min(awakeHours, 2)
            if pressure.score > 55 {
                stressDrain = Double(pressure.score - 55) / 45 * observedHours * 1.5
            } else if pressure.score < 30 && health.heartRateIsSedentary == true && activeKcal <= awakeHours * 30 {
                restCharge = Double(30 - pressure.score) / 30 * observedHours * 1.5
            }
        }

        var result = previousLevel + sleepCharge + restCharge - activityDrain - awakeDrain - stressDrain
        if sleepHours > 0 {
            result = min(result, max(previousLevel, Double(recoveryScore + 10)))
        }
        return BatteryAssessment(level: result.clamped(to: 0...100), previousLevel: previousLevel,
            sleepCharge: sleepCharge, restCharge: restCharge, activityDrain: activityDrain,
            awakeDrain: awakeDrain, stressDrain: stressDrain, resetReason: nil)
    }
}
