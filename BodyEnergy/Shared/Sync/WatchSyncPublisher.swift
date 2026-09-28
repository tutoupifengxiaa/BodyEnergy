import Foundation

@MainActor
protocol WatchSyncPublishing: AnyObject {
    var onRefreshRequested: (@MainActor () async -> Void)? { get set }
    var onHealthPayloadReceived: (@MainActor (WatchSyncPayload) -> Void)? { get set }
    var onActivityRecordsReceived: (@MainActor ([ActivityRecord]) -> Void)? { get set }
    var onUserFeaturesReceived: (@MainActor (UserFeaturesState) -> Void)? { get set }
    func publish(_ payload: WatchSyncPayload)
}

extension WatchSyncPublishing {
    var onHealthPayloadReceived: (@MainActor (WatchSyncPayload) -> Void)? {
        get { nil }
        set {}
    }
    var onUserFeaturesReceived: (@MainActor (UserFeaturesState) -> Void)? {
        get { nil }
        set {}
    }
    var onActivityRecordsReceived: (@MainActor ([ActivityRecord]) -> Void)? {
        get { nil }
        set {}
    }
}

@MainActor
final class NoopWatchSyncPublisher: WatchSyncPublishing {
    var onRefreshRequested: (@MainActor () async -> Void)?
    var onHealthPayloadReceived: (@MainActor (WatchSyncPayload) -> Void)?
    var onActivityRecordsReceived: (@MainActor ([ActivityRecord]) -> Void)?
    var onUserFeaturesReceived: (@MainActor (UserFeaturesState) -> Void)?
    func publish(_ payload: WatchSyncPayload) {}
}

#if os(iOS)
import WatchConnectivity
import UIKit

