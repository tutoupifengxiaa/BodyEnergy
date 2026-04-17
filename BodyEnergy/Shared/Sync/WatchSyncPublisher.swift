import Foundation

protocol WatchSyncPublishing {
    func publish(
        snapshot: EnergySnapshot,
        workoutRecommendation: WorkoutRecommendation,
        metrics: WatchKeyMetricsSnapshot,
        stressScore: Int,
        stressLevelTitle: String
    )
}

struct NoopWatchSyncPublisher: WatchSyncPublishing {
    func publish(
        snapshot: EnergySnapshot,
        workoutRecommendation: WorkoutRecommendation,
        metrics: WatchKeyMetricsSnapshot,
        stressScore: Int,
        stressLevelTitle: String
    ) {}
}

#if os(iOS)
import WatchConnectivity

final class WatchSyncPublisheriOS: NSObject, WatchSyncPublishing, WCSessionDelegate {
    private let session: WCSession?
    private var latestPayload: WatchSyncPayload?

    override init() {
        if WCSession.isSupported() {
            self.session = WCSession.default
        } else {
            self.session = nil
        }
        super.init()

        session?.delegate = self
        session?.activate()
    }

    func publish(
        snapshot: EnergySnapshot,
        workoutRecommendation: WorkoutRecommendation,
        metrics: WatchKeyMetricsSnapshot,
        stressScore: Int,
        stressLevelTitle: String
    ) {
        let payload = WatchSyncPayload(
            snapshot: snapshot,
            workoutRecommendation: workoutRecommendation,
            metrics: metrics,
            stressScore: stressScore,
            stressLevelTitle: stressLevelTitle
        )
        latestPayload = payload
        pushLatestPayloadIfPossible()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard error == nil, activationState == .activated else { return }
        pushLatestPayloadIfPossible()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let request = message["request"] as? String, request == "latestEnergy" else { return }
        pushLatestPayloadIfPossible()
    }
}

private extension WatchSyncPublisheriOS {
    func pushLatestPayloadIfPossible() {
        guard let session, let latestPayload else { return }
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }

        do {
            try session.updateApplicationContext(latestPayload.applicationContext)
        } catch {
            return
        }

        guard session.isReachable else { return }
        session.sendMessage(latestPayload.applicationContext, replyHandler: nil) { _ in }
    }
}
#endif

enum WatchSyncPublisherFactory {
    static func makeDefault() -> WatchSyncPublishing {
        #if os(iOS)
        return WatchSyncPublisheriOS()
        #else
        return NoopWatchSyncPublisher()
        #endif
    }
}
