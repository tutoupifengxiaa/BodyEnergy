import Foundation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isShowingRecommendationDetail = false
    private let screenBounds = UIScreen.main.bounds

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.setLocalizedDateFormatFromTemplate("M月d日 EEEE")
        return formatter
    }()

    private var energyScore: Int {
        bounded(store.snapshot.energyScore, to: 0...100)
    }

    private var recoveryScore: Int {
        bounded(store.snapshot.recoveryScore, to: 0...100)
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
        [-9, -6, -4, -2, 0, -1, 0].map { bounded(energyScore + $0, to: 0...100) }
    }

    private var weekdayLabels: [String] {
        ["一", "二", "三", "四", "五", "六", "日"]
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                pageBackground

                ScrollView {
                    VStack(spacing: 16) {
                        Color.clear
                            .frame(height: proxy.safeAreaInsets.top + 92)
                        heroCard
                        systemStateCard
                        scoreBreakdownCard
                        stressCard
                        trendCard
                        metricsSection
                        focusCard
                        recommendationCard
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)

                topHeader(topInset: proxy.safeAreaInsets.top)
            }
            .frame(
                width: max(proxy.size.width, screenBounds.width),
                height: max(proxy.size.height, screenBounds.height),
                alignment: .top
            )
            .ignoresSafeArea(edges: [.top, .bottom])
            .refreshable {
                await store.refreshHealthData()
            }
        }
        .frame(
            width: screenBounds.width,
            height: screenBounds.height
        )
        .background(pageBackground)
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
        .ignoresSafeArea()
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
            .padding(.top, topInset + 8)
            .padding(.horizontal, 16)
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
                        colors: [Color.green, Color.yellow, Color.orange, Color.red],
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
                ProgressView().controlSize(.small)
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
            return "睡眠、HRV 和静息心率整体表现较好，恢复面更稳。"
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
