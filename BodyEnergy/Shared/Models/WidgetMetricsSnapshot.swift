import Foundation

enum SharedContainer {
    static let appGroupID = "group.com.tutoupifengxiaa.BodyEnergy"
}

struct StressSnapshot: Codable, Equatable, Sendable {
    var score: Int
    var levelTitle: String
    var updatedAt: Date
    var validUntil: Date
    var basis: String

    var isStale: Bool { validUntil < .now }
}

struct WidgetMetricsSnapshot: Codable, Equatable, Sendable {
    var energyScore: Int
    var recoveryScore: Int
    var stressScore: Int
    var stressLevelTitle: String
    var updatedAt: Date
    var hasData: Bool = true
    var validUntil: Date?
    var isSampleData: Bool = false
    var stress: StressSnapshot?

    var isStale: Bool { validUntil.map { $0 < Date.now } ?? true }
    var hasStressData: Bool { stress != nil || hasData }
    var isStressStale: Bool { stress?.isStale ?? isStale }
    var stressUpdatedAt: Date { stress?.updatedAt ?? updatedAt }

    static func stressTitle(for score: Int) -> String {
        switch score {
        case ..<30: return "压力较低"
        case 30..<55: return "压力适中"
        case 55..<75: return "压力偏高"
        default: return "压力较高"
        }
    }


    init(
        energyScore: Int,
        recoveryScore: Int,
        stressScore: Int,
        stressLevelTitle: String,
        updatedAt: Date, validUntil: Date? = nil, hasData: Bool = true, isSampleData: Bool = false,
        stress: StressSnapshot? = nil
    ) {
        self.energyScore = energyScore
        self.recoveryScore = recoveryScore
        self.stressScore = stressScore
        self.stressLevelTitle = stressLevelTitle
        self.updatedAt = updatedAt
        self.validUntil = validUntil
        self.hasData = hasData
        self.isSampleData = isSampleData
        self.stress = stress
    }

    static let empty = WidgetMetricsSnapshot(energyScore: 0, recoveryScore: 0, stressScore: 0,
                                             stressLevelTitle: "暂无数据", updatedAt: .distantPast, hasData: false)

    static let preview = WidgetMetricsSnapshot(
        energyScore: 78,
        recoveryScore: 82,
        stressScore: 38,
        stressLevelTitle: "压力适中",
        updatedAt: .now, validUntil: .distantFuture, isSampleData: true
    )
}

enum WidgetMetricsStore {
    private static let defaults = UserDefaults(suiteName: SharedContainer.appGroupID)
    private static let storageKey = "widget.metrics.snapshot.v2"

    static func save(_ snapshot: WidgetMetricsSnapshot) {
        guard let defaults, snapshot.hasData || snapshot.hasStressData, !snapshot.isSampleData else { return }
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
