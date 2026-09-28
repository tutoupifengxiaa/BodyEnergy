import Foundation
import SwiftUI

struct HealthMetricDetailView: View {
    let explanation: HealthMetricExplanation
    var activities: ActivityStore? = nil
    var isPressure = false
    var refreshedAt: Date? = nil
    var synchronizedAt: Date? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingBreathing = false
    @State private var isShowingCheckIn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                readingCard
                if isPressure, activities != nil { pressureActions }
                if let comparison = explanation.comparison {
                    textCard("个人基线", text: comparison)
                }
                textCard("指标说明", text: explanation.explanation)
                textCard("对电量与恢复的影响", text: explanation.influence)
                sampleCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(explanation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("关闭") { dismiss() }
            }
        }
        .sheet(isPresented: $isShowingBreathing) {
            if let activities { ActivitySessionView(store: activities) }
        }
        .sheet(isPresented: $isShowingCheckIn) {
            if let activities { FeelingCheckInView(store: activities) }
        }
    }

    private var readingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("指标值")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(explanation.value)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Text(explanation.unit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(explanation.statusTitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(explanation.isStale ? Color.orange : Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(cardBackground)
    }

    private var sampleCard: some View {
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
            if let sourceTitle = explanation.sourceTitle {
                Text(sourceTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("采集时间来自该指标的实际健康记录。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(cardBackground)
    }

    private var pressureActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("此刻可以做什么").font(.headline)
            Button { isShowingBreathing = true } label: {
                Label("呼吸 \(activities?.preferences.settings.breathingMinutes ?? 1) 分钟", systemImage: "wind")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { isShowingCheckIn = true } label: {
                Label("记录感受", systemImage: "face.smiling")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
        .buttonStyle(.bordered)
        .padding(20)
        .background(cardBackground)
    }

    private func textCard(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
    }
}
