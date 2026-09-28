import Foundation
import UserNotifications
import WatchKit

@MainActor
final class WatchStressAlertCoordinator: NSObject, UNUserNotificationCenterDelegate {
    var onOpenDestination: ((String) -> Void)?

    private struct Reading {
        let stress: StressSnapshot
        let energyScore: Int?
        let energyValidUntil: Date?
    }

    private let preferences: PreferencesStore
    private let defaults: UserDefaults
    private let center = UNUserNotificationCenter.current()
    private let stateKey = "watch.stress.alertState.v1"
    private var state: StressAlertState
    private var pending: Reading?
    private var deliveryTask: Task<Void, Never>?

    init(preferences: PreferencesStore, defaults: UserDefaults = .standard) {
        self.preferences = preferences
        self.defaults = defaults
        state = defaults.data(forKey: "watch.stress.alertState.v1")
            .flatMap { try? JSONDecoder().decode(StressAlertState.self, from: $0) } ?? StressAlertState()
        super.init()
        center.delegate = self
        let breathe = UNNotificationAction(identifier: "bodyenergy.stress.breathe", title: "舒缓呼吸", options: .foreground)
        let status = UNNotificationAction(identifier: "bodyenergy.stress.status", title: "查看状态", options: .foreground)
        center.setNotificationCategories([UNNotificationCategory(identifier: "bodyenergy.stress", actions: [breathe, status], intentIdentifiers: [])])
    }

    func activate() {
        guard WKApplication.shared().applicationState == .active else { return }
        preferences.refreshReminders()
    }

    func establishBaseline(_ stress: StressSnapshot?) {
        guard let stress, stress.updatedAt.timeIntervalSince1970.isFinite, stress.updatedAt <= .now,
              stress.updatedAt > (state.lastHandledSampleAt ?? .distantPast) else { return }
        state.lastHandledSampleAt = stress.updatedAt
        persist()
    }

    func receive(stress: StressSnapshot?, energyScore: Int?, energyValidUntil: Date?) {
        guard let stress, stress.updatedAt.timeIntervalSince1970.isFinite, stress.updatedAt <= .now,
              stress.updatedAt > (state.lastHandledSampleAt ?? .distantPast) else { return }
        if let pending, pending.stress.updatedAt > stress.updatedAt { return }
        pending = Reading(stress: stress, energyScore: energyScore, energyValidUntil: energyValidUntil)
        guard deliveryTask == nil else { return }
        deliveryTask = Task { [weak self] in
            guard let self else { return }
            while let reading = self.pending {
                self.pending = nil
                await self.deliver(reading)
            }
            self.deliveryTask = nil
        }
    }

    func finishPendingAlerts() async { await deliveryTask?.value }

    private func deliver(_ reading: Reading) async {
        let previousState = state
        guard reading.stress.updatedAt > (state.lastHandledSampleAt ?? .distantPast) else { return }
        let decision = StressAlertPolicy.decision(stress: reading.stress, energyScore: reading.energyScore,
            energyValidUntil: reading.energyValidUntil, now: .now, preferences: preferences.settings, state: previousState)
        state.lastHandledSampleAt = reading.stress.updatedAt
        persist()
        guard decision != nil else { return }
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional].contains(settings.authorizationStatus), !Task.isCancelled else { return }
        if let pending, pending.stress.updatedAt > reading.stress.updatedAt { return }
        // Recheck quiet hours, freshness and cooldown after the permission query.
        guard let current = StressAlertPolicy.decision(stress: reading.stress, energyScore: reading.energyScore,
            energyValidUntil: reading.energyValidUntil, now: .now, preferences: preferences.settings, state: previousState) else { return }
        let content = UNMutableNotificationContent()
        content.title = current.title
        content.body = current.body
        content.sound = .default
        content.categoryIdentifier = "bodyenergy.stress"
        content.userInfo = ["destination": "stress"]
        let request = UNNotificationRequest(identifier: "bodyenergy.stress." + current.kind.rawValue,
            content: content, trigger: nil)
        do {
            try await center.add(request)
            state.lastNotificationAt = .now
            persist()
        } catch {
            // The sample stays consumed; failed delivery must not repeat on each refresh.
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: stateKey) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.notification.request.identifier.hasPrefix("bodyenergy.stress."),
              response.actionIdentifier != UNNotificationDismissActionIdentifier else { completionHandler(); return }
        let destination = response.actionIdentifier == "bodyenergy.stress.breathe" ? "breathing" : "stress"
        Task { @MainActor in
            self.onOpenDestination?(destination)
            completionHandler()
        }
    }
}
