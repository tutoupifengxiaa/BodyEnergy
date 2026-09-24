import Foundation

struct RecommendationEngine {
    func plan(for scores: EnergyScores) -> WorkoutRecommendation {
        switch scores.energyScore {
        case 75...100:
            return WorkoutRecommendation(
                title: "力量或间歇主训练",
                summary: "力量训练或间歇有氧，35–50 分钟。",
                durationText: "35 到 50 分钟",
                intensityText: "中高强度",
                purposeText: "力量与心肺训练。",
                cautionText: "热身后心率异常偏高或感觉不适时，降低强度。",
                steps: [
                    "动态热身 8 分钟，活动髋、踝和肩背。",
                    "力量循环或短间歇，保持动作稳定。",
                    "整理活动与拉伸 6–10 分钟，结束后补水。"
                ]
            )
        case 45..<75:
            return WorkoutRecommendation(
                title: "二区有氧恢复课",
                summary: "稳态有氧、轻力量或技术训练，20–30 分钟。",
                durationText: "20 到 30 分钟",
                intensityText: "低到中等强度",
                purposeText: "低到中等强度活动。",
                cautionText: "疲劳明显时缩短训练时间。",
                steps: [
                    "步行或动态热身 5 分钟。",
                    "稳态有氧 15–20 分钟，保持能顺畅说话的强度。",
                    "放缓活动与拉伸 5 分钟。"
                ]
            )
        default:
            return WorkoutRecommendation(
                title: "轻松步行与恢复",
                summary: "轻松步行与拉伸，15–25 分钟。",
                durationText: "15 到 25 分钟",
                intensityText: "轻强度",
                purposeText: "轻活动与恢复。",
                cautionText: "以恢复为主，避免高强度和爆发动作。",
                steps: [
                    "轻柔活动 3–5 分钟，放松肩颈、髋部和小腿。",
                    "轻松步行 12–20 分钟，保持呼吸放松。",
                    "拉伸 5 分钟，补水并提早休息。"
                ]
            )
        }
    }

    func recommendation(for scores: EnergyScores) -> String {
        plan(for: scores).summary
    }
}
