import Foundation

enum AppDateTime {
    static func timestamp(_ date: Date) -> String { string(date, format: "yyyy-MM-dd HH:mm:ss") }
    static func day(_ date: Date) -> String { string(date, format: "yyyy-MM-dd") }
    static func time(_ date: Date) -> String { string(date, format: "HH:mm:ss") }

    private static func string(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

enum HealthInsightMetric: String, Identifiable {
    case sleep, hrv, restingHeartRate, heartRate, activeEnergy, pressure, recovery

    var id: String { rawValue }
}

struct PressureDataStatus {
    let title: String
    let detail: String

    init(health: HealthSnapshot, pressure: StressSnapshot?, now: Date = .now) {
        if let pressure {
            if pressure.validUntil < now {
                title = "上次压力估算"
                detail = "保留上次有效结果，等待新的有效采样。"
            } else {
                title = pressure.levelTitle
                detail = "身体压力估算 · \(pressure.basis)；结合个人常态解读。"
            }
            return
        }

        let days = health.pressureMeasurement?.baseline.dayCount ?? health.hrvBaselineDayCount
        if let days, (0..<7).contains(days) {
            title = "个人基线建立中"
            detail = "已有 \(days) / 7 个可比有效日期；需相近时段、相同睡眠状态的历史记录。"
        } else if let measurement = health.pressureMeasurement,
                  StressAnalyzer().isValid(measurement: measurement),
                  measurement.sampledAt.addingTimeInterval(StressAnalyzer.pressureSampleMaxAge) < now {
            title = "等待新的压力采样"
            detail = "上次有效压力采样已过期，新的有效记录到达后更新。"
        } else if health.isUsable(.hrv, at: now) {
            title = "压力估算条件待补充"
            detail = "已读取 SDNN。压力估算还需个人基线与近期有效采样；基线至少需要 7 个可比有效日期。"
        } else if !health.missingMetrics.contains(.hrv), health.heartRateVariabilityMS.isFinite,
                  health.heartRateVariabilityMS > 0, let date = health.sampleDates[.hrv],
                  date.addingTimeInterval(HealthMetric.hrv.maxAge) < now {
            title = "HRV 记录已过期"
            detail = "原始 HRV 仍可查看，压力估算等待新的有效记录。"
        } else if health.pressureMeasurement != nil {
            title = "压力估算条件待补充"
            detail = "采样或个人基线暂不满足估算条件，请等待更新后的有效记录。"
        } else {
            title = "尚无可用 HRV 记录"
            detail = "佩戴手表并在 Apple 健康中确认 HRV 记录；没有记录不代表未授权。"
        }
    }
}

struct HealthMetricExplanation {
    let metric: HealthInsightMetric
    private let health: HealthSnapshot
    private let pressure: StressSnapshot?
    private let recoveryScore: Int?
    private let recoveryUpdatedAt: Date?
    private let recoveryIsStale: Bool?
    private let now: Date
    private var displayedRecovery: Int? {
        health.scoringVersion == BodyBatteryScorer.algorithmVersion ? health.morningRecovery?.score : recoveryScore
    }

    init(metric: HealthInsightMetric, health: HealthSnapshot, pressure: StressSnapshot?,
         recoveryScore: Int?, recoveryUpdatedAt: Date? = nil, recoveryIsStale: Bool? = nil,
         now: Date = .now) {
        self.metric = metric
        self.health = health
        self.pressure = pressure
        self.recoveryScore = recoveryScore
        self.recoveryUpdatedAt = recoveryUpdatedAt
        self.recoveryIsStale = recoveryIsStale
        self.now = now
    }

    var title: String {
        switch metric {
        case .sleep: return "睡眠"
        case .hrv: return "HRV · SDNN"
        case .restingHeartRate: return "静息心率"
        case .heartRate: return "最近心率"
        case .activeEnergy: return "活动消耗"
        case .pressure: return "身体压力估算"
        case .recovery: return "晨间恢复"
        }
    }

    var unit: String {
        switch metric {
        case .sleep: return "小时"
        case .hrv: return "ms"
        case .restingHeartRate, .heartRate: return "bpm"
        case .activeEnergy: return "千卡"
        case .pressure, .recovery: return "/ 100"
        }
    }

    var value: String {
        guard hasValue else { return "—" }
        switch metric {
        case .sleep: return String(format: "%.1f", health.sleepHours)
        case .hrv: return "\(Int(health.heartRateVariabilityMS.rounded()))"
        case .restingHeartRate: return "\(Int(health.restingHeartRateBPM.rounded()))"
        case .heartRate: return "\(Int(health.heartRateBPM.rounded()))"
        case .activeEnergy: return "\(Int(health.activeEnergyKcal.rounded()))"
        case .pressure: return pressure.map { "\($0.score)" } ?? "—"
        case .recovery: return displayedRecovery.map { "\($0)" } ?? "—"
        }
    }

    var sampledAt: Date? {
        guard hasValue else { return nil }
        switch metric {
        case .pressure: return pressure?.updatedAt
        case .recovery: return health.morningRecovery?.sleepEnd ?? recoveryUpdatedAt
        default: return healthMetric.flatMap { health.sampleDates[$0] }
        }
    }

    var isStale: Bool {
        switch metric {
        case .pressure: return pressure.map { $0.validUntil < now } ?? true
        case .recovery:
            if health.scoringVersion == BodyBatteryScorer.algorithmVersion { return health.morningRecovery?.isValid(at: now) != true }
            return recoveryIsStale ?? !health.isUsable(at: now)
        default: return healthMetric.map { !health.isUsable($0, at: now) } ?? true
        }
    }

    var statusTitle: String {
        if metric == .pressure { return PressureDataStatus(health: health, pressure: pressure, now: now).title }
        guard hasValue else { return "暂无数据" }
        if let sampledAt, sampledAt > now.addingTimeInterval(300) { return "采样时间待核对" }
        if isStale { return metric == .recovery ? "上次有效评分" : "上次记录" }
        return "有效记录"
    }

    var comparison: String? {
        switch metric {
        case .sleep:
            guard let history = health.sleepHistory else { return nil }
            let debt = history.debtHours.map { "睡眠债约 \(String(format: "%.1f", $0)) 小时" } ?? "睡眠债记录积累中"
            let regularity = history.regularityScore.map { "作息规律 \($0)/100" } ?? "作息规律记录积累中"
            return "近 \(history.windowDays) 天已记录 \(history.recordedDays) 天 · \(debt) · \(regularity)。截至 \(AppDateTime.timestamp(history.asOf))。"
        case .hrv:
            guard hasValue, let baseline = health.hrvBaselineMS,
                  EnergyConfig.default.hrvValidRange.contains(baseline) else { return nil }
            return baselineComparison(value: health.heartRateVariabilityMS, baseline: baseline, unit: "ms", name: "SDNN")
        case .restingHeartRate:
            guard hasValue, let baseline = health.restingHeartRateBaselineBPM,
                  EnergyConfig.default.restingHeartRateValidRange.contains(baseline) else { return nil }
            return baselineComparison(value: health.restingHeartRateBPM, baseline: baseline, unit: "bpm", name: "静息心率")
        case .pressure:
            guard let measurement = matchingPressureMeasurement else { return nil }
            return baselineComparison(value: measurement.hrvMS, baseline: measurement.baseline.medianMS,
                                      unit: "ms", name: measurement.metric.title)
                + " · \(measurement.baseline.dayCount) 个可比有效日期"
        case .recovery:
            guard let morning = health.morningRecovery else { return nil }
            return "主睡眠 \(String(format: "%.1f", morning.sleepHours)) 小时 · 睡眠内 SDNN \(Int(morning.hrvMS.rounded())) ms · 心率 \(Int(morning.sleepingHeartRateBPM.rounded())) bpm。"
                + (morning.baselineNightCount >= 7 ? "基线来自 \(morning.baselineNightCount) 个有效日期。" : "个人夜间基线建立中，暂用模型参考值。")
                + (morning.sleepHistory.map { "睡眠历史修正 −\(String(format: "%.1f", $0.recoveryPenalty)) 分。" } ?? "")
        default: return nil
        }
    }

    var explanation: String {
        switch metric {
        case .sleep: return "最近一次主睡眠与随后小睡的有效时长，重叠记录合并计算。睡眠债和作息规律按主睡眠结束时的近 7 天记录估算，缺测日不当作零睡眠。"
        case .hrv: return "SDNN 描述心跳间期的波动。这里展示 Apple 健康中的原始 SDNN；压力估算可能使用 RMSSD，两种数值应分别与各自的个人基线比较。"
        case .restingHeartRate: return "Apple 健康记录的静息心率。与自己的近期常态一起观察，比只看单个数字更容易理解变化。"
        case .heartRate: return "最近一次心率采样，并非持续实时心率。活动场景的心率不会直接被当成静息压力；压力估算仅采用与 HRV 配对的静息样本。"
        case .activeEnergy: return "当天累计活动能量，不含静息消耗。它反映活动量，单凭热量不能判断某次运动的强度。"
        case .pressure:
            let status = PressureDataStatus(health: health, pressure: pressure, now: now)
            return "根据 HRV 与个人基线估算身体压力，有配对的静息心率时也会纳入参考。当前依据：\(pressure?.basis ?? "等待有效采样")。它不代表主观心情。" + (pressure == nil ? "\n\n\(status.detail)" : "")
        case .recovery: return "最近一次完整主睡眠结束后，用该睡眠的时长、SDNN 中位数和睡眠内心率估算，并参考近 7 天已记录的睡眠债与作息波动。白天的 HRV 和小睡不会改写本次晨间恢复；晚到的睡眠历史可修正结果。主睡眠结束 90 分钟后评估，个人夜间基线至少需要 7 个有效日期。"
        }
    }

    var influence: String {
        switch metric {
        case .sleep: return "睡眠参与恢复评分和电量补充。累积睡眠不足与作息波动可适度降低晨间恢复；补觉按有限比例抵扣已有睡眠债。缺测日不额外扣分，稳定的白天睡眠同样视为规律。"
        case .hrv: return "晨间恢复使用主睡眠内的 SDNN 汇总，白天最近读数不会改写它。压力采用当前可用的 HRV 算法及其独立基线，有效压力区间再参与电量估算。"
        case .restingHeartRate: return "有可比数据时修正日间压力估算。晨间恢复另外使用主睡眠内的心率汇总及其夜间基线。"
        case .heartRate: return "训练负荷按运动记录内的心率强度与持续时间累计；不使用一次最近心率替代整场训练。没有同期静息样本时，不用最近心率修正压力。"
        case .activeEnergy: return "从主睡眠结束开始，按活动能量的实际时间区间重算电量消耗，跨午夜也不遗漏。训练负荷另由运动心率和时长计算。"
        case .pressure: return "近期有效的压力估算参与电量消耗；满足低压静坐等条件时可估算少量补充。缺测时不补造压力数据。"
        case .recovery: return "晨间恢复建立本睡眠周期的电量起点；白天电量再根据活动、小睡、清醒时间与有效压力区间变化。运动建议同时考虑晨间恢复、电量和训练负荷。"
        }
    }

    var sourceTitle: String? {
        guard hasValue else { return nil }
        switch metric {
        case .hrv: return "Apple 健康 · SDNN"
        case .pressure:
            switch pressure?.hrvMetric {
            case .rmssd: return "Apple 健康心跳间期 · RMSSD 估算"
            case .sdnn: return "Apple 健康 · SDNN 估算"
            case nil: return "健康数据压力估算"
            }
        case .recovery: return "健康数据综合估算"
        default: return "Apple 健康"
        }
    }

    private var healthMetric: HealthMetric? {
        switch metric {
        case .sleep: return .sleep
        case .hrv: return .hrv
        case .restingHeartRate: return .restingHeartRate
        case .heartRate: return .heartRate
        case .activeEnergy: return .activeEnergy
        case .pressure, .recovery: return nil
        }
    }

    private var hasValue: Bool {
        if metric == .pressure { return pressure.map { (0...100).contains($0.score) } ?? false }
        if metric == .recovery { return displayedRecovery.map { (0...100).contains($0) } ?? false }
        guard let healthMetric, !health.missingMetrics.contains(healthMetric) else { return false }
        switch healthMetric {
        case .hrv: return EnergyConfig.default.hrvValidRange.contains(health.heartRateVariabilityMS)
        case .restingHeartRate: return EnergyConfig.default.restingHeartRateValidRange.contains(health.restingHeartRateBPM)
        case .heartRate: return EnergyConfig.default.heartRateValidRange.contains(health.heartRateBPM)
        case .sleep: return health.sleepHours > 0 && EnergyConfig.default.sleepValidRange.contains(health.sleepHours)
        case .activeEnergy: return EnergyConfig.default.activeEnergyValidRange.contains(health.activeEnergyKcal)
        }
    }

    private var matchingPressureMeasurement: PressureMeasurement? {
        guard let pressure, let measurement = health.pressureMeasurement,
              measurement.metric == (pressure.hrvMetric ?? .sdnn), measurement.sampledAt == pressure.updatedAt,
              StressAnalyzer().isValid(measurement: measurement) else { return nil }
        return measurement
    }

    private func baselineComparison(value: Double, baseline: Double, unit: String, name: String) -> String {
        let change = Int(((value / baseline - 1) * 100).rounded())
        let direction = change == 0 ? "接近个人基线" : "\(change > 0 ? "高于" : "低于")个人基线 \(abs(change))%"
        return "\(name) 基线 \(Int(baseline.rounded())) \(unit) · \(direction)"
    }
}
