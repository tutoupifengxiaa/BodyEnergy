import XCTest
@testable import BodyEnergy

final class StressAnalyzerTests: XCTestCase {
    func testAvailablePressureUsesHRVWithoutSleepOrHeartRate() {
        let now = Date.now
        var health = HealthSnapshot.empty
        health.heartRateVariabilityMS = 55
        health.missingMetrics.remove(.hrv)
        health.sampleDates[.hrv] = now.addingTimeInterval(-120)
        let analyzer = StressAnalyzer()
        let result = analyzer.evaluateAvailable(snapshot: health, now: now)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.snapshot.basis, "HRV 估算")
        XCTAssertEqual(result?.snapshot.updatedAt, health.sampleDates[.hrv])
        XCTAssertEqual(result?.reading.score, result?.reading.hrvStressScore)
        XCTAssertFalse(health.isUsable(at: now))
        health.sampleDates[.hrv] = now.addingTimeInterval(-40 * 3600)
        XCTAssertNil(analyzer.evaluateAvailable(snapshot: health, now: now))
        health.sampleDates[.hrv] = now.addingTimeInterval(600)
        XCTAssertNil(analyzer.evaluateAvailable(snapshot: health, now: now))
        health.sampleDates[.hrv] = now
        health.heartRateVariabilityMS = 0
        XCTAssertNil(analyzer.evaluateAvailable(snapshot: health, now: now))
        XCTAssertNil(analyzer.evaluateAvailable(snapshot: .empty, now: now))
    }

    func testAvailablePressureUsesHeartRatesWhenSamplesArePaired() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var health = HealthSnapshot.empty
        health.heartRateVariabilityMS = 55
        health.heartRateBPM = 132
        health.restingHeartRateBPM = 54
        health.missingMetrics.subtract([.hrv, .heartRate, .restingHeartRate])
        health.sampleDates[.hrv] = now.addingTimeInterval(-600)
        health.sampleDates[.heartRate] = now.addingTimeInterval(-600)
        health.sampleDates[.restingHeartRate] = now.addingTimeInterval(-24 * 3600)

        let analyzer = StressAnalyzer()
        let result = analyzer.evaluateAvailable(snapshot: health, now: now)

        XCTAssertEqual(result?.reading, analyzer.evaluate(snapshot: health))
        XCTAssertEqual(result?.snapshot.basis, "HRV 与心率估算")
        XCTAssertEqual(result?.snapshot.updatedAt, health.sampleDates[.heartRate])
        XCTAssertEqual(result?.snapshot.validUntil, health.sampleDates[.heartRate]?.addingTimeInterval(HealthMetric.heartRate.maxAge))

        health.sampleDates[.heartRate] = now.addingTimeInterval(-300)
        let newerHeartRate = analyzer.evaluateAvailable(snapshot: health, now: now)
        XCTAssertEqual(newerHeartRate?.snapshot.updatedAt, health.sampleDates[.heartRate])
        XCTAssertEqual(newerHeartRate?.snapshot.validUntil,
                       health.sampleDates[.heartRate]?.addingTimeInterval(HealthMetric.heartRate.maxAge))
    }

    func testAvailablePressureIgnoresHeartRateFromAnotherTime() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var health = HealthSnapshot.empty
        health.heartRateVariabilityMS = 55
        health.heartRateBPM = 132
        health.restingHeartRateBPM = 54
        health.missingMetrics.subtract([.hrv, .heartRate, .restingHeartRate])
        health.sampleDates[.hrv] = now.addingTimeInterval(-600)
        health.sampleDates[.heartRate] = now.addingTimeInterval(-3600)
        health.sampleDates[.restingHeartRate] = now.addingTimeInterval(-24 * 3600)

        let analyzer = StressAnalyzer()
        let result = analyzer.evaluateAvailable(snapshot: health, now: now)

        XCTAssertEqual(result?.reading.score, analyzer.evaluate(hrvMS: health.heartRateVariabilityMS))
        XCTAssertEqual(result?.reading.acuteStressScore, 0)
        XCTAssertEqual(result?.snapshot.basis, "HRV 估算")
        XCTAssertEqual(result?.snapshot.updatedAt, health.sampleDates[.hrv])
        XCTAssertEqual(result?.snapshot.validUntil, health.sampleDates[.hrv]?.addingTimeInterval(HealthMetric.hrv.maxAge))

        health.sampleDates[.heartRate] = now
        XCTAssertEqual(analyzer.evaluateAvailable(snapshot: health, now: now)?.snapshot.basis, "HRV 与心率估算")
        health.missingMetrics.insert(.restingHeartRate)
        XCTAssertEqual(analyzer.evaluateAvailable(snapshot: health, now: now)?.snapshot.basis, "HRV 估算")
    }

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
