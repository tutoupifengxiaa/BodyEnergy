import Foundation

struct RecommendationEngine {
    func plan(for scores: EnergyScores, on date: Date = .now) -> WorkoutRecommendation {
        guard scores.trainingLoadAvailable else { return .generalActivity }
        let alternateDay = (Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0).isMultiple(of: 2)

        switch scores.energyScore {
        case 75...100:
            if scores.recoveryScore < 70 || scores.trainingLoadScore >= 70 {
                return steadyTraining
            }
            return alternateDay ? strengthTraining : intervalTraining
        case 45..<75:
            if scores.recoveryScore < 55 || scores.trainingLoadScore >= 70 {
                return gentleTraining
            }
            return alternateDay ? moderateCardio : lightStrength
        default:
            if scores.recoveryScore < 35 || scores.trainingLoadScore >= 70 {
                return activeRest
            }
            return alternateDay ? easyWalk : mobilityTraining
        }
    }

    func recommendation(for scores: EnergyScores, on date: Date = .now) -> String {
        plan(for: scores, on: date).summary
    }

    func plan(for scores: EnergyScores, preferences: TrainingPreferences, on date: Date = .now) -> WorkoutRecommendation {
        guard scores.trainingLoadAvailable else { return .generalActivity }
        var base = plan(for: scores, on: date)
        let recovering = scores.energyScore < 45 || scores.recoveryScore < 55 || scores.trainingLoadScore >= 70
        let restDay = base.title == "主动休息日"
        let originalActivity: TrainingActivity = base.title.contains("力量") ? .strength :
            (base.title.contains("舒展") || base.title.contains("拉伸") || restDay ? .mobility : .walking)
        let selected = TrainingActivity.allCases.filter { preferences.preferredActivities.contains($0) }
        let activity: TrainingActivity
        if recovering {
            activity = selected.contains(.mobility) && !selected.contains(.walking) ? .mobility : .walking
        } else {
            activity = selected.contains(originalActivity) || selected.isEmpty ? originalActivity : selected[0]
        }
        let minutes = min(max(10, preferences.availableMinutes), restDay ? 15 : recovering ? 25 : 45)
        base.activityType = restDay ? .mobility : activity
        base.targetMinutes = minutes
        base.durationText = restDay ? "可选 \(minutes) 分钟" : "约 \(minutes) 分钟"
        if restDay {
            base.summary = "今天可以休息；想活动时可做约 \(minutes) 分钟轻柔走动或舒展。"
            base.steps = ["先休息，确认自己是否愿意活动；今天完全休息也可以。",
                          "若想活动，慢走 2 分钟，再用 \(minutes - 4) 分钟温和活动肩、髋和踝，不憋气。",
                          "最后用 2 分钟放缓，补水并安排休息。"]
            return base
        }
        let warmup = min(5, max(2, minutes / 5))
        let cooldown = min(5, max(2, minutes / 5))
        let main = minutes - warmup - cooldown
        base.title = recovering ? "轻松\(activity.title)与恢复" : "\(activity.title)训练"
        base.summary = "今天可用约 \(minutes) 分钟\(activity.title)，按\(base.intensityText)安排，感觉疲惫时缩短或休息。"
        base.purposeText = recovering ? "以恢复为主，用舒适的\(activity.title)保持日常活动，控制额外消耗。" :
            (activity == .strength ? "用从容的力量练习维持肌力和动作协调，保留恢复余量。" :
             activity == .mobility ? "通过柔和活动关节与舒展维持舒适的活动范围。" : "用稳定的\(activity.title)维持心肺活动，按今天的恢复状态控制总量。")
        base.cautionText = "感觉明显疲惫时降低强度或休息；出现胸闷、头晕或疼痛时停止活动。" +
            (activity == .strength ? "动作质量优先，不追求最大重量。" : activity == .mobility ? "只在舒适范围内移动，不勉强拉伸。" : "以仍能完整交谈为准，不追求冲刺。")
        let movement: String
        switch activity {
        case .walking: movement = "在平地步行 \(main) 分钟，以仍能完整交谈的速度为准，不追求步数或配速。"
        case .running: movement = "在熟悉路线慢跑或走跑交替 \(main) 分钟，保持可交谈的呼吸；吃力时改走。"
        case .cycling: movement = "使用可用的自行车或健身车平稳骑行 \(main) 分钟，控制阻力；没有车时改成步行。"
        case .mobility: movement = "用 \(main) 分钟缓慢活动肩、髋和踝，再做舒适范围内的柔和舒展，不憋气。"
        case .strength:
            switch preferences.equipment {
            case .none: movement = "用 \(main) 分钟选择坐站、臀桥和靠墙俯卧撑，做 1–2 组，每组 8–10 次；动作之间充分休息。"
            case .dumbbells: movement = "用 \(main) 分钟选择轻哑铃深蹲、划船和推举，做 1–2 组，每组 8–10 次；选能从容控制的重量。"
            case .gym: movement = "用 \(main) 分钟选择熟悉的力量器械练习 2–3 个动作，做 1–2 组，每组 8–10 次；不追求最大重量。"
            }
        }
        base.steps = ["先用 \(warmup) 分钟慢走或原地踏步，活动相关关节。", movement,
                      "最后用 \(cooldown) 分钟逐步放慢，轻柔舒展并补水。"]
        return base
    }

