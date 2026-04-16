import Foundation
import Combine

final class AppStore: ObservableObject {
    @Published var health: HealthSnapshot
    @Published var snapshot: EnergySnapshot
    @Published var isLoadingHealth = false
    @Published var healthErrorMessage: String?

    private let healthManager: HealthManaging
    private let scorer: EnergyScorer
    private let recommendationEngine: RecommendationEngine
    private let watchSyncPublisher: WatchSyncPublishing

    init(
        health: HealthSnapshot,
        snapshot: EnergySnapshot,
        healthManager: HealthManaging = HealthManager(),
        scorer: EnergyScorer = EnergyScorer(),
        recommendationEngine: RecommendationEngine = RecommendationEngine(),
        watchSyncPublisher: WatchSyncPublishing = WatchSyncPublisherFactory.makeDefault()
    ) {
        self.health = health
        self.snapshot = snapshot
        self.healthManager = healthManager
        self.scorer = scorer
        self.recommendationEngine = recommendationEngine
        self.watchSyncPublisher = watchSyncPublisher
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
        snapshot = EnergySnapshot(
            energyScore: scores.energyScore,
            recoveryScore: scores.recoveryScore,
            recommendation: recommendationEngine.recommendation(for: scores),
            updatedAt: .now
        )
        watchSyncPublisher.publish(snapshot: snapshot)
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
            return "Using sample data until HealthKit has recent readings."
        case .healthDataUnavailable:
            return "HealthKit is unavailable here. Showing sample data."
        case .missingType:
            return "Some HealthKit data types are unavailable on this device."
        }
    }
}
