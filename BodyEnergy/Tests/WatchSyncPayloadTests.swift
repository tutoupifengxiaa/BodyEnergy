import XCTest
@testable import BodyEnergy

final class WatchSyncPayloadTests: XCTestCase {
    func testSamplePayloadsAreRejected() {
        var payload = WatchSyncPayload(snapshot: .preview, sampleScenarioTitle: "状态平稳")
        XCTAssertNil(WatchSyncPayload(applicationContext: payload.applicationContext))
        XCTAssertNil(payload.widgetSnapshot())

        payload.isSampleData = false
        XCTAssertNil(WatchSyncPayload(applicationContext: payload.applicationContext))

        payload.sampleScenarioTitle = nil
        payload.isSampleData = true
        XCTAssertNil(WatchSyncPayload(applicationContext: payload.applicationContext))

        var legacyContext = payload.applicationContext
        legacyContext.removeValue(forKey: "payloadV2")
        legacyContext["sampleScenarioTitle"] = "状态平稳"
        XCTAssertNil(WatchSyncPayload(applicationContext: legacyContext))
    }

    func testPayloadCarriesStructuredRecommendationFieldsStressAndBodyStatus() {
        let recommendation = WorkoutRecommendation(
            title: "二区有氧恢复课",
            summary: "身体状态平稳，建议以二区有氧为主，并适当减少训练总量。",
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
        let bodyStatus = BodyStatusDescriptor.make(energyScore: snapshot.energyScore)

        var payload = WatchSyncPayload(
            snapshot: snapshot,
            workoutRecommendation: recommendation,
            metrics: WatchKeyMetricsSnapshot(
                heartRateBPM: 72,
                heartRateVariabilityMS: 55,
                restingHeartRateBPM: 58,
                sleepHours: 7.5,
                activeEnergyKcal: 520,
                stressScore: 48,
                stressLevelTitle: "压力适中"
            ),
            stressScore: 48,
            stressLevelTitle: "压力适中",
            bodyStatus: bodyStatus
        )
        payload.hourlyStress = [HourlyStress(hour: snapshot.updatedAt, score: 42)]
        let restored = WatchSyncPayload(applicationContext: payload.applicationContext)

        XCTAssertEqual(restored?.workoutRecommendation.steps, recommendation.steps)
        XCTAssertEqual(restored?.workoutRecommendation.cautionText, recommendation.cautionText)
        XCTAssertEqual(restored?.workoutRecommendation.purposeText, recommendation.purposeText)
        XCTAssertEqual(restored?.widgetSnapshot()?.stressScore, 48)
        XCTAssertEqual(restored?.recommendationTitle, recommendation.title)
        XCTAssertEqual(restored?.recommendationDurationText, recommendation.durationText)
        XCTAssertEqual(restored?.recommendationIntensityText, recommendation.intensityText)
        XCTAssertEqual(restored?.stressScore, 48)
        XCTAssertEqual(restored?.stressLevelTitle, "压力适中")
        XCTAssertEqual(restored?.hourlyStress, payload.hourlyStress)
        XCTAssertEqual(restored?.bodyStatus?.title, bodyStatus.title)
        XCTAssertEqual(restored?.bodyStatus?.detail, bodyStatus.detail)
        XCTAssertEqual(restored?.bodyStatus?.action, bodyStatus.action)
        XCTAssertEqual(restored?.metrics?.heartRateBPM, 72)
        XCTAssertEqual(restored?.metrics?.heartRateVariabilityMS, 55)
        XCTAssertEqual(restored?.metrics?.restingHeartRateBPM, 58)
        XCTAssertEqual(restored?.metrics?.sleepHours, 7.5)
        XCTAssertEqual(restored?.metrics?.activeEnergyKcal, 520)
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
        XCTAssertNil(payload?.metrics)
    }

    func testWidgetSnapshotDerivesTitleFromCurrentScore() {
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
        XCTAssertEqual(widgetSnapshot?.stressLevelTitle, "压力偏高")
    }
}

final class DataIterationTests: XCTestCase {
    @MainActor
    func testRecommendationsStayAvailableWithMissingOrStaleHealthData() async {
        let suite = "BodyEnergy.RecommendationVisibilityTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let stub = IterationHealthStub()
        let store = AppStore(healthManager: stub, watchSyncPublisher: IterationPublisherSpy(),
                             historyStore: HealthHistoryStore(defaults: defaults), widgetWriter: { _ in })
        XCTAssertFalse(store.hasCurrentRecommendation)
        XCTAssertEqual(store.displayedWorkoutRecommendation, .generalActivity)
        XCTAssertEqual(store.workoutRecommendation, .empty)
        XCTAssertFalse(store.hasScore)

        var health = HealthSnapshot.baseline
        health.sampleDates = Dictionary(uniqueKeysWithValues: HealthMetric.allCases.map { ($0, Date.now) })
        health.missingMetrics = [.sleep]
        stub.value = health
        await store.refreshHealthData(requestAuthorization: false)
        XCTAssertFalse(store.hasScore)
        XCTAssertTrue(store.hasPressure)
        XCTAssertEqual(store.displayedWorkoutRecommendation, .generalActivity)

        health.missingMetrics = []
        stub.value = health
        await store.refreshHealthData(requestAuthorization: false)
        XCTAssertTrue(store.hasCurrentRecommendation)
        XCTAssertEqual(store.displayedWorkoutRecommendation, store.workoutRecommendation)
        XCTAssertNotEqual(store.displayedWorkoutRecommendation, .generalActivity)

        stub.error = HealthManagerError.healthDataUnavailable
        await store.refreshHealthData(requestAuthorization: false)
        XCTAssertTrue(store.hasScore)
        XCTAssertFalse(store.hasCurrentRecommendation)
        XCTAssertEqual(store.displayedWorkoutRecommendation, .generalActivity)
    }

