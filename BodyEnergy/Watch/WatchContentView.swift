import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var viewModel: WatchEnergyViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPage = 0
    @State private var selectedHistoryDate: Date?
    @State private var selectedStressHour: Int?
    @State private var selectedMetric: HealthInsightMetric?
    @State private var selectedFeature: WatchFeature?

    private var mint: Color { viewModel.activities.preferences.settings.theme.tint }
    private var cardColor: Color { mint.opacity(0.10) }

    var body: some View {
        TabView(selection: $selectedPage) {
            overviewPage.tag(0)
            Group { if viewModel.hasPressure { stressPage } else { emptyPressureCard } }.tag(1)
            metricsPage.tag(2)
            workoutPage.tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .background(Color.black)
        .tint(mint)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            viewModel.onAppear()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                viewModel.refresh()
            }
        }
        .onOpenURL { url in if url.host == "stress" { selectedPage = 1 } }
        .onReceive(viewModel.$notificationDestination) { destination in
            guard let destination else { return }
            if destination == "breathing" { selectedMetric = nil; selectedFeature = .breathing }
            else { selectedFeature = nil; selectedMetric = nil; selectedPage = 1 }
            viewModel.clearNotificationDestination()
        }
        .fullScreenCover(item: $selectedMetric) { metric in
            WatchMetricDetailView(explanation: viewModel.explanation(for: metric),
                                  sleepDetails: metric == .sleep ? viewModel.metrics.health?.sleepDetails : nil)
                .tint(mint)
        }
        .fullScreenCover(item: $selectedFeature) { feature in
            Group {
                switch feature {
                case .breathing: ActivitySessionView(store: viewModel.activities)
                case .feeling: FeelingCheckInView(store: viewModel.activities)
                case .insights: InsightsView(appStore: viewModel.appStore)
                case .history: ActivityHistoryView(store: viewModel.activities)
                case .settings: AppSettingsView(store: viewModel.appStore.preferences)
                }
            }
            .tint(mint)
        }
    }

    private var overviewPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                HStack {
                    pageTitle("身体电量")
                    Spacer(minLength: 4)
                    Button { selectedFeature = .settings } label: {
                        Image(systemName: "gearshape")
                            .font(.caption.weight(.semibold))
                            .frame(width: 28, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开设置")
                    Button(action: viewModel.refresh) {
                        Group {
                            if viewModel.isRefreshingHealth { ProgressView().tint(mint) }
                            else { Image(systemName: "arrow.clockwise").font(.caption.weight(.semibold)) }
                        }
                        .foregroundStyle(mint)
                        .frame(width: 32, height: 32)
                        .background(cardColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isRefreshingHealth)
                    .accessibilityLabel("刷新健康数据")
                    .accessibilityValue(viewModel.isRefreshingHealth ? "读取中" : "")
                }

                if viewModel.hasScore { scoreCard }
                else if viewModel.hasPressure { Text("电量数据待补充").font(.caption2).foregroundStyle(.secondary) }
                else { emptyScoreCard }

                Button { selectedPage = 3 } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.hasCurrentRecommendation ? "今日建议" : "通用建议 · 健康数据待补充")
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(viewModel.shortRecommendation)
                                .font(.caption.weight(.medium))
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(cardColor, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .accessibilityHint("查看训练安排与完整建议")

                ActivityHubView(store: viewModel.activities)
                RecoveryHabitsView(store: viewModel.appStore.habits)

                if viewModel.hasPressure { Button { selectedPage = 1 } label: {
                    HStack(spacing: 10) {
                        StressFace(score: viewModel.metrics.stressScore)
                            .frame(width: 38, height: 38)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(viewModel.isPressureStale ? "上次压力变化" : "最近压力变化").font(.caption2).foregroundStyle(.secondary)
                            Text("\(viewModel.metrics.stressScore) · \(stressMood.title)")
                                .font(.caption.weight(.semibold))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(cardColor, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .accessibilityHint("打开卡通表情与压力详情")
                }

                syncFooter(sampledAt: viewModel.metrics.health?.measuredAt ?? viewModel.pressure?.updatedAt)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 24)
        }
    }

    private var scoreCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(viewModel.snapshot.energyScore, 0), 100)) / 100)
                    .stroke(mint.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text("\(viewModel.snapshot.energyScore)")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("电量 / 100")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(width: 84, height: 84)
            .padding(4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("身体电量 \(viewModel.snapshot.energyScore) 分")

            HStack {
                Text(viewModel.isStale ? "上次记录" : viewModel.bodyStatus.state.title)
                Spacer(minLength: 4)
                Text("恢复 \(viewModel.explanation(for: .recovery).value)")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(mint)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [mint.opacity(0.24), mint.opacity(0.12)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private var stressPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                pageTitle(viewModel.isPressureStale ? "上次压力变化" : "压力状态")

                VStack(spacing: 5) {
                    StressFace(score: viewModel.metrics.stressScore)
                        .frame(width: 80, height: 80)
                        .accessibilityHidden(true)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(viewModel.metrics.stressScore)")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(stressMood.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(stressMood.color)
                    }
                    Text("压力 / 100")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(stressMood.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("压力估算 \(viewModel.metrics.stressScore) 分，\(stressMood.title)")

                Button("查看压力依据") { selectedMetric = .pressure }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(mint)

                HStack(spacing: 8) {
                    statPill(title: viewModel.pressureHRVTitle, value: viewModel.pressureHRVValue == "—" ? "—" : "\(viewModel.pressureHRVValue) ms")
                    statPill(title: "静息心率", value: viewModel.metrics.health?.missingMetrics.contains(.restingHeartRate) == true ? "—" : "\(Int(viewModel.metrics.restingHeartRateBPM.rounded())) bpm")
                }
                pressureActions
                hourlyStressCard
                stressTrendCard
                syncFooter(sampledAt: viewModel.pressure?.updatedAt)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 24)
        }
    }

    private var emptyScoreCard: some View {
        VStack(spacing: 12) {
            Text("暂无可用评分").font(.headline)
            Text(viewModel.statusMessage ?? "评分所需数据尚不完整，请等待新的健康记录。")
                .font(.caption2).foregroundStyle(.secondary)
            Button("刷新", action: viewModel.refresh)
                .disabled(viewModel.isRefreshingHealth)
        }
        .padding(12)
    }

    private var emptyPressureCard: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                Text(viewModel.pressureDataStatus.title).font(.headline)
                Text(viewModel.pressureDataStatus.detail)
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("查看说明") { selectedMetric = .pressure }
                    .font(.caption2)
                Button("刷新", action: viewModel.refresh)
                    .disabled(viewModel.isRefreshingHealth)
                pressureActions
                syncFooter(sampledAt: viewModel.pressure?.updatedAt)
            }
            .padding(12)
        }
    }

    private var stressTrendCard: some View {
        let days = HistoryDay.recentWeek(viewModel.pressureHistory)
        let point = days.first { $0.date == selectedHistoryDate } ?? days.last { $0.metrics != nil } ?? days[6]
        return VStack(alignment: .leading, spacing: 10) {
            Text("近 7 天压力").font(.caption.weight(.semibold))
            Text(point.metrics?.stressScore.map { "\($0) 分" } ?? "暂无记录").font(.headline)
            Text(AppDateTime.day(point.date)).font(.caption2).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(days) { day in
                    Button { selectedHistoryDate = day.date } label: {
                        VStack(spacing: 5) {
                            if let score = day.metrics?.stressScore {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(day.date == point.date ? mint : mint.opacity(0.25))
                                    .frame(height: max(4, CGFloat(score) * 0.6))
                                    .frame(height: 60, alignment: .bottom)
                            } else {
                                Text("—").foregroundStyle(.tertiary).frame(height: 60, alignment: .bottom)
                            }
                            Text("\(Calendar.current.component(.day, from: day.date))").font(.system(size: 8))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 20))
    }

    private var hourlyStressCard: some View {
        let today = viewModel.hourlyStress.filter { Calendar.current.isDateInToday($0.hour) }
        let scores = Dictionary(today.map { (Calendar.current.component(.hour, from: $0.hour), $0.score) }, uniquingKeysWith: { _, latest in latest })
        let selected = selectedStressHour ?? today.last.map { Calendar.current.component(.hour, from: $0.hour) }
        return VStack(alignment: .leading, spacing: 8) {
            Label("今日逐小时压力", systemImage: "chart.bar.xaxis")
                .font(.caption.weight(.semibold))
            Text(selected.map { hour in scores[hour].map { "\(hour):00  \($0) 分" } ?? "\(hour):00 无采样" } ?? "今天暂无逐小时压力记录")
                .font(.caption.weight(.semibold))
            ZStack(alignment: .bottom) {
                Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(0..<24, id: \.self) { hour in
                        Button { selectedStressHour = hour } label: {
                            Group {
                                if let score = scores[hour] {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(hour == selected ? mint : mint.opacity(0.4))
                                        .frame(width: 4, height: max(3, CGFloat(score) * 0.5))
                                } else {
                                    Color.clear.frame(width: 4, height: 1)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50, alignment: .bottom)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(hour) 点到 \(hour + 1) 点，" + (scores[hour].map { "压力 \($0) 分" } ?? "无采样"))
                    }
                }
            }
            .frame(height: 50)
            HStack(spacing: 0) {
                Text("00")
                Spacer()
                Text("06")
                Spacer()
                Text("12")
                Spacer()
                Text("18")
                Spacer()
                Text("24")
            }
            .font(.system(size: 8, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(12)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 20))
    }

    private var metricsPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                pageTitle("健康指标")
                Button { selectedFeature = .insights } label: {
                    Label("查看趋势与睡眠详情", systemImage: "chart.xyaxis.line")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                    spacing: 7
                ) {
                    ForEach(viewModel.metricCards) { card in
                        metricTile(card)
                    }
                }
                syncFooter(sampledAt: viewModel.metrics.health?.measuredAt)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 24)
        }
    }

    private var workoutPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                pageTitle("训练安排")
                if !viewModel.hasCurrentRecommendation {
                    Text("通用建议 · 健康数据待补充")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "figure.run")
                        .font(.title3).foregroundStyle(mint)
                    Text(viewModel.recommendationTitle)
                        .font(.headline)
                    Text(viewModel.displayedWorkoutRecommendation.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(cardColor, in: RoundedRectangle(cornerRadius: 20))

                HStack(spacing: 8) {
                    statPill(title: "时长", value: viewModel.recommendationDurationText)
                    statPill(title: "强度", value: viewModel.recommendationIntensityText)
                }

                WatchWorkoutTimingEntry(store: viewModel.activities,
                                        recommendation: viewModel.displayedWorkoutRecommendation)
                Button { selectedFeature = .history } label: {
                    Label("查看活动记录", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                Text(viewModel.displayedWorkoutRecommendation.purposeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(cardColor, in: RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(viewModel.displayedWorkoutRecommendation.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(mint)
                                .frame(width: 20, height: 20)
                                .background(mint.opacity(0.12), in: Circle())
                            Text(step)
                                .font(.caption2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .background(cardColor, in: RoundedRectangle(cornerRadius: 20))

                Text(viewModel.displayedWorkoutRecommendation.cautionText)
                    .font(.caption2).foregroundStyle(.secondary)
                syncFooter(sampledAt: viewModel.metrics.health?.measuredAt)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 24)
        }
    }

    private var stressMood: StressMood {
        StressMood(score: viewModel.metrics.stressScore)
    }

    private func pageTitle(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
    }

    private func syncFooter(sampledAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("采集时间").font(.caption2.weight(.semibold))
            if let sampledAt {
                Text(AppDateTime.timestamp(sampledAt)).monospacedDigit()
            } else { Text("暂无采集记录") }
            if viewModel.isRefreshingHealth { Text("正在读取手表健康数据…") }
            else if let note = viewModel.localRefreshNote { Text(note) }
            Text(viewModel.phoneSyncNote ?? viewModel.connectionNote)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var syncLabel: String {
        switch viewModel.syncBadge {
        case .waiting: return "等待健康数据"
        case .connected: return "已连接·待数据"
        case .active: return "数据已更新"
        case .error: return "同步失败"
        }
    }

    private var pressureActions: some View {
        VStack(spacing: 8) {
            Button { selectedFeature = .breathing } label: {
                Label("舒缓呼吸", systemImage: "wind")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { selectedFeature = .feeling } label: {
                Label("记录感受", systemImage: "face.smiling")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.bordered)
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.caption2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 16))
    }

    private func metricTile(_ card: WatchMetricCard) -> some View {
        let metric: HealthInsightMetric = ["hrv": .hrv, "resting": .restingHeartRate, "sleep": .sleep,
            "currentHeartRate": .heartRate, "activity": .activeEnergy, "stress": .pressure][card.id] ?? .recovery
        let explanation = viewModel.explanation(for: metric)
        return Button { selectedMetric = metric } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: card.symbol)
                        .font(.caption).foregroundStyle(mint)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                }
                Text(explanation.title).font(.system(size: 10)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(explanation.value)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                    Text(explanation.unit).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Text(explanation.statusTitle)
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("查看指标解释与采样时间")
    }

}

private enum WatchFeature: String, Identifiable {
    case breathing, feeling, insights, history, settings
    var id: String { rawValue }
}

private struct WatchWorkoutTimingEntry: View {
    @ObservedObject var store: ActivityStore
    let recommendation: WorkoutRecommendation
    @State private var capturedRecommendation: WorkoutRecommendation?
    @State private var showingSession = false

    var body: some View {
        Button {
            capturedRecommendation = recommendation
            showingSession = true
        } label: {
            Text(store.active == nil ? "开始计时" : "继续当前计时")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .fullScreenCover(isPresented: $showingSession) {
            ActivitySessionView(store: store, recommendation: capturedRecommendation)
        }
    }
}

struct WatchContentView_Previews: PreviewProvider {
    static var previews: some View {
        WatchContentView()
            .environmentObject(WatchEnergyViewModel())
    }
}
