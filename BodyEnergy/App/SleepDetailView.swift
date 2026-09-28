import Foundation
import SwiftUI

struct SleepDetailView: View {
    let health: HealthSnapshot
    @Environment(\.dismiss) private var dismiss

    private var explanation: HealthMetricExplanation {
        HealthMetricExplanation(metric: .sleep, health: health, pressure: nil, recoveryScore: nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard
                if let details = health.sleepDetails {
                    periodCard(details)
                    if !details.segments.isEmpty { segmentsCard(details) }
                    if details.hasStages {
                        stagesCard(details)
                    } else {
                        noteCard("当前来源提供睡眠总时长，尚无核心、深睡或 REM 分期记录。")
                    }
                } else {
                    noteCard("健康记录暂未提供可展示的睡眠片段。")
                }
                noteCard(explanation.influence)
                dataTimeCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("睡眠详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("关闭") { dismiss() }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("有效睡眠", systemImage: "moon.zzz.fill")
                .font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(explanation.value)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Text(explanation.unit).foregroundStyle(.secondary)
            }
            Text(explanation.statusTitle)
                .font(.caption)
                .foregroundStyle(explanation.isStale ? Color.orange : Color.secondary)
        }
        .sleepCard()
    }

    private func periodCard(_ details: SleepDetails) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("睡眠区间").font(.headline)
            Text("开始 \(AppDateTime.timestamp(details.startedAt))")
            Text("结束 \(AppDateTime.timestamp(details.endedAt))")
            Text("来源：\(details.sourceTitle)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .sleepCard()
    }

    private func segmentsCard(_ details: SleepDetails) -> some View {
        let span = max(1, details.endedAt.timeIntervalSince(details.startedAt))
        return VStack(alignment: .leading, spacing: 14) {
            Text("睡眠片段").font(.headline)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.10))
                    ForEach(Array(details.segments.enumerated()), id: \.offset) { _, segment in
                        let offset = max(0, segment.start.timeIntervalSince(details.startedAt)) / span
                        let duration = max(0, segment.end.timeIntervalSince(segment.start)) / span
                        Rectangle()
                            .fill(stageColor(segment.stage))
                            .frame(width: geometry.size.width * min(duration, 1 - min(offset, 1)))
                            .offset(x: geometry.size.width * min(offset, 1))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 22)
            HStack {
                Text(AppDateTime.time(details.startedAt))
                Spacer()
                Text(AppDateTime.time(details.endedAt))
            }
            .font(.caption2).foregroundStyle(.secondary)
            ForEach(Array(details.segments.enumerated()), id: \.offset) { _, segment in
                HStack(spacing: 10) {
                    Circle().fill(stageColor(segment.stage)).frame(width: 8, height: 8)
                    Text(segment.stage.title)
                    Spacer()
                    Text("\(AppDateTime.time(segment.start))–\(AppDateTime.time(segment.end))")
                        .monospacedDigit()
                }
                .font(.caption)
            }
            Text("浅色空隙表示没有对应记录。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .sleepCard()
    }

    private func stagesCard(_ details: SleepDetails) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("阶段时长").font(.headline)
            ForEach([SleepStage.core, .deep, .rem, .awake, .unspecified], id: \.self) { stage in
                let duration = details.duration(for: stage)
                if duration > 0 {
                    HStack {
                        Circle().fill(stageColor(stage)).frame(width: 8, height: 8)
                        Text(stage.title)
                        Spacer()
                        Text(durationText(duration)).monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
        }
        .sleepCard()
    }

    private func noteCard(_ text: String) -> some View {
        Text(text)
            .font(.subheadline).foregroundStyle(.secondary)
            .sleepCard()
    }

    private var dataTimeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("采集时间", systemImage: "clock")
                .font(.headline)
            if let sampledAt = explanation.sampledAt {
                Text(AppDateTime.timestamp(sampledAt))
                    .font(.subheadline)
                    .monospacedDigit()
            } else {
                Text("暂无实际采样记录")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .sleepCard()
    }

    private func durationText(_ seconds: Double) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分钟" : "\(minutes) 分钟"
    }

    private func stageColor(_ stage: SleepStage) -> Color {
        switch stage {
        case .awake: return .orange
        case .core: return .blue
        case .deep: return .indigo
        case .rem: return .teal
        case .unspecified: return .gray
        }
    }
}

private extension View {
    func sleepCard() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}
