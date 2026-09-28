import Foundation

enum HealthCollectionSource: String, Codable, Equatable, Sendable {
    case iPhone
    case appleWatch
}

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
    var sentAt: Date = .now
    var hasScore: Bool = true
    var isSampleData: Bool = false
    var validUntil: Date?
    var history: [DailyMetrics] = []
    var hourlyStress: [HourlyStress]?
    var recommendationSteps: [String]?
    var recommendationCaution: String?
    var recommendationPurpose: String?
    var statusMessage: String?
    var stress: StressSnapshot?
    var stressAlgorithmVersion: Int? = StressSnapshot.algorithmVersion
    var collectionSource: HealthCollectionSource? = nil
    var activityRecords: [ActivityRecord]? = nil
    var userFeatures: UserFeaturesState? = nil
    var batteryTimeline: [BatteryTimelinePoint]? = nil
    var batteryAssessment: BatteryAssessment? = nil
    var pressureSamples: [EnergyPressureSample]? = nil
    var recommendationActivityType: TrainingActivity? = nil
    var recommendationTargetMinutes: Int? = nil

    var availableBatteryAssessment: BatteryAssessment? {
        guard let batteryAssessment, batteryAssessment.isValid,
              Int(batteryAssessment.level.rounded()) == energyScore else { return nil }
        return batteryAssessment
    }

    var availableStress: StressSnapshot? {
        guard stressAlgorithmVersion == StressSnapshot.algorithmVersion else { return nil }
        if let stress { return stress }
        guard hasScore, let stressScore else { return nil }
        return StressSnapshot(score: stressScore, levelTitle: stressLevelTitle ?? WidgetMetricsSnapshot.stressTitle(for: stressScore),
            updatedAt: metrics?.health?.pressureMeasurement?.sampledAt ?? metrics?.health?.sampleDates[.hrv] ?? updatedAt,
            validUntil: validUntil ?? .distantPast,
            basis: "HRV 估算", hrvMetric: metrics?.health?.pressureMeasurement?.metric)
    }

    var availableHistory: [DailyMetrics] {
        guard stressAlgorithmVersion == StressSnapshot.algorithmVersion else {
            return history.map { DailyMetrics(date: $0.date, energyScore: $0.energyScore,
                recoveryScore: $0.recoveryScore, stressScore: nil) }
        }
        return history.map { $0.matchingPressureMetric(availableStress?.hrvMetric ?? metrics?.health?.pressureMeasurement?.metric ?? .sdnn) }
    }

    var availableHourlyStress: [HourlyStress] {
        guard stressAlgorithmVersion == StressSnapshot.algorithmVersion else { return [] }
        let metric = availableStress?.hrvMetric ?? metrics?.health?.pressureMeasurement?.metric ?? .sdnn
        return (hourlyStress ?? []).filter { ($0.hrvMetric ?? .sdnn) == metric }
    }

    var availableMetrics: WatchKeyMetricsSnapshot? {
        guard var metrics else { return nil }
        metrics.stressScore = availableStress?.score ?? 0
        metrics.stressLevelTitle = availableStress?.levelTitle ?? "暂无评分"
        return metrics
    }

    func isNewer(than previous: WatchSyncPayload?) -> Bool {
        previous.map { sentAt > $0.sentAt } ?? true
    }


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
        self.recommendationSteps = workoutRecommendation?.steps
        self.recommendationCaution = workoutRecommendation?.cautionText
        self.recommendationPurpose = workoutRecommendation?.purposeText
        self.recommendationActivityType = workoutRecommendation?.activityType
        self.recommendationTargetMinutes = workoutRecommendation?.targetMinutes
        self.isSampleData = sampleScenarioTitle != nil
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
            purposeText: recommendationPurpose ?? fallback.purposeText,
            cautionText: recommendationCaution ?? fallback.cautionText,
            steps: recommendationSteps ?? fallback.steps,
            activityType: recommendationActivityType, targetMinutes: recommendationTargetMinutes
        )
    }

    func widgetSnapshot(fallback: WidgetMetricsSnapshot? = nil) -> WidgetMetricsSnapshot? {
        guard !isSampleData, sampleScenarioTitle == nil, hasScore || availableStress != nil else { return nil }

        return WidgetMetricsSnapshot(
            energyScore: energyScore,
            recoveryScore: recoveryScore,
            stressScore: availableStress?.score ?? 0,
            stressLevelTitle: availableStress?.levelTitle ?? "暂无评分",
            updatedAt: updatedAt, validUntil: validUntil, hasData: hasScore, stress: availableStress
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
        context["stressAlgorithmVersion"] = stressAlgorithmVersion
        context["sampleScenarioTitle"] = sampleScenarioTitle
        context["sampleScenarioSummary"] = sampleScenarioSummary
        context["bodyStatusState"] = bodyStatus?.state.rawValue
        context["bodyStatusTitle"] = bodyStatus?.title
        context["bodyStatusDetail"] = bodyStatus?.detail
        context["bodyStatusAction"] = bodyStatus?.action
        var wire = self
        // Completed actions also travel independently, so detailed sleep and
        // current readings fit within WatchConnectivity's message budget.
        wire.activityRecords = activityRecords.map { Array($0.prefix(20)) }
        func encoded() -> Data? {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            return try? encoder.encode(wire)
        }
        var data = encoded()
        if (data?.count ?? 0) > 55 * 1024 {
            wire.batteryTimeline = Array((batteryTimeline ?? []).suffix(8))
            wire.pressureSamples = Array((pressureSamples ?? []).suffix(8))
            wire.activityRecords = nil
            data = encoded()
        }
        if (data?.count ?? 0) > 55 * 1024 {
            wire.metrics?.health?.sleepDetails = nil
            data = encoded()
        }
        if let data, data.count <= 55 * 1024 { context["payloadV2"] = data }
        return context
    }

    init?(applicationContext: [String: Any]) {
        if let data = applicationContext["payloadV2"] as? Data {
            guard data.count <= 60 * 1024, let decoded = try? JSONDecoder().decode(Self.self, from: data),
                  !decoded.isSampleData, decoded.sampleScenarioTitle == nil,
                  (0...100).contains(decoded.energyScore), (0...100).contains(decoded.recoveryScore),
                  decoded.stressScore.map({ (0...100).contains($0) }) ?? true else { return nil }
            self = decoded
            return
        }
        guard applicationContext["sampleScenarioTitle"] == nil,
              applicationContext["isSampleData"] as? Bool != true else { return nil }
        // Older senders do not identify measurement freshness.
        self.hasScore = false

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
        self.stressAlgorithmVersion = applicationContext["stressAlgorithmVersion"] as? Int
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
                stressLevelTitle: applicationContext["stressLevelTitle"] as? String ?? WidgetMetricsSnapshot.stressTitle(for: stressScore)
            )
        } else {
            self.metrics = nil
        }

        self.updatedAt = Date(timeIntervalSince1970: timestamp)
        self.sentAt = updatedAt
    }
}
