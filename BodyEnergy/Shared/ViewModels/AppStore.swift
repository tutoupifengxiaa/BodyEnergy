import Combine
import Foundation
import HealthKit
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class AppStore: ObservableObject {
    let activities: ActivityStore
    let preferences: PreferencesStore
    let habits: RecoveryHabitStore
    @Published var health: HealthSnapshot
    @Published var snapshot: EnergySnapshot
    @Published var stressReading: StressReading
    @Published var workoutRecommendation: WorkoutRecommendation
    @Published var isLoadingHealth = false
    @Published var healthErrorMessage: String?
    @Published private(set) var hasScore = false
    @Published private(set) var history: [DailyMetrics] = []
    @Published private(set) var batteryHistory: [DailyMetrics] = []
    @Published private(set) var hourlyStress: [HourlyStress] = []
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var lastRefreshSucceeded: Bool?
    @Published private(set) var scoreValidUntil: Date?
    @Published private(set) var pressure: StressSnapshot?
    @Published private(set) var batteryChange: Int?
    @Published private(set) var historyRecords: [HealthRecord] = []
    @Published private(set) var batteryTimeline: [BatteryTimelinePoint] = []
    @Published private(set) var batteryAssessment: BatteryAssessment?
    @Published private(set) var pressureSamples: [EnergyPressureSample] = []

    var hasPressure: Bool { pressure != nil }
    var recoveryScoreForDisplay: Int? {
        health.scoringVersion == BodyBatteryScorer.algorithmVersion ? health.morningRecovery?.score
            : (hasScore ? snapshot.recoveryScore : nil)
    }
    var isPressureStale: Bool { pressure?.isStale ?? true }
    var pressureHistory: [DailyMetrics] {
        history.map { $0.matchingPressureMetric(pressure?.hrvMetric ?? health.pressureMeasurement?.metric ?? .sdnn) }
    }
    var hasCurrentRecommendation: Bool { hasScore && !isScoreStale }
    var displayedWorkoutRecommendation: WorkoutRecommendation {
        hasCurrentRecommendation ? workoutRecommendation : .generalActivity
    }

    private let healthManager: HealthManaging
    private let scorer: EnergyScorer
    private let batteryScorer = BodyBatteryScorer()
    private let stressAnalyzer: StressAnalyzer
    private let recommendationEngine: RecommendationEngine
    private let watchSyncPublisher: WatchSyncPublishing
    private let historyStore: HealthHistoryStore
    private let timelineStore: BatteryTimelineStore
    private let pressureHistoryStore: PressureHistoryStore
    private let dailyHistoryStore: DailyMetricsHistoryStore
    private var subscriptions = Set<AnyCancellable>()
    private var processedHabitRecordIDs = Set<UUID>()
    private let widgetWriter: (WidgetMetricsSnapshot) -> Void
    private var lastRealRecord: HealthRecord?
    private var watchPressure: SyncedPressureRecord?
    private var canReadHealthData: @MainActor () -> Bool = { true }
    private var refreshPending = false
    private var authorizationPending = false
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        health: HealthSnapshot = .empty,
        snapshot: EnergySnapshot = .empty,
        healthManager: HealthManaging = HealthManager(),
        scorer: EnergyScorer = EnergyScorer(),
        stressAnalyzer: StressAnalyzer = StressAnalyzer(),
        recommendationEngine: RecommendationEngine = RecommendationEngine(),
        watchSyncPublisher: WatchSyncPublishing? = nil,
        historyStore: HealthHistoryStore = HealthHistoryStore(),
        activities: ActivityStore? = nil,
        preferences: PreferencesStore? = nil,
        habits: RecoveryHabitStore? = nil,
        timelineStore: BatteryTimelineStore = BatteryTimelineStore(),
        pressureHistoryStore: PressureHistoryStore = PressureHistoryStore(),
        dailyHistoryStore: DailyMetricsHistoryStore = DailyMetricsHistoryStore(),
        widgetWriter: @escaping (WidgetMetricsSnapshot) -> Void = WidgetMetricsStore.save
    ) {
        self.health = health
        self.snapshot = snapshot
        self.healthManager = healthManager
        self.scorer = scorer
        self.stressAnalyzer = stressAnalyzer
        self.recommendationEngine = recommendationEngine
        self.watchSyncPublisher = watchSyncPublisher ?? WatchSyncPublisherFactory.makeDefault()
        self.historyStore = historyStore
        self.preferences = activities?.preferences ?? preferences ?? PreferencesStore()
        self.activities = activities ?? ActivityStore(preferences: self.preferences)
        processedHabitRecordIDs = Set(self.activities.records.map(\.id))
        self.habits = habits ?? RecoveryHabitStore(preferences: self.preferences)
        self.timelineStore = timelineStore
        self.pressureHistoryStore = pressureHistoryStore
        self.dailyHistoryStore = dailyHistoryStore
        self.widgetWriter = widgetWriter
        self.stressReading = StressReading(score: 0, level: .low, hrvStressScore: 0, restingHeartRateStressScore: 0, acuteStressScore: 0)
        self.workoutRecommendation = .empty
        let records = historyStore.load()
        historyRecords = records
        batteryTimeline = timelineStore.load()
        batteryAssessment = records.last?.batteryAssessment
        history = dailyHistoryStore.merge(records.map(\.dailyMetrics))
        batteryHistory = records.filter { $0.batteryLevel != nil }.map(\.dailyMetrics)
        lastRealRecord = records.last
        restoreRealData()
        if let latest = historyStore.loadLatestHealth() {
            self.health = latest
            if latest.pressureContextPrepared == true,
               latest.pressureAlgorithmVersion == StressSnapshot.algorithmVersion, lastRealRecord?.health != latest {
                updatePressure(from: latest, now: .now)
            }
            if !latest.isUsable(at: .now) { healthErrorMessage = missingDataMessage(for: latest) }
        }
        if let saved = historyStore.loadWatchPressure() {
            adoptWatchPressure(saved, publish: false)
        }
        self.watchSyncPublisher.onHealthPayloadReceived = { [weak self] payload in
            self?.receiveWatchHealth(payload)
        }
        self.watchSyncPublisher.onRefreshRequested = { [weak self] in
            guard let self else { return }
            guard self.canReadHealthData() else {
                self.publishCurrent()
                return
            }
            await self.refreshHealthData(requestAuthorization: false, followUpIfInFlight: false)
        }
        let previousRecordsChanged = self.activities.onRecordsChanged
        self.activities.onRecordsChanged = { [weak self] records in
            previousRecordsChanged?(records)
            self?.updateHabitProgress(records: records)
            self?.publishCurrent()
        }
        self.watchSyncPublisher.onActivityRecordsReceived = { [weak self] records in
            guard let self, self.activities.merge(records) else { return }
            self.updateHabitProgress(records: self.activities.records)
            self.publishCurrent()
        }
        let previousPreferencesChanged = self.preferences.onChanged
        self.preferences.onChanged = { [weak self] settings in
            previousPreferencesChanged?(settings)
            self?.refreshRecommendation()
            self?.publishCurrent()
        }
        let previousHabitsChanged = self.habits.onChanged
        self.habits.onChanged = { [weak self] days in
            previousHabitsChanged?(days)
            self?.publishCurrent()
        }
        self.watchSyncPublisher.onUserFeaturesReceived = { [weak self] state in
            guard let self else { return }
            let changed = self.mergeUserFeatures(state)
            if changed { self.publishCurrent() }
        }
        preferencesChanges()
        updateActivityPressureSamples()
    }

    private func preferencesChanges() {
        preferences.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        habits.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        activities.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
    }

    private func updateHabitProgress(records: [ActivityRecord]) {
        guard records.contains(where: { !processedHabitRecordIDs.contains($0.id) }) else { return }
        processedHabitRecordIDs = Set(records.map(\.id))
        let today = records.filter { Calendar.current.isDateInToday($0.completedAt) }
        let breathing = today.filter { $0.kind == .breathing }.reduce(0) { $0 + $1.durationSeconds }
        let walking = today.filter { $0.kind == .workout && $0.activityType == .walking }.reduce(0) { $0 + $1.durationSeconds }
        if breathing >= preferences.settings.breathingGoalMinutes * 60 { habits.markCompleted(.breathing, on: .now) }
        if walking >= preferences.settings.walkingGoalMinutes * 60 { habits.markCompleted(.walking, on: .now) }
    }

    private func refreshRecommendation() {
        guard hasCurrentRecommendation else { return }
        let raw = scorer.computeScores(input: EnergyInput(snapshot: health))
        let scores = EnergyScores(recoveryScore: snapshot.recoveryScore, energyScore: snapshot.energyScore,
            trainingLoadScore: raw.trainingLoadScore, trainingLoadAvailable: raw.trainingLoadAvailable)
        workoutRecommendation = recommendationEngine.plan(for: scores, preferences: preferences.settings.training)
        snapshot.recommendation = workoutRecommendation.summary
    }

    @discardableResult
    func mergeUserFeatures(_ state: UserFeaturesState) -> Bool {
        let preferencesChanged = state.preferences.map { preferences.merge($0) } ?? false
        let habitsChanged = habits.merge(state.habitDays ?? [])
        if preferencesChanged { refreshRecommendation() }
        return preferencesChanged || habitsChanged
    }

    private func updateActivityPressureSamples() {
        pressureSamples = pressureHistoryStore.merge(EnergyPressureSample.samples(records: historyRecords, currentHealth: health, currentPressure: pressure))
        activities.updatePressureSamples(pressureSamples)
    }

    func receiveWatchHealth(_ payload: WatchSyncPayload) {
        guard payload.collectionSource == .appleWatch, !payload.isSampleData,
              payload.sampleScenarioTitle == nil,
              payload.stressAlgorithmVersion == StressSnapshot.algorithmVersion,
              let stress = payload.availableStress,
              let measurement = payload.metrics?.health?.pressureMeasurement else { return }
        adoptWatchPressure(SyncedPressureRecord(stress: stress, measurement: measurement,
            hourlyStress: payload.availableHourlyStress, algorithmVersion: StressSnapshot.algorithmVersion), publish: true)
    }

    private func adoptWatchPressure(_ incomingRecord: SyncedPressureRecord, publish: Bool) {
        var record = incomingRecord
        let now = Date.now
        let incoming = record.stress
        guard record.algorithmVersion == StressSnapshot.algorithmVersion,
              (0...100).contains(incoming.score), incoming.updatedAt.timeIntervalSince1970.isFinite,
              incoming.updatedAt <= now, incoming.validUntil.timeIntervalSince1970.isFinite,
              incoming.validUntil >= incoming.updatedAt,
              !publish || incoming.validUntil >= now,
              record.measurement.sampledAt == incoming.updatedAt,
              record.measurement.metric == (incoming.hrvMetric ?? .sdnn),
              stressAnalyzer.isValid(measurement: record.measurement),
              incoming.updatedAt >= (watchPressure?.stress.updatedAt ?? .distantPast),
              incoming.updatedAt >= (pressure?.updatedAt ?? .distantPast) else { return }
        if let previous = watchPressure, incoming.updatedAt == previous.stress.updatedAt {
            guard incoming == previous.stress, record.measurement == previous.measurement else { return }
            let hours = Dictionary((previous.hourlyStress + record.hourlyStress).map { ($0.hour, $0) },
                uniquingKeysWith: { _, latest in latest }).values.sorted { $0.hour < $1.hour }
            record = SyncedPressureRecord(stress: incoming, measurement: record.measurement,
                hourlyStress: hours, algorithmVersion: record.algorithmVersion)
            guard record != previous else { return }
        }
        watchPressure = record
        historyStore.saveWatchPressure(record)
        health = preservingWatchPressure(in: health)
        pressure = incoming
        stressReading = StressReading(score: incoming.score, level: stressAnalyzer.level(for: incoming.score),
            hrvStressScore: incoming.score, restingHeartRateStressScore: 0, acuteStressScore: 0)
        hourlyStress = mergedHourlyStress(hourlyStress)
        historyStore.saveLatestHealth(health)
        updateActivityPressureSamples()
        if publish { publishCurrent() }
    }

    private func preservingWatchPressure(in source: HealthSnapshot) -> HealthSnapshot {
        guard let record = watchPressure,
              record.stress.updatedAt >= (pressure?.updatedAt ?? .distantPast) else { return source }
        let localDate = source.pressureMeasurement.flatMap {
            stressAnalyzer.isValid(measurement: $0) ? $0.sampledAt : nil
        } ?? stressAnalyzer.evaluateAvailable(snapshot: source)?.snapshot.updatedAt ?? .distantPast
        guard record.stress.updatedAt >= localDate else { return source }
        var merged = source
        // Pressure has its own sampling clock; keep the phone's other health metrics.
        merged.pressureMeasurement = record.measurement
        merged.pressureContextPrepared = true
        merged.pressureAlgorithmVersion = record.algorithmVersion
        return merged
    }

    private func mergedHourlyStress(_ local: [HourlyStress]) -> [HourlyStress] {
        guard let record = watchPressure else { return local }
        let prefersWatch = health.pressureMeasurement == record.measurement
        let metric = health.pressureMeasurement?.metric ?? .sdnn
        let ordered = prefersWatch ? local + record.hourlyStress : record.hourlyStress + local
        var byHour: [Date: HourlyStress] = [:]
        for value in ordered where (value.hrvMetric ?? .sdnn) == metric &&
            value.hour.timeIntervalSince1970.isFinite && Calendar.current.isDateInToday(value.hour) &&
            value.hour <= .now && (0...100).contains(value.score) {
            byHour[value.hour] = value
        }
        return byHour.values.sorted { $0.hour < $1.hour }
    }

    func applySyncedInsights(_ payload: WatchSyncPayload, includeCurrent: Bool = true) {
        if let state = payload.userFeatures { mergeUserFeatures(state) }
        if let records = payload.activityRecords { activities.merge(records); updateHabitProgress(records: activities.records) }
        if let points = payload.batteryTimeline { batteryTimeline = timelineStore.merge(Array(points.suffix(32))) }
        if payload.stressAlgorithmVersion == StressSnapshot.algorithmVersion, let samples = payload.pressureSamples {
            pressureSamples = pressureHistoryStore.merge(Array(samples.suffix(32)))
            activities.updatePressureSamples(pressureSamples)
        }
        history = dailyHistoryStore.merge(payload.availableHistory)
        guard includeCurrent, let incomingHealth = payload.metrics?.health,
              incomingHealth.measuredAt.map({ $0 >= (health.measuredAt ?? .distantPast) }) ?? false else { return }
        health = incomingHealth
        healthErrorMessage = payload.statusMessage
        pressure = payload.availableStress
        if payload.hasScore {
            snapshot = payload.asSnapshot
            workoutRecommendation = payload.workoutRecommendation
            hasScore = true
            scoreValidUntil = payload.validUntil
            batteryAssessment = payload.availableBatteryAssessment
            let record = HealthRecord(health: health, energy: snapshot, stressScore: pressure?.score,
                stressLevelTitle: pressure?.levelTitle, recommendation: workoutRecommendation,
                batteryLevel: batteryAssessment?.level ?? Double(snapshot.energyScore), batteryAssessment: batteryAssessment)
            if incomingHealth.isUsable(at: .now) {
                lastRealRecord = record
                historyRecords = historyStore.save(record)
            }
        }
        updateActivityPressureSamples()
    }

    var bodyStatusDescriptor: BodyStatusDescriptor { .make(energyScore: snapshot.energyScore) }
    var isScoreStale: Bool {
        healthErrorMessage != nil || (scoreValidUntil.map { $0 < Date.now } ?? true)
    }
    var dataStatusTitle: String {
        if !hasScore { return "暂无评分" }
        if isScoreStale || healthErrorMessage != nil { return "上次有效评分" }
        return "健康数据"
    }

    func refreshIfNeeded() async {
        if let lastRefreshAt, Date.now.timeIntervalSince(lastRefreshAt) <= 60 { return }
        await refreshHealthData(requestAuthorization: false)
    }

    func refreshHealthData(requestAuthorization: Bool = true, followUpIfInFlight: Bool = true) async {
        if isLoadingHealth {
            refreshPending = refreshPending || followUpIfInFlight || requestAuthorization
            authorizationPending = authorizationPending || requestAuthorization
            await withCheckedContinuation { refreshWaiters.append($0) }
            return
        }
        isLoadingHealth = true
        defer {
            isLoadingHealth = false
            let waiters = refreshWaiters
            refreshWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        var authorize = requestAuthorization
        repeat {
            refreshPending = false
            await performHealthRefresh(requestAuthorization: authorize)
            authorize = authorizationPending
            authorizationPending = false
        } while refreshPending
    }

    var onAutomaticRefreshComplete: (@MainActor () async -> Void)?

    func startAutomaticUpdates(canReadHealthData: @escaping @MainActor () -> Bool = { true }) {
        self.canReadHealthData = canReadHealthData
        healthManager.observeChanges { [weak self] in
            guard canReadHealthData() else { return }
            await self?.refreshHealthData(requestAuthorization: false)
            await self?.onAutomaticRefreshComplete?()
        }
        healthManager.enableBackgroundUpdates()
    }

    private func performHealthRefresh(requestAuthorization: Bool) async {
        do {
            if requestAuthorization { try await healthManager.requestAuthorization() }
            let queryTime = Date.now
            var latest = preservingWatchPressure(in: try await healthManager.fetchLatestSnapshot(now: queryTime))
            lastRefreshSucceeded = true
            health = latest
            do {
                hourlyStress = mergedHourlyStress(try await healthManager.fetchTodayHourlyStress(now: queryTime))
            } catch {
                hourlyStress = mergedHourlyStress([])
            }
            latest = preservingWatchPressure(in: latest)
            health = latest
            historyStore.saveLatestHealth(latest)
            let evaluationTime = Date.now
            lastRefreshAt = evaluationTime
            if latest.isUsable(at: evaluationTime) {
                healthErrorMessage = nil
                recalculateScores(from: latest, now: evaluationTime)
            } else {
                updatePressure(from: latest, now: evaluationTime)
                healthErrorMessage = missingDataMessage(for: latest)
                publishCurrent()
            }
        } catch {
            lastRefreshAt = .now
            lastRefreshSucceeded = false
            markPressureAsPrevious()
            let failure = error as NSError
            UserDefaults.standard.set(failure.domain, forKey: "health.lastRead.errorDomain")
            UserDefaults.standard.set(failure.code, forKey: "health.lastRead.errorCode")
            UserDefaults.standard.set(Date.now, forKey: "health.lastRead.failedAt")
            if failure.domain == HKErrorDomain && failure.code == HKError.Code.errorDatabaseInaccessible.rawValue {
                healthErrorMessage = "健康数据暂不可读，解锁设备后自动更新。"
            } else {
                healthErrorMessage = "本次健康数据读取未完成，保留上次记录，稍后自动重试。"
            }
            publishCurrent()
        }
    }

    private func missingDataMessage(for health: HealthSnapshot) -> String {
        if health.scoringVersion == BodyBatteryScorer.algorithmVersion && health.morningRecovery == nil {
            return "等待完整主睡眠及睡眠内有效 HRV、心率；主睡眠结束 90 分钟后评估。"
        }
        let missing = HealthMetric.allCases.filter { health.missingMetrics.contains($0) }.map(\.title)
        return missing.isEmpty ? "部分测量已过期，请等待新的健康记录。" : "暂未读取到：" + missing.joined(separator: "、")
    }

    private func restoreRealData() {
        guard let record = lastRealRecord else {
            health = .empty
            snapshot = .empty
            hasScore = false
            scoreValidUntil = nil
            return
        }
        health = record.health
        snapshot = record.energy
        if record.stressAlgorithmVersion == StressSnapshot.algorithmVersion, let stressScore = record.stressScore {
            stressReading = StressReading(score: stressScore,
                level: stressAnalyzer.level(for: stressScore), hrvStressScore: 0,
                restingHeartRateStressScore: 0, acuteStressScore: 0)
            pressure = StressSnapshot(score: stressScore, levelTitle: stressAnalyzer.level(for: stressScore).title,
                updatedAt: record.health.pressureMeasurement?.sampledAt ?? record.health.sampleDates[.hrv] ?? record.energy.updatedAt,
                validUntil: .distantPast, basis: "上次估算", hrvMetric: record.health.pressureMeasurement?.metric)
        }
        workoutRecommendation = record.recommendation
        hasScore = true
        scoreValidUntil = record.health.validUntil
    }

    private func updatePressure(from source: HealthSnapshot, now: Date) {
        if let record = watchPressure, source.pressureMeasurement == record.measurement {
            pressure = record.stress
            stressReading = StressReading(score: record.stress.score, level: stressAnalyzer.level(for: record.stress.score),
                hrvStressScore: record.stress.score, restingHeartRateStressScore: 0, acuteStressScore: 0)
            updateActivityPressureSamples()
            return
        }
        guard let result = stressAnalyzer.evaluateAvailable(snapshot: source, now: now) else {
            markPressureAsPrevious()
            return
        }
        stressReading = result.reading
        pressure = result.snapshot
        let observations = EnergyPressureSample.samples(records: [], currentHealth: source, currentPressure: pressure, now: now)
        pressureSamples = pressureHistoryStore.merge(observations, now: now)
        activities.updatePressureSamples(pressureSamples)
    }

    private func markPressureAsPrevious() {
        guard var previous = pressure else { return }
        if let record = watchPressure, previous.updatedAt == record.stress.updatedAt,
           !record.stress.isStale { return }
        previous.validUntil = min(previous.validUntil, Date.now.addingTimeInterval(-1))
        pressure = previous
    }

    func recalculateScores(from source: HealthSnapshot? = nil, now: Date = .now) {
        let source = source ?? health
        updatePressure(from: source, now: now)
        guard source.isUsable(at: now) else { return }
        let scores = scorer.computeScores(input: EnergyInput(snapshot: source))
        let currentPressure = pressure.flatMap { $0.isStale ? nil : $0 }
        let assessment = lastRealRecord.flatMap { $0.health == source ? $0.batteryAssessment : nil } ?? batteryScorer.assessment(previous: lastRealRecord, health: source,
            recoveryScore: scores.recoveryScore, initialScore: scores.energyScore,
            pressure: currentPressure, now: now)
        let batteryLevel = assessment.level
        batteryAssessment = assessment
        let currentScores = EnergyScores(recoveryScore: scores.recoveryScore,
            energyScore: Int(batteryLevel.rounded()), trainingLoadScore: scores.trainingLoadScore,
            trainingLoadAvailable: scores.trainingLoadAvailable)
        if let previous = lastRealRecord, previous.batteryLevel != nil, previous.health != source {
            batteryChange = currentScores.energyScore - previous.energy.energyScore
        } else {
            batteryChange = nil
        }
        let plan = recommendationEngine.plan(for: currentScores, preferences: preferences.settings.training, on: now)
        snapshot = EnergySnapshot(energyScore: currentScores.energyScore, recoveryScore: scores.recoveryScore,
                                  recommendation: plan.summary, updatedAt: source.measuredAt ?? .now)
        workoutRecommendation = plan
        hasScore = true
        scoreValidUntil = source.validUntil
        let record = HealthRecord(health: source, energy: snapshot, stressScore: currentPressure?.score,
                                  stressLevelTitle: currentPressure?.levelTitle, recommendation: plan,
                                  batteryLevel: batteryLevel, batteryAssessment: assessment)
        lastRealRecord = record
        let records = historyStore.save(record, now: now)
        historyRecords = records
        batteryTimeline = timelineStore.save(BatteryTimelinePoint(date: snapshot.updatedAt, level: batteryLevel, assessment: assessment), now: now)
        history = dailyHistoryStore.merge(records.map(\.dailyMetrics), now: now)
        batteryHistory = records.filter { $0.batteryLevel != nil }.map(\.dailyMetrics)
        updateActivityPressureSamples()
        publishCurrent()
    }

    private func publishCurrent() {
        var payload = WatchSyncPayload(snapshot: snapshot, workoutRecommendation: hasScore ? workoutRecommendation : nil,
            metrics: WatchKeyMetricsSnapshot(health: health, stressScore: pressure?.score ?? 0, stressLevelTitle: pressure?.levelTitle ?? "暂无评分"),
            stressScore: pressure?.score, stressLevelTitle: pressure?.levelTitle,
            bodyStatus: hasScore ? bodyStatusDescriptor : nil)
        payload.hasScore = hasScore
        payload.validUntil = scoreValidUntil
        payload.history = history
        payload.hourlyStress = hourlyStress
        payload.statusMessage = healthErrorMessage
        payload.stress = pressure
        payload.activityRecords = activities.records
        payload.userFeatures = UserFeaturesState(preferences: preferences.settings, habitDays: habits.days)
        payload.batteryTimeline = Array(batteryTimeline.filter { Calendar.current.isDateInToday($0.date) }.suffix(32))
        payload.batteryAssessment = batteryAssessment
        payload.pressureSamples = Array(pressureSamples.suffix(32))
        #if os(watchOS)
        payload.collectionSource = .appleWatch
        #else
        payload.collectionSource = .iPhone
        #endif
        if let widget = payload.widgetSnapshot() {
            widgetWriter(widget)
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
        watchSyncPublisher.publish(payload)
    }

}
