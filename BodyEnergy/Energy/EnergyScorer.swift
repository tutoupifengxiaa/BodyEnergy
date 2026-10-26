import Foundation

struct EnergyScores: Equatable, Sendable {
    var recoveryScore: Int
    var energyScore: Int
    var trainingLoadScore: Int
    var trainingLoadAvailable: Bool = true
}

struct EnergyScorer {
    let config: EnergyConfig

    init(config: EnergyConfig = .default) {
        self.config = config
    }

    func computeScores(input rawInput: EnergyInput) -> EnergyScores {
        let input = sanitize(rawInput)
        let recovery = input.morningRecoveryScore.map { Double($0.clamped(to: 0...100)) / 100 }
            ?? recoveryScore(for: input)
        let fatigue = fatigueScore(for: input)
        // A rest day or an early morning must not lose points for low activity.
        let activityBalance = centeredScore(
            max(input.activeEnergyKcal, config.baselines.targetActiveEnergyKcal),
            target: config.baselines.targetActiveEnergyKcal,
            tolerance: config.baselines.activityBalanceToleranceKcal
        )

        let trainingLoad = input.trainingLoadScore.map { Double($0.clamped(to: 0...100)) / 100 } ?? 0

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
            trainingLoadScore: bounded(Int((trainingLoad * 100).rounded()), to: 0...100),
            trainingLoadAvailable: input.trainingLoadScore != nil
        )
    }

    private func sanitize(_ input: EnergyInput) -> EnergyInput {
        var result = EnergyInput(
            heartRateBPM: bounded(input.heartRateBPM, to: config.heartRateValidRange),
            heartRateVariabilityMS: bounded(input.heartRateVariabilityMS, to: config.hrvValidRange),
            restingHeartRateBPM: bounded(input.restingHeartRateBPM, to: config.restingHeartRateValidRange),
            sleepHours: bounded(input.sleepHours, to: config.sleepValidRange),
            activeEnergyKcal: bounded(input.activeEnergyKcal, to: config.activeEnergyValidRange),
            hrvBaselineMS: input.hrvBaselineMS,
            restingHeartRateBaselineBPM: input.restingHeartRateBaselineBPM
        )
        result.morningRecoveryScore = input.morningRecoveryScore
        result.trainingLoadScore = input.trainingLoadScore
        return result
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
    var anchorDate: Date? = nil

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
    static let algorithmVersion = 2
    // A spot observation supports only this short interval, never hours before it.
    static let pressureSupportSeconds: TimeInterval = 15 * 60

    func level(previous: HealthRecord?, health: HealthSnapshot, recoveryScore: Int,
               initialScore: Int, pressure: StressSnapshot?, now: Date) -> Double {
        assessment(previous: previous, health: health, recoveryScore: recoveryScore,
                   initialScore: initialScore, pressure: pressure, now: now).level
    }

    func assessment(previous: HealthRecord?, health: HealthSnapshot, recoveryScore: Int,
                    initialScore: Int, pressure: StressSnapshot?, now: Date) -> BatteryAssessment {
        if health.scoringVersion == Self.algorithmVersion, health.morningRecovery?.isValid(at: now) == true,
           let result = health.cycleBattery, result.isValid { return result }
        // Old snapshots can still be displayed, but never resume the old delta ledger.
        return BatteryAssessment(level: previous?.batteryLevel ?? Double(initialScore), previousLevel: nil,
            sleepCharge: 0, restCharge: 0, activityDrain: 0, awakeDrain: 0, stressDrain: 0,
            resetReason: "等待完整主睡眠与区间数据后，建立新的晨间电量起点。")
    }

    func replay(morning: MorningRecovery, sleep: [DateInterval], activeEnergy: [TimedHealthValue],
                pressures: [PressureMeasurement], through end: Date) -> BatteryAssessment {
        let start = morning.sleepEnd
        let initial = Double(morning.score.clamped(to: 0...100))
        guard end >= start, end.timeIntervalSince(start) <= 36 * 3600 else {
            return BatteryAssessment(level: initial, previousLevel: nil, sleepCharge: 0, restCharge: 0,
                activityDrain: 0, awakeDrain: 0, stressDrain: 0, resetReason: "晨间恢复记录已过期，等待新的主睡眠。")
        }
        let sleeping = PhysiologyIntervals.union(sleep).compactMap { PhysiologyIntervals.clip($0, start: start, end: end) }
        let energy = Array(Set(activeEnergy.filter {
            $0.value.isFinite && $0.value >= 0 && $0.start < $0.end && $0.start < end && $0.end > start
        })).sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        let analyzer = StressAnalyzer()
        let observations = pressures.filter {
            analyzer.isValid(measurement: $0) && !$0.isSleeping && $0.sampledAt <= end
                && $0.sampledAt.addingTimeInterval(Self.pressureSupportSeconds) > start
        }
        // Collapse duplicate timestamps deterministically before assigning support windows.
        let points = Dictionary(grouping: observations, by: \.sampledAt).values.compactMap { group in
            group.max {
                let left = analyzer.evaluate(measurement: $0).score
                let right = analyzer.evaluate(measurement: $1).score
                return left == right ? ($0.heartRateBPM == nil && $1.heartRateBPM != nil) : left < right
            }
        }.sorted { $0.sampledAt < $1.sampledAt }
        let pressureWindows = points.enumerated().compactMap { index, point -> (DateInterval, Int, Bool)? in
            let next = index + 1 < points.count ? points[index + 1].sampledAt : end
            let until = min(next, point.sampledAt.addingTimeInterval(Self.pressureSupportSeconds), end)
            guard let interval = PhysiologyIntervals.clip(DateInterval(start: point.sampledAt, end: max(point.sampledAt, until)),
                                                          start: start, end: end) else { return nil }
            return (interval, analyzer.evaluate(measurement: point).score, point.heartRateBPM != nil)
        }
        var boundaries = Set([start, end])
        for interval in sleeping { boundaries.formUnion([interval.start, interval.end]) }
        for sample in energy { boundaries.formUnion([max(start, sample.start), min(end, sample.end)]) }
        for point in pressureWindows { boundaries.formUnion([point.0.start, point.0.end]) }
        let times = boundaries.sorted()
        var result = BatteryAssessment(level: initial, previousLevel: initial, sleepCharge: 0, restCharge: 0,
                                       activityDrain: 0, awakeDrain: 0, stressDrain: 0, resetReason: nil,
                                       anchorDate: start)
        for (beginning, ending) in zip(times, times.dropFirst()) where ending > beginning {
            let seconds = ending.timeIntervalSince(beginning)
            let hours = seconds / 3600
            let midpoint = beginning.addingTimeInterval(seconds / 2)
            let asleep = sleeping.contains { $0.start <= midpoint && midpoint < $0.end }
            let kcal = energy.reduce(0.0) { sum, sample in
                let overlap = max(0, min(ending, sample.end).timeIntervalSince(max(beginning, sample.start)))
                return sum + sample.value * overlap / sample.end.timeIntervalSince(sample.start)
            }
            let sleepCharge = asleep ? hours * 7 * (0.35 + 0.65 * initial / 100) : 0
            let awakeDrain = asleep ? 0 : hours * 0.35
            var stressDrain = 0.0
            var restCharge = 0.0
            if !asleep, let point = pressureWindows.first(where: { $0.0.start <= midpoint && midpoint < $0.0.end }) {
                if point.1 > 55 {
                    stressDrain = Double(point.1 - 55) / 45 * hours * 1.5
                } else if point.1 < 30 && point.2 && kcal <= hours * 30 {
                    restCharge = Double(30 - point.1) / 30 * hours * 1.5
                }
            }
            let ceiling = asleep ? max(result.level, min(100, initial + 10)) : 100
            result.level = (result.level + sleepCharge + restCharge - kcal / 25 - awakeDrain - stressDrain)
                .clamped(to: 0...ceiling)
            result.sleepCharge += sleepCharge
            result.restCharge += restCharge
            result.activityDrain += kcal / 25
            result.awakeDrain += awakeDrain
            result.stressDrain += stressDrain
        }
        return result
    }
}