@MainActor
final class WatchSyncPublisheriOS: NSObject, WatchSyncPublishing, WCSessionDelegate {
    var onRefreshRequested: (@MainActor () async -> Void)?
    var onHealthPayloadReceived: (@MainActor (WatchSyncPayload) -> Void)? {
        didSet { replayReceivedHealthPayload() }
    }
    var onActivityRecordsReceived: (@MainActor ([ActivityRecord]) -> Void)?
    var onUserFeaturesReceived: (@MainActor (UserFeaturesState) -> Void)?
    private let session: WCSession?
    private var latestPayload: WatchSyncPayload?
    private var pendingReceivedHealthPayload: WatchSyncPayload?
    private let cacheKey = "watch.outgoing.payload.v2"
    private var refreshTask: Task<Void, Never>?
    private var backgroundTaskID = UIBackgroundTaskIdentifier.invalid
    private var hasPendingRefreshResponse = false
    private var syncState = "complete"
    private var syncStateAt = Date.now

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let payload = try? JSONDecoder().decode(WatchSyncPayload.self, from: data),
           !payload.isSampleData, payload.sampleScenarioTitle == nil {
            latestPayload = payload
        }
        session?.delegate = self
        session?.activate()
    }

    func publish(_ payload: WatchSyncPayload) {
        latestPayload = payload
        updateSyncState(UIApplication.shared.isProtectedDataAvailable ? "complete" : "waitingForUnlock")
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
        recordStage("published")
        pushLatestPayloadIfPossible()
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error { self.recordStage("activationFailed", error: error); return }
            guard activationState == .activated else { return }
            self.replayReceivedHealthPayload()
            self.pushLatestPayloadIfPossible()
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let payload = Self.watchHealthPayload(from: message) {
            Task { @MainActor in self.receiveHealthPayload(payload) }
            return
        }
        if let state = UserFeaturesMessage.state(from: message) {
            Task { @MainActor in self.onUserFeaturesReceived?(state) }
            return
        }
        if let records = ActivityRecordsMessage.records(from: message) {
            Task { @MainActor in self.onActivityRecordsReceived?(records) }
            return
        }
        guard message["request"] as? String == "latestEnergy" else { return }
        Task { @MainActor in
            self.handleRefreshRequest()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if let payload = Self.watchHealthPayload(from: message) {
            Task { @MainActor in
                self.receiveHealthPayload(payload)
                replyHandler(["watchHealthAccepted": true])
            }
            return
        }
        if let state = UserFeaturesMessage.state(from: message) {
            Task { @MainActor in
                self.onUserFeaturesReceived?(state)
                replyHandler(["userFeaturesAccepted": true])
            }
            return
        }
        if let records = ActivityRecordsMessage.records(from: message) {
            Task { @MainActor in
                self.onActivityRecordsReceived?(records)
                replyHandler(["activityRecordsAccepted": true])
            }
            return
        }
        guard message["request"] as? String == "latestEnergy" else { replyHandler([:]); return }
        Task { @MainActor in
            self.handleRefreshRequest(replyHandler: replyHandler)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.pushLatestPayloadIfPossible() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.pushLatestPayloadIfPossible() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if let payload = Self.watchHealthPayload(from: userInfo) {
            Task { @MainActor in self.receiveHealthPayload(payload) }
            return
        }
        if let state = UserFeaturesMessage.state(from: userInfo) {
            Task { @MainActor in self.onUserFeaturesReceived?(state) }
            return
        }
        if let records = ActivityRecordsMessage.records(from: userInfo) {
            Task { @MainActor in self.onActivityRecordsReceived?(records) }
            return
        }
        guard userInfo["request"] as? String == "latestEnergy" else { return }
        Task { @MainActor in
            self.handleRefreshRequest()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let payload = Self.watchHealthPayload(from: applicationContext) else { return }
        Task { @MainActor in self.receiveHealthPayload(payload) }
    }

    private nonisolated static func watchHealthPayload(from message: [String: Any]) -> WatchSyncPayload? {
        guard let payload = WatchSyncPayload(applicationContext: message),
              payload.collectionSource == .appleWatch,
              payload.sentAt.timeIntervalSince1970.isFinite,
              payload.sentAt <= Date.now.addingTimeInterval(300) else { return nil }
        return payload
    }

    private func receiveHealthPayload(_ payload: WatchSyncPayload) {
        guard let onHealthPayloadReceived else {
            if pendingReceivedHealthPayload.map({ $0.sentAt < payload.sentAt }) ?? true {
                pendingReceivedHealthPayload = payload
            }
            return
        }
        onHealthPayloadReceived(payload)
    }

    private func replayReceivedHealthPayload() {
        guard onHealthPayloadReceived != nil else { return }
        var candidates = [pendingReceivedHealthPayload].compactMap { $0 }
        if let context = session?.receivedApplicationContext,
           let payload = Self.watchHealthPayload(from: context) {
            candidates.append(payload)
        }
        pendingReceivedHealthPayload = nil
        for payload in candidates.sorted(by: { $0.sentAt < $1.sentAt }) {
            receiveHealthPayload(payload)
        }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        guard userInfoTransfer.userInfo["syncResponse"] as? Bool == true else { return }
        Task { @MainActor in
            self.recordStage(error == nil ? "responseTransferred" : "responseTransferFailed", error: error)
        }
    }

    private var outgoingContext: [String: Any] {
        var context = latestPayload?.applicationContext ?? [:]
        context["syncState"] = syncState
        context["syncStateAt"] = syncStateAt.timeIntervalSince1970
        context["refreshAccepted"] = hasPendingRefreshResponse
        return context
    }

    private func handleRefreshRequest(replyHandler: (([String: Any]) -> Void)? = nil) {
        hasPendingRefreshResponse = true
        let canReadHealth = UIApplication.shared.isProtectedDataAvailable
        updateSyncState(canReadHealth ? "updating" : "waitingForUnlock")
        recordStage("requestAccepted")
        // A cold RMSSD refresh can take longer than the live message reply window.
        // Reply with the cached state immediately, then publish the refreshed result.
        if let replyHandler {
            replyHandler(outgoingContext)
        } else {
            pushLatestPayloadIfPossible()
        }
        guard canReadHealth, refreshTask == nil else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Watch health sync") { [weak self] in
            guard let self else { return }
            self.recordStage("backgroundExpired")
            self.endBackgroundTask()
        }
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.refreshTask = nil
                self.endBackgroundTask()
            }
            self.recordStage("refreshStarted")
            await self.onRefreshRequested?()
            if self.syncState == "updating" {
                self.updateSyncState(UIApplication.shared.isProtectedDataAvailable ? "complete" : "waitingForUnlock")
            }
            self.pushLatestPayloadIfPossible()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func pushLatestPayloadIfPossible() {
        guard let session, latestPayload != nil || hasPendingRefreshResponse,
              session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let context = outgoingContext
        pushActivityRecords(session: session)
        do {
            try session.updateApplicationContext(context)
            recordStage("contextUpdated")
        } catch {
            recordStage("contextFailed", error: error)
        }
        if session.isReachable {
            session.sendMessage(context, replyHandler: nil) { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    self.recordStage("messageFailed", error: error)
                    if self.syncState == "complete" { self.queueLatestResponse() }
                }
            }
        }
        if syncState == "complete", hasPendingRefreshResponse || !session.isReachable {
            queueLatestResponse()
        }
    }

    private func queueLatestResponse() {
        guard let session, latestPayload != nil, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        var response = outgoingContext
        response["syncResponse"] = true
        let transfers = session.outstandingUserInfoTransfers.filter { $0.userInfo["syncResponse"] as? Bool == true }
        let matching = transfers.first { $0.userInfo["payloadV2"] as? Data == response["payloadV2"] as? Data }
        for transfer in transfers where transfer !== matching { transfer.cancel() }
        if matching == nil {
            session.transferUserInfo(response)
            recordStage("responseQueued")
        }
        hasPendingRefreshResponse = false
    }

    private func pushActivityRecords(session: WCSession) {
        guard let records = latestPayload?.activityRecords, !records.isEmpty else { return }
        let message = ActivityRecordsMessage.applicationContext(records: records)
        guard let data = message[ActivityRecordsMessage.key] as? Data else { return }
        if session.isReachable { session.sendMessage(message, replyHandler: nil, errorHandler: { _ in }) }
        let transfers = session.outstandingUserInfoTransfers.filter { $0.userInfo[ActivityRecordsMessage.key] is Data }
        guard !transfers.contains(where: { $0.userInfo[ActivityRecordsMessage.key] as? Data == data }) else { return }
        transfers.forEach { $0.cancel() }
        session.transferUserInfo(message)
    }

    private func recordStage(_ stage: String, error: Error? = nil) {
        let defaults = UserDefaults.standard
        defaults.set(Date.now, forKey: "watch.sync.iphone." + stage + ".at")
        defaults.set(syncState, forKey: "watch.sync.iphone.state")
        defaults.set(syncStateAt.timeIntervalSince1970, forKey: "watch.sync.iphone.stateAt")
        if let error { defaults.set((error as NSError).code, forKey: "watch.sync.iphone." + stage + ".errorCode") }
    }

    private func updateSyncState(_ state: String) {
        syncState = state
        syncStateAt = .now
    }
}
#endif

@MainActor
enum WatchSyncPublisherFactory {
    static func makeDefault() -> WatchSyncPublishing {
        #if os(iOS)
        return WatchSyncPublisheriOS()
        #else
        return NoopWatchSyncPublisher()
        #endif
    }
}
