import Foundation

struct EnergyConfig: Sendable {
    struct Baselines: Sendable {
        var targetSleepHours: Double = 8.0
        var restorativeSleepFloorHours: Double = 6.0
        var targetHRV: Double = 60.0
        var targetRestingHeartRate: Double = 55.0
        // Product scoring calibration; these targets are not personal baselines.
        var recoveryMarkerScoreAtTarget: Double = 0.8
        var targetActiveEnergyKcal: Double = 650.0
        var activityBalanceToleranceKcal: Double = 260.0
        var overloadActiveEnergyKcal: Double = 1150.0
        var heartRateReserveBufferBPM: Double = 24.0
        var heartRateReserveRampBPM: Double = 12.0
    }

    struct Weights: Sendable {
        var recoverySleep: Double = 0.38
        var recoveryHRV: Double = 0.37
        var recoveryRHR: Double = 0.25

        var fatigueHeartRate: Double = 0.42
        var fatigueSleepDebt: Double = 0.24
        var fatigueActivity: Double = 0.34

        var energyRecovery: Double = 0.64
        var energyFatigueResistance: Double = 0.24
        var energyActivityBalance: Double = 0.12
    }

    // Product estimates, not clinical sleep-debt or sleep-regularity measures.
    struct SleepHistory: Sendable {
        var windowDays = 7
        var minimumRecordedDays = 3
        var maximumDebtHours = 12.0
        var surplusRepaymentFraction = 0.5
        var maximumDailyRepaymentHours = 2.0
        var minimumTimingPairs = 2
        var irregularityFullScaleMinutes = 180.0
        var maximumDebtPenalty = 12.0
        var maximumRegularityPenalty = 6.0
    }

    var baselines = Baselines()
    var weights = Weights()
    var sleepHistory = SleepHistory()

    var sleepValidRange: ClosedRange<Double> = 0...16
    var hrvValidRange: ClosedRange<Double> = 5...220
    var restingHeartRateValidRange: ClosedRange<Double> = 30...120
    var heartRateValidRange: ClosedRange<Double> = 35...210
    var activeEnergyValidRange: ClosedRange<Double> = 0...6000

    static let `default` = EnergyConfig()
}