    private var strengthTraining: WorkoutRecommendation {
        WorkoutRecommendation(
            title: "全身力量训练",
            summary: "今天可做全身力量：动态热身、基础动作和放缓整理，约 35–45 分钟。",
            durationText: "35 到 45 分钟",
            intensityText: "中等强度",
            purposeText: "身体电量和恢复较充足，可以安排完整的肌力练习；动作质量比增加重量更重要。",
            cautionText: "如果最近已练过同一肌群，可改做轻松有氧；热身后感觉不适时减少组数或停止。",
            steps: [
                "热身 8 分钟：轻快走 3 分钟，再活动髋、踝和肩背。",
                "主训练 22–28 分钟：从坐站或深蹲、臀桥、推和拉动作中选 3–4 个，做 2–3 组，每组 8–12 次，组间休息 60–90 秒。",
                "没有器械可用自重坐站、臀桥和靠墙俯卧撑；有弹力带时可加入划船。选择能稳定完成动作的难度。",
                "最后慢走约 3 分钟，再轻柔拉伸 5 分钟，并补水。"
            ]
        )
    }

    private var intervalTraining: WorkoutRecommendation {
        WorkoutRecommendation(
            title: "可控有氧间歇",
            summary: "今天可尝试快慢交替的有氧训练，约 30–40 分钟，无需冲刺。",
            durationText: "30 到 40 分钟",
            intensityText: "中等偏高强度",
            purposeText: "用短时间的快慢交替练习心肺，同时保留充分的慢速恢复段。",
            cautionText: "若不熟悉间歇，或近期已做高强度训练，可改成均匀步行或骑行；出现胸闷、头晕或疼痛时停止。",
            steps: [
                "先慢走或低速骑行 8 分钟，让呼吸和关节逐渐进入运动状态。",
                "快走、骑行或椭圆机做 6 轮：稍快 1 分钟，放慢 2 分钟；快段以还能说几句话为宜，不追求冲刺。",
                "每轮慢段都等呼吸趋于平稳再开始下一轮；如果难以恢复，减少轮数。",
                "结束后用 6–8 分钟逐步放慢，再补水和轻柔拉伸。"
            ]
        )
    }

    private var steadyTraining: WorkoutRecommendation {
        WorkoutRecommendation(
            title: "低冲击稳态有氧",
            summary: "今天适合控制总量，安排 25–35 分钟步行、骑行或椭圆机。",
            durationText: "25 到 35 分钟",
            intensityText: "低到中等强度",
            purposeText: "身体电量尚可，但恢复或当前活动负担提示宜采用更平稳的训练节奏。",
            cautionText: "以能完整交谈的节奏为准；若热身后仍明显疲劳，可缩短主训练或改为休息。",
            steps: [
                "先慢走或低速骑行 5 分钟，逐步提高活动量。",
                "选择步行、骑行或椭圆机，保持 18–22 分钟均匀节奏，以呼吸稍快但仍能完整交谈为宜。",
                "不追求速度或距离；感觉吃力时放慢，也可以提前结束。",
                "最后用 5–8 分钟放缓并活动小腿、髋部和肩背。"
            ]
        )
    }

    private var moderateCardio: WorkoutRecommendation {
        WorkoutRecommendation(
            title: "稳态有氧训练",
            summary: "今天可安排 25–35 分钟的快走、骑行或慢速游泳，保持稳定节奏。",
            durationText: "25 到 35 分钟",
            intensityText: "中等强度",
            purposeText: "维持规律的心肺活动，同时控制运动总量。",
            cautionText: "以仍能完整交谈为宜；如果呼吸持续急促或主观疲劳明显，就放慢或缩短时间。",
            steps: [
                "用 5–8 分钟慢走或低速骑行热身。",
                "主训练 15–20 分钟：快走、骑行或慢速游泳任选其一，保持呼吸稍快但能完整交谈。",
                "每隔几分钟检查呼吸和动作；节奏不稳时降低速度。",
                "最后用 5–8 分钟逐步放慢，再轻柔拉伸。"
            ]
        )
    }

