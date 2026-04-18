import Foundation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isShowingRecommendationDetail = false
    @State private var stressRange: StressStatsRange = .day
    @State private var selectedDailyStressIndex = 6
    @State private var selectedWeeklyStressIndex = 5

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

    private var stressReading: StressReading {
        store.stressReading
    }

    private var sampleScenario: SampleScenario? {
        store.sampleScenario
    }

    private var energyProgress: CGFloat {
        CGFloat(energyScore) / 100
    }

    private var bodyStatus: BodyStatusDescriptor {
        store.bodyStatusDescriptor
    }

    private var trendPoints: [Int] {
        [-9, -6, -4, -2, 0, -1, 0].map { bounded(energyScore + $0, to: 0 ... 100) }
    }

    private var weekdayLabels: [String] {
        ["一", "二", "三", "四", "五", "六", "日"]
    }

    var body: some View {
        ZStack {
            pageBackground.ignoresSafeArea()

            GeometryReader { proxy in
                let topInset = proxy.safeAreaInsets.top
                let bottomInset = proxy.safeAreaInsets.bottom

                VStack(spacing: 0) {
                    topHeader(topInset: topInset)

                    ScrollView(.vertical) {
                        VStack(spacing: 16) {
                            heroCard
                            systemStateCard
                            scoreBreakdownCard
                            stressInsightsCard
                            metricsSection
                            focusCard
                            recommendationCard
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .padding(.bottom, max(bottomInset, 28))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .scrollIndicators(.hidden)
                    .refreshable {
                        await store.refreshHealthData()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .fullScreenCover(isPresented: $isShowingRecommendationDetail) {
            NavigationStack {
                RecommendationDetailView(recommendation: store.workoutRecommendation)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("关闭") {
                                isShowingRecommendationDetail = false
                            }
                        }
                    }
            }
        }
    }

    private func refreshData() {
        Task {
            await store.refreshHealthData()
        }
    }

    private var pageBackground: some View {
        LinearGradient(
            colors: [
                Color(.systemGroupedBackground),
                Color(.secondarySystemGroupedBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func topHeader(topInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer()

                    Button(action: refreshData) {
                        if store.isLoadingHealth {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.title3.weight(.semibold))
                        }
                    }
                    .accessibilityLabel("刷新健康数据")
                }

                Text("身体电量")
                    .font(.system(size: 28, weight: .bold))
            }
            .padding(.horizontal, 16)
            .padding(.top, max(topInset, 8))
            .padding(.bottom, 14)

            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGroupedBackground))
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("今日状态")
                        .font(.title2.weight(.bold))

                    Text(daySummaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    if let sampleScenario {
                        badge(title: sampleScenario.title, systemImage: "sparkles", tint: .purple)
                    } else {
                        badge(title: syncState.title, systemImage: syncState.icon, tint: syncState.color)
                    }

                    badge(title: bodyStatus.state.title, systemImage: "bolt.heart.fill", tint: bodyStatusColor)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) {
                    scoreRing(size: 178)
                    heroDetails
                }

                VStack(alignment: .leading, spacing: 18) {
                    scoreRing(size: 196)
                    heroDetails
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            bodyStatusColor.opacity(0.18),
                            Color(.systemBackground),
                            Color(.secondarySystemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 14, y: 8)
        )
    }

    private var heroDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(bodyStatus.title)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(bodyStatusColor)

                Text(bodyStatus.detail)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Text(bodyStatus.action)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(bodyStatusColor.opacity(0.10))
            )

            Text("恢复分数 \(recoveryScore) 分，\(recoverySummary)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            heroStatRow(title: "睡眠", value: String(format: "%.1f 小时", store.health.sleepHours), icon: "bed.double.fill")
            heroStatRow(title: "活动", value: "\(Int(store.health.activeEnergyKcal)) 千卡", icon: "flame.fill")
            heroStatRow(title: "HRV", value: "\(Int(store.health.heartRateVariabilityMS)) ms", icon: "waveform.path.ecg")
            heroStatRow(title: "压力", value: stressSummaryShort, icon: "brain.head.profile")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heroStatRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundColor(bodyStatusColor)
                .frame(width: 28, height: 28)
                .background(bodyStatusColor.opacity(0.12), in: Circle())

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func scoreRing(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 16, lineCap: .round))

            Circle()
                .trim(from: 0, to: energyProgress)
                .stroke(
                    AngularGradient(
                        colors: [.green, .yellow, .orange, .red],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: energyProgress)

            VStack(spacing: 6) {
                Text("\(energyScore)")
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))

                Text("电量分数")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("\(store.snapshot.updatedAt, style: .time) 更新")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private func badge(title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
    }

    @ViewBuilder
    private var systemStateCard: some View {
        if let message = store.healthErrorMessage {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前显示示例数据")
                            .font(.subheadline.weight(.semibold))

                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if sampleScenario != nil {
                    sampleScenarioPicker
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
            )
        } else if store.isLoadingHealth {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                Text("正在同步健康数据...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
        }
    }

    private var sampleScenarioPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("示例场景")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(SampleScenario.allCases) { scenario in
                    Button {
                        store.applySampleScenario(scenario)
                    } label: {
                        Text(scenario.title)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(sampleScenario == scenario ? .white : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(sampleScenario == scenario ? Color.accentColor : Color.white.opacity(0.7))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var scoreBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "分数拆解", subtitle: "把身体电量分成恢复基础与当日负荷两个层面来看。")

            scoreBar(
                title: "身体电量",
                value: energyScore,
                tint: bodyStatusColor,
                detail: energyDetail
            )

            scoreBar(
                title: "恢复分数",
                value: recoveryScore,
                tint: .blue,
                detail: recoveryDetail
            )

            HStack(spacing: 8) {
                detailChip(title: "睡眠", value: sleepInsight, tint: .indigo)
                detailChip(title: "HRV", value: hrvInsight, tint: .teal)
                detailChip(title: "活动", value: activityInsight, tint: .green)
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private var stressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "压力状态", subtitle: "以 HRV 为主，结合静息心率和当前心率估计当前压力。")

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(stressTitle)
                        .font(.headline)
                        .foregroundColor(stressColor)

                    Text(stressDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(stressReading.score)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(stressColor)

                    Text("压力分")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: Double(stressReading.score), total: 100)
                .tint(stressColor)

            HStack(spacing: 8) {
                detailChip(title: "HRV 压力", value: "\(stressReading.hrvStressScore) 分", tint: .teal)
                detailChip(title: "静息心率", value: "\(stressReading.restingHeartRateStressScore) 分", tint: .pink)
                detailChip(title: "即时负荷", value: "\(stressReading.acuteStressScore) 分", tint: .orange)
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private func scoreBar(title: String, value: Int, tint: Color, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("\(value) 分")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(tint)
            }

            ProgressView(value: Double(value), total: 100)
                .tint(tint)

            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var stressInsightsCard: some View {
        let points = visibleStressPoints
        let selectedPoint = selectedStressPoint

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                sectionHeader(
                    title: "压力趋势",
                    subtitle: stressRange == .day
                        ? "按天查看最近 7 天的压力估算。"
                        : "按周查看最近 6 周的周均压力。"
                )

                Spacer(minLength: 8)

                Picker("压力统计维度", selection: $stressRange) {
                    ForEach(StressStatsRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 148)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        Button {
                            selectStressPoint(at: index)
                        } label: {
                            StressSelectionPill(
                                title: point.badgeTitle,
                                subtitle: point.badgeSubtitle,
                                score: point.score,
                                isSelected: index == selectedStressIndex,
                                tint: stressColor(for: point.score)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 20) {
                    stressGauge(point: selectedPoint, size: 186)
                    stressSummary(point: selectedPoint)
                }

                VStack(alignment: .leading, spacing: 18) {
                    stressGauge(point: selectedPoint, size: 210)
                        .frame(maxWidth: .infinity)
                    stressSummary(point: selectedPoint)
                }
            }

            HStack(spacing: 10) {
                StressSummaryTile(
                    title: stressRange == .day ? "7天均值" : "6周均值",
                    value: "\(averageStressScore(in: points))",
                    tint: .blue
                )
                StressSummaryTile(
                    title: "最高",
                    value: "\(points.map(\.score).max() ?? selectedPoint.score)",
                    tint: .orange
                )
                StressSummaryTile(
                    title: "最低",
                    value: "\(points.map(\.score).min() ?? selectedPoint.score)",
                    tint: .green
                )
            }

            HStack(spacing: 8) {
                detailChip(title: "HRV 压力", value: "\(selectedPoint.hrvScore) 分", tint: .teal)
                detailChip(title: "静息心率", value: "\(selectedPoint.restingScore) 分", tint: .pink)
                detailChip(title: "即时负荷", value: "\(selectedPoint.acuteScore) 分", tint: .orange)
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "近 7 天趋势", subtitle: "基于当前状态推演的恢复走势参考。")

            TrendSparkline(values: trendPoints, tint: bodyStatusColor)
                .frame(height: 110)

            HStack {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "关键指标", subtitle: "用最常看的 6 个指标快速判断今天的身体负荷。")

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                metricTile(title: "恢复值", value: "\(recoveryScore)", unit: "分", tint: .blue, icon: "heart.text.square", note: recoveryInsight)
                metricTile(title: "HRV", value: "\(Int(store.health.heartRateVariabilityMS))", unit: "ms", tint: .teal, icon: "waveform.path.ecg", note: hrvInsight)
                metricTile(title: "静息心率", value: "\(Int(store.health.restingHeartRateBPM))", unit: "bpm", tint: .pink, icon: "heart.fill", note: restingHeartRateInsight)
                metricTile(title: "睡眠", value: String(format: "%.1f", store.health.sleepHours), unit: "小时", tint: .indigo, icon: "bed.double.fill", note: sleepInsight)
                metricTile(title: "当前心率", value: "\(Int(store.health.heartRateBPM))", unit: "bpm", tint: .red, icon: "bolt.heart.fill", note: heartRateInsight)
                metricTile(title: "活动消耗", value: "\(Int(store.health.activeEnergyKcal))", unit: "千卡", tint: .green, icon: "flame.fill", note: activityInsight)
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "今日关注", subtitle: "把训练、恢复和节奏压缩成两个最重要的判断。")

            focusRow(
                title: "恢复节奏",
                detail: recoveryFocus,
                icon: "bed.double.fill",
                tint: .blue
            )

            focusRow(
                title: "活动安排",
                detail: activityFocus,
                icon: "figure.walk.motion",
                tint: bodyStatusColor
            )
        }
        .padding(18)
        .background(cardBackground)
    }

    private var recommendationCard: some View {
        Button {
            isShowingRecommendationDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(title: "训练建议", subtitle: "结合当前电量与恢复情况生成，可点击查看详细动作安排。")

                Text(store.workoutRecommendation.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(store.workoutRecommendation.summary)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    detailChip(title: "时长", value: store.workoutRecommendation.durationText, tint: .blue)
                    detailChip(title: "强度", value: store.workoutRecommendation.intensityText, tint: .orange)
                }

                Divider()

                HStack(spacing: 10) {
                    Image(systemName: "figure.run")
                        .foregroundColor(.secondary)

                    Text("点击查看完整动作安排、节奏说明和注意事项。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
    }

    private func metricTile(title: String, value: String, unit: String, tint: Color, icon: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2.weight(.bold))

                Text(unit)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

    private func detailChip(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(tint)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.1))
        )
    }

    private func focusRow(title: String, detail: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(.secondarySystemBackground))
    }

    private var daySummaryText: String {
        Self.dayFormatter.string(from: store.snapshot.updatedAt)
    }

    private var bodyStatusColor: Color {
        switch bodyStatus.state {
        case .high:
            return .green
        case .medium:
            return .orange
        case .low:
            return .red
        }
    }

    private var recoverySummary: String {
        if recoveryScore >= 75 {
            return "恢复基础充足"
        }
        if recoveryScore >= 50 {
            return "恢复还算稳定"
        }
        return "恢复储备偏紧"
    }

    private var energyDetail: String {
        switch bodyStatus.state {
        case .high:
            return "电量充足，今天可以承接更明确的训练目标。"
        case .medium:
            return "电量中等，保持节奏比追求高强度更重要。"
        case .low:
            return "电量偏低，先把恢复和补能放在前面。"
        }
    }

    private var recoveryDetail: String {
        if recoveryScore >= 75 {
            return "睡眠、HRV 和静息心率整体表现较好，恢复面更扎实。"
        }
        if recoveryScore >= 50 {
            return "恢复基础尚可，建议控制训练总量，避免连续透支。"
        }
        return "恢复端偏弱，今天更适合轻运动、补水和提早休息。"
    }

    private var recoveryInsight: String {
        if recoveryScore >= 75 {
            return "恢复储备较足"
        }
        if recoveryScore >= 50 {
            return "恢复处于中段"
        }
        return "恢复优先"
    }

    private var hrvInsight: String {
        if store.health.heartRateVariabilityMS >= 65 {
            return "波动良好"
        }
        if store.health.heartRateVariabilityMS >= 40 {
            return "处于常见区间"
        }
        return "偏低，留意压力"
    }

    private var restingHeartRateInsight: String {
        if store.health.restingHeartRateBPM <= 58 {
            return "静息负担较轻"
        }
        if store.health.restingHeartRateBPM <= 66 {
            return "整体平稳"
        }
        return "偏高，先看恢复"
    }

    private var sleepInsight: String {
        if store.health.sleepHours >= 8 {
            return "睡眠很充足"
        }
        if store.health.sleepHours >= 6.5 {
            return "睡眠基本达标"
        }
        return "睡眠偏少"
    }

    private var heartRateInsight: String {
        if store.health.heartRateBPM <= 85 {
            return "当前较平稳"
        }
        if store.health.heartRateBPM <= 110 {
            return "略有活动负荷"
        }
        return "当前负荷偏高"
    }

    private var activityInsight: String {
        if store.health.activeEnergyKcal >= 900 {
            return "活动量较高"
        }
        if store.health.activeEnergyKcal >= 450 {
            return "活动量适中"
        }
        return "今天还比较轻"
    }

    private var recoveryFocus: String {
        if recoveryScore >= 75 {
            return "恢复面已经给到不错支撑，今天更需要注意训练后的拉伸和补水。"
        }
        if recoveryScore >= 50 {
            return "建议把总量压一档，让睡眠和 HRV 在今晚继续回升。"
        }
        return "优先保证补水、轻松步行和更早休息，先把恢复储备拉回来。"
    }

    private var activityFocus: String {
        switch bodyStatus.state {
        case .high:
            return "可安排更完整的有氧或力量训练，但仍建议保留收操和放松时间。"
        case .medium:
            return "更适合稳态有氧、轻力量或技术训练，重点是节奏稳定。"
        case .low:
            return "今天先不要追求训练量，轻松步行、拉伸和呼吸练习会更合适。"
        }
    }

    private var stressTitle: String {
        switch stressReading.level {
        case .low:
            return "压力较低"
        case .moderate:
            return "压力适中"
        case .elevated:
            return "压力偏高"
        case .high:
            return "压力较高"
        }
    }

    private var stressSummaryShort: String {
        switch stressReading.level {
        case .low:
            return "较低"
        case .moderate:
            return "适中"
        case .elevated:
            return "偏高"
        case .high:
            return "较高"
        }
    }

    private var stressDetail: String {
        switch stressReading.level {
        case .low:
            return "HRV 表现不错，静息心率和当前心率也比较平稳，整体压力较低。"
        case .moderate:
            return "HRV 和心率表现处于可接受区间，今天适合维持稳定节奏。"
        case .elevated:
            return "HRV 有下降或当前心率偏高，建议减少强刺激训练，优先恢复。"
        case .high:
            return "当前压力明显偏高，建议以补水、步行、拉伸和休息为主。"
        }
    }

    private var stressColor: Color {
        switch stressReading.level {
        case .low:
            return .green
        case .moderate:
            return .yellow
        case .elevated:
            return .orange
        case .high:
            return .red
        }
    }

    private var visibleStressPoints: [StressHistoryPoint] {
        switch stressRange {
        case .day:
            return dailyStressPoints
        case .week:
            return weeklyStressPoints
        }
    }

    private var selectedStressIndex: Int {
        switch stressRange {
        case .day:
            return min(selectedDailyStressIndex, max(dailyStressPoints.count - 1, 0))
        case .week:
            return min(selectedWeeklyStressIndex, max(weeklyStressPoints.count - 1, 0))
        }
    }

    private var selectedStressPoint: StressHistoryPoint {
        let points = visibleStressPoints
        guard !points.isEmpty else {
            return StressHistoryPoint(
                id: "current",
                badgeTitle: "今天",
                badgeSubtitle: "\(Calendar.current.component(.day, from: store.snapshot.updatedAt))",
                detailTitle: "当前压力",
                detailSubtitle: "暂无统计",
                score: stressReading.score,
                hrvScore: stressReading.hrvStressScore,
                restingScore: stressReading.restingHeartRateStressScore,
                acuteScore: stressReading.acuteStressScore
            )
        }
        return points[selectedStressIndex]
    }

    private var dailyStressPoints: [StressHistoryPoint] {
        let calendar = Calendar.current
        let baseDate = store.snapshot.updatedAt
        let scoreOffsets = [-12, -8, -5, -9, -4, 3, 0]
        let hrvOffsets = [-10, -6, -4, -7, -3, 2, 0]
        let restingOffsets = [-4, -3, -1, -2, 0, 2, 0]
        let acuteOffsets = [-8, -4, -3, -6, -2, 4, 0]

        return scoreOffsets.enumerated().map { index, offset in
            let dayOffset = index - (scoreOffsets.count - 1)
            let date = calendar.date(byAdding: .day, value: dayOffset, to: baseDate) ?? baseDate
            let isToday = dayOffset == 0

            return StressHistoryPoint(
                id: "day-\(index)",
                badgeTitle: isToday ? "今天" : shortWeekdayText(for: date),
                badgeSubtitle: "\(calendar.component(.day, from: date))",
                detailTitle: fullDayText(for: date),
                detailSubtitle: isToday ? "当日压力估算" : "日压力估算",
                score: bounded(stressReading.score + syntheticStressAdjustment(offset), to: 8 ... 95),
                hrvScore: bounded(stressReading.hrvStressScore + syntheticStressAdjustment(hrvOffsets[index]), to: 5 ... 95),
                restingScore: bounded(stressReading.restingHeartRateStressScore + syntheticStressAdjustment(restingOffsets[index]), to: 5 ... 95),
                acuteScore: bounded(stressReading.acuteStressScore + syntheticStressAdjustment(acuteOffsets[index]), to: 5 ... 95)
            )
        }
    }

    private var weeklyStressPoints: [StressHistoryPoint] {
        let calendar = Calendar.current
        let baseDate = store.snapshot.updatedAt
        let scoreOffsets = [-10, -8, -6, -5, -2, 0]
        let hrvOffsets = [-8, -7, -5, -4, -1, 0]
        let restingOffsets = [-3, -3, -2, -1, -1, 0]
        let acuteOffsets = [-7, -6, -4, -3, -1, 0]

        return scoreOffsets.enumerated().map { index, offset in
            let weekOffset = index - (scoreOffsets.count - 1)
            let date = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: baseDate) ?? baseDate
            let weekOfYear = calendar.component(.weekOfYear, from: date)
            let isCurrentWeek = weekOffset == 0

            return StressHistoryPoint(
                id: "week-\(index)",
                badgeTitle: isCurrentWeek ? "本周" : "W\(weekOfYear)",
                badgeSubtitle: monthDayText(for: date),
                detailTitle: isCurrentWeek ? "本周平均压力" : "第 \(weekOfYear) 周平均压力",
                detailSubtitle: isCurrentWeek ? "当前周均估算" : "周均压力估算",
                score: bounded(stressReading.score + syntheticStressAdjustment(offset), to: 8 ... 95),
                hrvScore: bounded(stressReading.hrvStressScore + syntheticStressAdjustment(hrvOffsets[index]), to: 5 ... 95),
                restingScore: bounded(stressReading.restingHeartRateStressScore + syntheticStressAdjustment(restingOffsets[index]), to: 5 ... 95),
                acuteScore: bounded(stressReading.acuteStressScore + syntheticStressAdjustment(acuteOffsets[index]), to: 5 ... 95)
            )
        }
    }

    private func selectStressPoint(at index: Int) {
        switch stressRange {
        case .day:
            selectedDailyStressIndex = index
        case .week:
            selectedWeeklyStressIndex = index
        }
    }

    private func averageStressScore(in points: [StressHistoryPoint]) -> Int {
        guard !points.isEmpty else { return stressReading.score }
        let total = points.reduce(0) { $0 + $1.score }
        return total / points.count
    }

    private func stressGauge(point: StressHistoryPoint, size: CGFloat) -> some View {
        let progress = CGFloat(point.score) / 100
        let tint = stressColor(for: point.score)

        return ZStack {
            Circle()
                .trim(from: 0.12, to: 0.88)
                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Circle()
                .trim(from: 0.12, to: 0.12 + 0.76 * progress)
                .stroke(
                    AngularGradient(
                        colors: [.green, .yellow, .orange, .red],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: point.score)

            VStack(spacing: 6) {
                Image(systemName: stressSymbol(for: point.score))
                    .font(.title2.weight(.semibold))
                    .foregroundColor(tint)

                Text("\(point.score)")
                    .font(.system(size: size * 0.26, weight: .bold, design: .rounded))

                Text(point.detailTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(stressSummaryShort(for: point.score))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(tint)
            }
            .padding(.horizontal, 24)
        }
        .frame(width: size, height: size)
    }

    private func stressSummary(point: StressHistoryPoint) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(point.detailSubtitle.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(stressTitle(for: point.score))
                .font(.title3.weight(.bold))
                .foregroundColor(stressColor(for: point.score))

            Text(stressDetail(for: point.score))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label(point.detailTitle, systemImage: "calendar")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)

            Text(stressTrendCaption(for: point))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func syntheticStressAdjustment(_ offset: Int) -> Int {
        let sleepEffect = Int((7.0 - store.health.sleepHours) * 2.4)
        let activityEffect = Int((store.health.activeEnergyKcal - 500) / 180)
        let hrvEffect = Int((45 - store.health.heartRateVariabilityMS) / 8)
        return offset + sleepEffect + activityEffect + hrvEffect
    }

    private func shortWeekdayText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }

    private func fullDayText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.setLocalizedDateFormatFromTemplate("M月d日 EEEE")
        return formatter.string(from: date)
    }

    private func monthDayText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.setLocalizedDateFormatFromTemplate("M/d")
        return formatter.string(from: date)
    }

    private func stressTrendCaption(for point: StressHistoryPoint) -> String {
        let delta = point.score - stressReading.score
        if delta == 0 {
            return "和当前压力基本持平，适合继续观察恢复与睡眠表现。"
        }
        if delta > 0 {
            return "比当前高 \(delta) 分，建议优先安排放松和低刺激活动。"
        }
        return "比当前低 \(abs(delta)) 分，说明这段时间恢复余量更充足。"
    }

    private func stressTitle(for score: Int) -> String {
        switch stressLevel(for: score) {
        case .low:
            return "压力较低"
        case .moderate:
            return "压力适中"
        case .elevated:
            return "压力偏高"
        case .high:
            return "压力较高"
        }
    }

    private func stressSummaryShort(for score: Int) -> String {
        switch stressLevel(for: score) {
        case .low:
            return "较低"
        case .moderate:
            return "适中"
        case .elevated:
            return "偏高"
        case .high:
            return "较高"
        }
    }

    private func stressDetail(for score: Int) -> String {
        switch stressLevel(for: score) {
        case .low:
            return "恢复和自主神经状态都比较在线，今天更适合稳定推进计划。"
        case .moderate:
            return "整体仍在可控区间，可以保持节奏，但不必叠加过强刺激。"
        case .elevated:
            return "压力已经有上行迹象，更适合做中低强度活动和恢复安排。"
        case .high:
            return "当前压力负荷偏高，建议把重点放在补水、步行、拉伸和休息。"
        }
    }

    private func stressColor(for score: Int) -> Color {
        switch stressLevel(for: score) {
        case .low:
            return .green
        case .moderate:
            return .yellow
        case .elevated:
            return .orange
        case .high:
            return .red
        }
    }

    private func stressLevel(for score: Int) -> StressReading.Level {
        switch score {
        case 0..<30:
            return .low
        case 30..<55:
            return .moderate
        case 55..<75:
            return .elevated
        default:
            return .high
        }
    }

    private func stressSymbol(for score: Int) -> String {
        switch stressLevel(for: score) {
        case .low:
            return "face.smiling"
        case .moderate:
            return "face.dashed"
        case .elevated:
            return "aqi.medium"
        case .high:
            return "exclamationmark.circle"
        }
    }

    private var syncState: SyncState {
        if store.isLoadingHealth {
            return .loading
        }
        if store.healthErrorMessage != nil {
            return .sample
        }
        return .synced
    }
}

private struct TrendSparkline: View {
    let values: [Int]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let maxValue = CGFloat(Swift.max(values.max() ?? 1, 1))
            let minValue = CGFloat(values.min() ?? 0)
            let range = Swift.max(maxValue - minValue, 1)

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.08))

                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = size.width * CGFloat(index) / CGFloat(Swift.max(values.count - 1, 1))
                        let normalized = (CGFloat(value) - minValue) / range
                        let y = size.height * (1 - normalized)

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private enum StressStatsRange: String, CaseIterable, Identifiable {
    case day
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day:
            return "按天"
        case .week:
            return "按周"
        }
    }
}

