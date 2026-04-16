import Foundation
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif

final class AppStore: ObservableObject {
    @Published var health: HealthSnapshot
    @Published var snapshot: EnergySnapshot
    @Published var stressReading: StressReading
    @Published var workoutRecommendation: WorkoutRecommendation
    @Published var isLoadingHealth = false
    @Published var healthErrorMessage: String?

    private let healthManager: HealthManaging
    private let scorer: EnergyScorer
    private let stressAnalyzer: StressAnalyzer
    private let recommendationEngine: RecommendationEngine
    private let watchSyncPublisher: WatchSyncPublishing

    init(
        health: HealthSnapshot,
        snapshot: EnergySnapshot,
        healthManager: HealthManaging = HealthManager(),
        scorer: EnergyScorer = EnergyScorer(),
        stressAnalyzer: StressAnalyzer = StressAnalyzer(),
        recommendationEngine: RecommendationEngine = RecommendationEngine(),
        watchSyncPublisher: WatchSyncPublishing = WatchSyncPublisherFactory.makeDefault()
    ) {
        let initialStressReading = stressAnalyzer.evaluate(snapshot: health)

        self.health = health
        self.snapshot = snapshot
        self.stressReading = initialStressReading
        self.healthManager = healthManager
        self.scorer = scorer
        self.stressAnalyzer = stressAnalyzer
        self.recommendationEngine = recommendationEngine
        self.watchSyncPublisher = watchSyncPublisher
        self.workoutRecommendation = recommendationEngine.plan(
            for: scorer.computeScores(input: EnergyInput(snapshot: health))
        )
    }

    @MainActor
    func refreshHealthData() async {
        guard !isLoadingHealth else { return }
        isLoadingHealth = true
        healthErrorMessage = nil

        do {
            try await healthManager.requestAuthorization()
            let latest = try await healthManager.fetchLatestSnapshot(now: .now)
            health = latest
            recalculateScores(from: latest)
        } catch {
            healthErrorMessage = presentableHealthMessage(for: error)
            recalculateScores(from: health)
        }

        isLoadingHealth = false
    }

    @MainActor
    func recalculateScores(from health: HealthSnapshot? = nil) {
        let source = health ?? self.health
        let scores = scorer.computeScores(input: EnergyInput(snapshot: source))
        let stress = stressAnalyzer.evaluate(snapshot: source)
        let recommendation = recommendationEngine.plan(for: scores)
        let energySnapshot = EnergySnapshot(
            energyScore: scores.energyScore,
            recoveryScore: scores.recoveryScore,
            recommendation: recommendation.summary,
            updatedAt: .now
        )

        stressReading = stress
        workoutRecommendation = recommendation
        snapshot = energySnapshot

        WidgetMetricsStore.save(
            WidgetMetricsSnapshot(
                energyScore: energySnapshot.energyScore,
                recoveryScore: energySnapshot.recoveryScore,
                stressScore: stress.score,
                stressLevelTitle: stress.level.title,
                updatedAt: energySnapshot.updatedAt
            )
        )
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif

        watchSyncPublisher.publish(
            snapshot: energySnapshot,
            workoutRecommendation: recommendation,
            stressScore: stress.score,
            stressLevelTitle: stress.level.title
        )
    }

    static let preview = AppStore(
        health: .baseline,
        snapshot: .preview
    )
}

private extension AppStore {
    func presentableHealthMessage(for error: Error) -> String {
        guard let healthError = error as? HealthManagerError else {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        switch healthError {
        case .noData:
            return "HealthKit 暂无最近数据，当前先展示示例结果。"
        case .healthDataUnavailable:
            return "当前环境无法使用 HealthKit，正在展示示例数据。"
        case .missingType:
            return "设备缺少部分 HealthKit 数据类型，展示结果可能不完整。"
        }
    }
}