enum PhysiologyIntervals {
    static func clip(_ interval: DateInterval, start: Date, end: Date) -> DateInterval? {
        let beginning = max(interval.start, start)
        let ending = min(interval.end, end)
        return ending > beginning ? DateInterval(start: beginning, end: ending) : nil
    }

    static func union(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.filter {
            $0.start.timeIntervalSince1970.isFinite && $0.end.timeIntervalSince1970.isFinite && $0.duration > 0
        }.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        var result: [DateInterval] = []
        for interval in sorted {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else { result.append(interval) }
        }
        return result
    }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    static func mainSleeps(_ intervals: [DateInterval], through now: Date) -> [MainSleep] {
        var episodes: [MainSleep] = []
        for interval in union(intervals) {
            if let last = episodes.last, interval.start.timeIntervalSince(last.end) <= 90 * 60 {
                episodes[episodes.count - 1].intervals.append(interval)
            } else { episodes.append(MainSleep(intervals: [interval])) }
        }
        // Allow daytime main sleep. Wait for the episode's 90-minute merge window
        // to close, so a brief awakening cannot prematurely create a new morning.
        var mains: [MainSleep] = []
        for episode in episodes where (3...16).contains(episode.hours) && episode.end.addingTimeInterval(90 * 60) <= now {
            if let previous = mains.last, episode.start.timeIntervalSince(previous.end) < 12 * 3600,
               episode.hours < 6 { continue }
            mains.append(episode)
        }
        return mains
    }
}

