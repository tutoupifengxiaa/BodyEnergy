import Foundation
import Combine
import SwiftUI

@MainActor
final class WatchEnergyViewModel: ObservableObject {
    @Published private(set) var snapshot: EnergySnapshot = .preview
    @Published private(set) var workoutRecommendation: WorkoutRecommendation = .preview
    @Published private(set) var metrics: WatchKeyMetricsSnapshot = .preview
    @Published private(set) var status: WatchEnergyStatus = .medium
    @Published private(set) var syncBadge: WatchSyncBadge = .waiting
    @Published private(set) var connectionNote: String = "等待 iPhone 同步"
    @Published private(set) var sampleScenarioTitle: String?
    @Published private(set) var sampleScenarioSummary: String?
    @Published private(set) var bodyStatus: BodyStatusDescriptor = .make(energyScore: EnergySnapshot.preview.energyScore)

    private let manager: WatchConnectivityManager
    private var cancellables: Set<AnyCancellable> = []

    convenience init() {
        self.init(manager: WatchConnectivityManager())
    }

    init(manager: WatchConnectivityManager) {
        self.manager = manager

        manager.$snapshot
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.snapshot = snapshot
                self.status = WatchEnergyStatus(score: snapshot.energyScore)
            }
            .store(in: &cancellables)

        manager.$workoutRecommendation
            .assign(to: &$workoutRecommendation)

        manager.$metrics
            .assign(to: &$metrics)

        manager.$syncBadge
            .assign(to: &$syncBadge)

        manager.$connectionNote
            .assign(to: &$connectionNote)

        manager.$sampleScenarioTitle
            .assign(to: &$sampleScenarioTitle)

        manager.$sampleScenarioSummary
            .assign(to: &$sampleScenarioSummary)

        manager.$bodyStatus
            .assign(to: &$bodyStatus)
    }

    func onAppear() {
        manager.activate()
        manager.requestLatest()
    }

    func refresh() {
        manager.requestLatest()
    }

    var shortRecommendation: String {
        workoutRecommendation.summary.shortened(limit: 72)
    }

    var recommendationTitle: String {
        workoutRecommendation.title
    }

    var recommendationDurationText: String {
        workoutRecommendation.durationText
    }

    var recommendationIntensityText: String {
        workoutRecommendation.intensityText
    }

    var compactSteps: [String] {
        Array(workoutRecommendation.steps.prefix(2))
    }

    var updatedTimeText: String {
        snapshot.updatedAt.formatted(date: .omitted, time: .shortened)
    }

    var syncStatusTitle: String {
        switch syncBadge {
        case .waiting:
            return "等待 iPhone 数据"
        case .active:
            return "已同步到当前状态"
        case .error:
            return "同步出现问题"
        }
    }

    var syncStatusDetail: String {
        switch syncBadge {
        case .waiting:
            return "打开 iPhone App 或下拉刷新后，会把最新数据推到手表。"
        case .active:
            return connectionNote
        case .error:
            return connectionNote
        }
    }

    var metricCards: [WatchMetricCard] {
        [
            WatchMetricCard(
                id: "recovery",
                title: "恢复值",
                value: "\(snapshot.recoveryScore)",
                unit: "分",
                note: recoveryInsight,
                tint: .blue,
                symbol: "heart.text.square"
            ),
            WatchMetricCard(
                id: "hrv",
                title: "HRV",
                value: "\(Int(metrics.heartRateVariabilityMS.rounded()))",
                unit: "ms",
                note: hrvInsight,
                tint: .cyan,
                symbol: "waveform.path.ecg"
            ),
            WatchMetricCard(
                id: "resting",
                title: "静息心率",
                value: "\(Int(metrics.restingHeartRateBPM.rounded()))",
                unit: "bpm",
                note: restingHeartRateInsight,
                tint: .pink,
                symbol: "heart.fill"
            ),
            WatchMetricCard(
                id: "sleep",
                title: "睡眠",
                value: String(format: "%.1f", metrics.sleepHours),
                unit: "小时",
                note: sleepInsight,
                tint: .indigo,
                symbol: "bed.double.fill"
            ),
            WatchMetricCard(
                id: "currentHeartRate",
                title: "当前心率",
                value: "\(Int(metrics.heartRateBPM.rounded()))",
                unit: "bpm",
                note: heartRateInsight,
                tint: .red,
                symbol: "bolt.heart.fill"
            ),
            WatchMetricCard(
                id: "activity",
                title: "活动消耗",
                value: "\(Int(metrics.activeEnergyKcal.rounded()))",
                unit: "千卡",
                note: activityInsight,
                tint: .green,
                symbol: "flame.fill"
            ),
            WatchMetricCard(
                id: "stress",
                title: "压力",
                value: "\(metrics.stressScore)",
                unit: "分",
                note: metrics.stressLevelTitle,
                tint: stressTint,
                symbol: "brain.head.profile"
            )
        ]
    }

    private var recoveryInsight: String {
        if snapshot.recoveryScore >= 75 {
            return "恢复储备较足"
        }
        if snapshot.recoveryScore >= 50 {
            return "恢复处于中段"
        }
        return "恢复优先"
    }

    private var hrvInsight: String {
        if metrics.heartRateVariabilityMS >= 65 {
            return "波动良好"
        }
        if metrics.heartRateVariabilityMS >= 40 {
            return "处于常见区间"
        }
        return "偏低，留意压力"
    }

    private var restingHeartRateInsight: String {
        if metrics.restingHeartRateBPM <= 58 {
            return "静息负担较轻"
        }
        if metrics.restingHeartRateBPM <= 66 {
            return "整体平稳"
        }
        return "偏高，先看恢复"
    }

    private var sleepInsight: String {
        if metrics.sleepHours >= 8 {
            return "睡眠很充足"
        }
        if metrics.sleepHours >= 6.5 {
            return "睡眠基本达标"
        }
        return "睡眠偏少"
    }

    private var heartRateInsight: String {
        if metrics.heartRateBPM <= 85 {
            return "当前较平稳"
        }
        if metrics.heartRateBPM <= 110 {
            return "略有活动负荷"
        }
        return "当前负荷偏高"
    }

    private var activityInsight: String {
        if metrics.activeEnergyKcal >= 900 {
            return "活动量较高"
        }
        if metrics.activeEnergyKcal >= 450 {
            return "活动量适中"
        }
        return "今天还比较轻"
    }

    private var stressTint: Color {
        switch metrics.stressScore {
        case 0..<30:
            return .green
        case 30..<55:
            return .yellow
        case 55..<75:
            return .orange
        default:
            return .red
        }
    }
}

enum WatchEnergyStatus {
    case high
    case medium
    case low

    init(score: Int) {
        switch score {
        case 70...100:
            self = .high
        case 40..<70:
            self = .medium
        default:
            self = .low
        }
    }

    var title: String {
        switch self {
        case .high:
            return "高"
        case .medium:
            return "中"
        case .low:
            return "低"
        }
    }

    var color: Color {
        switch self {
        case .high:
            return .green
        case .medium:
            return .yellow
        case .low:
            return .red
        }
    }
}

private extension String {
    func shortened(limit: Int) -> String {
        guard count > limit else { return self }
        let cutoffIndex = index(startIndex, offsetBy: max(limit - 3, 0))
        return String(self[..<cutoffIndex]) + "..."
    }
}
