import Foundation
import HealthKit
import OSLog

protocol HealthManaging {
    func requestAuthorization() async throws
    func fetchLatestSnapshot(now: Date) async throws -> HealthSnapshot
    func fetchTodayHourlyStress(now: Date) async throws -> [HourlyStress]
    func observeChanges(_ onChange: @escaping @MainActor () async -> Void)
    func enableBackgroundUpdates()
}

enum HealthManagerError: LocalizedError {
    case healthDataUnavailable
    case missingType(String)
    case noData(String)

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "当前设备无法使用健康数据。"
        case .missingType(let identifier):
            return "HealthKit 数据类型不可用：\(identifier)。"
        case .noData(let metric):
            return "暂未读取到\(metric)的 HealthKit 数据。"
        }
    }
}

final class HealthManager: HealthManaging {
    private let healthStore: HKHealthStore
    private let calendar: Calendar
    private var observers: [HKObserverQuery] = []
    private var cachedPressureContext: (date: Date, measurements: [PressureMeasurement], sdnnMeasurement: PressureMeasurement?)?
    private struct HeartbeatCacheKey: Hashable {
        let identifier: UUID
        let start: Date
        let end: Date
        let count: Int
        let source: String
    }
    private struct HeartbeatCacheEntry {
        let result: RMSSDResult?
    }
    private var heartbeatCache: [HeartbeatCacheKey: HeartbeatCacheEntry] = [:]
    private var pressureReference: PressureMeasurement?
    private let logger = Logger(subsystem: "com.tutoupifengxiaa.BodyEnergy", category: "HealthUpdates")

    init(healthStore: HKHealthStore = HKHealthStore(), calendar: Calendar = .current) {
        self.healthStore = healthStore
        self.calendar = calendar
    }

    func usePressureReference(_ reference: PressureMeasurement?) {
        guard pressureReference != reference else { return }
        pressureReference = reference
        cachedPressureContext = nil
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthManagerError.healthDataUnavailable
        }

