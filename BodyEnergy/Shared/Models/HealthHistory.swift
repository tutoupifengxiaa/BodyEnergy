import Foundation

struct HealthRecord: Codable, Equatable, Sendable {
    let health: HealthSnapshot
    let energy: EnergySnapshot
    let stressScore: Int?
    let stressLevelTitle: String?
    let recommendation: WorkoutRecommendation
    let stressAlgorithmVersion: Int?
    let batteryLevel: Double?
    let batteryAssessment: BatteryAssessment?

    init(health: HealthSnapshot, energy: EnergySnapshot, stressScore: Int?,
         stressLevelTitle: String?, recommendation: WorkoutRecommendation, stressAlgorithmVersion: Int? = StressSnapshot.algorithmVersion,
         batteryLevel: Double? = nil, batteryAssessment: BatteryAssessment? = nil) {
        self.health = health
        self.energy = energy
        self.stressScore = stressScore
        self.stressLevelTitle = stressLevelTitle
        self.recommendation = recommendation
        self.stressAlgorithmVersion = stressAlgorithmVersion
        self.batteryLevel = batteryLevel
        self.batteryAssessment = batteryAssessment
    }

    var dailyMetrics: DailyMetrics {
        DailyMetrics(date: energy.updatedAt, energyScore: energy.energyScore,
                     recoveryScore: energy.recoveryScore,
                     stressScore: stressAlgorithmVersion == StressSnapshot.algorithmVersion ? stressScore : nil,
                     stressMetric: health.pressureMeasurement?.metric)
    }
}

struct BatteryTimelinePoint: Codable, Equatable, Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let level: Double
    var assessment: BatteryAssessment? = nil
}

final class BatteryTimelineStore {
    static let maximumCount = 4_320
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let key = "health.battery.timeline.v1"

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    func load(now: Date = .now) -> [BatteryTimelinePoint] {
        guard let data = defaults.data(forKey: key),
              let points = try? JSONDecoder().decode([BatteryTimelinePoint].self, from: data) else { return [] }
        return normalized(points, now: now)
    }

    @discardableResult
    func save(_ point: BatteryTimelinePoint, now: Date = .now) -> [BatteryTimelinePoint] {
        merge([point], now: now)
    }

    @discardableResult
    func merge(_ incoming: [BatteryTimelinePoint], now: Date = .now) -> [BatteryTimelinePoint] {
        let points = normalized(load(now: now) + incoming, now: now)
        if let data = try? JSONEncoder().encode(points) { defaults.set(data, forKey: key) }
        return points
    }

    private func normalized(_ points: [BatteryTimelinePoint], now: Date) -> [BatteryTimelinePoint] {
        guard let start = calendar.date(byAdding: .day, value: -30, to: now) else { return [] }
        var byDate: [Date: BatteryTimelinePoint] = [:]
        for point in points {
            guard point.date.timeIntervalSince1970.isFinite, point.date >= start,
                  point.date <= now.addingTimeInterval(300),
                  point.level.isFinite, (0...100).contains(point.level),
                  point.assessment.map({ $0.isValid && abs($0.level - point.level) < 0.000_001 }) ?? true else { continue }
            byDate[point.date] = point
        }
        return Array(byDate.values.sorted { $0.date < $1.date }.suffix(Self.maximumCount))
    }
}

struct DailyMetrics: Codable, Equatable, Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let energyScore: Int
    let recoveryScore: Int
    let stressScore: Int?
    var stressMetric: HRVMetric? = nil

    func matchingPressureMetric(_ metric: HRVMetric) -> DailyMetrics {
        DailyMetrics(date: date, energyScore: energyScore, recoveryScore: recoveryScore,
                     stressScore: (stressMetric ?? .sdnn) == metric ? stressScore : nil,
                     stressMetric: stressMetric)
    }
}

struct HourlyStress: Codable, Equatable, Identifiable, Sendable {
    var id: Date { hour }
    let hour: Date
    let score: Int
    var hrvMetric: HRVMetric? = nil
}

struct SyncedPressureRecord: Codable, Equatable, Sendable {
    let stress: StressSnapshot
    let measurement: PressureMeasurement
    let hourlyStress: [HourlyStress]
    let algorithmVersion: Int
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
    private let watchPressureKey = "health.watch.pressure.v1"

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

    func loadWatchPressure() -> SyncedPressureRecord? {
        guard let data = defaults.data(forKey: watchPressureKey) else { return nil }
        return try? JSONDecoder().decode(SyncedPressureRecord.self, from: data)
    }

    func saveWatchPressure(_ record: SyncedPressureRecord) {
        if let data = try? JSONEncoder().encode(record) { defaults.set(data, forKey: watchPressureKey) }
    }

    @discardableResult
    func save(_ record: HealthRecord, now: Date = .now) -> [HealthRecord] {
        var records = load()
        guard record.health.isUsable(at: now) else { return records }
        if let index = records.firstIndex(where: { calendar.isDate($0.energy.updatedAt, inSameDayAs: record.energy.updatedAt) }) {
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
