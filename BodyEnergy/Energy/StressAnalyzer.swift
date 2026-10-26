import Foundation

struct HeartbeatTimestamp: Equatable, Sendable {
    var timeIntervalSinceStart: TimeInterval
    var precededByGap: Bool
}

struct RMSSDResult: Equatable, Sendable {
    var milliseconds: Double
    var effectiveDurationSeconds: TimeInterval
    var differenceCount: Int
    var endOffsetSeconds: TimeInterval
    var quality: RMSSDQuality
}

enum RMSSDParser {
    // Conservative signal-quality settings; not clinical cutoffs. All observations
    // use at most 60 seconds from one continuous fragment, with no interpolated beats.
    static let minimumDuration: TimeInterval = 30
    static let maximumDuration: TimeInterval = 60
    static let minimumDifferenceCount = 20
    static let minimumCoverage = 0.8
    static let rrRange: ClosedRange<TimeInterval> = 0.3...2
    static let qualityVersion = 1
    static let maximumRejectedFraction = 0.1
    static let localRadius = 5
    static let minimumRelativeDeviation = 0.2
    static let maximumRelativeDeviation = 0.4
    static let deviationMultiplier = 5.0

    static func calculate(_ beats: [HeartbeatTimestamp], seriesDuration: TimeInterval) -> RMSSDResult? {
        guard seriesDuration.isFinite, seriesDuration >= minimumDuration else { return nil }
        var fragments: [[TimeInterval]] = []
        var fragment: [TimeInterval] = []
        func finishFragment() {
            if fragment.count > 1 { fragments.append(fragment) }
            fragment.removeAll(keepingCapacity: true)
        }
        for beat in beats {
            let time = beat.timeIntervalSinceStart
            guard time.isFinite, time >= 0, time <= seriesDuration else {
                finishFragment()
                continue
            }
            if beat.precededByGap { finishFragment() }
            if let previous = fragment.last, !rrRange.contains(time - previous) {
                finishFragment()
                // Duplicate or backwards timestamps are discarded entirely.
                guard time > previous else { continue }
            }
            fragment.append(time)
        }
        finishFragment()
        guard let longest = fragments.max(by: { ($0.last! - $0.first!) < ($1.last! - $1.first!) }),
              let first = longest.first, let last = longest.last,
              (last - first) / seriesDuration >= minimumCoverage else { return nil }
        let window = longest.filter { last - $0 <= maximumDuration }
        guard let beginning = window.first, let end = window.last,
              end - beginning >= minimumDuration else { return nil }
        let rr = zip(window.dropFirst(), window).map { $0 - $1 }
        // Robust local RR comparisons catch short/long artifacts that still fit
        // physiological bounds. This is a conservative product quality filter.
        let valid = rr.indices.map { index -> Bool in
            let neighbors = (max(0, index - localRadius)...min(rr.count - 1, index + localRadius))
                .filter { $0 != index }.map { rr[$0] }
            guard let center = PhysiologyIntervals.median(neighbors),
                  let mad = PhysiologyIntervals.median(neighbors.map { abs($0 - center) }) else { return false }
            let threshold = max(minimumRelativeDeviation * center,
                                min(maximumRelativeDeviation * center, deviationMultiplier * 1.4826 * mad))
            return abs(rr[index] - center) <= threshold
        }
        let differences = rr.indices.dropFirst().compactMap { index -> Double? in
            // Never join intervals across a rejected beat or synthesize a heartbeat.
            guard valid[index - 1], valid[index] else { return nil }
            return rr[index] - rr[index - 1]
        }
        let quality = RMSSDQuality(version: qualityVersion, intervalCount: rr.count,
            rejectedIntervalCount: valid.filter { !$0 }.count,
            usableDurationSeconds: rr.indices.filter { valid[$0] }.reduce(0) { $0 + rr[$1] })
        guard isUsable(quality: quality, duration: end - beginning, differenceCount: differences.count) else { return nil }
        let value = sqrt(differences.reduce(0) { $0 + $1 * $1 } / Double(differences.count)) * 1000
        guard value.isFinite, value > 0 else { return nil }
        return RMSSDResult(milliseconds: value, effectiveDurationSeconds: end - beginning,
                           differenceCount: differences.count, endOffsetSeconds: end, quality: quality)
    }

    static func isUsable(quality: RMSSDQuality, duration: TimeInterval, differenceCount: Int) -> Bool {
        guard quality.version == qualityVersion, duration.isFinite,
              (minimumDuration...maximumDuration).contains(duration),
              quality.intervalCount > minimumDifferenceCount,
              quality.intervalCount <= Int(maximumDuration / rrRange.lowerBound),
              (0...quality.intervalCount).contains(quality.rejectedIntervalCount),
              differenceCount >= minimumDifferenceCount,
              differenceCount <= quality.intervalCount - quality.rejectedIntervalCount - 1,
              Double(quality.rejectedIntervalCount) / Double(quality.intervalCount) <= maximumRejectedFraction,
              Double(differenceCount) / Double(quality.intervalCount - 1) >= minimumCoverage,
              quality.usableDurationSeconds.isFinite,
              quality.usableDurationSeconds >= minimumDuration,
              quality.usableDurationSeconds <= duration + 0.000001,
              quality.usableDurationSeconds / duration >= minimumCoverage else { return false }
        return true
    }
}

