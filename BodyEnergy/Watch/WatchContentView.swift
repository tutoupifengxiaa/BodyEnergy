import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var viewModel: WatchEnergyViewModel

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
                sectionCard(title: "今日状态", subtitle: overviewSummary)
                hintFooter(text: "左右滑动切页，旋转表冠继续浏览")
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

                hintFooter(text: viewModel.connectionNote)
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

                hintFooter(text: "在 iPhone 端可查看完整训练详情")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("身体电量")
                    .font(.headline)
                Text("更新于 \(viewModel.updatedTimeText)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
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

    private var overviewSummary: String {
        switch viewModel.status {
        case .high:
            return "状态在线，适合安排更完整的训练。"
        case .medium:
            return "整体平稳，保持中等强度更容易持续。"
        case .low:
            return "当前更需要恢复，建议轻活动和休息。"
        }
    }

    private var syncBadgeText: String {
        switch viewModel.syncBadge {
        case .waiting:
            return "等待"
        case .active:
            return "实时"
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

    private func sectionCard(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote.weight(.semibold))
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(4)
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

struct WatchContentView_Previews: PreviewProvider {
    static var previews: some View {
        WatchContentView()
            .environmentObject(WatchEnergyViewModel())
    }
}
