import XCTest
@testable import BodyEnergy

final class WatchSyncPayloadTests: XCTestCase {
    func testPayloadCarriesStructuredRecommendationFieldsStressAndBodyStatus() {
        let recommendation = WorkoutRecommendation(
            title: "二区有氧恢复课",
            summary: "身体状态平稳，建议以二区有氧为主，并适当减少训练总量。",
            durationText: "20 到 30 分钟",
            intensityText: "低到中等强度",
            purposeText: "维持心肺刺激。",
            cautionText: "疲劳明显时降低训练量。",
            steps: ["热身", "主训练", "放松"]
        )
        let snapshot = EnergySnapshot(
            energyScore: 61,
            recoveryScore: 64,
            recommendation: recommendation.summary,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let bodyStatus = BodyStatusDescriptor.make(energyScore: snapshot.energyScore)

        let payload = WatchSyncPayload(
            snapshot: snapshot,
            workoutRecommendation: recommendation,
            metrics: WatchKeyMetricsSnapshot(
                heartRateBPM: 72,
                heartRateVariabilityMS: 55,
                restingHeartRateBPM: 58,
                sleepHours: 7.5,
                activeEnergyKcal: 520,
                stressScore: 48,
                stressLevelTitle: "压力适中"
            ),
            stressScore: 48,
            stressLevelTitle: "压力适中",
            sampleScenarioTitle: "状态平稳",
            sampleScenarioSummary: "恢复和活动负荷比较均衡。",
            bodyStatus: bodyStatus
        )
        let restored = WatchSyncPayload(applicationContext: payload.applicationContext)

        XCTAssertEqual(restored?.recommendationTitle, recommendation.title)
        XCTAssertEqual(restored?.recommendationDurationText, recommendation.durationText)
        XCTAssertEqual(restored?.recommendationIntensityText, recommendation.intensityText)
        XCTAssertEqual(restored?.stressScore, 48)
        XCTAssertEqual(restored?.stressLevelTitle, "压力适中")
        XCTAssertEqual(restored?.sampleScenarioTitle, "状态平稳")
        XCTAssertEqual(restored?.sampleScenarioSummary, "恢复和活动负荷比较均衡。")
        XCTAssertEqual(restored?.bodyStatus?.title, bodyStatus.title)
        XCTAssertEqual(restored?.bodyStatus?.detail, bodyStatus.detail)
        XCTAssertEqual(restored?.bodyStatus?.action, bodyStatus.action)
        XCTAssertEqual(restored?.metrics?.heartRateBPM, 72)
        XCTAssertEqual(restored?.metrics?.heartRateVariabilityMS, 55)
        XCTAssertEqual(restored?.metrics?.restingHeartRateBPM, 58)
        XCTAssertEqual(restored?.metrics?.sleepHours, 7.5)
        XCTAssertEqual(restored?.metrics?.activeEnergyKcal, 520)
    }

    func testPayloadFallsBackToDisplayableRecommendationWhenStructuredFieldsMissing() {
        let payload = WatchSyncPayload(applicationContext: [
            "energyScore": 28,
            "recoveryScore": 33,
            "recommendation": "身体状态偏低，优先恢复，可安排轻松步行、补水和更早入睡。",
            "updatedAt": Date.now.timeIntervalSince1970
        ])

        XCTAssertEqual(payload?.workoutRecommendation.title, "今日恢复建议")
        XCTAssertFalse(payload?.workoutRecommendation.steps.isEmpty ?? true)
        XCTAssertNil(payload?.stressScore)
        XCTAssertNil(payload?.stressLevelTitle)
        XCTAssertNil(payload?.metrics)
    }

    func testWidgetSnapshotFallsBackToPreviousStressTitle() {
        let payload = WatchSyncPayload(
            snapshot: EnergySnapshot(
                energyScore: 52,
                recoveryScore: 58,
                recommendation: "今天适合稳态训练。",
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            stressScore: 62
        )
        let fallback = WidgetMetricsSnapshot.preview

        let widgetSnapshot = payload.widgetSnapshot(fallback: fallback)

        XCTAssertEqual(widgetSnapshot?.energyScore, 52)
        XCTAssertEqual(widgetSnapshot?.recoveryScore, 58)
        XCTAssertEqual(widgetSnapshot?.stressScore, 62)
        XCTAssertEqual(widgetSnapshot?.stressLevelTitle, fallback.stressLevelTitle)
    }
}
