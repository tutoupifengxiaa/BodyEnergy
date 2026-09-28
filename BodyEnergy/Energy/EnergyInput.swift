import Foundation

struct EnergyInput: Sendable {
    var heartRateBPM: Double
    var heartRateVariabilityMS: Double
    var restingHeartRateBPM: Double
    var sleepHours: Double
    var activeEnergyKcal: Double
    var hrvBaselineMS: Double? = nil
    var restingHeartRateBaselineBPM: Double? = nil

    init(
        heartRateBPM: Double,
        heartRateVariabilityMS: Double,
        restingHeartRateBPM: Double,
        sleepHours: Double,
        activeEnergyKcal: Double,
        hrvBaselineMS: Double? = nil,
        restingHeartRateBaselineBPM: Double? = nil
    ) {
        self.heartRateBPM = heartRateBPM
        self.heartRateVariabilityMS = heartRateVariabilityMS
        self.restingHeartRateBPM = restingHeartRateBPM
        self.sleepHours = sleepHours
        self.activeEnergyKcal = activeEnergyKcal
        self.hrvBaselineMS = hrvBaselineMS
        self.restingHeartRateBaselineBPM = restingHeartRateBaselineBPM
    }
}

extension EnergyInput {
    init(snapshot: HealthSnapshot) {
        self.init(
            heartRateBPM: snapshot.heartRateIsSedentary == true
                ? snapshot.heartRateBPM : snapshot.restingHeartRateBPM,
            heartRateVariabilityMS: snapshot.heartRateVariabilityMS,
            restingHeartRateBPM: snapshot.restingHeartRateBPM,
            sleepHours: snapshot.sleepHours,
            activeEnergyKcal: snapshot.activeEnergyKcal,
            hrvBaselineMS: snapshot.hrvBaselineMS,
            restingHeartRateBaselineBPM: snapshot.restingHeartRateBaselineBPM
        )
    }
}