        let types = try requiredReadTypes()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: nil, read: types) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        enableBackgroundUpdates()
    }

    func observeChanges(_ onChange: @escaping @MainActor () async -> Void) {
        guard observers.isEmpty, HKHealthStore.isHealthDataAvailable(),
              let types = try? requiredReadTypes() else { return }
        for case let type as HKSampleType in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                guard error == nil else { completion(); return }
                Task { @MainActor in
                    await onChange()
                    completion()
                }
            }
            observers.append(query)
            healthStore.execute(query)
        }
    }

    func enableBackgroundUpdates() {
        guard HKHealthStore.isHealthDataAvailable(), let types = try? requiredReadTypes() else { return }
        for case let type as HKSampleType in types {
            healthStore.enableBackgroundDelivery(for: type, frequency: .immediate) { [logger] success, error in
                // Keep only registration status, never health measurements, for device verification.
                UserDefaults.standard.set(success, forKey: "health.background.enabled." + type.identifier)
                if let error {
                    logger.error("Background delivery registration failed: code \((error as NSError).code)")
                }
            }
        }
    }

    func fetchLatestSnapshot(now: Date = .now) async throws -> HealthSnapshot {
        async let heartRate = reading(.heartRate, identifier: .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute()), now: now)
        async let hrv = reading(.hrv, identifier: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), now: now)
        async let resting = reading(.restingHeartRate, identifier: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), now: now)
        async let sleep = sleepReading(now: now)
        async let energy = energyReading(now: now)
        async let fitness = fitnessContext(now: now)
        let readings = await [heartRate, hrv, resting, sleep, energy]
        if let error = readings.compactMap(\.error).first { throw error }
        var snapshot = HealthSnapshot.empty
        let pressureMeasurements = try? await pressureMeasurements(now: now)
        snapshot.pressureContextPrepared = true
        snapshot.pressureMeasurement = pressureMeasurements?.max { $0.sampledAt < $1.sampledAt }
        // Body energy continues to use SDNN even when pressure uses RMSSD.
        let sdnnMeasurement = cachedPressureContext?.date == now ? cachedPressureContext?.sdnnMeasurement : nil
        snapshot.hrvBaselineMS = sdnnMeasurement?.baseline.medianMS
        snapshot.hrvBaselineLogSpread = sdnnMeasurement?.baseline.logSpread
        snapshot.hrvBaselineDayCount = sdnnMeasurement?.baseline.dayCount
        snapshot.hrvTrend = snapshot.pressureMeasurement?.trend
        if let restingDate = readings.first(where: { $0.metric == .restingHeartRate })?.date {
            snapshot.restingHeartRateBaselineBPM = try? await personalRestingHeartRateBaseline(asOf: min(restingDate, now))
        }
        for reading in readings {
            guard let value = reading.value, let date = reading.date else { continue }
            snapshot.missingMetrics.remove(reading.metric)
            snapshot.sampleDates[reading.metric] = date
            switch reading.metric {
            case .heartRate:
                snapshot.heartRateBPM = value
                snapshot.heartRateIsSedentary = reading.heartRateIsSedentary
            case .hrv: snapshot.heartRateVariabilityMS = value
            case .restingHeartRate: snapshot.restingHeartRateBPM = value
            case .sleep:
                snapshot.sleepHours = value
                snapshot.sleepDetails = reading.sleepDetails
            case .activeEnergy: snapshot.activeEnergyKcal = value
            }
        }
        if let measurement = sdnnMeasurement {
            snapshot.heartRateVariabilityMS = measurement.hrvMS
            snapshot.sampleDates[.hrv] = measurement.sampledAt
            snapshot.missingMetrics.remove(.hrv)
        }
        snapshot.fitnessContext = await fitness
        return snapshot
    }

    func fetchTodayHourlyStress(now: Date = .now) async throws -> [HourlyStress] {
        Self.hourlyStress(from: try await pressureMeasurements(now: now), now: now, calendar: calendar)
    }

    static func hourlyStress(from measurements: [PressureMeasurement], now: Date,
                             calendar: Calendar) -> [HourlyStress] {
        let analyzer = StressAnalyzer()
        let start = calendar.startOfDay(for: now)
        let valid = measurements.filter {
            $0.sampledAt >= start && $0.sampledAt <= now && analyzer.isValid(measurement: $0)
        }
        let metric = valid.max { $0.sampledAt < $1.sampledAt }?.metric
        let grouped = Dictionary(grouping: valid.filter { $0.metric == metric }) {
            calendar.dateInterval(of: .hour, for: $0.sampledAt)?.start ?? $0.sampledAt
        }
        return grouped.compactMap { hour, samples in
            guard let score = median(samples.map { Double(analyzer.evaluate(measurement: $0).score) }) else { return nil }
            return HourlyStress(hour: hour, score: Int(score.rounded()), hrvMetric: samples.first?.metric)
        }.sorted { $0.hour < $1.hour }
    }

    private func pressureMeasurements(now: Date) async throws -> [PressureMeasurement] {
        // AppStore fetches the current card and hourly chart with the same query time.
        if let cachedPressureContext, cachedPressureContext.date == now { return cachedPressureContext.measurements }
        let dayStart = calendar.startOfDay(for: now)
        guard let historyStart = calendar.date(byAdding: .day, value: -60, to: dayStart) else { return [] }
        let historyPredicate = HKQuery.predicateForSamples(withStart: historyStart, end: now)
        let recentStart = dayStart.addingTimeInterval(-6 * 3600)
        let recentPredicate = HKQuery.predicateForSamples(withStart: recentStart, end: now)
        async let hrv = quantitySamples(type: try quantityType(.heartRateVariabilitySDNN),
            predicate: historyPredicate, limit: HKObjectQueryNoLimit)
        async let resting = quantitySamples(type: try quantityType(.restingHeartRate),
            predicate: historyPredicate, limit: HKObjectQueryNoLimit)
        async let hearts = quantitySamples(type: try quantityType(.heartRate),
            predicate: recentPredicate, limit: HKObjectQueryNoLimit)
        let activePredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [historyPredicate,
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyHeartRateMotionContext,
                operatorType: .equalTo, value: NSNumber(value: HKHeartRateMotionContext.active.rawValue))])
        async let activeHearts = quantitySamples(type: try quantityType(.heartRate),
            predicate: activePredicate, limit: HKObjectQueryNoLimit)
        async let sleep = contextIntervals(identifier: .sleepAnalysis, predicate: historyPredicate)
        async let mindful = contextIntervals(identifier: .mindfulSession, predicate: historyPredicate)
        async let workouts = workoutIntervals(predicate: historyPredicate)
        async let heartbeat = heartbeatSeriesSamples(predicate: historyPredicate)
        let (hrvSamples, restingSamples, heartSamples, activeSamples, sleepIntervals, mindfulIntervals, workoutIntervals, heartbeatSamples) =
            try await (hrv, resting, hearts, activeHearts, sleep, mindful, workouts, heartbeat)
        let exclusions = mindfulIntervals + workoutIntervals.map {
            // Avoid interpreting immediate post-workout recovery as sedentary stress.
            DateInterval(start: $0.start, end: $0.end.addingTimeInterval(30 * 60))
        }
        let eligible = hrvSamples.filter { sample in
            let value = sample.quantity.doubleValue(for: .secondUnit(with: .milli))
            return StressAnalyzer().validHRV(value)
                && isEligiblePressureSample(sample, activeSamples: activeSamples, exclusions: exclusions)
        }
        let sdnnSamples = preferredSourceSamples(eligible).map {
            PressureSample(sample: $0, value: $0.quantity.doubleValue(for: .secondUnit(with: .milli)), rmssd: nil)
        }
        let sdnnMeasurements = calibratedMeasurements(from: sdnnSamples, metric: .sdnn, recentStart: recentStart,
            now: now, restingSamples: restingSamples, heartSamples: heartSamples, sleepIntervals: sleepIntervals)
        let eligibleSeries = heartbeatSamples.filter {
            $0.endDate > $0.startDate && $0.count >= RMSSDParser.minimumDifferenceCount + 2
                && isEligiblePressureSample($0, activeSamples: activeSamples, exclusions: exclusions)
        }
        let selectedSeries = preferredSourceSamples(eligibleSeries)
        let rmssdSamples = await rmssdPressureSamples(from: selectedSeries, allSeries: heartbeatSamples)
        let rmssdMeasurements = calibratedMeasurements(from: rmssdSamples, metric: .rmssd, recentStart: recentStart,
            now: now, restingSamples: restingSamples, heartSamples: heartSamples, sleepIntervals: sleepIntervals)
        // One metric supplies both the current card and all hourly values in a refresh.
        // Without a fresh RMSSD sample and its own baseline, retain the SDNN result.
        let latestRMSSD = rmssdMeasurements.max { $0.sampledAt < $1.sampledAt }
        let useRMSSD = latestRMSSD.map {
            $0.sampledAt <= now && $0.sampledAt.addingTimeInterval(StressAnalyzer.pressureSampleMaxAge) >= now
        } ?? false
        let measurements = useRMSSD ? rmssdMeasurements : sdnnMeasurements
        cachedPressureContext = (now, measurements, sdnnMeasurements.max { $0.sampledAt < $1.sampledAt })
        return measurements
    }

    private struct PressureSample {
        let sample: HKSample
        let value: Double
        let rmssd: RMSSDResult?

        var sampledAt: Date {
            rmssd.map { sample.startDate.addingTimeInterval($0.endOffsetSeconds) } ?? sample.endDate
        }
        var windowStart: Date {
            rmssd.map { sampledAt.addingTimeInterval(-$0.effectiveDurationSeconds) } ?? sample.startDate
        }
    }

    private func preferredSourceSamples<Sample: HKSample>(_ samples: [Sample]) -> [Sample] {
        // Samples arrive newest first. Keep one origin for current values and baseline.
        let watch = samples.filter { $0.sourceRevision.productType?.hasPrefix("Watch") == true }
        guard let source = (watch.isEmpty ? samples : watch).first?.sourceRevision.source.bundleIdentifier else { return [] }
        return samples.filter { $0.sourceRevision.source.bundleIdentifier == source }
    }

    private func isEligiblePressureSample(_ sample: HKSample, activeSamples: [HKQuantitySample],
                                         exclusions: [DateInterval]) -> Bool {
        let userEntered = (sample.metadata?[HKMetadataKeyWasUserEntered] as? NSNumber)?.boolValue == true
        let active = (sample.metadata?[HKMetadataKeyHeartRateMotionContext] as? NSNumber)?.intValue == HKHeartRateMotionContext.active.rawValue
            || activeSamples.contains {
                $0.sourceRevision.source.bundleIdentifier == sample.sourceRevision.source.bundleIdentifier
                    && $0.startDate <= sample.endDate && $0.endDate >= sample.startDate
            }
        return !userEntered && !active
            && !exclusions.contains { $0.start <= sample.endDate && $0.end >= sample.startDate }
    }

    private func calibratedMeasurements(from samples: [PressureSample], metric: HRVMetric,
                                        recentStart: Date, now: Date, restingSamples: [HKQuantitySample],
                                        heartSamples: [HKQuantitySample], sleepIntervals: [DateInterval]) -> [PressureMeasurement] {
        guard let source = samples.first?.sample.sourceRevision.source.bundleIdentifier else { return [] }
        let heartUnit = HKUnit.count().unitDivided(by: .minute())
        let sourceResting = restingSamples.filter {
            $0.sourceRevision.source.bundleIdentifier == source
                && ($0.metadata?[HKMetadataKeyWasUserEntered] as? NSNumber)?.boolValue != true
        }
        let restingHistory = sourceResting.map { (date: $0.endDate, value: $0.quantity.doubleValue(for: heartUnit)) }
        return samples.filter { $0.sampledAt >= recentStart && $0.sampledAt <= now }.compactMap { observation -> PressureMeasurement? in
            let sampledAt = observation.sampledAt
            let sleeping = sleepIntervals.contains { $0.start <= sampledAt && $0.end >= sampledAt }
            let history = samples.filter {
                guard let duration = observation.rmssd?.effectiveDurationSeconds,
                      let historicalDuration = $0.rmssd?.effectiveDurationSeconds else { return true }
                return abs(duration - historicalDuration) <= 15
            }.map { historical in
                (date: historical.sampledAt, value: historical.value,
                 isSleeping: sleepIntervals.contains { $0.start <= historical.sampledAt && $0.end >= historical.sampledAt })
            }
            let referenceBaseline = Self.referenceHRVCalibration(pressureReference, asOf: sampledAt,
                metric: metric, sourceIdentifier: source, isSleeping: sleeping,
                duration: observation.rmssd?.effectiveDurationSeconds, calendar: calendar)
            guard let baseline = Self.personalHRVCalibration(from: history, asOf: sampledAt,
                isSleeping: sleeping, calendar: calendar, metric: metric) ?? referenceBaseline else { return nil }
            let pairedHearts = heartSamples.filter {
                $0.sourceRevision.source.bundleIdentifier == source
                    && $0.endDate >= observation.windowStart.addingTimeInterval(-5 * 60) && $0.endDate <= sampledAt
                    && ($0.metadata?[HKMetadataKeyHeartRateMotionContext] as? NSNumber)?.intValue == HKHeartRateMotionContext.sedentary.rawValue
                    && ($0.metadata?[HKMetadataKeyWasUserEntered] as? NSNumber)?.boolValue != true
            }.map { $0.quantity.doubleValue(for: heartUnit) }
                .filter { $0.isFinite && EnergyConfig.default.heartRateValidRange.contains($0) }
            let resting = restingHistory.first {
                $0.date <= sampledAt && $0.date.addingTimeInterval(HealthMetric.restingHeartRate.maxAge) >= sampledAt
                    && $0.value.isFinite && EnergyConfig.default.restingHeartRateValidRange.contains($0.value)
            }?.value
            return PressureMeasurement(hrvMS: observation.value,
                baseline: baseline, sampledAt: sampledAt, heartRateBPM: Self.median(pairedHearts),
                restingHeartRateBPM: resting, restingHeartRateBaselineBPM: Self.personalRestingHeartRateBaseline(
                    from: restingHistory, asOf: sampledAt, calendar: calendar)
                    ?? (referenceBaseline == nil ? nil : pressureReference?.restingHeartRateBaselineBPM), isSleeping: sleeping,
                trend: Self.personalHRVTrend(from: history, asOf: sampledAt,
                                            isSleeping: sleeping, calendar: calendar, metric: metric),
                hrvMetric: metric, sourceIdentifier: source,
                effectiveDurationSeconds: observation.rmssd?.effectiveDurationSeconds,
                differenceCount: observation.rmssd?.differenceCount)
        }
    }

    static func referenceHRVCalibration(_ reference: PressureMeasurement?, asOf date: Date,
                                       metric: HRVMetric, sourceIdentifier: String, isSleeping: Bool,
                                       duration: TimeInterval?, calendar: Calendar) -> HRVBaseline? {
        // Watch HealthKit history can be shorter than the phone's. Reuse only an
        // already calibrated, comparable phone baseline; never invent extra days.
        guard let reference, StressAnalyzer().isValid(measurement: reference),
              reference.metric == metric, reference.sourceIdentifier == sourceIdentifier,
              !sourceIdentifier.isEmpty, reference.isSleeping == isSleeping,
              reference.sampledAt <= date.addingTimeInterval(300),
              let expiry = calendar.date(byAdding: .day, value: 30, to: reference.sampledAt), expiry >= date else { return nil }
        let target = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let origin = calendar.component(.hour, from: reference.sampledAt) * 60
            + calendar.component(.minute, from: reference.sampledAt)
        let distance = abs(target - origin)
        guard min(distance, 24 * 60 - distance) <= 3 * 60 else { return nil }
        if metric == .rmssd {
            guard let duration, let original = reference.effectiveDurationSeconds,
                  duration.isFinite, abs(duration - original) <= 15 else { return nil }
        }
        return reference.baseline
    }

    private func heartbeatSeriesSamples(predicate: NSPredicate) async -> [HKHeartbeatSeriesSample] {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: HKSeriesType.heartbeat(), predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                    if let error { continuation.resume(throwing: error); return }
                    continuation.resume(returning: (samples as? [HKHeartbeatSeriesSample]) ?? [])
                }
                healthStore.execute(query)
            }
        } catch {
            // Heartbeat access is optional; it must not interrupt SDNN pressure or energy.
            logger.error("Heartbeat sample query failed: code \((error as NSError).code)")
            return []
        }
    }

    private func heartbeatCacheKey(for sample: HKHeartbeatSeriesSample) -> HeartbeatCacheKey {
        HeartbeatCacheKey(identifier: sample.uuid, start: sample.startDate, end: sample.endDate,
                          count: sample.count, source: sample.sourceRevision.source.bundleIdentifier)
    }

    private func rmssdPressureSamples(from samples: [HKHeartbeatSeriesSample],
                                      allSeries: [HKHeartbeatSeriesSample]) async -> [PressureSample] {
        // UUID identifies the immutable HealthKit sample; dates/count also invalidate
        // an unfinished series. Re-query sample headers, reuse the expensive beat results.
        let retained = Set(allSeries.map { heartbeatCacheKey(for: $0) })
        heartbeatCache = heartbeatCache.filter { retained.contains($0.key) }
        let missing = samples.filter { heartbeatCache[heartbeatCacheKey(for: $0)] == nil }
        for beginning in stride(from: 0, to: missing.count, by: 8) {
            let batch = Array(missing[beginning..<min(beginning + 8, missing.count)])
            let results = await withTaskGroup(of: (HeartbeatCacheKey, HeartbeatCacheEntry?).self) { group in
                for sample in batch {
                    let key = heartbeatCacheKey(for: sample)
                    group.addTask { [healthStore] in
                        do {
                            var beats: [HeartbeatTimestamp] = []
                            for try await beat in HKHeartbeatSeriesQueryDescriptor(sample).results(for: healthStore) {
                                beats.append(HeartbeatTimestamp(timeIntervalSinceStart: beat.timeIntervalSinceStart,
                                                                precededByGap: beat.precededByGap))
                            }
                            return (key, HeartbeatCacheEntry(result: RMSSDParser.calculate(beats,
                                seriesDuration: sample.endDate.timeIntervalSince(sample.startDate))))
                        } catch {
                            // Retry transient query errors next time; do not cache them as poor signal.
                            return (key, nil)
                        }
                    }
                }
                var results: [(HeartbeatCacheKey, HeartbeatCacheEntry?)] = []
                for await result in group { results.append(result) }
                return results
            }
            for (key, entry) in results {
                if let entry { heartbeatCache[key] = entry }
            }
        }
        return samples.compactMap { sample in
            guard let result = heartbeatCache[heartbeatCacheKey(for: sample)]?.result else { return nil }
            return PressureSample(sample: sample, value: result.milliseconds, rmssd: result)
        }
    }

    static func isEligibleHRV(value: Double, interval: DateInterval, userEntered: Bool,
                              active: Bool, exclusions: [DateInterval]) -> Bool {
        StressAnalyzer().validHRV(value) && !userEntered && !active
            && !exclusions.contains { $0.start <= interval.end && $0.end >= interval.start }
    }

    private func contextIntervals(identifier: HKCategoryTypeIdentifier, predicate: NSPredicate) async throws -> [DateInterval] {
        guard let type = HKObjectType.categoryType(forIdentifier: identifier) else { return [] }
        let samples = try await categorySamples(type: type, predicate: predicate, limit: HKObjectQueryNoLimit)
        return samples.filter {
            identifier != .sleepAnalysis || [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue].contains($0.value)
        }.filter { $0.endDate > $0.startDate }.map { DateInterval(start: $0.startDate, end: $0.endDate) }
    }

    private func workoutIntervals(predicate: NSPredicate) async throws -> [DateInterval] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: (samples ?? []).filter { $0.endDate > $0.startDate }
                    .map { DateInterval(start: $0.startDate, end: $0.endDate) })
            }
            healthStore.execute(query)
        }
    }

    private func personalRestingHeartRateBaseline(asOf date: Date) async throws -> Double? {
        let type = try quantityType(.restingHeartRate)
        let end = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .day, value: -30, to: end) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        let samples = try await quantitySamples(type: type, predicate: predicate, limit: HKObjectQueryNoLimit)
        let history = samples.map {
            ($0.endDate, $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
        }
        return Self.personalRestingHeartRateBaseline(from: history, asOf: date, calendar: calendar)
    }

    static func personalRestingHeartRateBaseline(from history: [(date: Date, value: Double)], asOf date: Date,
                                                calendar: Calendar) -> Double? {
        let end = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .day, value: -30, to: end) else { return nil }
        let daily = Dictionary(grouping: history.filter {
            $0.date >= start && $0.date < end && $0.value.isFinite
                && EnergyConfig.default.restingHeartRateValidRange.contains($0.value)
        }) { calendar.startOfDay(for: $0.date) }.values.compactMap { median($0.map(\.value)) }
        guard daily.count >= 7 else { return nil }
        return median(daily)
    }

    static func personalHRVBaseline(from history: [(date: Date, value: Double)], asOf date: Date,
                                    calendar: Calendar) -> Double? {
        personalHRVCalibration(from: history.map { ($0.date, $0.value, false) },
            asOf: date, isSleeping: false, calendar: calendar)?.medianMS
    }

    static func personalHRVCalibration(from history: [(date: Date, value: Double, isSleeping: Bool)],
                                       asOf date: Date, isSleeping: Bool, calendar: Calendar,
                                       metric: HRVMetric = .sdnn) -> HRVBaseline? {
        let end = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .day, value: -30, to: end) else { return nil }
        let targetMinute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let comparable = history.filter { sample in
            guard sample.date >= start, sample.date < end,
                  sample.isSleeping == isSleeping,
                  StressAnalyzer().validHRV(sample.value, metric: metric) else { return false }
            let minute = calendar.component(.hour, from: sample.date) * 60 + calendar.component(.minute, from: sample.date)
            let distance = abs(minute - targetMinute)
            return min(distance, 24 * 60 - distance) <= 3 * 60
        }
        let days = Dictionary(grouping: comparable) {
            calendar.startOfDay(for: $0.date)
        }
        let daily = days.values.compactMap { Self.median($0.map(\.value)) }
        guard daily.count >= 7, let center = Self.median(daily) else { return nil }
        // Each day has equal influence, including its ordinary within-day variation.
        let deviations = days.values.compactMap { day in
            Self.median(day.map { abs(log($0.value / center)) })
        }
        let spread = max(StressAnalyzer.minimumLogSpread, (Self.median(deviations) ?? 0) * 1.4826)
        return HRVBaseline(medianMS: center, logSpread: spread, dayCount: daily.count, hrvMetric: metric)
    }

    static func personalHRVTrend(from history: [(date: Date, value: Double, isSleeping: Bool)],
                                asOf date: Date, isSleeping: Bool, calendar: Calendar,
                                metric: HRVMetric = .sdnn) -> HRVTrend? {
        let end = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .day, value: -60, to: end),
              let recentStart = calendar.date(byAdding: .day, value: -7, to: end) else { return nil }
        let target = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let samples = history.filter {
            guard $0.date >= start, $0.date < end, $0.isSleeping == isSleeping,
                  StressAnalyzer().validHRV($0.value, metric: metric) else { return false }
            let minute = calendar.component(.hour, from: $0.date) * 60 + calendar.component(.minute, from: $0.date)
            let distance = abs(minute - target)
            return min(distance, 24 * 60 - distance) <= 3 * 60
        }
        let daily = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.date) }
            .compactMap { day, values -> (date: Date, value: Double)? in
                median(values.map(\.value)).map { (day, $0) }
            }
        let recent = daily.filter { $0.date >= recentStart }.map(\.value)
        let reference = daily.filter { $0.date < recentStart }.map(\.value)
        guard recent.count >= 3, reference.count >= 14,
              let recentMedian = median(recent), let referenceMedian = median(reference) else { return nil }
        return HRVTrend(recentMedianMS: recentMedian, referenceMedianMS: referenceMedian)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private struct Reading {
        let metric: HealthMetric
        var value: Double? = nil
        var date: Date? = nil
        var heartRateIsSedentary: Bool? = nil
        var sleepDetails: SleepDetails? = nil
        var error: Error? = nil
    }

    private func reading(_ metric: HealthMetric, identifier: HKQuantityTypeIdentifier, unit: HKUnit, now: Date) async -> Reading {
        do {
            let type = try quantityType(identifier)
            let predicate = HKQuery.predicateForSamples(withStart: now.addingTimeInterval(-7 * 86400), end: now)
            let samples = try await quantitySamples(type: type, predicate: predicate, limit: 20)
            guard let sample = samples.first(where: {
                let value = $0.quantity.doubleValue(for: unit)
                return value.isFinite && value >= 0
                    && (metric != .hrv || EnergyConfig.default.hrvValidRange.contains(value))
                    && ($0.metadata?[HKMetadataKeyWasUserEntered] as? NSNumber)?.boolValue != true
            }) else { return Reading(metric: metric) }
            let value = sample.quantity.doubleValue(for: unit)
            guard value.isFinite, value >= 0 else { return Reading(metric: metric) }
            let context = sample.metadata?[HKMetadataKeyHeartRateMotionContext] as? NSNumber
            let isSedentary = metric == .heartRate
                ? context?.intValue == HKHeartRateMotionContext.sedentary.rawValue : nil
            return Reading(metric: metric, value: value, date: sample.endDate,
                           heartRateIsSedentary: isSedentary)
        } catch { return Reading(metric: metric, error: error) }
    }

    private func energyReading(now: Date) async -> Reading {
        do {
            let type = try quantityType(.activeEnergyBurned)
            let predicate = HKQuery.predicateForSamples(withStart: calendar.startOfDay(for: now), end: now)
            let samples = try await quantitySamples(type: type, predicate: predicate, limit: 1)
            guard let sampledAt = samples.first?.endDate else { return Reading(metric: .activeEnergy) }
            return try await withCheckedThrowingContinuation { continuation in
                let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                    if let error { continuation.resume(throwing: error); return }
                    guard let total = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) else {
                        continuation.resume(returning: Reading(metric: .activeEnergy)); return
                    }
                    continuation.resume(returning: Reading(metric: .activeEnergy, value: total, date: sampledAt))
                }
                healthStore.execute(query)
            }
        } catch { return Reading(metric: .activeEnergy, error: error) }
    }

    private func sleepReading(now: Date) async -> Reading {
        do {
            guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return Reading(metric: .sleep) }
            let start = now.addingTimeInterval(-72 * 3600)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
            let samples = try await categorySamples(type: type, predicate: predicate, limit: HKObjectQueryNoLimit)
            let intervals = samples.filter {
                [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                 HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue].contains($0.value)
            }.compactMap { sample -> DateInterval? in
                let beginning = max(sample.startDate, start)
                let ending = min(sample.endDate, now)
                return ending > beginning ? DateInterval(start: beginning, end: ending) : nil
            }
            guard let selection = Self.recentSleepSelection(in: intervals, now: now, calendar: calendar) else {
                return Reading(metric: .sleep)
            }
            return Reading(metric: .sleep, value: Self.sleepDuration(selection.intervals) / 3600,
                           date: selection.measuredAt,
                           sleepDetails: Self.sleepDetails(from: samples, sleepIntervals: selection.intervals))
        } catch { return Reading(metric: .sleep, error: error) }
    }

    static func recentSleep(in intervals: [DateInterval], now: Date, calendar: Calendar) -> (duration: TimeInterval, measuredAt: Date)? {
        guard let selection = recentSleepSelection(in: intervals, now: now, calendar: calendar) else { return nil }
        return (sleepDuration(selection.intervals), selection.measuredAt)
    }

    private static func recentSleepSelection(in intervals: [DateInterval], now: Date,
                                             calendar: Calendar) -> (intervals: [DateInterval], measuredAt: Date)? {
        let sorted = intervals.compactMap { interval -> DateInterval? in
            guard interval.duration > 0, interval.start < now else { return nil }
            return DateInterval(start: interval.start, end: min(interval.end, now))
        }
            .sorted { $0.start < $1.start }
        var episodes: [[DateInterval]] = []
        for interval in sorted {
            if let lastEnd = episodes.last?.map(\.end).max(),
               interval.start.timeIntervalSince(lastEnd) <= 90 * 60 {
                episodes[episodes.count - 1].append(interval)
            } else {
                episodes.append([interval])
            }
        }

        let candidates = episodes.compactMap { episode -> (start: Date, periodStart: Date, priority: Int)? in
            guard let start = episode.first?.start, let end = episode.map(\.end).max(),
                  let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: start),
                  let periodStart = start >= evening ? evening : calendar.date(byAdding: .day, value: -1, to: evening)
            else { return nil }
            let crossesMidnight = !calendar.isDate(start, inSameDayAs: end)
            let hour = calendar.component(.hour, from: start)
            let duration = sleepDuration(episode)
            let priority: Int
            if crossesMidnight {
                priority = 2
            } else if hour >= 18 && duration >= 3 * 3600 {
                priority = 1
            } else if hour < 6 && duration >= 3 * 3600 {
                priority = 0
            } else {
                return nil
            }
            return (start, periodStart, priority)
        }
        guard let night = candidates.max(by: { left, right in
            if left.periodStart != right.periodStart { return left.periodStart < right.periodStart }
            if left.priority != right.priority { return left.priority < right.priority }
            return left.start < right.start
        }), let napCutoff = calendar.date(byAdding: .day, value: 1, to: night.periodStart),
              let midday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: napCutoff) else { return nil }

        let following = episodes.filter { episode in
            guard let start = episode.first?.start else { return false }
            return start >= night.start && start < napCutoff
        }
        let nightEnd = following.filter { ($0.first?.start ?? .distantFuture) < midday }
            .flatMap { $0 }.map(\.end).max() ?? night.start
        guard nightEnd.addingTimeInterval(HealthMetric.sleep.maxAge) >= now else { return nil }
        let sleep = following.flatMap { $0 }.compactMap { interval -> DateInterval? in
            let end = min(interval.end, napCutoff)
            return end > interval.start ? DateInterval(start: interval.start, end: end) : nil
        }
        let duration = sleepDuration(sleep)
        guard duration > 0 else { return nil }
        // Freshness follows the main sleep, so a nap cannot keep an old night current indefinitely.
        return (sleep, nightEnd)
    }

    static func sleepDetails(from samples: [HKCategorySample], sleepIntervals: [DateInterval]) -> SleepDetails? {
        guard let start = sleepIntervals.map(\.start).min(), let end = sleepIntervals.map(\.end).max(), end > start else { return nil }
        let sources = Dictionary(grouping: samples.filter {
            sleepStage(for: $0.value) != nil && $0.startDate < end && $0.endDate > start
        }) { $0.sourceRevision.source.bundleIdentifier }
        let preferred = sources.values.sorted { left, right in
            let leftWatch = left.contains { $0.sourceRevision.productType?.hasPrefix("Watch") == true }
            let rightWatch = right.contains { $0.sourceRevision.productType?.hasPrefix("Watch") == true }
            let leftStages = left.contains { [SleepStage.core, .deep, .rem].contains(sleepStage(for: $0.value) ?? .unspecified) }
            let rightStages = right.contains { [SleepStage.core, .deep, .rem].contains(sleepStage(for: $0.value) ?? .unspecified) }
            if leftStages != rightStages { return leftStages }
            if leftWatch != rightWatch { return leftWatch }
            let leftCoverage = sleepDuration(left.compactMap { stageInterval($0, start: start, end: end) })
            let rightCoverage = sleepDuration(right.compactMap { stageInterval($0, start: start, end: end) })
            if leftCoverage != rightCoverage { return leftCoverage > rightCoverage }
            return (left.first?.sourceRevision.source.bundleIdentifier ?? "") < (right.first?.sourceRevision.source.bundleIdentifier ?? "")
        }.first ?? []
        let observations = preferred.compactMap { sample -> SleepSegment? in
            guard let stage = sleepStage(for: sample.value), let interval = stageInterval(sample, start: start, end: end) else { return nil }
            return SleepSegment(start: interval.start, end: interval.end, stage: stage)
        }.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start > $1.start }
        let boundaries = Set(sleepIntervals.flatMap { [$0.start, $0.end] } + observations.flatMap { [$0.start, $0.end] }).sorted()
        var segments: [SleepSegment] = []
        for (beginning, ending) in zip(boundaries, boundaries.dropFirst()) {
            guard ending > beginning else { continue }
            let midpoint = beginning.addingTimeInterval(ending.timeIntervalSince(beginning) / 2)
            let asleep = sleepIntervals.contains { $0.start <= midpoint && midpoint < $0.end }
            let observation = observations.first { $0.start <= midpoint && midpoint < $0.end }
            let stage: SleepStage
            if asleep {
                // Keep the scoring input's deduplicated asleep union. A conflicting
                // awake sample cannot supply a known sleep stage for this interval.
                stage = observation?.stage == .awake ? .unspecified : (observation?.stage ?? .unspecified)
            } else if observation?.stage == .awake {
                stage = .awake
            } else { continue }
            if let previous = segments.last, previous.stage == stage, previous.end == beginning {
                segments[segments.count - 1].end = ending
            } else {
                segments.append(SleepSegment(start: beginning, end: ending, stage: stage))
            }
        }
        guard !segments.isEmpty else { return nil }
        let source = preferred.first?.sourceRevision.source.name ?? "Apple 健康"
        let supplemented = segments.contains { $0.stage == .unspecified }
        return SleepDetails(segments: segments, sourceTitle: supplemented ? "\(source) · 未分期片段已去重合并" : source,
                            startedAt: start, endedAt: end)
    }

    private static func stageInterval(_ sample: HKCategorySample, start: Date, end: Date) -> DateInterval? {
        let beginning = max(start, sample.startDate)
        let ending = min(end, sample.endDate)
        return ending > beginning ? DateInterval(start: beginning, end: ending) : nil
    }

    private static func sleepStage(for value: Int) -> SleepStage? {
        switch value {
        case HKCategoryValueSleepAnalysis.awake.rawValue: return .awake
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue: return .core
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: return .deep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue: return .rem
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: return .unspecified
        default: return nil
        }
    }

    private func fitnessContext(now: Date) async -> FitnessContext? {
        var context = FitnessContext()
        if let birthday = try? healthStore.dateOfBirthComponents(),
           birthday.year != nil, birthday.month != nil, birthday.day != nil {
            context.dateOfBirth = birthday
        }
        if let sex = try? healthStore.biologicalSex().biologicalSex {
            switch sex {
            case .female: context.biologicalSex = .female
            case .male: context.biologicalSex = .male
            case .other: context.biologicalSex = .other
            default: break
            }
        }
        if let type = HKObjectType.quantityType(forIdentifier: .vo2Max) {
            let start = calendar.date(byAdding: .year, value: -1, to: now)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
            let samples = try? await quantitySamples(type: type, predicate: predicate, limit: 20)
            let unit = HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo)).unitDivided(by: .minute())
            if let sample = samples?.first(where: {
                let value = $0.quantity.doubleValue(for: unit)
                return value.isFinite && value > 0
                    && ($0.metadata?[HKMetadataKeyWasUserEntered] as? NSNumber)?.boolValue != true
            }) {
                context.vo2MaxMLKgMin = sample.quantity.doubleValue(for: unit)
                context.sampledAt = sample.endDate
                context.sourceTitle = sample.sourceRevision.source.name
            }
        }
        return context.vo2MaxMLKgMin != nil || context.dateOfBirth != nil || context.biologicalSex != nil ? context : nil
    }

    static func sleepDuration(_ intervals: [DateInterval]) -> TimeInterval {
        let sorted = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return 0 }
        var total: TimeInterval = 0
        for next in sorted.dropFirst() {
            if next.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, next.end))
            } else {
                total += current.duration
                current = next
            }
        }
        return total + current.duration
    }

    private func requiredReadTypes() throws -> Set<HKObjectType> {
        guard
            let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate),
            let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            let restingHeartRate = HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
            let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession)
        else {
            throw HealthManagerError.missingType("必要的 HealthKit 类型")
        }

        var types: Set<HKObjectType> = [heartRate, hrv, restingHeartRate, activeEnergy, sleep, mindful,
                                     HKObjectType.workoutType(), HKSeriesType.heartbeat()]
        if let vo2Max = HKObjectType.quantityType(forIdentifier: .vo2Max) { types.insert(vo2Max) }
        if let birthday = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { types.insert(birthday) }
        if let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) { types.insert(sex) }
        return types
    }

    private func quantityType(_ identifier: HKQuantityTypeIdentifier) throws -> HKQuantityType {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw HealthManagerError.missingType(identifier.rawValue)
        }
        return type
    }

    private func quantitySamples(
        type: HKQuantityType,
        predicate: NSPredicate?,
        sort: [NSSortDescriptor] = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)],
        limit: Int
    ) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: sort) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let casted = (samples as? [HKQuantitySample]) ?? []
                continuation.resume(returning: casted)
            }
            healthStore.execute(query)
        }
    }

    private func categorySamples(
        type: HKCategoryType,
        predicate: NSPredicate?,
        limit: Int
    ) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }
}
