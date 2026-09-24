import Combine
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class AppStore: ObservableObject {
    @Published var health: HealthSnapshot
    @Published var snapshot: EnergySnapshot
    @Published var stressReading: StressReading
    @Published var workoutRecommendation: WorkoutRecommendation
    @Published var isLoadingHealth = false
    @Published var healthErrorMessage: String?
    @Published private(set) var hasScore = false
    @Published private(set) var history: [DailyMetrics] = []
    @Published private(set) var hourlyStress: [HourlyStress] = []
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var scoreValidUntil: Date?
    @Published private(set) var pressure: StressSnapshot?

    var hasPressure: Bool { pressure != nil }
    var isPressureStale: Bool { pressure?.isStale ?? true }
    var hasCurrentRecommendation: Bool { hasScore && !isScoreStale }
    var displayedWorkoutRecommendation: WorkoutRecommendation {
        hasCurrentRecommendation ? workoutRecommendation : .generalActivity
    }

    private let healthManager: HealthManaging
    private let scorer: EnergyScorer
    private let stressAnalyzer: StressAnalyzer
    private let recommendationEngine: RecommendationEngine
    private let watchSyncPublisher: WatchSyncPublishing
    private let historyStore: HealthHistoryStore
    private let widgetWriter: (WidgetMetricsSnapshot) -> Void
    private var lastRealRecord: HealthRecord?
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
        self.widgetWriter = widgetWriter
        self.stressReading = StressReading(score: 0, level: .low, hrvStressScore: 0, restingHeartRateStressScore: 0, acuteStressScore: 0)
        self.workoutRecommendation = .empty
        let records = historyStore.load()
        history = records.map(\.dailyMetrics)
        lastRealRecord = records.last
        restoreRealData()
        if let latest = historyStore.loadLatestHealth() {
            self.health = latest
            updatePressure(from: latest, now: .now)
            if !latest.isUsable(at: .now) { healthErrorMessage = missingDataMessage(for: latest) }
        }
        self.watchSyncPublisher.onRefreshRequested = { [weak self] in
            await self?.refreshHealthData(requestAuthorization: false)
        }
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

    func refreshHealthData(requestAuthorization: Bool = true) async {
        if isLoadingHealth {
            refreshPending = true
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

    func startAutomaticUpdates(canReadHealthData: @escaping @MainActor () -> Bool = { true }) {
        healthManager.observeChanges { [weak self] in
            guard canReadHealthData() else { return }
            await self?.refreshHealthData(requestAuthorization: false)
        }
        healthManager.enableBackgroundUpdates()
    }

    private func performHealthRefresh(requestAuthorization: Bool) async {
        do {
            if requestAuthorization { try await healthManager.requestAuthorization() }
            let now = Date.now
            let latest = try await healthManager.fetchLatestSnapshot(now: now)
            health = latest
            historyStore.saveLatestHealth(latest)
            lastRefreshAt = now
            updatePressure(from: latest, now: now)
            do {
                hourlyStress = try await healthManager.fetchTodayHourlyStress(now: now)
            } catch {
                hourlyStress = []
            }
            if latest.isUsable(at: now) {
                healthErrorMessage = nil
                recalculateScores(from: latest)
            } else {
                healthErrorMessage = missingDataMessage(for: latest)
                publishCurrent()
            }
        } catch {
            lastRefreshAt = .now
            markPressureAsPrevious()
            hourlyStress = []
            healthErrorMessage = "暂时无法读取健康数据，可在健康 App 中检查数据与访问设置。"
            publishCurrent()
        }
    }

    private func missingDataMessage(for health: HealthSnapshot) -> String {
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
        stressReading = stressAnalyzer.evaluate(snapshot: record.health)
        workoutRecommendation = record.recommendation
        hasScore = true
        scoreValidUntil = record.health.validUntil
        pressure = StressSnapshot(score: record.stressScore, levelTitle: record.stressLevelTitle,
            updatedAt: record.health.sampleDates[.hrv] ?? record.energy.updatedAt,
            validUntil: record.health.validUntil ?? .distantPast, basis: "HRV 与心率估算")
    }

    private func updatePressure(from source: HealthSnapshot, now: Date) {
        guard let result = stressAnalyzer.evaluateAvailable(snapshot: source, now: now) else {
            markPressureAsPrevious()
            return
        }
        stressReading = result.reading
        pressure = result.snapshot
    }

    private func markPressureAsPrevious() {
        guard var previous = pressure else { return }
        previous.validUntil = min(previous.validUntil, Date.now.addingTimeInterval(-1))
        pressure = previous
    }

    func recalculateScores(from source: HealthSnapshot? = nil) {
        let source = source ?? health
        updatePressure(from: source, now: .now)
        guard source.isUsable(at: .now) else { return }
        let scores = scorer.computeScores(input: EnergyInput(snapshot: source))
        let stress = stressAnalyzer.evaluate(snapshot: source)
        let plan = recommendationEngine.plan(for: scores)
        snapshot = EnergySnapshot(energyScore: scores.energyScore, recoveryScore: scores.recoveryScore,
                                  recommendation: plan.summary, updatedAt: source.measuredAt ?? .now)
        stressReading = stress
        workoutRecommendation = plan
        hasScore = true
        scoreValidUntil = source.validUntil
        let record = HealthRecord(health: source, energy: snapshot, stressScore: stress.score,
                                  stressLevelTitle: stress.level.title, recommendation: plan)
        lastRealRecord = record
        history = historyStore.save(record).map(\.dailyMetrics)
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
        if let widget = payload.widgetSnapshot() {
            widgetWriter(widget)
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
        watchSyncPublisher.publish(payload)
    }

}