struct StressReading: Equatable, Sendable {
    enum Level: String, Sendable {
        case low
        case moderate
        case elevated
        case high
    }

    var score: Int
    var level: Level
    var hrvStressScore: Int
    var restingHeartRateStressScore: Int
    var acuteStressScore: Int
}

struct StressAnalyzer {
    private static let heartRatePairingWindow: TimeInterval = 30 * 60
    static let pressureSampleMaxAge: TimeInterval = 6 * 3600
    // Product calibration, not diagnostic thresholds. A usual reading maps to 40;
    // one personal log-spread above/below it maps to about 20/64.
    static let minimumLogSpread = HRVBaseline.minimumLogSpread
    private static let fallbackLogSpread = HRVBaseline.fallbackLogSpread

    let config: EnergyConfig

    init(config: EnergyConfig = .default) {
        self.config = config
    }

    func evaluate(snapshot: HealthSnapshot, hrvBaselineMS: Double) -> StressReading {
        if let measurement = snapshot.pressureMeasurement { return evaluate(measurement: measurement) }
        return evaluate(
            hrvMS: snapshot.heartRateVariabilityMS,
            restingHeartRateBPM: snapshot.restingHeartRateBPM,
            currentHeartRateBPM: snapshot.heartRateBPM,
            hrvBaselineMS: hrvBaselineMS,
            restingHeartRateBaselineBPM: snapshot.restingHeartRateBaselineBPM,
            hrvLogSpread: snapshot.hrvBaselineLogSpread
        )
    }

    func evaluateAvailable(snapshot: HealthSnapshot, now: Date = .now) -> (reading: StressReading, snapshot: StressSnapshot)? {
        if snapshot.pressureContextPrepared == true {
            guard snapshot.pressureAlgorithmVersion == StressSnapshot.algorithmVersion,
                  let measurement = snapshot.pressureMeasurement,
                  measurement.sampledAt <= now.addingTimeInterval(300),
                  measurement.sampledAt.addingTimeInterval(Self.pressureSampleMaxAge) >= now,
                  measurement.baseline.dayCount >= 7,
                  isValid(measurement: measurement),
                  measurement.baseline.logSpread.isFinite, measurement.baseline.logSpread > 0 else { return nil }
            let reading = evaluate(measurement: measurement)
            return (reading, stressSnapshot(reading, sampledAt: measurement.sampledAt,
                hasHeartRate: measurement.heartRateBPM != nil && !measurement.isSleeping, metric: measurement.metric))
        }
        guard snapshot.isUsable(.hrv, at: now), let hrvDate = snapshot.sampleDates[.hrv],
              hrvDate.addingTimeInterval(Self.pressureSampleMaxAge) >= now,
              validHRV(snapshot.heartRateVariabilityMS),
              let baseline = snapshot.hrvBaselineMS, validHRV(baseline) else { return nil }
        // Resting heart rate is a daily baseline; current heart rate must be paired with the HRV sample.
        if snapshot.heartRateIsSedentary == true,
           snapshot.isUsable(.heartRate, at: now), snapshot.isUsable(.restingHeartRate, at: now),
           let heartRateDate = snapshot.sampleDates[.heartRate],
           abs(heartRateDate.timeIntervalSince(hrvDate)) <= Self.heartRatePairingWindow {
            let reading = evaluate(snapshot: snapshot, hrvBaselineMS: baseline)
            return (reading, stressSnapshot(reading, sampledAt: hrvDate, hasHeartRate: true))
        }

        let score = evaluate(hrvMS: snapshot.heartRateVariabilityMS, hrvBaselineMS: baseline,
                             hrvLogSpread: snapshot.hrvBaselineLogSpread)
        let reading = StressReading(score: score, level: level(for: score), hrvStressScore: score,
                                    restingHeartRateStressScore: 0, acuteStressScore: 0)
        return (reading, stressSnapshot(reading, sampledAt: hrvDate, hasHeartRate: false))
    }

    func evaluate(hrvMS: Double, hrvBaselineMS: Double, hrvLogSpread: Double? = nil) -> Int {
        Int(hrvScore(for: hrvMS, baseline: hrvBaselineMS, logSpread: hrvLogSpread).rounded())
    }

    func evaluate(measurement: PressureMeasurement) -> StressReading {
        reading(hrvMS: measurement.hrvMS, baseline: measurement.baseline.medianMS,
                logSpread: measurement.baseline.logSpread,
                restingHeartRate: measurement.isSleeping ? nil : measurement.restingHeartRateBPM,
                restingBaseline: measurement.restingHeartRateBaselineBPM,
                heartRate: measurement.isSleeping ? nil : measurement.heartRateBPM, metric: measurement.metric)
    }

