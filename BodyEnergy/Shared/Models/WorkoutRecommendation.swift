import Foundation

struct WorkoutRecommendation: Equatable, Sendable {
    var title: String
    var summary: String
    var durationText: String
    var intensityText: String
    var purposeText: String
    var cautionText: String
    var steps: [String]

    static let preview = WorkoutRecommendation(
        title: "二区有氧恢复课",
        summary: "今天适合安排 20 到 30 分钟稳态有氧，结束后加上 8 分钟拉伸放松。",
        durationText: "28 分钟",
        intensityText: "低到中等强度",
        purposeText: "维持心肺刺激，同时不过度消耗恢复储备。",
        cautionText: "如果当前心率持续偏高或主观疲劳明显，改成快走也可以。",
        steps: [
            "先做 5 分钟热身步行或动态活动，让心率逐步抬升。",
            "进入 18 分钟稳态有氧，保持能够完整对话的呼吸节奏。",
            "最后做 5 分钟放缓和 8 分钟下肢拉伸，帮助今天顺利恢复。"
        ]
    )

    static func fallback(summary: String, energyScore: Int) -> WorkoutRecommendation {
        if energyScore >= 75 {
            return WorkoutRecommendation(
                title: "今日训练建议",
                summary: summary,
                durationText: "35 到 50 分钟",
                intensityText: "中高强度",
                purposeText: "当前恢复较好，可以承接更完整的训练安排。",
                cautionText: "如果热身后主观状态不佳，建议及时降低强度。",
                steps: [
                    "先完成热身，让心率和关节活动逐步进入运动状态。",
                    "按建议进行主训练，优先保证动作质量和节奏稳定。",
                    "训练后记得补水和拉伸，帮助后续恢复。"
                ]
            )
        }

        if energyScore >= 45 {
            return WorkoutRecommendation(
                title: "今日训练建议",
                summary: summary,
                durationText: "20 到 30 分钟",
                intensityText: "低到中等强度",
                purposeText: "维持运动刺激，同时避免过量透支。",
                cautionText: "今天更适合稳定节奏，而不是追求冲刺性强度。",
                steps: [
                    "先做短热身，让身体从静息状态进入运动节奏。",
                    "保持均匀呼吸和可持续强度完成训练主体。",
                    "收尾时放缓节奏并简单拉伸。"
                ]
            )
        }

        return WorkoutRecommendation(
            title: "今日恢复建议",
            summary: summary,
            durationText: "15 到 25 分钟",
            intensityText: "轻强度",
            purposeText: "优先恢复，减少额外身体负担。",
            cautionText: "如果疲劳明显，今天不建议追加高强度运动。",
            steps: [
                "先做轻柔活动和简单放松。",
                "安排轻松步行或舒缓活动，不追求速度。",
                "补水并尽量提早休息。"
            ]
        )
    }
}
