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

    func testSleepDebtReducesRecoveryEvenWhenCardioMarkersMatch() {
        let scorer = EnergyScorer()

        let wellRested = EnergyInput(
            heartRateBPM: 82,
            heartRateVariabilityMS: 61,
            restingHeartRateBPM: 55,
            sleepHours: 8.1,
            activeEnergyKcal: 680
        )

        let sleepDeprived = EnergyInput(
            heartRateBPM: 82,
            heartRateVariabilityMS: 61,
            restingHeartRateBPM: 55,
            sleepHours: 5.2,
            activeEnergyKcal: 680
        )

        let restedScores = scorer.computeScores(input: wellRested)
        let deprivedScores = scorer.computeScores(input: sleepDeprived)

        XCTAssertGreaterThan(restedScores.recoveryScore, deprivedScores.recoveryScore)
        XCTAssertGreaterThan(restedScores.energyScore, deprivedScores.energyScore)
    }

    func testElevatedCurrentHeartRatePenalizesEnergy() {
        let scorer = EnergyScorer()

        let calm = EnergyInput(
            heartRateBPM: 78,
            heartRateVariabilityMS: 58,
            restingHeartRateBPM: 56,
            sleepHours: 7.7,
            activeEnergyKcal: 640
        )

        let strained = EnergyInput(
            heartRateBPM: 132,
            heartRateVariabilityMS: 58,
            restingHeartRateBPM: 56,
            sleepHours: 7.7,
            activeEnergyKcal: 640
        )

        let calmScores = scorer.computeScores(input: calm)
        let strainedScores = scorer.computeScores(input: strained)

        XCTAssertGreaterThan(calmScores.energyScore, strainedScores.energyScore)
        XCTAssertGreaterThan(strainedScores.trainingLoadScore, calmScores.trainingLoadScore)
    }
}
