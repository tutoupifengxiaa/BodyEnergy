import Foundation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isShowingRecommendationDetail = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedHistoryDate: Date?
    @State private var selectedBatteryDate: Date?
    @State private var selectedStressHour: Int?
    @State private var selectedMetric: HealthInsightMetric?
    @State private var isShowingTrainingSession = false
    @State private var isShowingBreathing = false
    @State private var isShowingCheckIn = false
    @State private var isShowingPreferences = false
    @State private var isShowingInsights = false
    @State private var isShowingHistory = false
    @State private var isShowingSettings = false

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.setLocalizedDateFormatFromTemplate("M月d日 EEEE")
        return formatter
    }()

    private var energyScore: Int {
        bounded(store.snapshot.energyScore, to: 0 ... 100)
    }

    private var recoveryScore: Int {
        bounded(store.snapshot.recoveryScore, to: 0 ... 100)
    }

    private var pressureDataStatus: PressureDataStatus {
        PressureDataStatus(health: store.health, pressure: store.pressure)
    }

    private var energyProgress: CGFloat {
        store.hasScore ? CGFloat(energyScore) / 100 : 0
    }

    private var bodyStatus: BodyStatusDescriptor {
        store.bodyStatusDescriptor
    }

    private var accent: Color {
        let theme = store.preferences.settings.theme
        return theme == .forest && colorScheme == .light
            ? Color(red: 0.10, green: 0.46, blue: 0.38) : theme.tint
    }

    private var homeContent: some View {
        VStack(spacing: 0) {
            topHeader

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        heroCard
                            .id("energy")
                        ForEach(store.preferences.settings.homeCards.filter {
                            !store.preferences.settings.hiddenCards.contains($0)
                        }, id: \.self) { card in
                            homeCard(card)
                        }
                        Button {
                            isShowingHistory = true
                        } label: {
                            Label("活动与感受历史", systemImage: "clock.arrow.circlepath")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(16)
                                .background(cardBackground)
                        }
                        .buttonStyle(.plain)
                        dataTimeSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .refreshable { await store.refreshHealthData() }
                .onOpenURL { url in
                    guard url.scheme == "bodyenergy", let target = url.host, ["energy", "stress"].contains(target) else { return }
                    if target == "stress", store.preferences.settings.hiddenCards.contains(.hourlyStress) {
                        selectedMetric = .pressure
                    } else {
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                    }
                }
            }
        }
    }

    var body: some View {
        homeContent
        .background {
            Color(.systemGroupedBackground)
                .overlay(store.preferences.settings.theme.background)
                .ignoresSafeArea()
        }
        .tint(accent)
        .sheet(item: $selectedMetric) { metric in
            NavigationStack {
                if metric == .sleep {
                    SleepDetailView(health: store.health)
                } else {
                    HealthMetricDetailView(explanation: metricExplanation(for: metric),
                                           activities: store.activities, isPressure: metric == .pressure,
                                           refreshedAt: store.lastRefreshAt)
                }
            }
            .tint(accent)
        }
        .sheet(isPresented: $isShowingTrainingSession) {
            ActivitySessionView(store: store.activities, recommendation: store.displayedWorkoutRecommendation)
                .tint(accent)
        }
        .sheet(isPresented: $isShowingBreathing) {
            ActivitySessionView(store: store.activities).tint(accent)
        }
        .sheet(isPresented: $isShowingCheckIn) {
            FeelingCheckInView(store: store.activities).tint(accent)
        }
        .sheet(isPresented: $isShowingPreferences) {
            TrainingPreferencesView(store: store.preferences).tint(accent)
        }
        .sheet(isPresented: $isShowingInsights) {
            InsightsView(appStore: store).tint(accent)
        }
        .sheet(isPresented: $isShowingHistory) {
            ActivityHistoryView(store: store.activities).tint(accent)
        }
        .sheet(isPresented: $isShowingSettings) {
            AppSettingsView(store: store.preferences).tint(accent)
        }
        .fullScreenCover(isPresented: $isShowingRecommendationDetail) {
            NavigationStack {
                RecommendationDetailView(recommendation: store.displayedWorkoutRecommendation,
                                         activities: store.activities, preferences: store.preferences)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("关闭") { isShowingRecommendationDetail = false }
                        }
                    }
            }
            .tint(accent)
        }
    }

    @ViewBuilder
    private func homeCard(_ card: HomeCard) -> some View {
        switch card {
        case .recommendation: recommendationCard
        case .actions: ActivityHubView(store: store.activities)
        case .habits: RecoveryHabitsView(store: store.habits)
        case .dataState: systemStateCard
        case .hourlyStress: hourlyStressCard
        case .metrics: metricsSection
        case .battery: batteryInsightsCard
        case .stressTrend: stressInsightsCard
        }
    }

    private var dataTimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("采集时间", systemImage: "clock").font(.headline)
            if let date = store.health.measuredAt {
                Text(AppDateTime.timestamp(date))
            } else {
                Text("暂无健康采样记录")
            }
            Text("来自最近健康采样，各项指标可能来自不同记录。")
                .font(.caption2)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(cardBackground)
    }

    private var topHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.dayFormatter.string(from: .now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("身体电量")
                    .font(.title2.bold())
            }
            Spacer()
            Button {
                Task { await store.refreshHealthData() }
            } label: {
                Group {
                    if store.isLoadingHealth {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.weight(.semibold))
                    }
                }
                .frame(width: 44, height: 44)
                .background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            .disabled(store.isLoadingHealth)
            .accessibilityLabel("刷新健康数据")
            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            .accessibilityLabel("设置首页、主题和提醒")
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private var heroCard: some View {
        VStack(spacing: 22) {
            HStack {
                Label("今日电量", systemImage: "bolt.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(store.hasScore ? bodyStatus.state.title : "暂无评分")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.12), in: Capsule())
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 24) {
                        scoreRing
                        heroDetails
                    }
                } else {
                    HStack(spacing: 18) {
                        scoreRing
                        heroDetails
                    }
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                Circle().fill(store.preferences.settings.theme.tint).frame(width: 5, height: 5)
                Text(store.isLoadingHealth ? "读取中" : store.dataStatusTitle)
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.72))
            Button {
                isShowingInsights = true
            } label: {
                HStack {
                    Label("电量时间线 · 趋势与周报", systemImage: "chart.xyaxis.line")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .foregroundStyle(.white)
        .background(
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.24, blue: 0.22), Color(red: 0.06, green: 0.15, blue: 0.14)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }

    private var scoreRing: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.10), lineWidth: 11)
            Circle()
                .trim(from: 0, to: energyProgress)
                .stroke(store.preferences.settings.theme.tint.gradient, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: energyProgress)
            VStack(spacing: 2) {
                Text(store.hasScore ? "\(energyScore)" : "—")
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("电量 / 100")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(width: 148, height: 148)
        .padding(6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.hasScore ? "身体电量，\(energyScore) 分，\(bodyStatus.state.title)" : "身体电量暂无评分")
    }

    private var heroDetails: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button {
                selectedMetric = .recovery
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text("晨间恢复")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    Text(store.recoveryScoreForDisplay.map(String.init) ?? "—")
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("查看恢复分数说明")
            Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.hasPressure && store.isPressureStale ? "上次压力变化" : "最近压力变化")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                Text(store.pressure?.levelTitle ?? pressureDataStatus.title)
                    .font(.headline)
                    .foregroundStyle(store.preferences.settings.theme.tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var systemStateCard: some View {
        if !store.hasPressure || store.isPressureStale || store.healthErrorMessage != nil {
            let status = pressureDataStatus
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("数据状态", systemImage: "info.circle")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if store.isLoadingHealth { ProgressView() }
                }
                Text(status.title)
                    .font(.subheadline.weight(.medium))
                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let message = store.healthErrorMessage {
                    Divider()
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(cardBackground)
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("健康指标")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                spacing: 12
            ) {
                metricTile(.sleep, icon: "moon.zzz.fill", tint: .indigo)
                metricTile(.hrv, icon: "waveform.path.ecg", tint: accent)
                metricTile(.restingHeartRate, icon: "heart.fill", tint: .pink)
                metricTile(.heartRate, icon: "heart", tint: .pink)
                metricTile(.activeEnergy, icon: "flame.fill", tint: .orange)
                metricTile(.pressure, icon: "waveform.path", tint: accent)
            }
        }
    }

    private var batteryInsightsCard: some View {
        let days = HistoryDay.recentWeek(store.batteryHistory)
        let selected = days.first { $0.date == selectedBatteryDate } ?? days.last { $0.metrics != nil } ?? days[6]
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("电量变化", systemImage: "bolt.heart")
                    .font(.headline)
                Spacer()
                if let change = store.batteryChange, !store.isScoreStale {
                    Text(change > 0 ? "+\(change)" : "\(change)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(change > 0 ? accent : .secondary)
                }
                Button("详情") { isShowingInsights = true }
                    .font(.caption.weight(.medium))
            }
            chartSummary(score: selected.metrics?.energyScore,
                         detail: AppDateTime.day(selected.date), tint: accent)
            HomeScoreBarChart(
                values: days.enumerated().map { index, day in
                    HomeScoreBarChart.Value(id: index, score: day.metrics?.energyScore,
                        label: "\(Calendar.current.component(.day, from: day.date))", tint: accent,
                        accessibilityLabel: AppDateTime.day(day.date) +
                            (day.metrics.map { "，电量 \($0.energyScore) 分" } ?? "，暂无记录"))
                },
                selectedID: days.firstIndex { $0.date == selected.date }
            ) { selectedBatteryDate = days[$0].date }
            Text("近 7 天 · 每日最后一次有效记录")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let comparison = metricExplanation(for: .hrv).comparison {
                Text(comparison)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("暂无个人 SDNN 基线")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let comparison = metricExplanation(for: .restingHeartRate).comparison {
                Text(comparison)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    private func metricTile(_ metric: HealthInsightMetric, icon: String, tint: Color) -> some View {
        let explanation = metricExplanation(for: metric)
        return Button {
            selectedMetric = metric
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: icon).foregroundStyle(tint)
                    Text(explanation.title).foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .font(.caption.weight(.medium))
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(explanation.value)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text(explanation.unit).font(.caption).foregroundStyle(.secondary)
                }
                Text(explanation.statusTitle)
                    .font(.caption2)
                    .foregroundStyle(explanation.isStale ? Color.orange : Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 96, alignment: .topLeading)
            .padding(18)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("查看指标说明、个人基线和采样信息")
    }

    private func metricExplanation(for metric: HealthInsightMetric) -> HealthMetricExplanation {
        HealthMetricExplanation(metric: metric, health: store.health, pressure: store.pressure,
                                recoveryScore: store.hasScore ? recoveryScore : nil,
                                recoveryUpdatedAt: store.hasScore ? store.snapshot.updatedAt : nil,
                                recoveryIsStale: store.isScoreStale)
    }

    private var hourlyStressCard: some View {
        let today = store.hourlyStress.filter { Calendar.current.isDateInToday($0.hour) }
        let scores = Dictionary(today.map { (Calendar.current.component(.hour, from: $0.hour), $0.score) }, uniquingKeysWith: { _, latest in latest })
        let selected = selectedStressHour ?? today.last.map { Calendar.current.component(.hour, from: $0.hour) }
        return VStack(alignment: .leading, spacing: 18) {
            Label("今日逐小时压力", systemImage: "chart.bar.xaxis")
                .font(.headline)
            if let selected, let score = scores[selected] {
                chartSummary(score: score,
                             detail: String(format: "%02d:00–%02d:00", selected, selected + 1),
                             tint: pressureChartTint(score), status: StressAnalyzer().level(for: score).title)
            } else if let selected {
                chartSummary(score: nil,
                             detail: String(format: "%02d:00–%02d:00 · 无采样", selected, selected + 1),
                             tint: accent)
            } else {
                if !store.hasPressure || store.isPressureStale {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pressureDataStatus.title)
                            .font(.subheadline)
                        Text(pressureDataStatus.detail)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Text("今天暂无逐小时压力记录")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HomeScoreBarChart(
                values: (0..<24).map { hour in
                    HomeScoreBarChart.Value(id: hour, score: scores[hour], label: "",
                        tint: accent,
                        accessibilityLabel: "\(hour) 点到 \(hour + 1) 点，" +
                            (scores[hour].map { "压力 \($0) 分" } ?? "无采样"))
                }, selectedID: selected, isHourly: true
            ) { selectedStressHour = $0 }
            Text("\(scores.count) 个小时有采样 · 空白时段无记录")
                .font(.caption2)
                .foregroundStyle(.secondary)
            pressureActions
        }
        .padding(20)
        .background(cardBackground)
        .id("stress")
    }

    private var stressInsightsCard: some View {
        let days = HistoryDay.recentWeek(store.pressureHistory)
        let selected = days.first { $0.date == selectedHistoryDate } ?? days.last { $0.metrics?.stressScore != nil } ?? days[6]
        let values = days.compactMap { $0.metrics?.stressScore }
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                sectionHeader("近 7 天压力")
                Spacer()
                Button("趋势") { isShowingInsights = true }
                    .font(.caption.weight(.medium))
            }
            chartSummary(score: selected.metrics?.stressScore, detail: AppDateTime.day(selected.date),
                         tint: selected.metrics?.stressScore.map(pressureChartTint) ?? accent,
                         status: selected.metrics?.stressScore.map { StressAnalyzer().level(for: $0).title })
            HomeScoreBarChart(
                values: days.enumerated().map { index, day in
                    HomeScoreBarChart.Value(id: index, score: day.metrics?.stressScore,
                        label: "\(Calendar.current.component(.day, from: day.date))",
                        tint: accent,
                        accessibilityLabel: AppDateTime.day(day.date) +
                            (day.metrics?.stressScore.map { "，压力 \($0) 分" } ?? "，暂无记录"))
                }, selectedID: days.firstIndex { $0.date == selected.date }
            ) { selectedHistoryDate = days[$0].date }
            Text("每日最后记录 · 缺少记录的日期留空")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if values.isEmpty {
                Text("首次有效读取后开始记录，缺失日期留空。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Divider()
                HStack {
                    detailChip(title: "均值", value: "\(values.reduce(0, +) / values.count)")
                    detailChip(title: "最高", value: "\(values.max() ?? 0)")
                    detailChip(title: "最低", value: "\(values.min() ?? 0)")
                }
            }
            if let measurement = store.health.pressureMeasurement, let trend = measurement.trend {
                Divider()
                HStack {
                    detailChip(title: "近 7 天 \(measurement.metric.title)", value: "\(Int(trend.recentMedianMS.rounded())) ms")
                    detailChip(title: "此前 53 天 \(measurement.metric.title)", value: "\(Int(trend.referenceMedianMS.rounded())) ms")
                }
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionHeader("今日建议")
                Spacer()
                Button("偏好") { isShowingPreferences = true }
                    .font(.caption.weight(.medium))
            }
            if !store.hasCurrentRecommendation {
                Text("通用建议 · 健康数据待补充")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Label(store.displayedWorkoutRecommendation.title, systemImage: "figure.run")
                .font(.subheadline.weight(.medium))
            Text(store.displayedWorkoutRecommendation.summary.components(separatedBy: "。").first ?? store.displayedWorkoutRecommendation.summary)
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                detailChip(title: "时长", value: store.displayedWorkoutRecommendation.durationText)
                detailChip(title: "强度", value: store.displayedWorkoutRecommendation.intensityText)
            }
            HStack(spacing: 12) {
                Button {
                    if store.activities.active == nil {
                        store.activities.startWorkout(store.displayedWorkoutRecommendation)
                    }
                    isShowingTrainingSession = true
                } label: {
                    Label(store.activities.active == nil ? "开始活动" : "继续计时", systemImage: "timer")
                }
                .buttonStyle(.borderedProminent)
                Button("查看步骤") { isShowingRecommendationDetail = true }
                    .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var pressureActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Button { isShowingBreathing = true } label: {
                    Label("呼吸 \(store.preferences.settings.breathingMinutes) 分钟", systemImage: "wind")
                }
                Button { isShowingCheckIn = true } label: {
                    Label("记录感受", systemImage: "face.smiling")
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Button { isShowingBreathing = true } label: {
                    Label("呼吸 \(store.preferences.settings.breathingMinutes) 分钟", systemImage: "wind")
                }
                Button { isShowingCheckIn = true } label: {
                    Label("记录感受", systemImage: "face.smiling")
                }
            }
        }
        .font(.caption.weight(.medium))
        .buttonStyle(.bordered)
    }

    private func detailChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chartSummary(score: Int?, detail: String, tint: Color, status: String? = nil) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return VStack(alignment: .leading, spacing: 6) {
            layout {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(score.map(String.init) ?? "—")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                    Text(score == nil ? "暂无记录" : "/ 100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let status {
                    Text(status)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(tint.opacity(0.10), in: Capsule())
                }
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func pressureChartTint(_ score: Int) -> Color {
        switch StressAnalyzer().level(for: score) {
        case .low, .moderate: return accent
        case .elevated: return .orange
        case .high: return .red
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.headline)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
    }

}

private struct HomeScoreBarChart: View {
    struct Value: Identifiable {
        let id: Int
        let score: Int?
        let label: String
        let tint: Color
        let accessibilityLabel: String
    }

    let values: [Value]
    let selectedID: Int?
    var isHourly = false
    let onSelect: (Int) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var plotHeight: CGFloat { dynamicTypeSize.isAccessibilitySize ? 160 : 144 }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing, spacing: 0) {
                Text("100")
                Spacer(minLength: 0)
                Text("50")
                Spacer(minLength: 0)
                Text("0")
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(height: plotHeight)
            .accessibilityHidden(true)

            VStack(spacing: 9) {
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        Path { path in
                            for fraction in [0.0, 0.5, 1.0] {
                                let y = geometry.size.height * fraction
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                            }
                        }
                        .stroke(Color.secondary.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .accessibilityHidden(true)

                        HStack(alignment: .bottom, spacing: 0) {
                            ForEach(values) { value in
                                bar(value, width: geometry.size.width / CGFloat(max(1, values.count)))
                            }
                        }
                    }
                }
                .frame(height: plotHeight)
                axis
            }
        }
    }

    private func bar(_ value: Value, width: CGFloat) -> some View {
        let isSelected = value.id == selectedID
        return Button { onSelect(value.id) } label: {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: isHourly ? 5 : 9, style: .continuous)
                    .fill(value.tint.opacity(isSelected ? 0.08 : 0))
                    .padding(.horizontal, isHourly ? 1 : 3)
                if let score = value.score {
                    RoundedRectangle(cornerRadius: isHourly ? 3 : 6, style: .continuous)
                        .fill(LinearGradient(
                            colors: [value.tint.opacity(isSelected ? 1 : 0.75),
                                     value.tint.opacity(isSelected ? 0.56 : 0.28)],
                            startPoint: .top, endPoint: .bottom))
                        .frame(width: min(isHourly ? 9 : 26, width * 0.58),
                               height: max(3, plotHeight * CGFloat(bounded(score, to: 0...100)) / 100))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: plotHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("选择并查看该时段数值")
    }

    @ViewBuilder
    private var axis: some View {
        if isHourly {
            HStack(spacing: 0) {
                Text("00")
                Spacer(minLength: 0)
                Text("06")
                Spacer(minLength: 0)
                Text("12")
                Spacer(minLength: 0)
                Text("18")
                Spacer(minLength: 0)
                Text("24")
            }
            .font(.caption2.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        } else {
            HStack(spacing: 0) {
                ForEach(values) { value in
                    Text(value.label)
                        .font(.caption2.weight(value.id == selectedID ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(value.id == selectedID ? value.tint : Color.secondary)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(value.tint.opacity(value.id == selectedID ? 0.09 : 0), in: Capsule())
                }
            }
            .accessibilityHidden(true)
        }
    }
}

private func bounded(_ value: Int, to range: ClosedRange<Int>) -> Int {
    Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppStore(watchSyncPublisher: NoopWatchSyncPublisher()))
    }
}
