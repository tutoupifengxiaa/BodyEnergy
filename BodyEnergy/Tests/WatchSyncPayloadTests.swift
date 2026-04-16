import XCTest
@testable import BodyEnergy

final class WatchSyncPayloadTests: XCTestCase {
    func testPayloadCarriesStructuredRecommendationFieldsAndStress() {
        let recommendation = WorkoutRecommendation(
            title: "二区有氧恢复跑",
            summary: "身体状态中等，建议以二区有氧为主，并适当减少训练总量。",
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

        let payload = WatchSyncPayload(
            snapshot: snapshot,
            workoutRecommendation: recommendation,
            stressScore: 48,
            stressLevelTitle: "压力适中"
        )
        let restored = WatchSyncPayload(applicationContext: payload.applicationContext)

        XCTAssertEqual(restored?.recommendationTitle, recommendation.title)
        XCTAssertEqual(restored?.recommendationDurationText, recommendation.durationText)
        XCTAssertEqual(restored?.recommendationIntensityText, recommendation.intensityText)
        XCTAssertEqual(restored?.stressScore, 48)
        XCTAssertEqual(restored?.stressLevelTitle, "压力适中")
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
