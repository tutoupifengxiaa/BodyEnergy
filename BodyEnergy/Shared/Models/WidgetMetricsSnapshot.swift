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
        energySnapshot: EnergySnapshot,
        stressScore: Int,
        stressLevelTitle: String
    ) {
        self.energyScore = energySnapshot.energyScore
        self.recoveryScore = energySnapshot.recoveryScore
        self.stressScore = stressScore
        self.stressLevelTitle = stressLevelTitle
        self.updatedAt = energySnapshot.updatedAt
    }

    static let preview = WidgetMetricsSnapshot(
        energySnapshot: .preview,
        stressScore: 38,
        stressLevelTitle: "压力适中"
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
