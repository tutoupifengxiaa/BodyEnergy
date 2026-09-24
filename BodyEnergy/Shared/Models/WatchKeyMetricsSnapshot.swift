import Foundation

struct WatchKeyMetricsSnapshot: Codable, Equatable, Sendable {
    var heartRateBPM: Double
    var heartRateVariabilityMS: Double
    var restingHeartRateBPM: Double
    var sleepHours: Double
    var activeEnergyKcal: Double
    var stressScore: Int
    var stressLevelTitle: String
    var health: HealthSnapshot? = nil

    init(
        health: HealthSnapshot,
        stressScore: Int,
        stressLevelTitle: String
    ) {
        self.health = health
        self.heartRateBPM = health.heartRateBPM
        self.heartRateVariabilityMS = health.heartRateVariabilityMS
        self.restingHeartRateBPM = health.restingHeartRateBPM
        self.sleepHours = health.sleepHours
        self.activeEnergyKcal = health.activeEnergyKcal
        self.stressScore = stressScore
        self.stressLevelTitle = stressLevelTitle
    }

    init(
        heartRateBPM: Double,
        heartRateVariabilityMS: Double,
        restingHeartRateBPM: Double,
        sleepHours: Double,
        activeEnergyKcal: Double,
        stressScore: Int,
        stressLevelTitle: String
    ) {
        self.heartRateBPM = heartRateBPM
        self.heartRateVariabilityMS = heartRateVariabilityMS
        self.restingHeartRateBPM = restingHeartRateBPM
        self.sleepHours = sleepHours
        self.activeEnergyKcal = activeEnergyKcal
        self.stressScore = stressScore
        self.stressLevelTitle = stressLevelTitle
    }

    static let empty = WatchKeyMetricsSnapshot(health: .empty, stressScore: 0, stressLevelTitle: "暂无评分")

    static let preview = WatchKeyMetricsSnapshot(
        heartRateBPM: 72,
        heartRateVariabilityMS: 55,
        restingHeartRateBPM: 58,
        sleepHours: 7.5,
        activeEnergyKcal: 520,
        stressScore: 38,
        stressLevelTitle: "压力适中"
    )
}
