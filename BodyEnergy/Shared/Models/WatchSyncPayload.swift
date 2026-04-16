import Foundation

struct WatchSyncPayload: Codable, Equatable, Sendable {
    var energyScore: Int
    var recoveryScore: Int
    var recommendation: String
    var recommendationTitle: String?
    var recommendationDurationText: String?
    var recommendationIntensityText: String?
    var stressScore: Int?
    var stressLevelTitle: String?
    var updatedAt: Date

    init(
        snapshot: EnergySnapshot,
        workoutRecommendation: WorkoutRecommendation? = nil,
        stressScore: Int? = nil,
        stressLevelTitle: String? = nil
    ) {
        self.energyScore = snapshot.energyScore
        self.recoveryScore = snapshot.recoveryScore
        self.recommendation = snapshot.recommendation
        self.recommendationTitle = workoutRecommendation?.title
        self.recommendationDurationText = workoutRecommendation?.durationText
        self.recommendationIntensityText = workoutRecommendation?.intensityText
        self.stressScore = stressScore
        self.stressLevelTitle = stressLevelTitle
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
            energySnapshot: asSnapshot,
            stressScore: stressScore,
            stressLevelTitle: stressLevelTitle ?? resolvedFallback.stressLevelTitle
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
        context["stressScore"] = stressScore
        context["stressLevelTitle"] = stressLevelTitle
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
        self.updatedAt = Date(timeIntervalSince1970: timestamp)
    }
}
