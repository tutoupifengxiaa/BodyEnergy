import Combine
import Foundation
import SwiftUI

@MainActor
final class WatchEnergyViewModel: ObservableObject {
    @Published private(set) var snapshot: EnergySnapshot = .empty
    @Published private(set) var workoutRecommendation: WorkoutRecommendation = .empty
    @Published private(set) var metrics: WatchKeyMetricsSnapshot = .empty
    @Published private(set) var status: WatchEnergyStatus = .medium
    @Published private(set) var syncBadge: WatchSyncBadge = .waiting
    @Published private(set) var connectionNote: String = "等待 iPhone 同步"
    @Published private(set) var bodyStatus: BodyStatusDescriptor = .make(energyScore: EnergySnapshot.empty.energyScore)

    @Published private(set) var hasScore = false
    @Published private(set) var validUntil: Date?
    @Published private(set) var history: [DailyMetrics] = []
    @Published private(set) var hourlyStress: [HourlyStress] = []
    @Published private(set) var receivedAt: Date?
    @Published private(set) var lastPhoneSyncAt: Date?
    @Published private(set) var lastLocalRefreshAt: Date?
    @Published private(set) var isRefreshingHealth = false
    @Published private(set) var localRefreshNote: String?
    @Published private(set) var phoneSyncNote: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var pressure: StressSnapshot?
    @Published private(set) var notificationDestination: String?

    var hasPressure: Bool { pressure != nil }
    var pressureHistory: [DailyMetrics] {
        history.map { $0.matchingPressureMetric(pressure?.hrvMetric ?? metrics.health?.pressureMeasurement?.metric ?? .sdnn) }
    }
    var isPressureStale: Bool { pressure?.isStale ?? true }
    var pressureHRVTitle: String { displayedPressureMeasurement?.metric.title ?? HRVMetric.sdnn.title }
    var pressureHRVValue: String {
        guard let measurement = displayedPressureMeasurement else { return explanation(for: .hrv).value }
        return "\(Int(measurement.hrvMS.rounded()))"
    }

    var pressureDataStatus: PressureDataStatus {
        PressureDataStatus(health: metrics.health ?? .empty, pressure: pressure)
    }

    func explanation(for metric: HealthInsightMetric) -> HealthMetricExplanation {
        HealthMetricExplanation(metric: metric, health: metrics.health ?? .empty, pressure: pressure,
                                recoveryScore: hasScore ? snapshot.recoveryScore : nil,
                                recoveryUpdatedAt: hasScore ? snapshot.updatedAt : nil,
                                recoveryIsStale: isStale)
    }

    private var displayedPressureMeasurement: PressureMeasurement? {
        guard let measurement = metrics.health?.pressureMeasurement else { return nil }
        if let pressure {
            guard measurement.metric == (pressure.hrvMetric ?? .sdnn),
                  measurement.sampledAt == pressure.updatedAt else { return nil }
        }
        return measurement
    }

    var isStale: Bool { statusMessage != nil || (validUntil.map { $0 < Date.now } ?? true) }
    var hasCurrentRecommendation: Bool { hasScore && !isStale }
    var displayedWorkoutRecommendation: WorkoutRecommendation {
        guard hasCurrentRecommendation else { return .generalActivity }
        let raw = EnergyScorer().computeScores(input: EnergyInput(snapshot: metrics.health ?? .empty))
        let scores = EnergyScores(recoveryScore: snapshot.recoveryScore, energyScore: snapshot.energyScore,
            trainingLoadScore: raw.trainingLoadScore, trainingLoadAvailable: raw.trainingLoadAvailable)
        return RecommendationEngine().plan(for: scores, preferences: activities.preferences.settings.training)
    }

    private let manager: WatchConnectivityManager
    private var cancellables: Set<AnyCancellable> = []

    var activities: ActivityStore { manager.activities }
    var appStore: AppStore { manager.appStore }

    convenience init() {
        self.init(manager: WatchConnectivityManager())
    }

