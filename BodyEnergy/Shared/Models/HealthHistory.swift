import Foundation

struct HealthRecord: Codable, Equatable, Sendable {
    let health: HealthSnapshot
    let energy: EnergySnapshot
    let stressScore: Int
    let stressLevelTitle: String
    let recommendation: WorkoutRecommendation

    var dailyMetrics: DailyMetrics {
        DailyMetrics(date: energy.updatedAt, energyScore: energy.energyScore,
                     recoveryScore: energy.recoveryScore, stressScore: stressScore)
    }
}

struct DailyMetrics: Codable, Equatable, Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let energyScore: Int
    let recoveryScore: Int
    let stressScore: Int
}

struct HourlyStress: Codable, Equatable, Identifiable, Sendable {
    var id: Date { hour }
    let hour: Date
    let score: Int
}

struct HistoryDay: Identifiable {
    var id: Date { date }
    let date: Date
    let metrics: DailyMetrics?

    static func recentWeek(_ records: [DailyMetrics], now: Date = .now, calendar: Calendar = .current) -> [HistoryDay] {
        let today = calendar.startOfDay(for: now)
        return (-6...0).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let record = records.filter { calendar.isDate($0.date, inSameDayAs: day) }.max { $0.date < $1.date }
            return HistoryDay(date: day, metrics: record)
        }
    }
}

final class HealthHistoryStore {
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let key = "health.daily.records.v1"
    private let latestHealthKey = "health.latest.snapshot.v1"

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    func load() -> [HealthRecord] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([HealthRecord].self, from: data) else { return [] }
        return records.sorted { $0.energy.updatedAt < $1.energy.updatedAt }
    }

    func loadLatestHealth() -> HealthSnapshot? {
        guard let data = defaults.data(forKey: latestHealthKey) else { return nil }
        return try? JSONDecoder().decode(HealthSnapshot.self, from: data)
    }

    func saveLatestHealth(_ health: HealthSnapshot) {
        if let data = try? JSONEncoder().encode(health) {
            defaults.set(data, forKey: latestHealthKey)
        }
    }

    @discardableResult
    func save(_ record: HealthRecord, now: Date = .now) -> [HealthRecord] {
        var records = load()
        guard record.health.isUsable(at: now) else { return records }
        if let index = records.firstIndex(where: { calendar.isDate($0.energy.updatedAt, inSameDayAs: record.energy.updatedAt) }) {
            guard records[index].energy.updatedAt <= record.energy.updatedAt else { return records }
            records[index] = record
        } else {
            records.append(record)
        }
        records.sort { $0.energy.updatedAt < $1.energy.updatedAt }
        records = Array(records.suffix(30))
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: key) }
        return records
    }
}