    @MainActor
    func testInitialAutomaticReadAndPartialMetricsSurviveRelaunch() async {
        let suite = "BodyEnergy.InitialMetricsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = HealthHistoryStore(defaults: defaults)
        let stub = IterationHealthStub()
        var health = HealthSnapshot.baseline
        let sampledAt = Date.now.addingTimeInterval(-60)
        health.sampleDates = Dictionary(uniqueKeysWithValues: HealthMetric.allCases.map { ($0, sampledAt) })
        health.missingMetrics = [.sleep]
        health.sampleDates.removeValue(forKey: .sleep)
        stub.value = health
        let store = AppStore(healthManager: stub, watchSyncPublisher: IterationPublisherSpy(),
                             historyStore: storage, widgetWriter: { _ in })
        await store.refreshIfNeeded()
        XCTAssertEqual(stub.fetchCount, 1)
        XCTAssertEqual(store.health, health)
        XCTAssertFalse(store.hasScore)
        XCTAssertTrue(storage.load().isEmpty)
        let reopened = AppStore(healthManager: stub, watchSyncPublisher: IterationPublisherSpy(),
                                historyStore: storage, widgetWriter: { _ in })
        XCTAssertEqual(reopened.health, health)
        XCTAssertEqual(reopened.pressure?.updatedAt, sampledAt)
        XCTAssertTrue(reopened.hasPressure)
        XCTAssertEqual(stub.fetchCount, 1)
    }

    @MainActor
    func testEveryForegroundActivationReadsWithoutMinuteDelay() async {
        let suite = "BodyEnergy.ForegroundMetricsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let stub = IterationHealthStub()
        let store = AppStore(healthManager: stub, watchSyncPublisher: IterationPublisherSpy(),
                             historyStore: HealthHistoryStore(defaults: defaults), widgetWriter: { _ in })
        let delegate = BodyEnergyAppDelegate(store: store)
        await delegate.refreshOnActivation()
        var health = HealthSnapshot.baseline
        health.sampleDates = Dictionary(uniqueKeysWithValues: HealthMetric.allCases.map { ($0, Date.now) })
        stub.value = health
        await delegate.refreshOnActivation()
        XCTAssertEqual(stub.fetchCount, 2)
        XCTAssertEqual(store.health, health)
    }

    @MainActor
    func testReadFailureDoesNotEraseMetricsButSuccessfulEmptyReadDoes() async {
        let suite = "BodyEnergy.ReadFailureTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = HealthHistoryStore(defaults: defaults)
        let stub = IterationHealthStub()
        let publisher = IterationPublisherSpy()
        var health = HealthSnapshot.baseline
        health.sampleDates = Dictionary(uniqueKeysWithValues: HealthMetric.allCases.map { ($0, Date.now) })
        health.missingMetrics = [.sleep]
        stub.value = health
        let store = AppStore(healthManager: stub, watchSyncPublisher: publisher,
                             historyStore: storage, widgetWriter: { _ in })
        await store.refreshHealthData(requestAuthorization: false)
        stub.error = HealthManagerError.healthDataUnavailable
        await store.refreshHealthData(requestAuthorization: false)
        XCTAssertEqual(store.health, health)
        XCTAssertEqual(publisher.latest?.metrics?.health, health)
        XCTAssertEqual(storage.loadLatestHealth(), health)
        XCTAssertNotNil(store.healthErrorMessage)
        stub.error = nil
        stub.value = .empty
        await store.refreshHealthData(requestAuthorization: false)
        XCTAssertEqual(store.health, .empty)
        XCTAssertEqual(storage.loadLatestHealth(), .empty)
    }

