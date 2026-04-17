import Foundation

struct HealthSnapshot: Equatable, Sendable {
    var heartRateBPM: Double
    var heartRateVariabilityMS: Double
    var restingHeartRateBPM: Double
    var sleepHours: Double
    var activeEnergyKcal: Double

    static let baseline = HealthSnapshot(
        heartRateBPM: 72,
        heartRateVariabilityMS: 55,
        restingHeartRateBPM: 58,
        sleepHours: 7.5,
        activeEnergyKcal: 520
    )
}

enum BodyBatteryState: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low

    init(energyScore: Int) {
        switch energyScore {
        case 70...100:
            self = .high
        case 40..<70:
            self = .medium
        default:
            self = .low
        }
    }

    var title: String {
        switch self {
        case .high:
            return "状态良好"
        case .medium:
            return "状态平稳"
        case .low:
            return "需要恢复"
        }
    }
}

struct BodyStatusDescriptor: Codable, Equatable, Sendable {
    var state: BodyBatteryState
    var title: String
    var detail: String
    var action: String

    static func make(energyScore: Int) -> BodyStatusDescriptor {
        let state = BodyBatteryState(energyScore: energyScore)
        switch state {
        case .high:
            return BodyStatusDescriptor(
                state: state,
                title: "身体储备充足",
                detail: "恢复和自主神经状态都比较在线，今天更适合安排完整训练，或者把重点项目做得更扎实。",
                action: "建议优先完成计划内主训练，训练后注意补水和放松。"
            )
        case .medium:
            return BodyStatusDescriptor(
                state: state,
                title: "身体状态平稳",
                detail: "当前恢复基础比较稳定，但训练储备还没到峰值，更适合中等强度、可持续的节奏。",
                action: "建议以稳态有氧、轻力量或技术训练为主。"
            )
        case .low:
            return BodyStatusDescriptor(
                state: state,
                title: "身体更需要恢复",
                detail: "当前身体电量偏低，通常意味着睡眠、压力或近期活动负荷还没有完全回到舒适区间。",
                action: "建议减少刺激，优先步行、拉伸、补水和提早休息。"
            )
        }
    }
}

enum SampleScenario: String, CaseIterable, Identifiable, Sendable {
    case recoveryReady
    case balanced
    case recoveryNeeded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recoveryReady:
            return "恢复良好"
        case .balanced:
            return "状态平稳"
        case .recoveryNeeded:
            return "恢复不足"
        }
    }

    var summary: String {
        switch self {
        case .recoveryReady:
            return "睡眠和 HRV 表现都比较好，适合查看高身体电量时的页面表现。"
        case .balanced:
            return "恢复和活动负荷比较均衡，适合查看中等身体电量下的典型状态。"
        case .recoveryNeeded:
            return "睡眠不足、HRV 偏低且活动负荷偏高，适合查看低身体电量场景。"
        }
    }

    var snapshot: HealthSnapshot {
        switch self {
        case .recoveryReady:
            return HealthSnapshot(
                heartRateBPM: 64,
                heartRateVariabilityMS: 78,
                restingHeartRateBPM: 52,
                sleepHours: 8.4,
                activeEnergyKcal: 420
            )
        case .balanced:
            return .baseline
        case .recoveryNeeded:
            return HealthSnapshot(
                heartRateBPM: 92,
                heartRateVariabilityMS: 28,
                restingHeartRateBPM: 72,
                sleepHours: 5.3,
                activeEnergyKcal: 980
            )
        }
    }
}
