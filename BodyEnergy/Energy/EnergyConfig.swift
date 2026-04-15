import Foundation

struct EnergyConfig: Sendable {
    struct Baselines: Sendable {
        var targetSleepHours: Double = 8.0
        var targetHRV: Double = 60.0
        var targetRestingHeartRate: Double = 55.0
        var targetTrainingHeartRate: Double = 140.0
        var targetActiveEnergyKcal: Double = 650.0
    }

    struct Weights: Sendable {
        var recoverySleep: Double = 0.35
        var recoveryHRV: Double = 0.40
        var recoveryRHR: Double = 0.25

        var loadHeartRate: Double = 0.45
        var loadActiveEnergy: Double = 0.55

        var energyRecovery: Double = 0.70
        var energyLoad: Double = 0.30
    }

    var baselines = Baselines()
    var weights = Weights()

    var sleepValidRange: ClosedRange<Double> = 0...16
    var hrvValidRange: ClosedRange<Double> = 5...220
    var restingHeartRateValidRange: ClosedRange<Double> = 30...120
    var heartRateValidRange: ClosedRange<Double> = 35...210
    var activeEnergyValidRange: ClosedRange<Double> = 0...6000

    static let `default` = EnergyConfig()
}
