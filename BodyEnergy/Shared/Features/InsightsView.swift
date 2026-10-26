import Charts
import Foundation
import SwiftUI

struct InsightsView: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject private var activities: ActivityStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize = insightsScoreSize
    @State private var periodDays = 7
    @State private var selectedMetric: InsightMetric = .energy
    @State private var selectedObservationDate: Date?
    @State private var selectedTrendDate: Date?

    init(appStore: AppStore) {
        self.appStore = appStore
        self.activities = appStore.activities
    }

    private var pressureMetric: HRVMetric {
        appStore.pressure?.hrvMetric ?? appStore.health.pressureMeasurement?.metric ?? .sdnn
    }

    private var accent: Color {
        let theme = appStore.preferences.settings.theme
        return theme == .forest && colorScheme == .light
            ? Color(red: 0.10, green: 0.46, blue: 0.38) : theme.tint
    }

    private var trendColor: Color { accent }

    private var pressureSamples: [EnergyPressureSample] {
        let now = Date.now
        let current = EnergyPressureSample.samples(records: appStore.historyRecords,
            currentHealth: appStore.health, currentPressure: appStore.pressure, now: now)
        var byDate: [Date: EnergyPressureSample] = [:]
        for sample in appStore.pressureSamples + current {
            guard sample.algorithmVersion == StressSnapshot.algorithmVersion, (0...100).contains(sample.score),
                  sample.date.timeIntervalSince1970.isFinite, sample.date <= now else { continue }
            byDate[sample.date] = sample
        }
        return byDate.values.sorted { $0.date < $1.date }
    }

    private var trend: EnergyTrend {
        EnergyTrend(periodDays: periodDays, records: appStore.historyRecords, dailyMetrics: appStore.history,
            pressureSamples: pressureSamples, pressureMetric: pressureMetric)
    }

    private var weeklyReport: EnergyWeeklyReport {
        EnergyWeeklyReport(records: appStore.historyRecords, dailyMetrics: appStore.history,
            activities: activities.records, batteryTimeline: appStore.batteryTimeline,
            pressureSamples: pressureSamples, pressureMetric: pressureMetric)
    }

    private var todayPoints: [BatteryTimelinePoint] {
        let now = Date.now
        let start = Calendar.current.startOfDay(for: now)
        return appStore.batteryTimeline.filter {
            $0.date >= start && $0.date <= now && $0.level.isFinite && (0...100).contains($0.level)
        }.sorted { $0.date < $1.date }
    }

    var body: some View {
        #if os(watchOS)
        insightsContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .bottom)
        #else
        NavigationStack {
            insightsContent
            .navigationTitle("趋势与周报")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        #endif
    }

    private var insightsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                #if os(watchOS)
                Text("趋势与周报")
                    .font(.headline)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                #endif
                todaySection
                assessmentSection
                trendSection
                weeklySection
                FitnessAgeView(health: appStore.health)
                feelingSection
                explanationSection
                dataTimeSection
            }
            .padding(insightsPadding)
        }
    }

    private var todaySection: some View {
        let points = todayPoints
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? .now
        let selected = selectedObservation(in: points)
        let highlighted = selected ?? points.last
        return VStack(alignment: .leading, spacing: 12) {
            Label("今日电量观测", systemImage: "battery.75percent")
                .font(.headline)
            if points.isEmpty {
                Text("今天尚无有效电量观测，新的有效健康记录到达后更新。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                if let highlighted {
                    chartSummary(
                        title: selected == nil ? "最近观测" : "选中观测",
                        value: "\(Int(highlighted.level.rounded()))",
                        detail: highlighted.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)),
                        color: accent
                    )
                }
                Chart(points) { point in
                    PointMark(x: .value("观测时间", point.date), y: .value("电量", point.level))
                        .foregroundStyle(accent.opacity(selected == nil || selected?.id == point.id ? 0.9 : 0.35))
                        .symbolSize(selected?.id == point.id ? 65 : 28)
                        .accessibilityLabel(point.date.formatted(date: .omitted, time: .complete))
                        .accessibilityValue("电量 \(Int(point.level.rounded())) 分")
                    if selected?.id == point.id {
                        RuleMark(x: .value("选中时间", point.date))
                            .foregroundStyle(accent.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    }
                }
                .chartXScale(domain: start...end)
                .chartYScale(domain: 0...100, range: .plotDimension(padding: 5))
                .chartXSelection(value: $selectedObservationDate)
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18].compactMap {
                        Calendar.current.date(bySettingHour: $0, minute: 0, second: 0, of: start)
                    } + [end]) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date == end ? "24" : String(format: "%02d", Calendar.current.component(.hour, from: date)))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                            .foregroundStyle(Color.secondary.opacity(0.2))
                        AxisValueLabel {
                            if let score = value.as(Int.self) {
                                Text("\(score)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: insightsChartHeight)
                Text("\(points.count) 次真实观测 · 空白时段没有记录")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .insightsCard()
    }

    private var assessmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appStore.isScoreStale ? "上次电量变化明细" : "本睡眠周期电量明细")
                .font(.headline)
            if let assessment = appStore.batteryAssessment, assessment.isValid {
                if let reason = assessment.resetReason {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                } else {
                    if let anchor = assessment.anchorDate, let initial = assessment.previousLevel {
                        Text("晨间起点 \(Int(initial.rounded())) 分 · \(AppDateTime.timestamp(anchor))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    componentRow("睡眠补能", value: assessment.sleepCharge)
                    componentRow("低压静坐补能", value: assessment.restCharge)
                    componentRow("活动消耗", value: -assessment.activityDrain)
                    componentRow("清醒时间消耗", value: -assessment.awakeDrain)
                    componentRow("压力消耗", value: -assessment.stressDrain)
                    if abs(assessment.limitAdjustment) >= 0.05 {
                        componentRow("电量上下限调整", value: assessment.limitAdjustment)
                    }
                    if let previous = assessment.previousLevel {
                        Divider()
                        componentRow("最终变化", value: assessment.level - previous)
                    }
                }
                Text(assessment.anchorDate == nil ? "单位为电量分；这是旧算法留下的历史明细。" : "单位为电量分；从晨间起点按实际区间重算，重复同步不重复记账。缺测压力不外推为整段压力。")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("尚无可解释的变化明细，等待下一次有效电量观测。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let load = appStore.health.trainingLoad {
                Divider()
                Text(load.score.map { "今日心血管训练负荷 \($0) / 100" } ?? "今日训练心率覆盖不足，暂不评分")
                    .font(.subheadline)
                Text(load.workoutSeconds == 0 ? "今日暂无已记录的运动。" : "已记录运动 \(Int((load.workoutSeconds / 60).rounded())) 分钟 · 心率覆盖 \(Int((load.coverage * 100).rounded()))%。仅累计有效心率区间，不含肌肉负荷。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .insightsCard()
    }

    private var trendSection: some View {
        let trend = self.trend
        let validDays = trend.validDayCount(for: selectedMetric)
        let selectedDay = selectedTrendDate.flatMap { date in
            trend.days.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
        }
        return VStack(alignment: .leading, spacing: 12) {
            Text("近 \(periodDays) 天趋势").font(.headline)
            HStack(spacing: 6) {
                ForEach([7, 30], id: \.self) { days in
                    Button {
                        periodDays = days
                        selectedTrendDate = nil
                    } label: {
                        Text("\(days) 天")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(periodDays == days ? accent : Color.secondary)
                            .background(periodDays == days ? accent.opacity(0.12) : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(periodDays == days ? "已选中" : "")
                }
            }
            .padding(3)
            .background(Color.secondary.opacity(0.06), in: Capsule())
            HStack(spacing: 6) {
                ForEach(InsightMetric.allCases) { metric in
                    Button {
                        selectedMetric = metric
                        selectedTrendDate = nil
                    } label: {
                        Text(metric.title)
                            .font(.caption.weight(selectedMetric == metric ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(selectedMetric == metric ? trendColor : Color.secondary)
                            .background(selectedMetric == metric ? trendColor.opacity(0.1) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(selectedMetric == metric ? "已选中" : "")
                }
            }
            if validDays > 0 {
                if let selectedDay {
                    chartSummary(
                        title: "\(selectedMetric.title) · 当日末次",
                        value: selectedDay.score(for: selectedMetric).map(String.init) ?? "—",
                        detail: selectedDay.date.formatted(.dateTime.month().day())
                            + (selectedDay.score(for: selectedMetric) == nil ? " · 无记录" : ""),
                        color: trendColor
                    )
                } else if let average = trend.average(for: selectedMetric) {
                    chartSummary(title: "\(selectedMetric.title) · 末次记录均值",
                                 value: String(format: "%.1f", average),
                                 detail: "有效 \(validDays) / \(periodDays) 天", color: trendColor)
                }
                Chart(trend.days) { day in
                    if let score = day.score(for: selectedMetric) {
                        BarMark(x: .value("日期", day.date, unit: .day), y: .value("分数", score), width: .ratio(0.62))
                            .foregroundStyle(
                                LinearGradient(colors: [trendColor, trendColor.opacity(0.5)],
                                               startPoint: .top, endPoint: .bottom)
                            )
                            .cornerRadius(4)
                            .opacity(selectedDay == nil || selectedDay?.id == day.id ? 1 : 0.35)
                            .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
                            .accessibilityValue("\(selectedMetric.title) \(score) 分")
                        if score == 0 {
                            PointMark(x: .value("日期", day.date, unit: .day), y: .value("分数", score))
                                .foregroundStyle(trendColor)
                                .symbolSize(26)
                        }
                    }
                    if selectedDay?.id == day.id {
                        RuleMark(x: .value("选中日期", day.date, unit: .day))
                            .foregroundStyle(trendColor.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    }
                }
                .chartXScale(domain: trend.startDate...trend.endDate)
                .chartYScale(domain: 0...100, range: .plotDimension(padding: 5))
                .chartXSelection(value: $selectedTrendDate)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: trendAxisStride)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text("\(Calendar.current.component(.day, from: date))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                            .foregroundStyle(Color.secondary.opacity(0.2))
                        AxisValueLabel {
                            if let score = value.as(Int.self) {
                                Text("\(score)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: insightsChartHeight)
            } else {
                Text("有效 0 / \(periodDays) 天 · 所选指标尚无有效记录。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("每天最后一条有效值，缺少记录的日期留空。")
                .font(.caption2).foregroundStyle(.secondary)
            if selectedMetric == .pressure {
                Text("按实际压力采样日期归档，仅汇总 \(pressureMetric.title) 估算。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .insightsCard()
    }

    private func selectedObservation(in points: [BatteryTimelinePoint]) -> BatteryTimelinePoint? {
        guard let selectedObservationDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedObservationDate)) < abs($1.date.timeIntervalSince(selectedObservationDate))
        }
    }

    private var trendAxisStride: Int {
        if periodDays == 30 { return 7 }
        #if os(watchOS)
        return 2
        #else
        return 1
        #endif
    }

    private func chartSummary(title: String, value: String, detail: String, color: Color) -> some View {
        let score = Text(value)
            .font(.system(size: scoreSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
        let unit = Text("分").font(.caption).foregroundStyle(.secondary)
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    score
                    unit
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 2) {
                    score.lineLimit(1).minimumScaleFactor(0.65)
                    unit
                }
            }
            Text(detail).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var weeklySection: some View {
        let report = weeklyReport
        return VStack(alignment: .leading, spacing: 12) {
            Text("最近 7 天报告").font(.headline)
            ForEach(InsightMetric.allCases) { metric in
                VStack(alignment: .leading, spacing: 4) {
                    if let average = report.current.average(for: metric) {
                        Text("\(metric.title)均值 \(String(format: "%.1f", average)) 分 · 有效 \(report.current.validDayCount(for: metric)) / 7 天")
                            .font(.caption.weight(.medium))
                    } else {
                        Text("\(metric.title)：暂无有效记录 · 有效 0 / 7 天")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let change = report.difference(for: metric) {
                        Text("较此前 7 天 \(signedValue(change)) 分；此前有效 \(report.previous.validDayCount(for: metric)) 天")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            Text("完成训练 \(report.workoutCount) 次 · 呼吸 \(report.breathingCount) 次")
                .font(.caption)
            Text("完成活动累计 \(report.completedActivitySeconds / 60) 分 \(report.completedActivitySeconds % 60) 秒")
                .font(.caption)
            Text("活动记录覆盖 \(report.activityDayCount) / 7 天，感受 \(report.feelingCount) 条，电量观测 \(report.batteryObservationCount) 次。")
                .font(.caption2).foregroundStyle(.secondary)
            Text("均值按各日末次有效值计算；前后两段各至少 3 个有效日期才展示变化。压力仅汇总 \(pressureMetric.title)。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .insightsCard()
    }

    private var feelingSection: some View {
        let records = Array(activities.records.filter { $0.feeling != nil && $0.completedAt <= .now }
            .sorted { $0.completedAt > $1.completedAt }.prefix(3))
        let samples = pressureSamples
        return VStack(alignment: .leading, spacing: 12) {
            Text("感受与压力一起回看").font(.headline)
            if records.isEmpty {
                Text("记录感受后，可查看结束前最近一次有效压力采样。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(records) { record in
                VStack(alignment: .leading, spacing: 5) {
                    if let feeling = record.feeling {
                        Label(feeling.title, systemImage: feeling.symbol)
                            .font(.caption.weight(.semibold))
                    }
                    Text(record.title).font(.caption)
                    Text(AppDateTime.timestamp(record.completedAt))
                        .font(.caption2).foregroundStyle(.secondary)
                    if let sample = EnergyPressureSample.nearest(to: record.completedAt, in: samples) {
                        Text("此前压力 \(sample.score) 分 · \(sample.metric.title)")
                            .font(.caption)
                    } else {
                        Text("前 2 小时内没有可匹配的有效压力采样")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Text("感受与采样并排回看，缺少压力记录时保留为空。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .insightsCard()
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("这些数值表示什么").font(.headline)
            Text("电量：0–100 的估算储备，随着睡眠、活动、清醒时长与有效压力观测变化。")
            Text("恢复：主睡眠结束后的独立评分，使用睡眠内 SDNN 和心率；白天新采样不会改写晨间状态。")
            Text("压力：相对个人常态的身体压力估算。SDNN 与 RMSSD 分别使用自己的基线，也与主观感受有所不同。")
            Text("图表显示实际留下的记录，未记录时段与日期留空。有效天数反映统计的数据覆盖度。")
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .insightsCard()
    }

    private var dataTimeSection: some View {
        let sampledAt = appStore.health.measuredAt ?? (appStore.hasScore ? appStore.snapshot.updatedAt : todayPoints.last?.date)
        return VStack(alignment: .leading, spacing: 10) {
            Text("采集时间").font(.headline)
            if let sampledAt {
                Text(AppDateTime.timestamp(sampledAt))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("暂无健康采样记录。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("各项指标与心肺参考可能来自不同健康记录。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .insightsCard()
    }

    private func componentRow(_ title: String, value: Double) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 6)
            Text(signedValue(value)).monospacedDigit()
        }
        .font(.caption)
    }

    private func signedValue(_ value: Double) -> String {
        let rounded = abs(value) < 0.05 ? 0 : value
        return String(format: rounded > 0 ? "+%.1f" : "%.1f", rounded)
    }
}

private var insightsPadding: CGFloat {
    #if os(watchOS)
    8
    #else
    20
    #endif
}

private var insightsChartHeight: CGFloat {
    #if os(watchOS)
    116
    #else
    210
    #endif
}

private var insightsScoreSize: CGFloat {
    #if os(watchOS)
    28
    #else
    36
    #endif
}

private extension View {
    func insightsCard() -> some View {
        #if os(watchOS)
        let background = Color.white.opacity(0.075)
        #else
        let background = Color(.secondarySystemGroupedBackground)
        #endif
        return self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(insightsPadding)
            .background(background, in: RoundedRectangle(cornerRadius: 20))
    }
}
