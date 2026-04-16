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

        let sleepRatio = input.sleepHours / config.baselines.targetSleepHours
        let sleepScore = normalizedPositive(sleepRatio)
        let sleepDebtPenalty = normalizedInverse(sleepRatio)
        let hrvScore = normalizedPositive(input.heartRateVariabilityMS / config.baselines.targetHRV)

        let rhrRatio = input.restingHeartRateBPM / config.baselines.targetRestingHeartRate
        let rhrScore = normalizedInverse(rhrRatio)

        let baseRecovery = weighted(
            [sleepScore, hrvScore, rhrScore],
            [config.weights.recoverySleep, config.weights.recoveryHRV, config.weights.recoveryRHR]
        )
        let recovery = (
            baseRecovery * 0.88 +
            sleepDebtPenalty * 0.12
        )
        let boundedRecovery = bounded(recovery, to: 0...1)

        let hrLoad = normalizedPositive(input.heartRateBPM / config.baselines.targetTrainingHeartRate)
        let energyLoad = normalizedPositive(input.activeEnergyKcal / config.baselines.targetActiveEnergyKcal)

        let load = weighted(
            [hrLoad, energyLoad],
            [config.weights.loadHeartRate, config.weights.loadActiveEnergy]
        )
        let loadBalance = centeredScore(load, target: 0.52, tolerance: 0.24)

        let energy = (
            config.weights.energyRecovery * boundedRecovery +
            config.weights.energyLoad * loadBalance
        )
        let boundedEnergy = bounded(energy, to: 0...1)

        return EnergyScores(
            recoveryScore: bounded(Int((boundedRecovery * 100).rounded()), to: 0...100),
            energyScore: bounded(Int((boundedEnergy * 100).rounded()), to: 0...100),
            trainingLoadScore: bounded(Int((load * 100).rounded()), to: 0...100)
        )
    }

    private func sanitize(_ input: EnergyInput) -> EnergyInput {
        EnergyInput(
            heartRateBPM: bounded(input.heartRateBPM, to: config.heartRateValidRange),
            heartRateVariabilityMS: bounded(input.heartRateVariabilityMS, to: config.hrvValidRange),
            restingHeartRateBPM: bounded(input.restingHeartRateBPM, to: config.restingHeartRateValidRange),
            sleepHours: bounded(input.sleepHours, to: config.sleepValidRange),
            activeEnergyKcal: bounded(input.activeEnergyKcal, to: config.activeEnergyValidRange)
        )
    }

    private func normalizedPositive(_ ratio: Double) -> Double {
        sigmoid((ratio - 1) * 2.2)
    }

    private func normalizedInverse(_ ratio: Double) -> Double {
        sigmoid((1 - ratio) * 2.4)
    }

    private func centeredScore(_ value: Double, target: Double, tolerance: Double) -> Double {
        let distance = abs(value - target)
        let normalizedDistance = bounded(distance / tolerance, to: 0...1.6)
        return bounded(1 - normalizedDistance, to: 0...1)
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
