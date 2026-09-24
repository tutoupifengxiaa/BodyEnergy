import Foundation
import WatchConnectivity
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    @Published private(set) var snapshot: EnergySnapshot = .empty
    @Published private(set) var workoutRecommendation: WorkoutRecommendation = .empty
    @Published private(set) var metrics: WatchKeyMetricsSnapshot = .empty
    @Published private(set) var syncBadge: WatchSyncBadge = .waiting
    @Published private(set) var connectionNote: String = "等待 iPhone 同步"
    @Published private(set) var bodyStatus: BodyStatusDescriptor = .make(energyScore: EnergySnapshot.empty.energyScore)

    @Published private(set) var hasScore = false
    @Published private(set) var validUntil: Date?
    @Published private(set) var history: [DailyMetrics] = []
    @Published private(set) var hourlyStress: [HourlyStress] = []
    @Published private(set) var receivedAt: Date?
    @Published private(set) var statusMessage: String?
    @Published private(set) var pressure: StressSnapshot?
    private var latestPayload: WatchSyncPayload?
    private let cacheKey = "watch.real.payload.v2"
    private let session: WCSession?
    private var requestsLatestAfterActivation = false

    override init() {
        if WCSession.isSupported() {
            self.session = WCSession.default
        } else {
            self.session = nil
        }
        super.init()
        session?.delegate = self
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let payload = try? JSONDecoder().decode(WatchSyncPayload.self, from: data), !payload.isSampleData {
            let receipt = UserDefaults.standard.object(forKey: "watch.real.receivedAt.v1") as? Date ?? payload.sentAt
            apply(payload, note: "上次同步记录", syncBadge: .active, receivedAt: receipt)
        }
    }

    func activate(requestLatest: Bool = true) {
        guard let session else {
            syncBadge = .error
            connectionNote = "当前设备不支持 WatchConnectivity"
            return
        }

        if requestLatest { requestsLatestAfterActivation = true }
        if session.activationState == .activated {
            if requestLatest { self.requestLatest() }
        } else {
            if receivedAt == nil { syncBadge = .waiting }
            connectionNote = "正在连接 iPhone"
            session.activate()
        }
    }

    func requestLatest() {
        guard let session else { return }
        requestsLatestAfterActivation = true
        guard session.activationState == .activated else { session.activate(); return }
        requestsLatestAfterActivation = false

        if let payload = WatchSyncPayload(applicationContext: session.receivedApplicationContext) {
            apply(payload, note: "已接收 iPhone 同步", syncBadge: .active)
        }

        guard session.isReachable else {
            queueBackgroundRequest()
            syncBadge = receivedAt == nil ? .waiting : .active
            connectionNote = receivedAt == nil ? "已排队，连接后自动同步" : "显示上次记录，连接后自动更新"
            return
        }
        let requestedAt = Date.now
        connectionNote = "正在请求最新健康数据"
        session.sendMessage(["request": "latestEnergy"], replyHandler: { [weak self] message in
            guard let payload = WatchSyncPayload(applicationContext: message) else { return }
            Task { @MainActor in self?.apply(payload, note: "已接收 iPhone 同步", syncBadge: .active) }
        }) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.receivedAt.map({ $0 < requestedAt }) ?? true else { return }
                self.queueBackgroundRequest()
                self.syncBadge = self.receivedAt == nil ? .waiting : .active
                self.connectionNote = "已排队，稍后自动同步"
            }
        }
    }

    private func queueBackgroundRequest() {
        guard let session, session.activationState == .activated else { return }
        guard !session.outstandingUserInfoTransfers.contains(where: {
            $0.userInfo["request"] as? String == "latestEnergy"
        }) else { return }
        session.transferUserInfo(["request": "latestEnergy"])
    }

    func receiveBackgroundUpdates() async {
        guard let session else { return }
        if session.activationState != .activated { session.activate() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while session.activationState != .activated || session.hasContentPending {
            guard ContinuousClock.now < deadline, !Task.isCancelled else { return }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
        // Persist the delivered context before returning background execution time to watchOS.
        if let payload = WatchSyncPayload(applicationContext: session.receivedApplicationContext) {
            apply(payload, note: "已自动同步", syncBadge: .active)
            UserDefaults.standard.set(Date.now, forKey: "watch.lastBackgroundReceipt")
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.requestLatest() }
    }

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
                syncBadge = receivedAt == nil ? .connected : .active
                if let payload = WatchSyncPayload(applicationContext: session.receivedApplicationContext) {
                    apply(payload, note: "已接收 iPhone 同步", syncBadge: .active)
                } else {
                    connectionNote = "已连接，等待 iPhone 发送数据"
                }
                if requestsLatestAfterActivation { requestLatest() }
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
    func apply(_ payload: WatchSyncPayload, note: String, syncBadge: WatchSyncBadge, receivedAt: Date = .now) {
        guard !payload.isSampleData, payload.sampleScenarioTitle == nil else { return }
        if let latestPayload, payload.sentAt < latestPayload.sentAt { return }
        self.syncBadge = syncBadge
        connectionNote = payload.statusMessage ?? note
        guard payload.isNewer(than: latestPayload) else { return }
        latestPayload = payload
        hasScore = payload.hasScore
        validUntil = payload.validUntil
        statusMessage = payload.statusMessage
        pressure = payload.availableStress
        history = payload.history
        hourlyStress = payload.hourlyStress ?? []
        self.receivedAt = receivedAt
        snapshot = payload.asSnapshot
        workoutRecommendation = payload.workoutRecommendation
        self.metrics = payload.metrics ?? .empty
        if let bodyStatus = payload.bodyStatus {
            self.bodyStatus = bodyStatus
        } else {
            self.bodyStatus = .make(energyScore: payload.energyScore)
        }
        self.syncBadge = syncBadge
        connectionNote = payload.statusMessage ?? note

        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(receivedAt, forKey: "watch.real.receivedAt.v1")
        }
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
    case connected
    case active
    case error
}
