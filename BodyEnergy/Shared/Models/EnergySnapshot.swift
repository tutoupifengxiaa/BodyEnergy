import Foundation

struct EnergySnapshot: Equatable, Sendable {
    var energyScore: Int
    var recoveryScore: Int
    var recommendation: String
    var updatedAt: Date

    static let preview = EnergySnapshot(
        energyScore: 78,
        recoveryScore: 82,
        recommendation: "20-30 min zone-2 cardio with mobility cooldown.",
        updatedAt: .now
    )
}