    @MainActor
    func testHealthObserverPublishesAutomaticallyAndDefersProtectedData() async throws {
        let suite = "BodyEnergy.ObserverTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let stub = IterationHealthStub()
        let publisher = IterationPublisherSpy()
        let store = AppStore(healthManager: stub, watchSyncPublisher: publisher,
                             historyStore: HealthHistoryStore(defaults: defaults), widgetWriter: { _ in })
        var unlocked = false
        store.startAutomaticUpdates(canReadHealthData: { unlocked })
        XCTAssertTrue(stub.backgroundEnabled)
        var health = HealthSnapshot.baseline
        health.sampleDates = Dictionary(uniqueKeysWithValues: HealthMetric.allCases.map { ($0, Date.now) })
        health.missingMetrics = [.sleep]
        stub.value = health
        await stub.onChange?()
        XCTAssertEqual(stub.fetchCount, 0)
        XCTAssertNil(publisher.latest)
        unlocked = true
        await stub.onChange?()
        XCTAssertEqual(stub.fetchCount, 1)
        XCTAssertNotNil(publisher.latest?.stress)
        XCTAssertEqual(publisher.latest?.hasScore, false)
    }

    @MainActor
    func testObserverDuringRefreshWaitsForNewestDataToBePublished() async throws {
        let suite = "BodyEnergy.ObserverQueueTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let stub = IterationHealthStub()
        let publisher = IterationPublisherSpy()
        let store = AppStore(healthManager: stub, watchSyncPublisher: publisher,
                             historyStore: HealthHistoryStore(defaults: defaults), widgetWriter: { _ in })
        store.startAutomaticUpdates()
        var health = HealthSnapshot.baseline
        let now = Date.now
        health.sampleDates = Dictionary(uniqueKeysWithValues: HealthMetric.allCases.map { ($0, now.addingTimeInterval(-60)) })
        stub.value = health
        let started = expectation(description: "First health read suspended")
        var release: CheckedContinuation<Void, Never>?
        stub.beforeFetch = {
            if stub.fetchCount == 1 {
                await withCheckedContinuation { release = $0; started.fulfill() }
            }
        }
        let first = Task { await stub.onChange?() }
        await fulfillment(of: [started], timeout: 2)
        health.sampleDates[.hrv] = now
        stub.value = health
        let secondStarted = expectation(description: "Next observer update delivered")
        var secondCompleted = false
        let second = Task {
            secondStarted.fulfill()
            await stub.onChange?()
            secondCompleted = true
        }
        await fulfillment(of: [secondStarted], timeout: 2)
        XCTAssertFalse(secondCompleted)
        release?.resume()
        await first.value
        await second.value
        XCTAssertEqual(stub.fetchCount, 2)
        XCTAssertEqual(publisher.latest?.stress?.updatedAt, now)
        XCTAssertFalse(store.isLoadingHealth)
    }

    @MainActor
    func testPressureSyncAndWidgetDoNotRequireSleep() async throws {
        let suite = "BodyEnergy.PressureTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = HealthHistoryStore(defaults: defaults)
        let stub = IterationHealthStub()
        let publisher = IterationPublisherSpy()
        var widget: WidgetMetricsSnapshot?
        let store = AppStore(healthManager: stub, watchSyncPublisher: publisher, historyStore: storage,
                             widgetWriter: { widget = $0 })
        var health = HealthSnapshot.baseline
        let measuredAt = Date.now.addingTimeInterval(-60)
        health.sampleDates = Dictionary(uniqueKeysWithValues: HealthMetric.allCases.map { ($0, measuredAt) })
        health.missingMetrics = [.sleep, .activeEnergy]
        health.sampleDates.removeValue(forKey: .sleep)
        health.sampleDates.removeValue(forKey: .activeEnergy)
        stub.value = health
        await publisher.onRefreshRequested?()
        XCTAssertFalse(store.hasScore)
        XCTAssertTrue(store.hasPressure)
        XCTAssertFalse(store.isPressureStale)
        XCTAssertEqual(store.pressure?.basis, "HRV 与心率估算")
        XCTAssertEqual(store.pressure?.updatedAt, measuredAt)
        XCTAssertEqual(storage.load().count, 0)
        XCTAssertEqual(widget?.hasData, false)
        XCTAssertEqual(widget?.hasStressData, true)
        let payload = try XCTUnwrap(publisher.latest)
        let restored = try XCTUnwrap(WatchSyncPayload(applicationContext: payload.applicationContext))
        XCTAssertFalse(restored.hasScore)
        XCTAssertEqual(restored.availableStress, store.pressure)
        XCTAssertEqual(restored.widgetSnapshot()?.stressUpdatedAt, measuredAt)
        XCTAssertEqual(restored.metrics?.health?.missingMetrics, health.missingMetrics)
        let encoded = try JSONEncoder().encode(try XCTUnwrap(widget))
        XCTAssertEqual(try JSONDecoder().decode(WidgetMetricsSnapshot.self, from: encoded).stress, store.pressure)
        stub.value = .empty
        await store.refreshHealthData()
        XCTAssertTrue(store.isPressureStale)
        XCTAssertEqual(widget?.isStressStale, true)
    }

