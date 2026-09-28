import Foundation
import WatchConnectivity
import WatchKit
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    let activities = ActivityStore(source: .appleWatch)
    private lazy var habitStore = RecoveryHabitStore(preferences: activities.preferences)
    var appStore: AppStore { makeLocalStoreIfNeeded() }
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
    @Published private(set) var lastPhoneSyncAt: Date?
    @Published private(set) var isRefreshingHealth = false
    @Published private(set) var lastLocalRefreshAt: Date?
    @Published private(set) var localRefreshNote: String?
    @Published private(set) var phoneSyncNote: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var pressure: StressSnapshot?
    @Published private(set) var notificationDestination: String?
    private lazy var stressAlerts: WatchStressAlertCoordinator = {
        let coordinator = WatchStressAlertCoordinator(preferences: activities.preferences)
        coordinator.onOpenDestination = { [weak self] in self?.notificationDestination = $0 }
        return coordinator
    }()
    private var latestPayload: WatchSyncPayload?
    private var latestLocalHealthPayload: WatchSyncPayload?
    private var lastLiveHealthPayloadData: Data?
    private let cacheKey = "watch.real.payload.v2"
    private let localHealthCacheKey = "watch.outgoing.health.payload.v1"
    private let session: WCSession?
    private var requestsLatestAfterActivation = false
    private var localStore: AppStore?
    private var localHealthManager: HealthManager?
    private var localRefreshTask: Task<Void, Never>?
    private var requestedLocalAuthorization = false
    private var localAuthorizationPending = false
    private var phonePressureReference: PressureMeasurement?
    private var lastPhoneSyncStateAt: TimeInterval = 0
    private var lastPhonePayloadSentAt: TimeInterval = 0

    private var hasLocalMeasurements: Bool {
        latestPayload?.collectionSource == .appleWatch && latestPayload.flatMap(measurementDate) != nil
    }

    override init() {
        if WCSession.isSupported() {
            self.session = WCSession.default
        } else {
            self.session = nil
        }
        super.init()
        activities.onRecordsChanged = { [weak self] _ in
            self?.sendActivityRecords()
        }
        activities.preferences.onChanged = { [weak self] _ in
            self?.sendUserFeatures()
            self?.stressAlerts.activate()
        }
        habitStore.onChanged = { [weak self] _ in self?.sendUserFeatures() }
        lastPhoneSyncStateAt = UserDefaults.standard.double(forKey: "watch.phone.syncStateAt.v1")
        lastLocalRefreshAt = UserDefaults.standard.object(forKey: "watch.local.lastRefreshAt.v1") as? Date
        if lastLocalRefreshAt != nil { localRefreshNote = "上次本机读取完成" }
        lastPhoneSyncAt = UserDefaults.standard.object(forKey: "watch.phone.lastReceipt.v1") as? Date
        lastPhonePayloadSentAt = UserDefaults.standard.double(forKey: "watch.phone.lastSentAt.v1")
        switch UserDefaults.standard.string(forKey: "watch.lastPhoneSyncState.v1") {
        case "waitingForUnlock": phoneSyncNote = "iPhone 健康数据暂不可读，解锁手机后自动同步。"
        case "updating": phoneSyncNote = "上次 iPhone 刷新仍待完成。"
        default: if lastPhoneSyncAt != nil { phoneSyncNote = "上次已接收 iPhone 数据。" }
        }
        if let data = UserDefaults.standard.data(forKey: "watch.phone.pressureReference.v1") {
            phonePressureReference = try? JSONDecoder().decode(PressureMeasurement.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: localHealthCacheKey),
           let payload = try? JSONDecoder().decode(WatchSyncPayload.self, from: data),
           payload.collectionSource == .appleWatch, !payload.isSampleData, payload.sampleScenarioTitle == nil {
            latestLocalHealthPayload = payload
        }
        session?.delegate = self
        if let data = UserDefaults.standard.data(forKey: cacheKey),
            let payload = try? JSONDecoder().decode(WatchSyncPayload.self, from: data), !payload.isSampleData {
            if latestLocalHealthPayload == nil, payload.collectionSource == .appleWatch,
               payload.sampleScenarioTitle == nil {
                latestLocalHealthPayload = payload
                UserDefaults.standard.set(data, forKey: localHealthCacheKey)
            }
            let receipt = UserDefaults.standard.object(forKey: "watch.real.receivedAt.v1") as? Date ?? payload.sentAt
            apply(payload, note: payload.collectionSource == .appleWatch ? "上次本机记录" : "上次同步记录",
                  syncBadge: .active, receivedAt: receipt, allowsStressAlert: false)
        }
    }

    func activate(requestLatest: Bool = true) {
        stressAlerts.activate()
        _ = makeLocalStoreIfNeeded()
        if requestLatest { refreshLocalHealthData(allowAuthorization: true) }
        guard let session else {
            return
        }

        if requestLatest { requestsLatestAfterActivation = true }
        if session.activationState == .activated {
            sendActivityRecords()
            sendUserFeatures()
            sendLatestLocalHealthPayload()
            if requestLatest { self.requestLatest() }
        } else {
            if requestLatest { phoneSyncNote = "正在连接 iPhone。" }
            if receivedAt == nil { syncBadge = .waiting }
            if !hasLocalMeasurements { connectionNote = "正在读取手表健康数据" }
            session.activate()
        }
    }

    func requestLatest() {
        refreshLocalHealthData(allowAuthorization: true)
        guard let session else { phoneSyncNote = "iPhone 同步当前不可用。"; return }
        requestsLatestAfterActivation = true
        guard session.activationState == .activated else {
            phoneSyncNote = "正在连接 iPhone。"
            session.activate()
            return
        }
        requestsLatestAfterActivation = false

        if let payload = WatchSyncPayload(applicationContext: session.receivedApplicationContext) {
            apply(payload, note: "已接收 iPhone 同步", syncBadge: .active)
        }

        guard session.isReachable else {
            queueBackgroundRequest()
            phoneSyncNote = "iPhone 暂不可达，刷新请求已排队。"
            guard !hasLocalMeasurements else { return }
            syncBadge = receivedAt == nil ? .waiting : .active
            connectionNote = "正在读取手表健康数据"
            return
        }
        let requestedAt = Date.now
        phoneSyncNote = "正在请求 iPhone 最新数据。"
        if !hasLocalMeasurements { connectionNote = "正在读取手表健康数据" }
        session.sendMessage(["request": "latestEnergy"], replyHandler: { [weak self] message in
            Task { @MainActor in self?.receive(message, note: "已接收 iPhone 同步") }
        }) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.lastPhoneSyncAt.map({ $0 < requestedAt }) ?? true else { return }
                self.queueBackgroundRequest()
                self.phoneSyncNote = "iPhone 暂未响应，刷新请求已排队。"
                guard !self.hasLocalMeasurements else { return }
                self.syncBadge = self.receivedAt == nil ? .waiting : .active
                self.connectionNote = "手表健康数据待补充"
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

    private func sendActivityRecords() {
        guard !activities.records.isEmpty, let session else { return }
        guard session.activationState == .activated else {
            session.activate()
            return
        }
        let message = ActivityRecordsMessage.applicationContext(records: activities.records)
        guard let encodedRecords = message["activityRecordsV1"] as? Data else { return }
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: { _ in })
        }
        let pending = session.outstandingUserInfoTransfers.filter {
            $0.userInfo["activityRecordsV1"] is Data
        }
        guard !pending.contains(where: { $0.userInfo["activityRecordsV1"] as? Data == encodedRecords }) else { return }
        pending.forEach { $0.cancel() }
        session.transferUserInfo(message)
    }

    private func sendUserFeatures() {
        guard let session else { return }
        guard session.activationState == .activated else { session.activate(); return }
        let state = UserFeaturesState(preferences: activities.preferences.settings, habitDays: habitStore.days)
        let message = UserFeaturesMessage.applicationContext(state)
        guard let data = message[UserFeaturesMessage.key] as? Data else { return }
        if session.isReachable { session.sendMessage(message, replyHandler: nil, errorHandler: { _ in }) }
        let pending = session.outstandingUserInfoTransfers.filter { $0.userInfo[UserFeaturesMessage.key] is Data }
        guard !pending.contains(where: { $0.userInfo[UserFeaturesMessage.key] as? Data == data }) else { return }
        pending.forEach { $0.cancel() }
        session.transferUserInfo(message)
    }

    private func publishLocalHealthPayload(_ payload: WatchSyncPayload) {
        guard payload.collectionSource == .appleWatch, !payload.isSampleData, payload.sampleScenarioTitle == nil,
              payload.metrics?.health?.measuredAt != nil || payload.availableStress != nil else { return }
        if var previous = latestLocalHealthPayload {
            if let previousStress = previous.availableStress,
               payload.availableStress.map({ $0.updatedAt < previousStress.updatedAt }) ?? true {
                sendLatestLocalHealthPayload()
                return
            }
            previous.sentAt = payload.sentAt
            previous.activityRecords = payload.activityRecords
            previous.userFeatures = payload.userFeatures
            if previous == payload { return }
        }
        latestLocalHealthPayload = payload
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: localHealthCacheKey)
        }
        sendLatestLocalHealthPayload()
    }

    private func sendLatestLocalHealthPayload(forceLiveSend: Bool = false) {
        guard let session, let payload = latestLocalHealthPayload else { return }
        guard session.activationState == .activated else { session.activate(); return }
        var message = payload.applicationContext
        guard let data = message["payloadV2"] as? Data else { return }
        message["watchHealthUpdate"] = true
        for transfer in session.outstandingUserInfoTransfers
            where transfer.userInfo["watchHealthUpdate"] as? Bool == true && transfer.userInfo["payloadV2"] as? Data != data {
            transfer.cancel()
        }
        if session.applicationContext["payloadV2"] as? Data != data || session.applicationContext["watchHealthUpdate"] as? Bool != true {
            do {
                try session.updateApplicationContext(message)
            } catch {
                queueLatestLocalHealthPayload()
            }
        }
        guard session.isReachable else { queueLatestLocalHealthPayload(); return }
        guard forceLiveSend || lastLiveHealthPayloadData != data else { return }
        lastLiveHealthPayloadData = data
        session.sendMessage(message, replyHandler: nil) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.lastLiveHealthPayloadData == data { self.lastLiveHealthPayloadData = nil }
                self.queueLatestLocalHealthPayload()
            }
        }
    }

    private func queueLatestLocalHealthPayload() {
        guard let session, session.activationState == .activated, let payload = latestLocalHealthPayload else { return }
        var message = payload.applicationContext
        guard let data = message["payloadV2"] as? Data else { return }
        message["watchHealthUpdate"] = true
        let pending = session.outstandingUserInfoTransfers.filter { $0.userInfo["watchHealthUpdate"] as? Bool == true }
        let matching = pending.first { $0.userInfo["payloadV2"] as? Data == data }
        for transfer in pending where transfer !== matching { transfer.cancel() }
        if matching == nil { session.transferUserInfo(message) }
    }

    private func mergeUserFeatures(_ state: UserFeaturesState) {
        if let localStore { _ = localStore.mergeUserFeatures(state) }
        else {
            if let preferences = state.preferences { activities.preferences.merge(preferences) }
            habitStore.merge(state.habitDays ?? [])
        }
        stressAlerts.activate()
    }

    func clearNotificationDestination() { notificationDestination = nil }

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
        await stressAlerts.finishPendingAlerts()
    }

    private func makeLocalStoreIfNeeded() -> AppStore {
        if let localStore { return localStore }
        let historyStore = HealthHistoryStore()
        if let payload = latestPayload, payload.hasScore,
           let health = payload.metrics?.health, health.isUsable(at: .now),
           historyStore.load().last.map({ $0.energy.updatedAt < payload.updatedAt }) ?? true {
            historyStore.save(HealthRecord(health: health, energy: payload.asSnapshot,
                stressScore: payload.availableStress?.score, stressLevelTitle: payload.availableStress?.levelTitle,
                recommendation: payload.workoutRecommendation,
                batteryLevel: payload.availableBatteryAssessment?.level ?? Double(payload.energyScore),
                batteryAssessment: payload.availableBatteryAssessment))
            historyStore.saveLatestHealth(health)
        }
        let publisher = WatchLocalPublisher { [weak self] payload in
            self?.receiveLocal(payload)
        }
        let healthManager = HealthManager()
        healthManager.usePressureReference(phonePressureReference)
        localHealthManager = healthManager
        let store = AppStore(healthManager: healthManager, watchSyncPublisher: publisher,
                             historyStore: historyStore, activities: activities, habits: habitStore)
        localStore = store
        if let payload = latestPayload { store.applySyncedInsights(payload) }
        store.onAutomaticRefreshComplete = { [weak self] in await self?.stressAlerts.finishPendingAlerts() }
        store.startAutomaticUpdates()
        return store
    }

    private func refreshLocalHealthData(allowAuthorization: Bool) {
        let requestAuthorization = allowAuthorization && WKApplication.shared().applicationState == .active
            && !requestedLocalAuthorization
        guard localRefreshTask == nil else {
            localAuthorizationPending = localAuthorizationPending || requestAuthorization
            return
        }
        let store = makeLocalStoreIfNeeded()
        let previousMeasuredAt = store.health.measuredAt
        let previousPressureAt = store.pressure?.updatedAt
        localHealthManager?.usePressureReference(phonePressureReference)
        if requestAuthorization { requestedLocalAuthorization = true }
        isRefreshingHealth = true
        localRefreshNote = "正在读取手表健康数据。"
        if !hasLocalMeasurements { connectionNote = "正在读取手表健康数据" }
        localRefreshTask = Task { [weak self] in
            await store.refreshHealthData(requestAuthorization: requestAuthorization, followUpIfInFlight: false)
            guard let self else { return }
            self.localRefreshTask = nil
            self.isRefreshingHealth = false
            if store.lastRefreshSucceeded == true, let completedAt = store.lastRefreshAt {
                self.lastLocalRefreshAt = completedAt
                UserDefaults.standard.set(completedAt, forKey: "watch.local.lastRefreshAt.v1")
                let hasNewMeasurement = store.health.measuredAt.map { $0 > (previousMeasuredAt ?? .distantPast) } ?? false
                let hasNewPressure = store.pressure.map { !$0.isStale && $0.updatedAt > (previousPressureAt ?? .distantPast) } ?? false
                if let missingData = store.healthErrorMessage {
                    self.localRefreshNote = "本机读取完成，" + missingData
                } else if hasNewMeasurement || hasNewPressure {
                    self.localRefreshNote = "本机读取完成，已读取新采样。"
                } else {
                    self.localRefreshNote = "本机读取完成，暂无新采样。"
                }
            } else {
                self.localRefreshNote = "本机读取未完成，" + (store.healthErrorMessage ?? "保留上次记录，请稍后重试。")
            }
            if self.localAuthorizationPending {
                self.localAuthorizationPending = false
                self.refreshLocalHealthData(allowAuthorization: true)
            }
        }
    }

    private func receiveLocal(_ payload: WatchSyncPayload) {
        guard let refreshSucceeded = localStore?.lastRefreshSucceeded else { return }
        guard refreshSucceeded else {
            statusMessage = payload.statusMessage ?? "手表健康数据更新未完成"
            connectionNote = statusMessage ?? "手表健康数据更新未完成"
            syncBadge = .error
            return
        }
        guard payload.metrics?.health?.measuredAt != nil || payload.availableStress.map({ !$0.isStale }) == true else {
            if !hasLocalMeasurements {
                connectionNote = "手表健康数据待补充"
                if receivedAt == nil { syncBadge = .active }
            }
            return
        }
        let originalPayload = payload
        var payload = payload
        if let previous = latestPayload, previous.hasScore,
           !payload.hasScore || (payload.metrics?.health?.isUsable(at: .now) != true && previous.updatedAt > payload.updatedAt) {
            payload.energyScore = previous.energyScore
            payload.recoveryScore = previous.recoveryScore
            payload.recommendation = previous.recommendation
            payload.recommendationTitle = previous.recommendationTitle
            payload.recommendationDurationText = previous.recommendationDurationText
            payload.recommendationIntensityText = previous.recommendationIntensityText
            payload.recommendationSteps = previous.recommendationSteps
            payload.recommendationCaution = previous.recommendationCaution
            payload.recommendationPurpose = previous.recommendationPurpose
            payload.updatedAt = previous.updatedAt
            payload.validUntil = previous.validUntil
            payload.bodyStatus = previous.bodyStatus
            payload.hasScore = true
        }
        apply(payload, note: "手表本机更新", syncBadge: .active)
        publishLocalHealthPayload(originalPayload)
    }

    private func receive(_ message: [String: Any], note: String) {
        if let state = UserFeaturesMessage.state(from: message) { mergeUserFeatures(state); return }
        if let records = ActivityRecordsMessage.records(from: message) { activities.merge(records); return }
        let payload = WatchSyncPayload(applicationContext: message)
        let previousPhoneSentAt = lastPhonePayloadSentAt
        if let payload {
            apply(payload, note: note, syncBadge: .active, recordPhoneReceipt: true)
        }
        let receivedNewPayload = lastPhonePayloadSentAt > previousPhoneSentAt
        let phonePayload = payload.flatMap { payload -> WatchSyncPayload? in
            guard !payload.isSampleData, payload.sampleScenarioTitle == nil, payload.collectionSource != .appleWatch else { return nil }
            return payload
        }
        guard let stateAt = message["syncStateAt"] as? TimeInterval, stateAt.isFinite,
              let state = message["syncState"] as? String,
              ["updating", "waitingForUnlock", "complete"].contains(state) else {
            let previousState = UserDefaults.standard.string(forKey: "watch.lastPhoneSyncState.v1")
            if message["syncState"] == nil, message["syncStateAt"] == nil, let phonePayload,
               phonePayload.sentAt.timeIntervalSince1970.isFinite,
               phonePayload.sentAt <= Date.now.addingTimeInterval(300),
               phonePayload.sentAt.timeIntervalSince1970 >= lastPhoneSyncStateAt,
               previousState != "updating", previousState != "waitingForUnlock" {
                phoneSyncNote = phonePayload.statusMessage.map { "iPhone 读取结果：" + $0 }
                    ?? (receivedNewPayload ? "已接收 iPhone 新数据包。" : "已接收 iPhone 数据，暂无新的数据包。")
            }
            return
        }
        guard stateAt >= lastPhoneSyncStateAt else { return }
        lastPhoneSyncStateAt = stateAt
        UserDefaults.standard.set(stateAt, forKey: "watch.phone.syncStateAt.v1")
        UserDefaults.standard.set(state, forKey: "watch.lastPhoneSyncState.v1")
        if let errorCode = message["errorCode"] as? Int {
            UserDefaults.standard.set(errorCode, forKey: "watch.lastPhoneSyncErrorCode.v1")
        }
        switch state {
        case "updating": phoneSyncNote = "iPhone 正在读取健康数据。"
        case "waitingForUnlock": phoneSyncNote = "iPhone 健康数据暂不可读，解锁手机后自动同步。"
        case "complete":
            if let message = phonePayload?.statusMessage {
                phoneSyncNote = "iPhone 读取结果：" + message
            } else if receivedNewPayload {
                phoneSyncNote = phonePayload?.hasScore == true ? "已接收 iPhone 新数据包。" : "已接收 iPhone 新数据包，健康指标仍待补充。"
            } else {
                phoneSyncNote = "iPhone 已响应，暂无新的数据包。"
            }
        default: break
        }
        if !hasLocalMeasurements { connectionNote = phoneSyncNote ?? note }
    }

    private func measurementDate(_ payload: WatchSyncPayload) -> Date? {
        var dates = [payload.metrics?.health?.measuredAt, payload.availableStress?.updatedAt].compactMap { $0 }
        if payload.hasScore { dates.append(payload.updatedAt) }
        return dates.max()
    }

    private func rememberPhoneReference(_ payload: WatchSyncPayload) {
        guard payload.collectionSource != .appleWatch,
              payload.stressAlgorithmVersion == StressSnapshot.algorithmVersion,
              let reference = payload.metrics?.health?.pressureMeasurement,
              StressAnalyzer().isValid(measurement: reference),
              phonePressureReference.map({ $0.sampledAt <= reference.sampledAt }) ?? true else { return }
        phonePressureReference = reference
        localHealthManager?.usePressureReference(reference)
        if let data = try? JSONEncoder().encode(reference) {
            UserDefaults.standard.set(data, forKey: "watch.phone.pressureReference.v1")
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.sendLatestLocalHealthPayload(forceLiveSend: session.isReachable)
            guard session.isReachable else { return }
            self.sendActivityRecords()
            self.sendUserFeatures()
            self.requestLatest()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                phoneSyncNote = "iPhone 连接失败：\(error.localizedDescription)"
                guard !hasLocalMeasurements else { return }
                syncBadge = .error
                connectionNote = "同步失败：\(error.localizedDescription)"
                return
            }

            if activationState == .activated {
                syncBadge = receivedAt == nil ? .connected : .active
                if let payload = WatchSyncPayload(applicationContext: session.receivedApplicationContext) {
                    apply(payload, note: "已接收 iPhone 同步", syncBadge: .active)
                } else {
                    if !hasLocalMeasurements { connectionNote = "正在读取手表健康数据" }
                }
                sendActivityRecords()
                sendUserFeatures()
                sendLatestLocalHealthPayload(forceLiveSend: true)
                if requestsLatestAfterActivation { requestLatest() }
            } else {
                phoneSyncNote = "正在连接 iPhone。"
                guard !hasLocalMeasurements else { return }
                syncBadge = .waiting
                connectionNote = "连接中"
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            receive(applicationContext, note: "已接收 iPhone 同步")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            receive(message, note: "刚刚从 iPhone 实时更新")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in receive(userInfo, note: "已接收 iPhone 后台同步") }
    }
}

