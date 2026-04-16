import XCTest
@testable import BodyEnergy

final class StressAnalyzerTests: XCTestCase {
    func testStressScoreIsLowerWhenHRVIsHigher() {
        let analyzer = StressAnalyzer()

        let relaxed = analyzer.evaluate(
            hrvMS: 72,
            restingHeartRateBPM: 54,
            currentHeartRateBPM: 78
        )
        let strained = analyzer.evaluate(
            hrvMS: 24,
            restingHeartRateBPM: 54,
            currentHeartRateBPM: 78
        )

        XCTAssertLessThan(relaxed.score, strained.score)
        XCTAssertEqual(relaxed.level, .moderate)
        XCTAssertTrue([StressReading.Level.elevated, .high].contains(strained.level))
    }

    func testElevatedHeartRateReserveRaisesAcuteStress() {
        let analyzer = StressAnalyzer()

        let calm = analyzer.evaluate(
            hrvMS: 58,
            restingHeartRateBPM: 56,
            currentHeartRateBPM: 78
        )
        let activated = analyzer.evaluate(
            hrvMS: 58,
            restingHeartRateBPM: 56,
            currentHeartRateBPM: 132
        )

        XCTAssertLessThan(calm.score, activated.score)
        XCTAssertLessThan(calm.acuteStressScore, activated.acuteStressScore)
    }

    func testStressScoreStaysWithinRange() {
        let analyzer = StressAnalyzer()

        let reading = analyzer.evaluate(
            hrvMS: 4,
            restingHeartRateBPM: 140,
            currentHeartRateBPM: 220
        )

        XCTAssertTrue((0...100).contains(reading.score))
        XCTAssertTrue((0...100).contains(reading.hrvStressScore))
        XCTAssertTrue((0...100).contains(reading.restingHeartRateStressScore))
        XCTAssertTrue((0...100).contains(reading.acuteStressScore))
    }
}