    private var lightStrength: WorkoutRecommendation {
        WorkoutRecommendation(
            title: "轻力量与动作练习",
            summary: "今天可做 25–35 分钟轻力量训练，以熟悉的动作为主。",
            durationText: "25 到 35 分钟",
            intensityText: "低到中等强度",
            purposeText: "在不过度消耗的前提下维持肌力和动作协调。",
            cautionText: "先选能从容完成的动作；出现疼痛或动作明显变形时停止该动作。",
            steps: [
                "热身约 7 分钟：原地踏步或慢走，再活动肩、髋和踝。",
                "从坐站、臀桥、靠墙俯卧撑和弹力带划船中选 3 个动作，各做 2 组，每组 8–10 次，组间休息 60–90 秒。",
                "动作保持缓慢、稳定；若今天不想练力量，可改为 15–20 分钟轻快步行。",
                "最后用 5–8 分钟慢走或轻柔拉伸收尾。"
            ]
        )
    }

    private var gentleTraining: WorkoutRecommendation {
        WorkoutRecommendation(
            title: "舒缓活动与拉伸",
            summary: "今天先以恢复为主，安排约 20–25 分钟轻活动。",
            durationText: "20 到 25 分钟",
            intensityText: "轻强度",
            purposeText: "恢复分数或当前活动负担提示宜放慢节奏，保持舒适的日常活动即可。",
            cautionText: "不必完成固定时长；如果明显疲劳或感觉不适，直接休息。",
            steps: [
                "先慢走 5 分钟，留意呼吸和身体感受。",
                "在平地轻松步行 10–15 分钟，保持能自然交谈的速度。",
                "如更想待在室内，可把步行换成轻柔的肩颈、髋部和小腿活动。",
                "最后用约 5 分钟逐步放慢，补水并安排休息。"
            ]
        )
    }

    private var easyWalk: WorkoutRecommendation {
        WorkoutRecommendation(
            title: "轻松步行与恢复",
            summary: "今天可选择 15–25 分钟轻松步行，把恢复放在首位。",
            durationText: "15 到 25 分钟",
            intensityText: "轻强度",
            purposeText: "身体电量偏低，使用舒适的轻活动维持日常节奏。",
            cautionText: "无需追求步数或配速；如果步行后更累，可缩短时间或改为休息。",
            steps: [
                "先轻柔活动肩颈、髋部和小腿 3–5 分钟。",
                "在平地轻松步行 10–15 分钟，保持呼吸放松。",
                "如果不方便外出，可在室内走动，或改做坐姿舒展。",
                "最后放慢 5 分钟，补水并留出休息时间。"
            ]
        )
    }

    private var mobilityTraining: WorkoutRecommendation {
        WorkoutRecommendation(
            title: "关节活动与舒展",
            summary: "今天可用 15–20 分钟做温和的关节活动与拉伸。",
            durationText: "15 到 20 分钟",
            intensityText: "轻强度",
            purposeText: "在身体电量偏低时保持柔和活动，不增加明显负担。",
            cautionText: "只在舒适范围内移动，不要勉强拉伸；出现疼痛时停止。",
            steps: [
                "先原地慢走或踏步 3–5 分钟，让身体逐渐活动起来。",
                "用 8–10 分钟依次活动肩背、髋和踝，每个动作缓慢重复数次，不憋气。",
                "也可把中段换成室内轻松步行，选择今天更舒服的方式。",
                "最后轻柔舒展 3–5 分钟，补水并休息。"
            ]
        )
    }

    private var activeRest: WorkoutRecommendation {
        WorkoutRecommendation(
            title: "主动休息日",
            summary: "今天可以休息；想活动时做 10–15 分钟轻柔走动或舒展即可。",
            durationText: "可选 10 到 15 分钟",
            intensityText: "很轻强度",
            purposeText: "身体电量与恢复状态提示应减少额外刺激，优先留出休息时间。",
            cautionText: "无需为了完成计划而运动；如有胸闷、头晕或疼痛，应停止活动。",
            steps: [
                "先休息，确认自己是否愿意活动；不舒服时今天完全休息也可以。",
                "如果想动一动，慢走约 3 分钟，再做 5–8 分钟轻柔的肩、髋和踝部活动。",
                "最后放慢 2–4 分钟，补水，并尽量保证睡眠。"
            ]
        )
    }
}
