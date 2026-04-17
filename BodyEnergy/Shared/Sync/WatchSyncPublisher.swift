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
        guard let session else { return }
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }

        let payload = WatchSyncPayload(
            snapshot: snapshot,
            workoutRecommendation: workoutRecommendation,
            metrics: metrics,
            stressScore: stressScore,
            stressLevelTitle: stressLevelTitle
        )

        do {
            try session.updateApplicationContext(payload.applicationContext)
        } catch {
            return
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}
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