struct MorningRecoveryScorer {
    func assess(sleep: [DateInterval], hrv: [TimedHealthValue], heartRates: [TimedHealthValue],
                now: Date, calendar: Calendar = .current) -> MorningRecovery? {
        let episodes = PhysiologyIntervals.mainSleeps(sleep, through: now)
        guard let main = episodes.last, main.end.addingTimeInterval(36 * 3600) >= now,
              let current = markers(for: main, hrv: hrv, heartRates: heartRates),
              let historyStart = calendar.date(byAdding: .day, value: -30, to: main.start) else { return nil }
        let historical = episodes.filter { $0.end < main.start && $0.start >= historyStart }.compactMap { episode -> (Date, Double, Double)? in
            guard let markers = markers(for: episode, hrv: hrv, heartRates: heartRates) else { return nil }
            return (calendar.startOfDay(for: episode.start), markers.0, markers.1)
        }
        let days = Dictionary(grouping: historical, by: { $0.0 }).values
        let nightlyHRV = days.compactMap { PhysiologyIntervals.median($0.map { $0.1 }) }
        let nightlyHR = days.compactMap { PhysiologyIntervals.median($0.map { $0.2 }) }
        let hrvBaseline = days.count >= 7 ? PhysiologyIntervals.median(nightlyHRV) : nil
        let heartBaseline = days.count >= 7 ? PhysiologyIntervals.median(nightlyHR) : nil
        let input = EnergyInput(heartRateBPM: current.1, heartRateVariabilityMS: current.0,
            restingHeartRateBPM: current.1, sleepHours: main.hours, activeEnergyKcal: 0,
            hrvBaselineMS: hrvBaseline, restingHeartRateBaselineBPM: heartBaseline)
        return MorningRecovery(sleepStart: main.start, sleepEnd: main.end, sleepHours: main.hours,
            hrvMS: current.0, sleepingHeartRateBPM: current.1, hrvBaselineMS: hrvBaseline,
            heartRateBaselineBPM: heartBaseline, baselineNightCount: days.count,
            score: EnergyScorer().computeScores(input: input).recoveryScore)
    }

