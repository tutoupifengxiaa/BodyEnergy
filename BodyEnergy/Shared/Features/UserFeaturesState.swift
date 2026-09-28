import Foundation

struct UserFeaturesState: Codable, Equatable, Sendable {
    var preferences: AppPreferences?
    var habitDays: [HabitDay]?
}

enum UserFeaturesMessage {
    static let key = "userFeaturesV1"
    static func applicationContext(_ state: UserFeaturesState) -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard (state.habitDays?.count ?? 0) <= 31,
              let data = try? encoder.encode(state), data.count <= 16 * 1024 else { return [:] }
        return [key: data]
    }
    static func state(from context: [String: Any]) -> UserFeaturesState? {
        guard let data = context[key] as? Data, data.count <= 16 * 1024,
              let state = try? JSONDecoder().decode(UserFeaturesState.self, from: data),
              (state.habitDays?.count ?? 0) <= 31 else { return nil }
        return state
    }
}

final class DailyMetricsHistoryStore {
    private let defaults: UserDefaults
    private let key = "health.daily.metrics.synced.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    @discardableResult
    func merge(_ values: [DailyMetrics], now: Date = .now) -> [DailyMetrics] {
        let previous = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([DailyMetrics].self, from: $0) } ?? []
        let oldest = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        var result: [Date: DailyMetrics] = [:]
        for value in previous + values where value.date.timeIntervalSince1970.isFinite && value.date >= oldest &&
            value.date <= now.addingTimeInterval(300) && (0...100).contains(value.energyScore) && (0...100).contains(value.recoveryScore) {
            let day = Calendar.current.startOfDay(for: value.date)
            if result[day].map({ $0.date > value.date }) ?? false { continue }
            result[day] = value
        }
        let next = Array(result.values.sorted { $0.date < $1.date }.suffix(30))
        if previous != next, let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: key) }
        return next
    }
}

final class PressureHistoryStore {
    private let defaults: UserDefaults
    private let key = "health.pressure.samples.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load(now: Date = .now) -> [EnergyPressureSample] {
        normalized(defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([EnergyPressureSample].self, from: $0) } ?? [], now: now)
    }

    @discardableResult
    func merge(_ values: [EnergyPressureSample], now: Date = .now) -> [EnergyPressureSample] {
        let existing = load(now: now)
        let next = normalized(existing + values, now: now)
        if next != existing, let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: key) }
        return next
    }

    private func normalized(_ values: [EnergyPressureSample], now: Date) -> [EnergyPressureSample] {
        let oldest = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        var result: [String: EnergyPressureSample] = [:]
        for value in values where value.algorithmVersion == StressSnapshot.algorithmVersion && value.date.timeIntervalSince1970.isFinite && value.date >= oldest && value.date <= now && (0...100).contains(value.score) {
            result["\(value.date.timeIntervalSince1970)-\(value.metric.rawValue)"] = value
        }
        return Array(result.values.sorted { $0.date == $1.date ? $0.metric.rawValue < $1.metric.rawValue : $0.date < $1.date }.suffix(1_000))
    }
}
