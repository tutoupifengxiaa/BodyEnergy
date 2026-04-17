import Foundation
import WatchConnectivity
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    @Published private(set) var snapshot: EnergySnapshot = .preview
    @Published private(set) var workoutRecommendation: WorkoutRecommendation = .preview
    @Published private(set) var metrics: WatchKeyMetricsSnapshot = .preview
    @Published private(set) var syncBadge: WatchSyncBadge = .waiting
    @Published private(set) var connectionNote: String = "等待 iPhone 同步"
    @Published private(set) var sampleScenarioTitle: String?
    @Published private(set) var sampleScenarioSummary: String?
    @Published private(set) var bodyStatus: BodyStatusDescriptor = .make(energyScore: EnergySnapshot.preview.energyScore)

    private let session: WCSession?

    override init() {
        if WCSession.isSupported() {
            self.session = WCSession.default
        } else {
            self.session = nil
        }
        super.init()
        session?.delegate = self
    }

    func activate() {
        guard let session else {
            syncBadge = .error
            connectionNote = "当前设备不支持 WatchConnectivity"
            return
        }

        syncBadge = .waiting
        connectionNote = "正在连接 iPhone"
        session.activate()
    }

    func requestLatest() {
        guard let session else { return }

        if let payload = WatchSyncPayload(applicationContext: session.receivedApplicationContext) {
            apply(payload, note: "已接收 iPhone 同步", syncBadge: .active)
        }

        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["request": "latestEnergy"], replyHandler: nil) { _ in }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                syncBadge = .error
                connectionNote = "同步失败：\(error.localizedDescription)"
                return
            }

            if activationState == .activated {
                syncBadge = .active
                if let payload = WatchSyncPayload(applicationContext: session.receivedApplicationContext) {
                    apply(payload, note: "已接收 iPhone 同步", syncBadge: .active)
                } else {
                    connectionNote = "已连接，等待 iPhone 发送数据"
                }
                requestLatest()
            } else {
                syncBadge = .waiting
                connectionNote = "连接中"
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let payload = WatchSyncPayload(applicationContext: applicationContext) else { return }
        Task { @MainActor in
            apply(
                payload,
                note: "最近更新 \(payload.updatedAt.formatted(date: .omitted, time: .shortened))",
                syncBadge: .active
            )
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let payload = WatchSyncPayload(applicationContext: message) else { return }
        Task { @MainActor in
            apply(payload, note: "刚刚从 iPhone 实时更新", syncBadge: .active)
        }
    }
}

private extension WatchConnectivityManager {
    func apply(_ payload: WatchSyncPayload, note: String, syncBadge: WatchSyncBadge) {
        snapshot = payload.asSnapshot
        workoutRecommendation = payload.workoutRecommendation
        if let metrics = payload.metrics {
            self.metrics = metrics
        }
        if let bodyStatus = payload.bodyStatus {
            self.bodyStatus = bodyStatus
        } else {
            self.bodyStatus = .make(energyScore: payload.energyScore)
        }
        sampleScenarioTitle = payload.sampleScenarioTitle
        sampleScenarioSummary = payload.sampleScenarioSummary
        self.syncBadge = syncBadge
        connectionNote = note

        if let widgetSnapshot = payload.widgetSnapshot(fallback: WidgetMetricsStore.load()) {
            WidgetMetricsStore.save(widgetSnapshot)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

enum WatchSyncBadge {
    case waiting
    case active
    case error
}
