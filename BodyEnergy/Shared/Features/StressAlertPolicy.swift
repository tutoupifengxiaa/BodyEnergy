import Foundation

enum StressAlertKind: String, Codable {
    case high, low, ready
}

struct StressAlertState: Codable, Equatable {
    var lastHandledSampleAt: Date? = nil
    var lastNotificationAt: Date? = nil
}

struct StressAlertDecision {
    let kind: StressAlertKind
    let sampledAt: Date
    let title: String
    let body: String
}

enum StressAlertPolicy {
    private static let minimumInterval: TimeInterval = 120 * 60

    static func decision(stress: StressSnapshot?, energyScore: Int?, energyValidUntil: Date?,
                         now: Date, preferences: AppPreferences, state: StressAlertState,
                         calendar: Calendar = .current) -> StressAlertDecision? {
        guard let stress, (0...100).contains(stress.score),
              now.timeIntervalSince1970.isFinite, stress.updatedAt.timeIntervalSince1970.isFinite,
              stress.validUntil.timeIntervalSince1970.isFinite, stress.updatedAt <= now,
              stress.validUntil >= now, stress.validUntil >= stress.updatedAt,
              now.timeIntervalSince(stress.updatedAt) <= 30 * 60 else { return nil }
        if let lastHandled = state.lastHandledSampleAt, stress.updatedAt <= lastHandled { return nil }
        if let lastNotification = state.lastNotificationAt {
            guard now.timeIntervalSince(lastNotification) >= minimumInterval else { return nil }
        }
        let components = calendar.dateComponents([.hour, .minute], from: now)
        guard let hour = components.hour, let minute = components.minute,
              !preferences.isQuiet(atMinutes: hour * 60 + minute) else { return nil }

        let level = StressAnalyzer().level(for: stress.score)
        if level == .elevated || level == .high {
            return StressAlertDecision(kind: .high, sampledAt: stress.updatedAt,
                title: "放慢节奏，放松一下",
                body: "最近压力估算偏高，可休息片刻或做舒缓呼吸。")
        }
        guard level == .low else { return nil }
        if let energyScore, (0...100).contains(energyScore), energyScore >= 70,
           let energyValidUntil, energyValidUntil.timeIntervalSince1970.isFinite, energyValidUntil >= now {
            return StressAlertDecision(kind: .ready, sampledAt: stress.updatedAt,
                title: "元气足，保持当前节奏",
                body: "最近压力估算较低，身体电量较充足，保持当前节奏，仍以感受为准。")
        }
        return StressAlertDecision(kind: .low, sampledAt: stress.updatedAt,
            title: "最近状态比较轻松",
            body: "最近压力估算较低，按自己的感受保持舒适节奏。")
    }
}