    init(manager: WatchConnectivityManager) {
        self.manager = manager
        manager.activities.preferences.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        manager.$hasScore.assign(to: &$hasScore)
        manager.$validUntil.assign(to: &$validUntil)
        manager.$history.assign(to: &$history)
        manager.$hourlyStress.assign(to: &$hourlyStress)
        manager.$receivedAt.assign(to: &$receivedAt)
        manager.$lastPhoneSyncAt.assign(to: &$lastPhoneSyncAt)
        manager.$lastLocalRefreshAt.assign(to: &$lastLocalRefreshAt)
        manager.$isRefreshingHealth.assign(to: &$isRefreshingHealth)
        manager.$localRefreshNote.assign(to: &$localRefreshNote)
        manager.$phoneSyncNote.assign(to: &$phoneSyncNote)
        manager.$statusMessage.assign(to: &$statusMessage)
        manager.$pressure.assign(to: &$pressure)
        manager.$notificationDestination.assign(to: &$notificationDestination)

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

        manager.$bodyStatus
            .assign(to: &$bodyStatus)
    }

    func onAppear() {
        manager.activate()
    }

    func refresh() {
        manager.requestLatest()
    }

    func clearNotificationDestination() { manager.clearNotificationDestination() }

    var shortRecommendation: String {
        displayedWorkoutRecommendation.summary.shortened(limit: 72)
    }

    var recommendationTitle: String {
        displayedWorkoutRecommendation.title
    }

    var recommendationDurationText: String {
        displayedWorkoutRecommendation.durationText
    }

    var recommendationIntensityText: String {
        displayedWorkoutRecommendation.intensityText
    }

    var compactSteps: [String] {
        Array(displayedWorkoutRecommendation.steps.prefix(2))
    }

    var updatedTimeText: String {
        AppDateTime.time(snapshot.updatedAt)
    }

    var syncStatusTitle: String {
        switch syncBadge {
        case .waiting, .connected:
            return "等待 iPhone 数据"
        case .active:
            return "已同步到当前状态"
        case .error:
            return "同步出现问题"
        }
    }

    var syncStatusDetail: String {
        switch syncBadge {
        case .waiting, .connected:
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
                title: "晨间恢复",
                value: explanation(for: .recovery).value,
                unit: "分",
                note: recoveryInsight,
                tint: .blue,
                symbol: "heart.text.square"
            ),
            WatchMetricCard(
                id: "hrv",
                title: "HRV · SDNN",
                value: explanation(for: .hrv).value,
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
                title: "最近心率",
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
                note: stressMoodTitle,
                tint: stressTint,
                symbol: "brain.head.profile"
            )
        ]
    }

    var stressMoodTitle: String {
        stressMoodTitle(for: metrics.stressScore)
    }

    var stressMoodDetail: String {
        stressMoodDetail(for: metrics.stressScore)
    }

    func stressTint(for score: Int) -> Color {
        switch score {
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

    func stressMoodTitle(for score: Int) -> String {
        switch score {
        case 0..<30:
            return "压力较低"
        case 30..<55:
            return "压力适中"
        case 55..<75:
            return "压力较高"
        default:
            return "压力很高"
        }
    }

    func stressMoodDetail(for score: Int) -> String {
        switch score {
        case 0..<30:
            return "压力较低，保持当前节奏。"
        case 30..<55:
            return "压力适中，适时休息。"
        case 55..<75:
            return "压力较高，放慢节奏。"
        default:
            return "压力很高，优先安排休息。"
        }
    }

    func stressTrendNote(for score: Int) -> String {
        let delta = score - metrics.stressScore
        if delta == 0 {
            return "和当前压力基本持平。"
        }
        if delta > 0 {
            return "比当前高\(delta)分。"
        }
        return "比当前低\(abs(delta))分。"
    }

    private var recoveryInsight: String {
        let detail = explanation(for: .recovery)
        guard !detail.isStale, let score = Int(detail.value) else { return detail.statusTitle }
        if score >= 75 {
            return "恢复储备较足"
        }
        if score >= 50 {
            return "恢复处于中段"
        }
        return "恢复优先"
    }

    private var hrvInsight: String {
        let detail = explanation(for: .hrv)
        return detail.comparison ?? detail.statusTitle
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
        stressTint(for: metrics.stressScore)
    }


}

struct WatchStressTrendPoint: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let detailTitle: String
    let score: Int
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