    func testSleepIntervalsMergeWithoutDoubleCounting() {
        let start = Date(timeIntervalSince1970: 1700000000)
        let intervals = [DateInterval(start: start, duration: 7 * 3600),
                         DateInterval(start: start, duration: 2 * 3600),
                         DateInterval(start: start.addingTimeInterval(3600), duration: 5 * 3600)]
        XCTAssertEqual(HealthManager.sleepDuration(intervals), 7 * 3600)
        XCTAssertEqual(HealthManager.sleepDuration([]), 0)
    }

    func testHistoryGapsAndPayloadOrdering() {
        let now = Date.now
        let metric = DailyMetrics(date: now, energyScore: 60, recoveryScore: 55, stressScore: 40)
        let days = HistoryDay.recentWeek([metric], now: now)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.filter { $0.metrics == nil }.count, 6)
        var old = WatchSyncPayload(snapshot: .preview)
        old.sentAt = now.addingTimeInterval(-10)
        var new = old
        new.sentAt = now
        XCTAssertFalse(old.isNewer(than: new))
        XCTAssertFalse(new.isNewer(than: new))
        XCTAssertTrue(new.isNewer(than: old))
    }

    @MainActor
    func testRealDataSurvivesMissingRead() async {
        let suite = "BodyEnergy.DataIterationTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = HealthHistoryStore(defaults: defaults)
        let stub = IterationHealthStub()
        let publisher = IterationPublisherSpy()
        var widgetWrites = 0
        let store = AppStore(healthManager: stub, watchSyncPublisher: publisher, historyStore: storage,
                             widgetWriter: { _ in widgetWrites += 1 })
        await store.refreshHealthData()
        XCTAssertFalse(store.hasScore)
        XCTAssertEqual(store.dataStatusTitle, "暂无评分")
        XCTAssertEqual(store.workoutRecommendation, .empty)
        XCTAssertEqual(widgetWrites, 0)
        var valid = HealthSnapshot.baseline
        let sampledAt = Date.now.addingTimeInterval(-60)
        valid.sampleDates = Dictionary(uniqueKeysWithValues: HealthMetric.allCases.map { ($0, sampledAt) })
        stub.value = valid
        await store.refreshHealthData()
        XCTAssertTrue(store.hasScore)
        XCTAssertEqual(store.snapshot.updatedAt, sampledAt)
        XCTAssertEqual(storage.load().count, 1)
        XCTAssertEqual(widgetWrites, 1)
        let real = store.snapshot
        stub.value = .empty
        await store.refreshHealthData()
        XCTAssertEqual(store.snapshot, real)
        XCTAssertTrue(store.health.missingMetrics.contains(.hrv))
        XCTAssertTrue(store.isScoreStale)
        XCTAssertEqual(storage.load().count, 1)
        XCTAssertEqual(widgetWrites, 2)
        XCTAssertFalse(publisher.latest?.isSampleData ?? true)
        XCTAssertEqual(store.history.count, 1)
        valid.sampleDates[.hrv] = Date.now.addingTimeInterval(-40 * 3600)
        XCTAssertFalse(valid.isUsable(at: .now))
    }
}

private final class IterationHealthStub: HealthManaging {
    var value = HealthSnapshot.empty
    var onChange: (@MainActor () async -> Void)?
    var fetchCount = 0
    var backgroundEnabled = false
    var beforeFetch: (() async -> Void)?
    var error: Error?
    func requestAuthorization() async throws {}
    func observeChanges(_ onChange: @escaping @MainActor () async -> Void) { self.onChange = onChange }
    func enableBackgroundUpdates() { backgroundEnabled = true }
    func fetchLatestSnapshot(now: Date) async throws -> HealthSnapshot {
        fetchCount += 1
        if let error { throw error }
        let snapshot = value
        await beforeFetch?()
        return snapshot
    }
    func fetchTodayHourlyStress(now: Date) async throws -> [HourlyStress] { [] }
}

@MainActor
private final class IterationPublisherSpy: WatchSyncPublishing {
    var onRefreshRequested: (@MainActor () async -> Void)?
    var latest: WatchSyncPayload?
    func publish(_ payload: WatchSyncPayload) { latest = payload }
}
