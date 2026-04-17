import Foundation

struct WatchSyncPayload: Codable, Equatable, Sendable {
    var energyScore: Int
    var recoveryScore: Int
    var recommendation: String
    var recommendationTitle: String?
    var recommendationDurationText: String?
    var recommendationIntensityText: String?
    var metrics: WatchKeyMetricsSnapshot?
    var stressScore: Int?
    var stressLevelTitle: String?
    var sampleScenarioTitle: String?
    var sampleScenarioSummary: String?
    var bodyStatus: BodyStatusDescriptor?
    var updatedAt: Date

    init(
        snapshot: EnergySnapshot,
        workoutRecommendation: WorkoutRecommendation? = nil,
        metrics: WatchKeyMetricsSnapshot? = nil,
        stressScore: Int? = nil,
        stressLevelTitle: String? = nil,
        sampleScenarioTitle: String? = nil,
        sampleScenarioSummary: String? = nil,
        bodyStatus: BodyStatusDescriptor? = nil
    ) {
        self.energyScore = snapshot.energyScore
        self.recoveryScore = snapshot.recoveryScore
        self.recommendation = snapshot.recommendation
        self.recommendationTitle = workoutRecommendation?.title
        self.recommendationDurationText = workoutRecommendation?.durationText
        self.recommendationIntensityText = workoutRecommendation?.intensityText
        self.metrics = metrics
        self.stressScore = stressScore
        self.stressLevelTitle = stressLevelTitle
        self.sampleScenarioTitle = sampleScenarioTitle
        self.sampleScenarioSummary = sampleScenarioSummary
        self.bodyStatus = bodyStatus
        self.updatedAt = snapshot.updatedAt
    }

    var asSnapshot: EnergySnapshot {
        EnergySnapshot(
            energyScore: energyScore,
            recoveryScore: recoveryScore,
            recommendation: recommendation,
            updatedAt: updatedAt
        )
    }

    var workoutRecommendation: WorkoutRecommendation {
        let fallback = WorkoutRecommendation.fallback(summary: recommendation, energyScore: energyScore)
        return WorkoutRecommendation(
            title: recommendationTitle ?? fallback.title,
            summary: recommendation,
            durationText: recommendationDurationText ?? fallback.durationText,
            intensityText: recommendationIntensityText ?? fallback.intensityText,
            purposeText: fallback.purposeText,
            cautionText: fallback.cautionText,
            steps: fallback.steps
        )
    }

    func widgetSnapshot(fallback: WidgetMetricsSnapshot? = nil) -> WidgetMetricsSnapshot? {
        let resolvedFallback = fallback ?? .preview
        guard let stressScore else { return nil }

        return WidgetMetricsSnapshot(
            energyScore: energyScore,
            recoveryScore: recoveryScore,
            stressScore: stressScore,
            stressLevelTitle: stressLevelTitle ?? resolvedFallback.stressLevelTitle,
            updatedAt: updatedAt
        )
    }

    var applicationContext: [String: Any] {
        var context: [String: Any] = [
            "energyScore": energyScore,
            "recoveryScore": recoveryScore,
            "recommendation": recommendation,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]

        context["recommendationTitle"] = recommendationTitle
        context["recommendationDurationText"] = recommendationDurationText
        context["recommendationIntensityText"] = recommendationIntensityText
        context["heartRateBPM"] = metrics?.heartRateBPM
        context["heartRateVariabilityMS"] = metrics?.heartRateVariabilityMS
        context["restingHeartRateBPM"] = metrics?.restingHeartRateBPM
        context["sleepHours"] = metrics?.sleepHours
        context["activeEnergyKcal"] = metrics?.activeEnergyKcal
        context["stressScore"] = stressScore
        context["stressLevelTitle"] = stressLevelTitle
        context["sampleScenarioTitle"] = sampleScenarioTitle
        context["sampleScenarioSummary"] = sampleScenarioSummary
        context["bodyStatusState"] = bodyStatus?.state.rawValue
        context["bodyStatusTitle"] = bodyStatus?.title
        context["bodyStatusDetail"] = bodyStatus?.detail
        context["bodyStatusAction"] = bodyStatus?.action
        return context
    }

    init?(applicationContext: [String: Any]) {
        guard
            let energyScore = applicationContext["energyScore"] as? Int,
            let recoveryScore = applicationContext["recoveryScore"] as? Int,
            let recommendation = applicationContext["recommendation"] as? String,
            let timestamp = applicationContext["updatedAt"] as? TimeInterval
        else {
            return nil
        }

        self.energyScore = energyScore
        self.recoveryScore = recoveryScore
        self.recommendation = recommendation
        self.recommendationTitle = applicationContext["recommendationTitle"] as? String
        self.recommendationDurationText = applicationContext["recommendationDurationText"] as? String
        self.recommendationIntensityText = applicationContext["recommendationIntensityText"] as? String
        self.stressScore = applicationContext["stressScore"] as? Int
        self.stressLevelTitle = applicationContext["stressLevelTitle"] as? String
        self.sampleScenarioTitle = applicationContext["sampleScenarioTitle"] as? String
        self.sampleScenarioSummary = applicationContext["sampleScenarioSummary"] as? String

        if
            let stateRawValue = applicationContext["bodyStatusState"] as? String,
            let state = BodyBatteryState(rawValue: stateRawValue),
            let title = applicationContext["bodyStatusTitle"] as? String,
            let detail = applicationContext["bodyStatusDetail"] as? String,
            let action = applicationContext["bodyStatusAction"] as? String
        {
            self.bodyStatus = BodyStatusDescriptor(
                state: state,
                title: title,
                detail: detail,
                action: action
            )
        } else {
            self.bodyStatus = nil
        }

        if
            let heartRateBPM = applicationContext["heartRateBPM"] as? Double,
            let heartRateVariabilityMS = applicationContext["heartRateVariabilityMS"] as? Double,
            let restingHeartRateBPM = applicationContext["restingHeartRateBPM"] as? Double,
            let sleepHours = applicationContext["sleepHours"] as? Double,
            let activeEnergyKcal = applicationContext["activeEnergyKcal"] as? Double,
            let stressScore = applicationContext["stressScore"] as? Int
        {
            self.metrics = WatchKeyMetricsSnapshot(
                heartRateBPM: heartRateBPM,
                heartRateVariabilityMS: heartRateVariabilityMS,
                restingHeartRateBPM: restingHeartRateBPM,
                sleepHours: sleepHours,
                activeEnergyKcal: activeEnergyKcal,
                stressScore: stressScore,
                stressLevelTitle: applicationContext["stressLevelTitle"] as? String ?? WidgetMetricsSnapshot.preview.stressLevelTitle
            )
        } else {
            self.metrics = nil
        }

        self.updatedAt = Date(timeIntervalSince1970: timestamp)
    }
}
