import Foundation

enum SharedContainer {
    static let appGroupID = "group.com.tutoupifengxiaa.BodyEnergy"
}

struct WidgetMetricsSnapshot: Codable, Equatable, Sendable {
    var energyScore: Int
    var recoveryScore: Int
    var stressScore: Int
    var stressLevelTitle: String
    var updatedAt: Date

    init(
        energyScore: Int,
        recoveryScore: Int,
        stressScore: Int,
        stressLevelTitle: String,
        updatedAt: Date
    ) {
        self.energyScore = energyScore
        self.recoveryScore = recoveryScore
        self.stressScore = stressScore
        self.stressLevelTitle = stressLevelTitle
        self.updatedAt = updatedAt
    }

    static let preview = WidgetMetricsSnapshot(
        energyScore: 78,
        recoveryScore: 82,
        stressScore: 38,
        stressLevelTitle: "压力适中",
        updatedAt: .now
    )
}

enum WidgetMetricsStore {
    private static let defaults = UserDefaults(suiteName: SharedContainer.appGroupID)
    private static let storageKey = "widget.metrics.snapshot"

    static func save(_ snapshot: WidgetMetricsSnapshot) {
        guard let defaults else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func load() -> WidgetMetricsSnapshot? {
        guard
            let defaults,
            let data = defaults.data(forKey: storageKey)
        else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetMetricsSnapshot.self, from: data)
    }
}
