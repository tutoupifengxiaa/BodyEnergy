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

    func testRecoveryAndEnergyAreHigherForRestedInput() {
        let scorer = EnergyScorer()

        let rested = EnergyInput(
            heartRateBPM: 78,
            heartRateVariabilityMS: 72,
            restingHeartRateBPM: 52,
            sleepHours: 8.3,
            activeEnergyKcal: 520
        )

        let fatigued = EnergyInput(
            heartRateBPM: 154,
            heartRateVariabilityMS: 24,
            restingHeartRateBPM: 71,
            sleepHours: 4.9,
            activeEnergyKcal: 1420
        )

        let restedScores = scorer.computeScores(input: rested)
        let fatiguedScores = scorer.computeScores(input: fatigued)

        XCTAssertGreaterThan(restedScores.recoveryScore, fatiguedScores.recoveryScore)
        XCTAssertGreaterThan(restedScores.energyScore, fatiguedScores.energyScore)
    }

    func testModerateTrainingLoadIsPreferredOverExcessiveLoad() {
        let scorer = EnergyScorer()

        let moderateLoad = EnergyInput(
            heartRateBPM: 118,
            heartRateVariabilityMS: 58,
            restingHeartRateBPM: 56,
            sleepHours: 7.8,
            activeEnergyKcal: 640
        )

        let excessiveLoad = EnergyInput(
            heartRateBPM: 178,
            heartRateVariabilityMS: 58,
            restingHeartRateBPM: 56,
            sleepHours: 7.8,
            activeEnergyKcal: 2200
        )

        let moderateScores = scorer.computeScores(input: moderateLoad)
        let excessiveScores = scorer.computeScores(input: excessiveLoad)

        XCTAssertGreaterThan(moderateScores.energyScore, excessiveScores.energyScore)
        XCTAssertGreaterThan(excessiveScores.trainingLoadScore, moderateScores.trainingLoadScore)
    }
}
