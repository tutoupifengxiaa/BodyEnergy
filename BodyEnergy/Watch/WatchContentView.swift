import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var viewModel: WatchEnergyViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPage = 0
    @State private var selectedHistoryDate: Date?
    @State private var selectedStressHour: Int?

    private let mint = Color(red: 0.66, green: 0.91, blue: 0.76)
    private let cardColor = Color.white.opacity(0.075)
    private static let collectionTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

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

    }

    private var overviewPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                HStack {
                    pageTitle("身体电量")
                    Spacer(minLength: 4)
                    Button(action: viewModel.refresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(mint)
                            .frame(width: 32, height: 32)
                            .background(cardColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("刷新健康数据")
                }

                if viewModel.hasScore { scoreCard }
                else if viewModel.hasPressure { Text("电量数据待补充").font(.caption2).foregroundStyle(.secondary) }
                else { emptyScoreCard }


                if viewModel.hasPressure { Button { selectedPage = 1 } label: {
                    HStack(spacing: 10) {
                        StressFace(score: viewModel.metrics.stressScore)
                            .frame(width: 38, height: 38)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(viewModel.isPressureStale ? "上次压力" : "压力估算").font(.caption2).foregroundStyle(.secondary)
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

                syncFooter
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
                Text("恢复 \(viewModel.snapshot.recoveryScore)")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(mint)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.24, blue: 0.22), Color(red: 0.06, green: 0.15, blue: 0.14)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private var stressPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                pageTitle(viewModel.isPressureStale ? "上次压力" : "压力估算")

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
                    Text("压力指数 / 100")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(stressMood.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("压力估算 \(viewModel.metrics.stressScore) 分，\(stressMood.title)")

                HStack(spacing: 8) {
                    statPill(title: "HRV", value: viewModel.metrics.health?.missingMetrics.contains(.hrv) == true ? "—" : "\(Int(viewModel.metrics.heartRateVariabilityMS.rounded())) ms")
                    statPill(title: "静息心率", value: viewModel.metrics.health?.missingMetrics.contains(.restingHeartRate) == true ? "—" : "\(Int(viewModel.metrics.restingHeartRateBPM.rounded())) bpm")
                }
                Text(viewModel.pressure?.basis ?? "等待 HRV")
                    .font(.caption2).foregroundStyle(.secondary)
                syncFooter
                hourlyStressCard
                stressTrendCard
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 24)
        }
    }

    private var emptyScoreCard: some View {
        VStack(spacing: 12) {
            Text("暂无可用评分").font(.headline)
            Text(viewModel.receivedAt == nil ? "打开 iPhone App 后刷新。" : (viewModel.statusMessage ?? "评分所需数据尚不完整。"))
                .font(.caption2).foregroundStyle(.secondary)
            Button("刷新", action: viewModel.refresh)
        }
        .padding(12)
    }

    private var emptyPressureCard: some View {
        VStack(spacing: 12) {
            Text("等待 HRV 数据").font(.headline)
            Text("需要近期 HRV 测量，不依赖睡眠记录。")
                .font(.caption2).foregroundStyle(.secondary)
            Button("刷新", action: viewModel.refresh)
            syncFooter
        }
        .padding(12)
    }

    private var stressTrendCard: some View {
        let days = HistoryDay.recentWeek(viewModel.history)
        let point = days.first { $0.date == selectedHistoryDate } ?? days.last { $0.metrics != nil } ?? days[6]
        return VStack(alignment: .leading, spacing: 10) {
            Text("近 7 天压力").font(.caption.weight(.semibold))
            Text(point.metrics.map { "\($0.stressScore) 分" } ?? "暂无记录").font(.headline)
            Text(point.date, format: .dateTime.month().day()).font(.caption2).foregroundStyle(.secondary)
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
                            Text(day.date, format: .dateTime.day()).font(.system(size: 8))
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
            Text("按 HRV 估算 · 空白表示无采样")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Text(selected.map { hour in scores[hour].map { "\(hour):00  \($0) 分" } ?? "\(hour):00 无采样" } ?? "今天暂无 HRV 采样")
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
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                    spacing: 7
                ) {
                    ForEach(viewModel.metricCards.filter { $0.id != "stress" }) { card in
                        metricTile(card)
                    }
                }
                if let collectedAt = viewModel.metrics.health?.measuredAt {
                    Text("最近采集时间：\(Self.collectionTimeFormatter.string(from: collectedAt))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                syncFooter
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(cardColor, in: RoundedRectangle(cornerRadius: 20))

                HStack(spacing: 8) {
                    statPill(title: "时长", value: viewModel.recommendationDurationText)
                    statPill(title: "强度", value: viewModel.recommendationIntensityText)
                }

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
                syncFooter
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

    private var syncFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(syncLabel)
                Spacer(minLength: 4)
                Text(viewModel.receivedAt.map { $0.formatted(.dateTime.hour().minute()) } ?? "—")
            }
            Text(viewModel.connectionNote)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private var syncLabel: String {
        switch viewModel.syncBadge {
        case .waiting: return "等待同步"
        case .connected: return "已连接·待数据"
        case .active: return "已接收同步"
        case .error: return "同步失败"
        }
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
        let metric: HealthMetric? = ["hrv": .hrv, "resting": .restingHeartRate, "sleep": .sleep, "currentHeartRate": .heartRate, "activity": .activeEnergy][card.id]
        let available = metric.map { !(viewModel.metrics.health?.missingMetrics.contains($0) ?? true) } ?? viewModel.hasScore
        return VStack(alignment: .leading, spacing: 8) {
            Image(systemName: card.symbol)
                .font(.caption).foregroundStyle(mint)
            Text(card.title).font(.system(size: 10)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(available ? card.value : "—")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Text(card.unit).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

}

struct WatchContentView_Previews: PreviewProvider {
    static var previews: some View {
        WatchContentView()
            .environmentObject(WatchEnergyViewModel())
    }
}
