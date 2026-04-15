import XCTest
@testable import BodyEnergy

final class EnergyScorerTests: XCTestCase {
    func testScoresAreWithinRange() {
        let input = EnergyInput(
            heartRateBPM: 160,
            heartRateVariabilityMS: 42,
            restingHeartRateBPM: 62,
            sleepHours: 6.4,
            activeEnergyKcal: 830
        )

        let scores = EnergyScorer().computeScores(input: input)

        XCTAssertTrue((0...100).contains(scores.recoveryScore))
        XCTAssertTrue((0...100).contains(scores.energyScore))
        XCTAssertTrue((0...100).contains(scores.trainingLoadScore))
    }
}
