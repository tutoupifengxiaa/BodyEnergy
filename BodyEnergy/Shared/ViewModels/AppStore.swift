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
    @Published var sampleScenario: SampleScenario?

    private let healthManager: HealthManaging
    private let scorer: EnergyScorer
    private let stressAnalyzer: StressAnalyzer
    private let recommendationEngine: RecommendationEngine
    private let watchSyncPublisher: WatchSyncPublishing

    init(
        health: HealthSnapshot,
        snapshot: EnergySnapshot,
        sampleScenario: SampleScenario? = nil,
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
        self.sampleScenario = sampleScenario
        self.workoutRecommendation = recommendationEngine.plan(
            for: scorer.computeScores(input: EnergyInput(snapshot: health))
        )
    }

    var bodyStatusDescriptor: BodyStatusDescriptor {
        BodyStatusDescriptor.make(energyScore: snapshot.energyScore)
    }

    @MainActor
    func refreshHealthData() async {
        guard !isLoadingHealth else { return }
        isLoadingHealth = true
        healthErrorMessage = nil

        do {
            try await healthManager.requestAuthorization()
            let latest = try await healthManager.fetchLatestSnapshot(now: .now)
            sampleScenario = nil
            health = latest
            recalculateScores(from: latest)
        } catch {
            let scenario = sampleScenario ?? .balanced
            sampleScenario = scenario
            health = scenario.snapshot
            healthErrorMessage = "\(presentableHealthMessage(for: error)) 当前展示“\(scenario.title)”场景。"
            recalculateScores(from: scenario.snapshot)
        }

        isLoadingHealth = false
    }

    @MainActor
    func applySampleScenario(_ scenario: SampleScenario) {
        sampleScenario = scenario
        health = scenario.snapshot
        healthErrorMessage = "当前正在展示“\(scenario.title)”示例数据。\(scenario.summary)"
        recalculateScores(from: scenario.snapshot)
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
            metrics: WatchKeyMetricsSnapshot(
                health: source,
                stressScore: stress.score,
                stressLevelTitle: stress.level.title
            ),
            stressScore: stress.score,
            stressLevelTitle: stress.level.title,
            sampleScenarioTitle: sampleScenario?.title,
            sampleScenarioSummary: sampleScenario?.summary,
            bodyStatus: BodyStatusDescriptor.make(energyScore: scores.energyScore)
        )
    }

    static let preview = AppStore(
        health: SampleScenario.balanced.snapshot,
        snapshot: .preview,
        sampleScenario: .balanced
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
