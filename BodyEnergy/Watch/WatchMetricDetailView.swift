import Foundation
import SwiftUI

struct WatchMetricDetailView: View {
    let explanation: HealthMetricExplanation
    var sleepDetails: SleepDetails? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                    Text(explanation.title).font(.headline)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(explanation.value)
                                .font(.system(.title2, design: .rounded, weight: .semibold))
                                .monospacedDigit()
                            Text(explanation.unit)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(explanation.statusTitle)
                            .font(.caption2)
                            .foregroundStyle(explanation.isStale ? Color.orange : Color.secondary)
                        if let comparison = explanation.comparison {
                            Text(comparison)
                                .font(.caption2)
                        }
                    }

                    detailSection("这个指标是什么", text: explanation.explanation)
                    detailSection("怎样影响身体状态", text: explanation.influence)

                    if let sleepDetails, sleepDetails.hasStages {
                        sleepStages(sleepDetails)
                    }

                    if let sourceTitle = explanation.sourceTitle {
                        Text(sourceTitle)
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("采集时间").font(.caption.weight(.semibold))
                        if let sampledAt = explanation.sampledAt {
                            Text(AppDateTime.timestamp(sampledAt))
                        } else {
                            Text("尚无该指标的采集时间。")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func sleepStages(_ details: SleepDetails) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("真实睡眠片段").font(.caption2.weight(.semibold))
            GeometryReader { geometry in
                let span = max(1, details.endedAt.timeIntervalSince(details.startedAt))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.08))
                    ForEach(details.segments) { segment in
                        Rectangle()
                            .fill(stageColor(segment.stage))
                            .frame(width: max(1, geometry.size.width * segment.durationSeconds / span))
                            .offset(x: geometry.size.width * max(0, segment.start.timeIntervalSince(details.startedAt)) / span)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 16)
            .accessibilityHidden(true)
            ForEach(SleepStage.allCases.filter { details.duration(for: $0) > 0 }, id: \.self) { stage in
                HStack {
                    Circle().fill(stageColor(stage)).frame(width: 6, height: 6)
                    Text(stage.title)
                    Spacer(minLength: 3)
                    Text("\(Int((details.duration(for: stage) / 60).rounded())) 分钟")
                        .monospacedDigit()
                }
                .font(.caption2)
            }
            Text(details.sourceTitle)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stageColor(_ stage: SleepStage) -> Color {
        switch stage {
        case .awake: return .orange
        case .core: return .blue
        case .deep: return .indigo
        case .rem: return .cyan
        case .unspecified: return .gray
        }
    }

    private func detailSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
