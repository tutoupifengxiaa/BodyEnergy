import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var viewModel: WatchEnergyViewModel
    @State private var stressTrendRange: WatchStressTrendRange = .day
    @State private var selectedDailyStressIndex = 6
    @State private var selectedWeeklyStressIndex = 5

    var body: some View {
        TabView {
            overviewPage
            metricsPage
            workoutPage
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .background(Color.black.opacity(0.05))
        .task {
            viewModel.onAppear()
        }
    }

    private var overviewPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                headerRow
                scoreCard
                stressTrendCard

                if let sampleScenarioTitle = viewModel.sampleScenarioTitle {
                    sectionCard(
                        title: "当前场景",
                        subtitle: sampleScenarioTitle,
                        detail: viewModel.sampleScenarioSummary ?? "当前正在展示来自 iPhone 的示例状态。"
                    )
                }

                sectionCard(
                    title: "身体状态提示",
                    subtitle: viewModel.bodyStatus.title,
                    detail: viewModel.bodyStatus.detail
                )

                actionCard
                hintFooter(text: "左右滑动切页，旋转表冠继续浏览。")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var metricsPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                Text("关键数据")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                    spacing: 6
                ) {
                    ForEach(viewModel.metricCards) { card in
                        metricTile(card)
                    }
                }

                hintFooter(text: viewModel.syncStatusDetail)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var workoutPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                Text("训练建议")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.recommendationTitle)
                        .font(.footnote.weight(.semibold))
                    Text(viewModel.shortRecommendation)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )

                HStack(spacing: 6) {
                    statPill(title: "时长", value: viewModel.recommendationDurationText, tint: .blue)
                    statPill(title: "强度", value: viewModel.recommendationIntensityText, tint: .orange)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(viewModel.compactSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(index + 1)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 16, height: 16)
                                .background(viewModel.status.color, in: Circle())

                            Text(step)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )

                hintFooter(text: "完整训练建议可在 iPhone 端继续查看。")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("身体电量")
                    .font(.headline)
                Text(viewModel.syncStatusTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(syncBadgeColor)
                Text(viewModel.syncStatusDetail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            Spacer()

            Button(action: viewModel.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var scoreCard: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 10)

                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.snapshot.energyScore) / 100)
                    .stroke(viewModel.status.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(viewModel.snapshot.energyScore)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(viewModel.status.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(viewModel.status.color)
                }
            }
            .frame(width: 92, height: 92)

            HStack(spacing: 6) {
                statPill(title: "恢复", value: "\(viewModel.snapshot.recoveryScore)", tint: .blue)
                statPill(title: "同步", value: syncBadgeText, tint: syncBadgeColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private var stressTrendCard: some View {
        let point = selectedStressPoint
        let tint = viewModel.stressTint(for: point.score)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("压力趋势")
                    .font(.footnote.weight(.semibold))

                Spacer(minLength: 6)

                HStack(spacing: 4) {
                    ForEach(WatchStressTrendRange.allCases) { range in
                        Button {
                            stressTrendRange = range
                        } label: {
                            stressRangeButton(range)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 92)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(visibleStressPoints.enumerated()), id: \.element.id) { index, point in
                        Button {
                            selectStressPoint(at: index)
                        } label: {
                            stressTrendPill(point: point, isSelected: index == selectedStressIndex)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .trim(from: 0.12, to: 0.88)
                        .stroke(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Circle()
                        .trim(from: 0.12, to: 0.12 + 0.76 * CGFloat(point.score) / 100)
                        .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 1) {
                        Text("\(point.score)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text(point.title)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.stressMoodTitle(for: point.score))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(tint)

                    Text(point.detailTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.primary)

                    Text(viewModel.stressMoodDetail(for: point.score))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(3)

                    Text(viewModel.stressTrendNote(for: point.score))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(tint)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("当前建议")
                .font(.footnote.weight(.semibold))
            Text(viewModel.bodyStatus.action)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(bodyStatusColor.opacity(0.14))
        )
    }

    private var visibleStressPoints: [WatchStressTrendPoint] {
        switch stressTrendRange {
        case .day:
            return viewModel.dailyStressTrendPoints
        case .week:
            return viewModel.weeklyStressTrendPoints
        }
    }

    private var selectedStressIndex: Int {
        switch stressTrendRange {
        case .day:
            return min(selectedDailyStressIndex, max(viewModel.dailyStressTrendPoints.count - 1, 0))
        case .week:
            return min(selectedWeeklyStressIndex, max(viewModel.weeklyStressTrendPoints.count - 1, 0))
        }
    }

    private var selectedStressPoint: WatchStressTrendPoint {
        let points = visibleStressPoints
        guard !points.isEmpty else {
            return WatchStressTrendPoint(
                id: "current",
                title: "今天",
                subtitle: "\(Calendar.current.component(.day, from: viewModel.snapshot.updatedAt))",
                detailTitle: "当前压力",
                score: viewModel.metrics.stressScore
            )
        }
        return points[selectedStressIndex]
    }

    private func selectStressPoint(at index: Int) {
        switch stressTrendRange {
        case .day:
            selectedDailyStressIndex = index
        case .week:
            selectedWeeklyStressIndex = index
        }
    }

    private func stressTrendPill(point: WatchStressTrendPoint, isSelected: Bool) -> some View {
        let tint = viewModel.stressTint(for: point.score)

        return VStack(spacing: 4) {
            Text(point.title)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.secondary)

            Text(point.subtitle)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(isSelected ? .primary : .secondary)

            Capsule(style: .continuous)
                .fill(tint)
                .frame(width: 18, height: max(6, CGFloat(point.score) * 0.25))
        }
        .frame(width: 42, height: 68, alignment: .bottom)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? tint.opacity(0.14) : Color.white.opacity(0.05))
        )
    }

    private func stressRangeButton(_ range: WatchStressTrendRange) -> some View {
        let isSelected = stressTrendRange == range

        return Text(range.title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(isSelected ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.08))
            )
    }

    private var syncBadgeText: String {
        switch viewModel.syncBadge {
        case .waiting:
            return "等待"
        case .active:
            return "已连通"
        case .error:
            return "异常"
        }
    }

    private var syncBadgeColor: Color {
        switch viewModel.syncBadge {
        case .waiting:
            return .gray
        case .active:
            return .green
        case .error:
            return .orange
        }
    }

    private var bodyStatusColor: Color {
        switch viewModel.bodyStatus.state {
        case .high:
            return .green
        case .medium:
            return .orange
        case .low:
            return .red
        }
    }

    private func statPill(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

    private func sectionCard(title: String, subtitle: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote.weight(.semibold))
            Text(subtitle)
                .font(.caption.weight(.semibold))
                .foregroundColor(bodyStatusColor)
            Text(detail)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func metricTile(_ card: WatchMetricCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(card.title, systemImage: card.symbol)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(card.value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(card.unit)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Text(card.note)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(card.tint)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(card.tint.opacity(0.12))
        )
    }

    private func hintFooter(text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .frame(maxWidth: .infinity)
    }
}

private enum WatchStressTrendRange: String, CaseIterable, Identifiable {
    case day
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day:
            return "天"
        case .week:
            return "周"
        }
    }
}

struct WatchContentView_Previews: PreviewProvider {
    static var previews: some View {
        WatchContentView()
            .environmentObject(WatchEnergyViewModel())
    }
}
