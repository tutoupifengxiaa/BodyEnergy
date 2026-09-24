import XCTest
@testable import BodyEnergy

final class EnergyScorerTests: XCTestCase {
    func testShortSleepContinuesToReduceRecoveryAndEnergyBelowSixHours() {
        let scorer = EnergyScorer()
        var input = EnergyInput(heartRateBPM: 65, heartRateVariabilityMS: 60,
                                restingHeartRateBPM: 55, sleepHours: 1, activeEnergyKcal: 100)
        let scores = [1.0, 4.0, 6.0, 8.0].map { hours in
            input.sleepHours = hours
            return scorer.computeScores(input: input)
        }

        for index in 1..<scores.count {
            XCTAssertGreaterThan(scores[index].recoveryScore, scores[index - 1].recoveryScore)
            XCTAssertGreaterThan(scores[index].energyScore, scores[index - 1].energyScore)
        }
        XCTAssertEqual(scores[2].energyScore, 59)
        XCTAssertEqual(scores[3].energyScore, 90)
    }

    func testSleepBeyondTargetDoesNotReduceScores() {
        let scorer = EnergyScorer()
        var input = EnergyInput(heartRateBPM: 65, heartRateVariabilityMS: 60,
                                restingHeartRateBPM: 55, sleepHours: 8, activeEnergyKcal: 100)
        let rested = scorer.computeScores(input: input)

        for hours in [8.5, 9.0, 10.0, 11.0, 16.0] {
            input.sleepHours = hours
            let scores = scorer.computeScores(input: input)
            XCTAssertEqual(scores.recoveryScore, rested.recoveryScore, "Sleep: \(hours) hours")
            XCTAssertEqual(scores.energyScore, rested.energyScore, "Sleep: \(hours) hours")
        }
    }

    func testMorningActivityDoesNotRequireReachingDailyTarget() {
        let scorer = EnergyScorer()
        var input = EnergyInput(heartRateBPM: 65, heartRateVariabilityMS: 60,
                                restingHeartRateBPM: 55, sleepHours: 11, activeEnergyKcal: 650)
        let dailyTarget = scorer.computeScores(input: input)

        for energy in [0.0, 100.0, 390.0, 520.0] {
            input.activeEnergyKcal = energy
            XCTAssertGreaterThanOrEqual(scorer.computeScores(input: input).energyScore, dailyTarget.energyScore)
        }
    }

    func testRestedDefaultMarkersProduceHighButNotFullEnergy() {
        let scores = EnergyScorer().computeScores(input: EnergyInput(
            heartRateBPM: 65, heartRateVariabilityMS: 60, restingHeartRateBPM: 55,
            sleepHours: 8, activeEnergyKcal: 100
        ))

        XCTAssertGreaterThanOrEqual(scores.recoveryScore, 80)
        XCTAssertGreaterThanOrEqual(scores.energyScore, 80)
        XCTAssertLessThan(scores.energyScore, 100)
    }

    func testAdditionalActivityDoesNotRechargeEnergy() {
        let scorer = EnergyScorer()
        var input = EnergyInput(heartRateBPM: 65, heartRateVariabilityMS: 60,
                                restingHeartRateBPM: 55, sleepHours: 8, activeEnergyKcal: 0)
        var previous = scorer.computeScores(input: input)

        for energy in stride(from: 100.0, through: 3000.0, by: 100.0) {
            input.activeEnergyKcal = energy
            let scores = scorer.computeScores(input: input)
            XCTAssertLessThanOrEqual(scores.energyScore, previous.energyScore)
            XCTAssertGreaterThanOrEqual(scores.trainingLoadScore, previous.trainingLoadScore)
            previous = scores
        }
    }

    func testLongSleepDoesNotHideUnfavorableHeartMarkers() {
        let scorer = EnergyScorer()
        let rested = EnergyInput(heartRateBPM: 65, heartRateVariabilityMS: 60,
                                 restingHeartRateBPM: 55, sleepHours: 11, activeEnergyKcal: 100)
        let reference = scorer.computeScores(input: rested)
        var lowHRV = rested
        lowHRV.heartRateVariabilityMS = 24
        var highRHR = rested
        highRHR.restingHeartRateBPM = 80

        for input in [lowHRV, highRHR] {
            let scores = scorer.computeScores(input: input)
            XCTAssertLessThan(scores.recoveryScore, reference.recoveryScore)
            XCTAssertLessThan(scores.energyScore, reference.energyScore)
        }
    }

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
