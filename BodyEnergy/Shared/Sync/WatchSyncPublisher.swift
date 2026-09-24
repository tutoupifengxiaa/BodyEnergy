import Foundation

@MainActor
protocol WatchSyncPublishing: AnyObject {
    var onRefreshRequested: (@MainActor () async -> Void)? { get set }
    func publish(_ payload: WatchSyncPayload)
}

@MainActor
final class NoopWatchSyncPublisher: WatchSyncPublishing {
    var onRefreshRequested: (@MainActor () async -> Void)?
    func publish(_ payload: WatchSyncPayload) {}
}

#if os(iOS)
import WatchConnectivity
import UIKit

@MainActor
final class WatchSyncPublisheriOS: NSObject, WatchSyncPublishing, WCSessionDelegate {
    var onRefreshRequested: (@MainActor () async -> Void)?
    private let session: WCSession?
    private var latestPayload: WatchSyncPayload?
    private let cacheKey = "watch.outgoing.payload.v2"

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
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
        pushLatestPayloadIfPossible()
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard error == nil, activationState == .activated else { return }
        Task { @MainActor in self.pushLatestPayloadIfPossible() }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message["request"] as? String == "latestEnergy" else { return }
        Task { @MainActor in
            await self.onRefreshRequested?()
            self.pushLatestPayloadIfPossible()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard message["request"] as? String == "latestEnergy" else { replyHandler([:]); return }
        Task { @MainActor in
            await self.onRefreshRequested?()
            replyHandler(self.latestPayload?.applicationContext ?? [:])
            self.pushLatestPayloadIfPossible()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.pushLatestPayloadIfPossible() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.pushLatestPayloadIfPossible() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard userInfo["request"] as? String == "latestEnergy" else { return }
        Task { @MainActor in
            let application = UIApplication.shared
            var taskID = UIBackgroundTaskIdentifier.invalid
            taskID = application.beginBackgroundTask(withName: "Watch health sync") {
                if taskID != .invalid {
                    application.endBackgroundTask(taskID)
                    taskID = .invalid
                }
            }
            defer { if taskID != .invalid { application.endBackgroundTask(taskID) } }
            await self.onRefreshRequested?()
            self.pushLatestPayloadIfPossible()
        }
    }

    private func pushLatestPayloadIfPossible() {
        guard let session, let latestPayload,
              session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(latestPayload.applicationContext)
        if session.isReachable { session.sendMessage(latestPayload.applicationContext, replyHandler: nil) { _ in } }
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
