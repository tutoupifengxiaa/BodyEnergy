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

        let sleepScore = normalizedPositive(input.sleepHours / config.baselines.targetSleepHours)
        let hrvScore = normalizedPositive(input.heartRateVariabilityMS / config.baselines.targetHRV)

        let rhrRatio = input.restingHeartRateBPM / config.baselines.targetRestingHeartRate
        let rhrScore = normalizedInverse(rhrRatio)

        let recovery = weighted(
            [sleepScore, hrvScore, rhrScore],
            [config.weights.recoverySleep, config.weights.recoveryHRV, config.weights.recoveryRHR]
        )

        let hrLoad = normalizedPositive(input.heartRateBPM / config.baselines.targetTrainingHeartRate)
        let energyLoad = normalizedPositive(input.activeEnergyKcal / config.baselines.targetActiveEnergyKcal)

        let load = weighted(
            [hrLoad, energyLoad],
            [config.weights.loadHeartRate, config.weights.loadActiveEnergy]
        )

        let energy = (
            config.weights.energyRecovery * recovery +
            config.weights.energyLoad * (1 - load)
        ).clamped(to: 0...1)

        return EnergyScores(
            recoveryScore: Int((recovery * 100).rounded()).clamped(to: 0...100),
            energyScore: Int((energy * 100).rounded()).clamped(to: 0...100),
            trainingLoadScore: Int((load * 100).rounded()).clamped(to: 0...100)
        )
    }

    private func sanitize(_ input: EnergyInput) -> EnergyInput {
        EnergyInput(
            heartRateBPM: input.heartRateBPM.clamped(to: config.heartRateValidRange),
            heartRateVariabilityMS: input.heartRateVariabilityMS.clamped(to: config.hrvValidRange),
            restingHeartRateBPM: input.restingHeartRateBPM.clamped(to: config.restingHeartRateValidRange),
            sleepHours: input.sleepHours.clamped(to: config.sleepValidRange),
            activeEnergyKcal: input.activeEnergyKcal.clamped(to: config.activeEnergyValidRange)
        )
    }

    private func normalizedPositive(_ ratio: Double) -> Double {
        sigmoid((ratio - 1) * 2.2)
    }

    private func normalizedInverse(_ ratio: Double) -> Double {
        sigmoid((1 - ratio) * 2.4)
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
        return (numerator / denominator).clamped(to: 0...1)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
