import Foundation

struct HealthSnapshot: Equatable, Sendable {
    var heartRateBPM: Double
    var heartRateVariabilityMS: Double
    var restingHeartRateBPM: Double
    var sleepHours: Double
    var activeEnergyKcal: Double

    static let baseline = HealthSnapshot(
        heartRateBPM: 72,
        heartRateVariabilityMS: 55,
        restingHeartRateBPM: 58,
        sleepHours: 7.5,
        activeEnergyKcal: 520
    )
}