private extension WatchConnectivityManager {
    func apply(_ payload: WatchSyncPayload, note: String, syncBadge: WatchSyncBadge, receivedAt: Date = .now,
               recordPhoneReceipt: Bool = false, allowsStressAlert: Bool = true) {
        guard !payload.isSampleData, payload.sampleScenarioTitle == nil else { return }
        if recordPhoneReceipt, payload.collectionSource != .appleWatch, payload.sentAt.timeIntervalSince1970.isFinite,
           payload.sentAt <= Date.now.addingTimeInterval(300), payload.sentAt.timeIntervalSince1970 > lastPhonePayloadSentAt {
            lastPhonePayloadSentAt = payload.sentAt.timeIntervalSince1970
            lastPhoneSyncAt = receivedAt
            UserDefaults.standard.set(receivedAt, forKey: "watch.phone.lastReceipt.v1")
            UserDefaults.standard.set(lastPhonePayloadSentAt, forKey: "watch.phone.lastSentAt.v1")
        }
        if let records = payload.activityRecords { activities.merge(records) }
        if let state = payload.userFeatures { mergeUserFeatures(state) }
        localStore?.applySyncedInsights(payload, includeCurrent: false)
        if let localStore { history = localStore.history }
        rememberPhoneReference(payload)
        var payload = payload
        if payload.statusMessage == "暂时无法读取健康数据，可在健康 App 中检查数据与访问设置。" {
            payload.statusMessage = "上次健康数据读取未完成，保留最近记录。"
        }
        if let previous = latestPayload {
            let previousDate = measurementDate(previous)
            let incomingDate = measurementDate(payload)
            if previous.collectionSource == .appleWatch, payload.collectionSource != .appleWatch,
               !payload.hasScore && payload.availableStress == nil { return }
            if let previousPressure = previous.availableStress,
               payload.availableStress.map({ $0.updatedAt < previousPressure.updatedAt }) ?? true {
                payload.stress = previousPressure
                payload.stressScore = previousPressure.score
                payload.stressLevelTitle = previousPressure.levelTitle
                payload.stressAlgorithmVersion = previous.stressAlgorithmVersion
                payload.hourlyStress = previous.availableHourlyStress
                if var metrics = payload.metrics ?? previous.availableMetrics {
                    metrics.stressScore = previousPressure.score
                    metrics.stressLevelTitle = previousPressure.levelTitle
                    if var health = metrics.health {
                        health.pressureMeasurement = previous.metrics?.health?.pressureMeasurement
                        health.pressureContextPrepared = previous.metrics?.health?.pressureContextPrepared
                        health.pressureAlgorithmVersion = previous.metrics?.health?.pressureAlgorithmVersion
                        health.hrvTrend = previous.metrics?.health?.hrvTrend
                        metrics.health = health
                    }
                    payload.metrics = metrics
                }
            }
            var preservesCurrentHealth = false
            if let previousDate {
                preservesCurrentHealth = incomingDate.map { $0 < previousDate } ?? true
                if incomingDate == previousDate {
                    preservesCurrentHealth = (previous.collectionSource == .appleWatch && payload.collectionSource != .appleWatch) ||
                        (previous.collectionSource == payload.collectionSource && payload.sentAt <= previous.sentAt)
                }
            } else { preservesCurrentHealth = incomingDate == nil && payload.sentAt <= previous.sentAt }
            if preservesCurrentHealth {
                // Pressure has its own sampling clock. Keep the newer health and energy while adopting new pressure.
                guard let incoming = payload.availableStress, !incoming.isStale,
                      incoming.updatedAt <= .now, (0...100).contains(incoming.score),
                      incoming.validUntil.timeIntervalSince1970.isFinite, incoming.validUntil >= incoming.updatedAt,
                      incoming.updatedAt > (previous.availableStress?.updatedAt ?? .distantPast) else { return }
                let source = payload
                payload = previous
                payload.sentAt = source.sentAt
                payload.stress = incoming
                payload.stressScore = incoming.score
                payload.stressLevelTitle = incoming.levelTitle
                payload.stressAlgorithmVersion = source.stressAlgorithmVersion
                payload.hourlyStress = source.availableHourlyStress
                var metrics = payload.metrics ?? source.availableMetrics ?? .empty
                metrics.stressScore = incoming.score
                metrics.stressLevelTitle = incoming.levelTitle
                if var health = metrics.health {
                    health.pressureMeasurement = source.metrics?.health?.pressureMeasurement
                    health.pressureContextPrepared = source.metrics?.health?.pressureContextPrepared
                    health.pressureAlgorithmVersion = source.metrics?.health?.pressureAlgorithmVersion
                    health.hrvTrend = source.metrics?.health?.hrvTrend
                    metrics.health = health
                }
                payload.metrics = metrics
            }
        }
        if allowsStressAlert {
            stressAlerts.receive(stress: payload.availableStress, energyScore: payload.hasScore ? payload.energyScore : nil,
                                 energyValidUntil: payload.hasScore ? payload.validUntil : nil)
        }
        latestPayload = payload
        localStore?.applySyncedInsights(payload)
        hasScore = payload.hasScore
        validUntil = payload.validUntil
        statusMessage = payload.statusMessage
        pressure = payload.availableStress
        history = localStore?.history ?? payload.availableHistory
        hourlyStress = payload.availableHourlyStress
        self.receivedAt = receivedAt
        snapshot = payload.asSnapshot
        workoutRecommendation = payload.workoutRecommendation
        self.metrics = payload.availableMetrics ?? .empty
        if let bodyStatus = payload.bodyStatus {
            self.bodyStatus = bodyStatus
        } else {
            self.bodyStatus = .make(energyScore: payload.energyScore)
        }
        self.syncBadge = syncBadge
        connectionNote = payload.collectionSource == .appleWatch ? note : (payload.statusMessage ?? note)

        if !allowsStressAlert { stressAlerts.establishBaseline(pressure) }

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

@MainActor
private final class WatchLocalPublisher: WatchSyncPublishing {
    var onRefreshRequested: (@MainActor () async -> Void)?
    private let onPublish: (WatchSyncPayload) -> Void

    init(onPublish: @escaping (WatchSyncPayload) -> Void) {
        self.onPublish = onPublish
    }

    func publish(_ payload: WatchSyncPayload) {
        var payload = payload
        payload.collectionSource = .appleWatch
        onPublish(payload)
    }
}

enum WatchSyncBadge {
    case waiting
    case connected
    case active
    case error
}
