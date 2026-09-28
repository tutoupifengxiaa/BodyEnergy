import Foundation

struct WorkoutRecommendation: Codable, Equatable, Sendable {
    var title: String
    var summary: String
    var durationText: String
    var intensityText: String
    var purposeText: String
    var cautionText: String
    var steps: [String]
    var activityType: TrainingActivity? = nil
    var targetMinutes: Int? = nil

    static let empty = WorkoutRecommendation(
        title: "暂无建议", summary: "等待健康数据后生成运动建议。",
        durationText: "—", intensityText: "—", purposeText: "", cautionText: "", steps: []
    )

    static let generalActivity = WorkoutRecommendation(
        title: "轻松步行或舒展", summary: "健康数据尚不完整，可按舒适程度选择轻松步行或柔和舒展。",
        durationText: "按舒适程度", intensityText: "轻强度",
        purposeText: "提供不依赖身体电量分数的日常轻活动参考。",
        cautionText: "无需完成固定时长；感觉不适时停止活动并休息。",
        steps: [
            "先慢走或原地踏步几分钟，留意呼吸与身体感受。",
            "如果感觉舒适，可继续轻松步行；也可改做肩、髋和小腿的柔和活动。",
            "结束前逐渐放慢，补水并休息；今天不想活动也可以。"
        ]
    )

    static let preview = WorkoutRecommendation(
        title: "稳态有氧训练",
        summary: "约 36 分钟稳态有氧：热身、主训练、放缓和拉伸。",
        durationText: "36 分钟",
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
