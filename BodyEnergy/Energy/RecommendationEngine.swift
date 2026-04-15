import Foundation

struct RecommendationEngine {
    func recommendation(for scores: EnergyScores) -> String {
        switch scores.energyScore {
        case 75...100:
            return "Great readiness. Use quality intervals or strength work, then finish with mobility."
        case 45..<75:
            return "Moderate readiness. Keep today at zone-2 intensity and reduce volume slightly."
        default:
            return "Low readiness. Prioritize recovery: easy walk, hydration, and earlier sleep."
        }
    }
}