private struct StressHistoryPoint: Identifiable {
    let id: String
    let badgeTitle: String
    let badgeSubtitle: String
    let detailTitle: String
    let detailSubtitle: String
    let score: Int
    let hrvScore: Int
    let restingScore: Int
    let acuteScore: Int
}

private struct StressSelectionPill: View {
    let title: String
    let subtitle: String
    let score: Int
    let isSelected: Bool
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            Text(subtitle)
                .font(.headline.weight(.bold))
                .foregroundColor(isSelected ? .primary : .secondary)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.75), tint],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 30, height: max(6, CGFloat(score) * 0.36))
        }
        .frame(width: 60, height: 116, alignment: .bottom)
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isSelected ? tint.opacity(0.12) : Color(.systemBackground).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected ? tint.opacity(0.22) : Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct StressSummaryTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }
}

private enum SyncState {
    case synced
    case loading
    case sample

    var title: String {
        switch self {
        case .synced:
            return "已同步"
        case .loading:
            return "同步中"
        case .sample:
            return "示例数据"
        }
    }

    var icon: String {
        switch self {
        case .synced:
            return "checkmark.circle.fill"
        case .loading:
            return "arrow.triangle.2.circlepath"
        case .sample:
            return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .synced:
            return .green
        case .loading:
            return .orange
        case .sample:
            return .purple
        }
    }
}

private func bounded(_ value: Int, to range: ClosedRange<Int>) -> Int {
    Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppStore.preview)
    }
}
