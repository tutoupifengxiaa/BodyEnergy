import Foundation

struct RecommendationEngine {
    func plan(for scores: EnergyScores) -> WorkoutRecommendation {
        switch scores.energyScore {
        case 75...100:
            return WorkoutRecommendation(
                title: "力量或间歇主训练",
                summary: "身体状态很好，适合进行高质量间歇训练或力量训练，结束后加上拉伸放松。",
                durationText: "35 到 50 分钟",
                intensityText: "中高强度",
                purposeText: "在恢复状态较好的窗口里承接更完整的训练刺激。",
                cautionText: "如果热身后心率异常偏高，建议把强度降一档，不要硬顶训练量。",
                steps: [
                    "先做 8 分钟动态热身，让心率平稳抬升并活动髋、踝和肩背。",
                    "主训练选择力量循环或短间歇，控制在动作质量稳定、但仍有训练感的区间。",
                    "结束后做 6 到 10 分钟整理活动和拉伸，补水后再进入日常节奏。"
                ]
            )
        case 45..<75:
            return WorkoutRecommendation(
                title: "二区有氧恢复跑",
                summary: "身体状态中等，建议以二区有氧为主，并适当减少训练总量。",
                durationText: "20 到 30 分钟",
                intensityText: "低到中等强度",
                purposeText: "维持心肺刺激，同时不过度消耗恢复储备。",
                cautionText: "如果主观疲劳明显，优先缩短时间，而不是勉强把强度提上去。",
                steps: [
                    "先做 5 分钟热身步行或动态活动，让身体从静息状态进入运动节奏。",
                    "保持 15 到 20 分钟稳定二区有氧，以呼吸均匀、可以对话的强度为准。",
                    "最后做 5 分钟放缓和简单拉伸，帮助今天顺利回到恢复区间。"
                ]
            )
        default:
            return WorkoutRecommendation(
                title: "轻松步行与恢复",
                summary: "身体状态偏低，优先恢复，可安排轻松步行、补水和更早入睡。",
                durationText: "15 到 25 分钟",
                intensityText: "轻强度",
                purposeText: "降低额外负担，把精力优先留给恢复和自主调节。",
                cautionText: "今天不建议追求训练量或爆发性动作，先把恢复放在第一位。",
                steps: [
                    "先做 3 到 5 分钟轻柔活动，放松肩颈、髋部和小腿。",
                    "安排 12 到 20 分钟轻松步行，保持呼吸放松，不以速度为目标。",
                    "结束后补水、做 5 分钟拉伸，并尽量把今晚睡眠时间提前。"
                ]
            )
        }
    }

    func recommendation(for scores: EnergyScores) -> String {
        plan(for: scores).summary
    }
}
