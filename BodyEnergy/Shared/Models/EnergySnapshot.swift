import Foundation

struct EnergySnapshot: Codable, Equatable, Sendable {
    var energyScore: Int
    var recoveryScore: Int
    var recommendation: String
    var updatedAt: Date

    static let empty = EnergySnapshot(energyScore: 0, recoveryScore: 0, recommendation: "", updatedAt: .distantPast)

    static let preview = EnergySnapshot(
        energyScore: 78,
        recoveryScore: 82,
        recommendation: "今天适合安排 20 到 30 分钟二区有氧，结束后加上 8 分钟拉伸放松。",
        updatedAt: .now
    )
}