    func evaluate(hrvMS: Double, restingHeartRateBPM: Double, currentHeartRateBPM: Double,
                  hrvBaselineMS: Double, restingHeartRateBaselineBPM: Double? = nil,
                  hrvLogSpread: Double? = nil) -> StressReading {
        reading(hrvMS: hrvMS, baseline: hrvBaselineMS, logSpread: hrvLogSpread,
                restingHeartRate: restingHeartRateBPM, restingBaseline: restingHeartRateBaselineBPM,
                heartRate: currentHeartRateBPM)
    }

    func level(for score: Int) -> StressReading.Level {
        switch score {
        case 0..<30: return .low
        case 30..<55: return .moderate
        case 55..<75: return .elevated
        default: return .high
        }
    }

    func validHRV(_ value: Double, metric: HRVMetric = .sdnn) -> Bool {
        guard value.isFinite else { return false }
        switch metric {
        case .sdnn: return config.hrvValidRange.contains(value)
        case .rmssd: return value > 0 && value <= (RMSSDParser.rrRange.upperBound - RMSSDParser.rrRange.lowerBound) * 1000
        }
    }

    func isValid(measurement: PressureMeasurement) -> Bool {
        guard measurement.baseline.metric == measurement.metric,
              measurement.baseline.dayCount >= 7,
              validHRV(measurement.hrvMS, metric: measurement.metric),
              validHRV(measurement.baseline.medianMS, metric: measurement.metric),
              measurement.baseline.logSpread.isFinite, measurement.baseline.logSpread > 0 else { return false }
        if measurement.metric == .rmssd {
            guard let duration = measurement.effectiveDurationSeconds,
                  let count = measurement.differenceCount, let quality = measurement.rmssdQuality,
                  RMSSDParser.isUsable(quality: quality, duration: duration, differenceCount: count) else { return false }
        }
        return true
    }

    private func hrvScore(for value: Double, baseline: Double, logSpread: Double?, metric: HRVMetric = .sdnn) -> Double {
        guard validHRV(value, metric: metric), validHRV(baseline, metric: metric) else { return 40 }
        let spread = logSpread.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? Self.fallbackLogSpread
        let deviation = log(value / baseline) / max(Self.minimumLogSpread, spread)
        return 100 * sigmoid(log(0.4 / 0.6) - deviation)
    }

    private func reading(hrvMS: Double, baseline: Double, logSpread: Double?,
                         restingHeartRate: Double?, restingBaseline: Double?, heartRate: Double?, metric: HRVMetric = .sdnn) -> StressReading {
        let core = hrvScore(for: hrvMS, baseline: baseline, logSpread: logSpread, metric: metric)
        var restingCorrection = 0.0
        var acuteCorrection = 0.0
        if let resting = restingHeartRate, resting.isFinite, config.restingHeartRateValidRange.contains(resting) {
            if let usual = restingBaseline, usual.isFinite, config.restingHeartRateValidRange.contains(usual) {
                restingCorrection = 8 * tanh((resting - usual) / 6)
            }
            if let heartRate, heartRate.isFinite, config.heartRateValidRange.contains(heartRate) {
                let excess = max(0, heartRate - resting - config.baselines.heartRateReserveBufferBPM)
                acuteCorrection = min(12, excess / max(1, config.baselines.heartRateReserveRampBPM) * 6)
            }
        }
        // Missing inputs add no correction. Calm paired heart rates also add zero,
        // so a change in input availability cannot replace 42% of the HRV evidence.
        let score = Int((core + restingCorrection + acuteCorrection).rounded()).clamped(to: 0...100)
        return StressReading(score: score, level: level(for: score), hrvStressScore: Int(core.rounded()),
            restingHeartRateStressScore: restingHeartRate == nil ? 0 : Int((50 + restingCorrection / 8 * 50).rounded()),
            acuteStressScore: Int((acuteCorrection / 12 * 100).rounded()))
    }

    private func stressSnapshot(_ reading: StressReading, sampledAt: Date, hasHeartRate: Bool, metric: HRVMetric = .sdnn) -> StressSnapshot {
        StressSnapshot(score: reading.score, levelTitle: reading.level.title, updatedAt: sampledAt,
            validUntil: sampledAt.addingTimeInterval(Self.pressureSampleMaxAge),
            basis: metric == .rmssd ? (hasHeartRate ? "RMSSD 与心率估算" : "RMSSD 估算")
                : (hasHeartRate ? "相对个人 HRV 与心率估算" : "相对个人 HRV 估算"), hrvMetric: metric)
    }

    private func sigmoid(_ x: Double) -> Double {
        1 / (1 + exp(-x))
    }
}

extension StressReading.Level {
    var title: String {
        switch self {
        case .low:
            return "压力较低"
        case .moderate:
            return "压力适中"
        case .elevated:
            return "压力较高"
        case .high:
            return "压力很高"
        }
    }
}
