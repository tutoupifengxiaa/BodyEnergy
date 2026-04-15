import Foundation

struct EnergyInput: Sendable {
    var heartRateBPM: Double
    var heartRateVariabilityMS: Double
    var restingHeartRateBPM: Double
    var sleepHours: Double
    var activeEnergyKcal: Double

    init(
        heartRateBPM: Double,
        heartRateVariabilityMS: Double,
        restingHeartRateBPM: Double,
        sleepHours: Double,
        activeEnergyKcal: Double
    ) {
        self.heartRateBPM = heartRateBPM
        self.heartRateVariabilityMS = heartRateVariabilityMS
        self.restingHeartRateBPM = restingHeartRateBPM
        self.sleepHours = sleepHours
        self.activeEnergyKcal = activeEnergyKcal
    }
}

extension EnergyInput {
    init(snapshot: HealthSnapshot) {
        self.init(
            heartRateBPM: snapshot.heartRateBPM,
            heartRateVariabilityMS: snapshot.heartRateVariabilityMS,
            restingHeartRateBPM: snapshot.restingHeartRateBPM,
            sleepHours: snapshot.sleepHours,
            activeEnergyKcal: snapshot.activeEnergyKcal
        )
    }
}
