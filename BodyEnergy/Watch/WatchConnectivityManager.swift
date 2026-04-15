import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    @Published private(set) var snapshot: EnergySnapshot = .preview
    @Published private(set) var connectionNote: String = "Waiting for iPhone sync"

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
            connectionNote = "WatchConnectivity unavailable"
            return
        }

        session.activate()

        if let payload = WatchSyncPayload(applicationContext: session.receivedApplicationContext) {
            snapshot = payload.asSnapshot
            connectionNote = "Synced"
        }
    }

    func requestLatest() {
        guard let session, session.isReachable else { return }
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
                connectionNote = "Sync error: \(error.localizedDescription)"
            } else {
                connectionNote = activationState == .activated ? "Connected" : "Connecting"
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let payload = WatchSyncPayload(applicationContext: applicationContext) else { return }
        Task { @MainActor in
            snapshot = payload.asSnapshot
            connectionNote = "Updated \(payload.updatedAt.formatted(date: .omitted, time: .shortened))"
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        guard let payload = WatchSyncPayload(applicationContext: message) else { return }
        Task { @MainActor in
            snapshot = payload.asSnapshot
            connectionNote = "Live updated"
        }
    }
}
