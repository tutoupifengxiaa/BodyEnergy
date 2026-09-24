import Foundation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isShowingRecommendationDetail = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedHistoryDate: Date?
    @State private var selectedStressHour: Int?

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.setLocalizedDateFormatFromTemplate("M月d日 EEEE")
        return formatter
    }()
    private static let collectionTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
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

    private var energyProgress: CGFloat {
        store.hasScore ? CGFloat(energyScore) / 100 : 0
    }

    private var bodyStatus: BodyStatusDescriptor {
        store.bodyStatusDescriptor
    }

    private var accent: Color {
        colorScheme == .dark ? mint : Color(red: 0.10, green: 0.46, blue: 0.38)
    }
    private let mint = Color(red: 0.66, green: 0.91, blue: 0.76)

    var body: some View {
        VStack(spacing: 0) {
            topHeader

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        heroCard
                            .id("energy")
                        systemStateCard
                        metricsSection
                        hourlyStressCard
                        stressInsightsCard
                        recommendationCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .refreshable { await store.refreshHealthData() }
                .onOpenURL { url in
                    guard url.scheme == "bodyenergy", let target = url.host, ["energy", "stress"].contains(target) else { return }
                    withAnimation { proxy.scrollTo(target, anchor: .top) }
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .tint(accent)
        .fullScreenCover(isPresented: $isShowingRecommendationDetail) {
            NavigationStack {
                RecommendationDetailView(recommendation: store.displayedWorkoutRecommendation)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("关闭") { isShowingRecommendationDetail = false }
                        }
                    }
            }
            .tint(accent)
        }
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

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 30) {
                    scoreRing
                    heroDetails
                }
                VStack(spacing: 24) {
                    scoreRing
                    heroDetails
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                Circle().fill(mint).frame(width: 5, height: 5)
                Text(store.isLoadingHealth ? "读取中" : store.dataStatusTitle)
                Spacer()
                if store.hasScore {
                    Text("采集 \(Self.collectionTimeFormatter.string(from: store.snapshot.updatedAt))")
                }
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.72))
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
                .stroke(mint.gradient, style: StrokeStyle(lineWidth: 11, lineCap: .round))
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
            VStack(alignment: .leading, spacing: 4) {
                Text("恢复分数")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                Text(store.hasScore ? "\(recoveryScore)" : "—")
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
            }
            Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.hasPressure && store.isPressureStale ? "上次压力" : "压力状态")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                Text(store.pressure?.levelTitle ?? "等待 HRV")
                    .font(.headline)
                    .foregroundStyle(mint)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var systemStateCard: some View {
        if let message = store.healthErrorMessage {
            Label(message, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("健康指标")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                spacing: 12
            ) {
                metricTile(title: "睡眠", value: String(format: "%.1f", store.health.sleepHours), unit: "小时", icon: "moon.zzz.fill", tint: .indigo, metric: .sleep)
                metricTile(title: "HRV", value: "\(Int(store.health.heartRateVariabilityMS))", unit: "ms", icon: "waveform.path.ecg", tint: accent, metric: .hrv)
                metricTile(title: "静息心率", value: "\(Int(store.health.restingHeartRateBPM))", unit: "bpm", icon: "heart.fill", tint: .pink, metric: .restingHeartRate)
                metricTile(title: "最近心率", value: "\(Int(store.health.heartRateBPM))", unit: "bpm", icon: "heart", tint: .pink, metric: .heartRate)
                metricTile(title: "活动消耗", value: "\(Int(store.health.activeEnergyKcal))", unit: "千卡", icon: "flame.fill", tint: .orange, metric: .activeEnergy)
                metricTile(title: "压力指数", value: "\(stressReading.score)", unit: "/ 100", icon: "waveform.path", tint: accent)
            }
        }
    }

    private func metricTile(title: String, value: String, unit: String, icon: String, tint: Color, metric: HealthMetric? = nil) -> some View {
        let available = metric.map { !store.health.missingMetrics.contains($0) } ?? store.hasPressure
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 7) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(available ? value : "—")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            if let metric, let date = store.health.sampleDates[metric] {
                if date.addingTimeInterval(metric.maxAge) < .now {
                    Text("上次记录").font(.caption2).foregroundStyle(.orange)
                }
            } else if metric == nil, let pressure = store.pressure {
                Text(store.isPressureStale ? "上次估算" : pressure.basis)
                    .font(.caption2).foregroundStyle(.secondary)
            } else if !available {
                Text("暂无数据").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 96, alignment: .topLeading)
        .padding(18)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
    }

    private var hourlyStressCard: some View {
        let today = store.hourlyStress.filter { Calendar.current.isDateInToday($0.hour) }
        let scores = Dictionary(today.map { (Calendar.current.component(.hour, from: $0.hour), $0.score) }, uniquingKeysWith: { _, latest in latest })
        let selected = selectedStressHour ?? today.last.map { Calendar.current.component(.hour, from: $0.hour) }
        return VStack(alignment: .leading, spacing: 14) {
            Label("今日逐小时压力", systemImage: "chart.bar.xaxis")
                .font(.headline)
            Text("按每小时 HRV 采样估算；无采样的时段留空")
                .font(.caption).foregroundStyle(.secondary)
            if let selected, let score = scores[selected] {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(score)")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                    Text("分").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%02d:00–%02d:00", selected, selected + 1))
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else if let selected {
                Text(String(format: "%02d:00–%02d:00 无采样", selected, selected + 1))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("今天暂无 HRV 采样").font(.subheadline).foregroundStyle(.secondary)
            }
            ZStack(alignment: .bottom) {
                VStack {
                    Rectangle().frame(height: 1)
                    Spacer()
                    Rectangle().frame(height: 1)
                    Spacer()
                    Rectangle().frame(height: 1)
                }
                .foregroundStyle(Color.secondary.opacity(0.12))
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<24, id: \.self) { hour in
                        Button { selectedStressHour = hour } label: {
                            Group {
                                if let score = scores[hour] {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(hour == selected ? accent : accent.opacity(0.45))
                                        .frame(width: 7, height: max(4, CGFloat(score) * 0.84))
                                } else {
                                    Color.clear.frame(width: 7, height: 1)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 84, alignment: .bottom)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(hour) 点到 \(hour + 1) 点，" + (scores[hour].map { "压力 \($0) 分" } ?? "无采样"))
                    }
                }
            }
            .frame(height: 84)
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
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(20)
        .background(cardBackground)
        .id("stress")
    }

    private var stressInsightsCard: some View {
        let days = HistoryDay.recentWeek(store.history)
        let selected = days.first { $0.date == selectedHistoryDate } ?? days.last { $0.metrics != nil } ?? days[6]
        let values = days.compactMap { $0.metrics?.stressScore }
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                sectionHeader("近 7 天压力")
                Spacer()
                Text("每日最后记录").font(.caption2).foregroundStyle(.secondary)
            }
            Text(selected.metrics.map { "\($0.stressScore) 分" } ?? "暂无记录")
                .font(.system(.title, design: .rounded, weight: .semibold))
            Text(selected.date, format: .dateTime.month().day())
                .font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(days) { day in
                    Button { selectedHistoryDate = day.date } label: {
                        VStack(spacing: 8) {
                            if let score = day.metrics?.stressScore {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(day.date == selected.date ? accent : accent.opacity(0.25))
                                    .frame(height: max(4, CGFloat(score)))
                                    .frame(height: 100, alignment: .bottom)
                            } else {
                                Text("—").foregroundStyle(.tertiary).frame(height: 100, alignment: .bottom)
                            }
                            Text(day.date, format: .dateTime.day()).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted) + (day.metrics.map { "，压力 \($0.stressScore) 分" } ?? "，暂无记录"))
                }
            }
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
        }
        .padding(20)
        .background(cardBackground)
    }

    private var recommendationCard: some View {
        Button {
            isShowingRecommendationDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    sectionHeader("训练安排")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                }
                if !store.hasCurrentRecommendation {
                    Text("通用建议 · 健康数据待补充")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Label(store.displayedWorkoutRecommendation.title, systemImage: "figure.run")
                    .font(.subheadline.weight(.medium))
                HStack {
                    detailChip(title: "时长", value: store.displayedWorkoutRecommendation.durationText)
                    detailChip(title: "强度", value: store.displayedWorkoutRecommendation.intensityText)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
        .accessibilityHint("查看训练步骤和注意事项")
    }

    private func detailChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.headline)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
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
