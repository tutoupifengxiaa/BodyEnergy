import XCTest
@testable import BodyEnergy

final class RecommendationEngineTests: XCTestCase {
    func testHighEnergyBuildsHigherIntensityPlan() {
        let plan = RecommendationEngine().plan(
            for: EnergyScores(recoveryScore: 84, energyScore: 82, trainingLoadScore: 46)
        )

        XCTAssertEqual(plan.title, "力量或间歇主训练")
        XCTAssertTrue(plan.intensityText.contains("中高强度"))
        XCTAssertEqual(plan.summary, RecommendationEngine().recommendation(
            for: EnergyScores(recoveryScore: 84, energyScore: 82, trainingLoadScore: 46)
        ))
    }

    func testLowEnergyBuildsRecoveryPlan() {
        let plan = RecommendationEngine().plan(
            for: EnergyScores(recoveryScore: 28, energyScore: 24, trainingLoadScore: 68)
        )

        XCTAssertEqual(plan.title, "轻松步行与恢复")
        XCTAssertTrue(plan.cautionText.contains("恢复"))
        XCTAssertEqual(plan.steps.count, 3)
    }
}