    private func markers(for episode: MainSleep, hrv: [TimedHealthValue],
                         heartRates: [TimedHealthValue]) -> (Double, Double)? {
        func asleep(_ value: TimedHealthValue) -> Bool {
            episode.intervals.contains { $0.start <= value.end && value.end <= $0.end }
        }
        let variability = Array(Set(hrv.filter {
            $0.value.isFinite && EnergyConfig.default.hrvValidRange.contains($0.value) && asleep($0)
        })).sorted { $0.end < $1.end }
        let hearts = Array(Set(heartRates.filter {
            $0.value.isFinite && EnergyConfig.default.restingHeartRateValidRange.contains($0.value) && asleep($0)
        })).sorted { $0.end < $1.end }
        guard variability.count >= 2, hearts.count >= 6,
              variability.last!.end.timeIntervalSince(variability.first!.end) >= 30 * 60,
              hearts.last!.end.timeIntervalSince(hearts.first!.end) >= 60 * 60,
              let hrvValue = PhysiologyIntervals.median(variability.map(\.value)),
              let heartValue = PhysiologyIntervals.median(hearts.map(\.value)) else { return nil }
        return (hrvValue, heartValue)
    }
}

struct TrainingLoadScorer {
    // Product calibration of observed cardiovascular work, not a clinical limit.
    static let maximumSampleGap: TimeInterval = 120
    static let minimumCoverage = 0.7

    func assess(heartRates: [TimedHealthValue], workouts: [DateInterval], dayStart: Date,
                through now: Date, age: Int?) -> TrainingLoad {
        let maximum = age.flatMap { (18...90).contains($0) ? 208 - 0.7 * Double($0) : nil } ?? 190
        let intervals = PhysiologyIntervals.union(workouts.compactMap {
            PhysiologyIntervals.clip($0, start: dayStart, end: now)
        })
        let duration = intervals.reduce(0) { $0 + $1.duration }
        let points = Dictionary(grouping: heartRates.filter {
            $0.end >= dayStart && $0.end <= now && $0.value.isFinite
                && EnergyConfig.default.heartRateValidRange.contains($0.value)
        }, by: \.end).compactMap { date, values -> (Date, Double)? in
            PhysiologyIntervals.median(Array(Set(values)).map(\.value)).map { (date, $0) }
        }.sorted { $0.0 < $1.0 }
        var observed = 0.0
        var weightedMinutes = 0.0
        for (left, right) in zip(points, points.dropFirst()) {
            let gap = right.0.timeIntervalSince(left.0)
            guard gap > 0, gap <= Self.maximumSampleGap else { continue }
            let pair = DateInterval(start: left.0, end: right.0)
            let seconds = intervals.reduce(0.0) { sum, workout in
                sum + (PhysiologyIntervals.clip(pair, start: workout.start, end: workout.end)?.duration ?? 0)
            }
            let ratio = (left.1 + right.1) / 2 / maximum
            let weight: Double
            switch ratio {
            case ..<0.5: weight = 0
            case ..<0.6: weight = 1
            case ..<0.7: weight = 2
            case ..<0.8: weight = 3
            case ..<0.9: weight = 4
            default: weight = 5
            }
            observed += seconds
            weightedMinutes += seconds / 60 * weight
        }
        let covered = duration == 0 || observed / duration >= Self.minimumCoverage
        let score = covered ? Int((100 * (1 - exp(-weightedMinutes / 180))).rounded()).clamped(to: 0...100) : nil
        return TrainingLoad(dayStart: dayStart, measuredThrough: now, workoutSeconds: duration,
            observedSeconds: observed, weightedMinutes: weightedMinutes, score: score, referenceMaxHeartRate: maximum)
    }
}
