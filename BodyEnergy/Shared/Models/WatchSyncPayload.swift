import Foundation

struct WatchSyncPayload: Codable, Equatable, Sendable {
    var energyScore: Int
    var recoveryScore: Int
    var recommendation: String
    var updatedAt: Date

    init(snapshot: EnergySnapshot) {
        self.energyScore = snapshot.energyScore
        self.recoveryScore = snapshot.recoveryScore
        self.recommendation = snapshot.recommendation
        self.updatedAt = snapshot.updatedAt
    }

    var asSnapshot: EnergySnapshot {
        EnergySnapshot(
            energyScore: energyScore,
            recoveryScore: recoveryScore,
            recommendation: recommendation,
            updatedAt: updatedAt
        )
    }

    var applicationContext: [String: Any] {
        [
            "energyScore": energyScore,
            "recoveryScore": recoveryScore,
            "recommendation": recommendation,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]
    }

    init?(applicationContext: [String: Any]) {
        guard
            let energyScore = applicationContext["energyScore"] as? Int,
            let recoveryScore = applicationContext["recoveryScore"] as? Int,
            let recommendation = applicationContext["recommendation"] as? String,
            let timestamp = applicationContext["updatedAt"] as? TimeInterval
        else {
            return nil
        }

        self.energyScore = energyScore
        self.recoveryScore = recoveryScore
        self.recommendation = recommendation
        self.updatedAt = Date(timeIntervalSince1970: timestamp)
    }
}
