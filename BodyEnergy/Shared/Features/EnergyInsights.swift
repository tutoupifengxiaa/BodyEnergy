import Foundation

enum InsightMetric: String, CaseIterable, Identifiable {
    case energy, recovery, pressure

    var id: String { rawValue }
    var title: String {
        switch self {
        case .energy: return "电量"
        case .recovery: return "恢复"
        case .pressure: return "压力"
        }
    }
}

struct EnergyPressureSample: Codable, Equatable, Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let score: Int
    let metric: HRVMetric
    var algorithmVersion: Int? = StressSnapshot.algorithmVersion

    static func samples(records: [HealthRecord], currentHealth: HealthSnapshot? = nil,
                        currentPressure: StressSnapshot? = nil, now: Date = .now) -> [EnergyPressureSample] {
        var byDate: [Date: EnergyPressureSample] = [:]
        for record in records.sorted(by: { $0.energy.updatedAt < $1.energy.updatedAt }) {
            guard record.stressAlgorithmVersion == StressSnapshot.algorithmVersion,
                  let score = record.stressScore, (0...100).contains(score),
                  let observation = observation(health: record.health, score: score),
                  observation.date <= now else { continue }
            byDate[observation.date] = observation
        }
        if let currentHealth, let currentPressure, (0...100).contains(currentPressure.score),
           let observation = observation(health: currentHealth, score: currentPressure.score),
           observation.date == currentPressure.updatedAt,
           observation.metric == (currentPressure.hrvMetric ?? .sdnn), observation.date <= now {
            byDate[observation.date] = observation
        }
        return byDate.values.sorted { $0.date < $1.date }
    }

    static func nearest(to date: Date, in samples: [EnergyPressureSample],
                        maximumAge: TimeInterval = 2 * 3600) -> EnergyPressureSample? {
        samples.filter {
            $0.algorithmVersion == StressSnapshot.algorithmVersion && (0...100).contains($0.score)
                && $0.date.timeIntervalSince1970.isFinite
                && $0.date <= date && date.timeIntervalSince($0.date) <= maximumAge
        }
            .max { $0.date < $1.date }
    }

    private static func observation(health: HealthSnapshot, score: Int) -> EnergyPressureSample? {
        if let measurement = health.pressureMeasurement {
            guard health.pressureAlgorithmVersion == StressSnapshot.algorithmVersion,
                  StressAnalyzer().isValid(measurement: measurement),
                  measurement.sampledAt.timeIntervalSince1970.isFinite else { return nil }
            return EnergyPressureSample(date: measurement.sampledAt, score: score, metric: measurement.metric)
        }
        guard health.pressureContextPrepared != true,
              !health.missingMetrics.contains(.hrv),
              StressAnalyzer().validHRV(health.heartRateVariabilityMS),
              let baseline = health.hrvBaselineMS, StressAnalyzer().validHRV(baseline),
              let date = health.sampleDates[.hrv], date.timeIntervalSince1970.isFinite else { return nil }
        return EnergyPressureSample(date: date, score: score, metric: .sdnn)
    }
}

struct EnergyTrendDay: Identifiable {
    var id: Date { date }
    let date: Date
    let energyScore: Int?
    let recoveryScore: Int?
    let pressureScore: Int?

    func score(for metric: InsightMetric) -> Int? {
        switch metric {
        case .energy: return energyScore
        case .recovery: return recoveryScore
        case .pressure: return pressureScore
        }
    }
}

struct EnergyTrend {
    let days: [EnergyTrendDay]
    let startDate: Date
    let endDate: Date

    init(periodDays: Int, records: [HealthRecord], dailyMetrics: [DailyMetrics],
         pressureSamples: [EnergyPressureSample], pressureMetric: HRVMetric,
         now: Date = .now, calendar: Calendar = .current) {
        let count = periodDays == 30 ? 30 : 7
        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -(count - 1), to: today) ?? today
        startDate = windowStart
        endDate = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let usable = (dailyMetrics + records.map(\.dailyMetrics)).filter {
            $0.date >= windowStart && $0.date <= now
                && (0...100).contains($0.energyScore) && (0...100).contains($0.recoveryScore)
        }
        let daily = Dictionary(grouping: usable) { calendar.startOfDay(for: $0.date) }
        let pressures = Dictionary(grouping: pressureSamples.filter {
            $0.date >= windowStart && $0.date <= now && $0.metric == pressureMetric
                && $0.algorithmVersion == StressSnapshot.algorithmVersion && (0...100).contains($0.score)
        }) { calendar.startOfDay(for: $0.date) }
        days = (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: windowStart) else { return nil }
            let metrics = daily[date]?.max { $0.date < $1.date }
            let pressure = pressures[date]?.max { $0.date < $1.date }
            return EnergyTrendDay(date: date, energyScore: metrics?.energyScore,
                recoveryScore: metrics?.recoveryScore, pressureScore: pressure?.score)
        }
    }

    func validDayCount(for metric: InsightMetric) -> Int {
        days.filter { $0.score(for: metric) != nil }.count
    }

    func average(for metric: InsightMetric) -> Double? {
        let values = days.compactMap { $0.score(for: metric).map(Double.init) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct EnergyWeeklyReport {
    let current: EnergyTrend
    let previous: EnergyTrend
    let workoutCount: Int
    let breathingCount: Int
    let feelingCount: Int
    let completedActivitySeconds: Int
    let activityDayCount: Int
    let batteryObservationCount: Int

    init(records: [HealthRecord], dailyMetrics: [DailyMetrics], activities: [ActivityRecord],
         batteryTimeline: [BatteryTimelinePoint], pressureSamples: [EnergyPressureSample],
         pressureMetric: HRVMetric, now: Date = .now, calendar: Calendar = .current) {
        let currentTrend = EnergyTrend(periodDays: 7, records: records, dailyMetrics: dailyMetrics,
            pressureSamples: pressureSamples, pressureMetric: pressureMetric, now: now, calendar: calendar)
        current = currentTrend
        let previousEnd = currentTrend.startDate.addingTimeInterval(-0.001)
        previous = EnergyTrend(periodDays: 7, records: records, dailyMetrics: dailyMetrics,
            pressureSamples: pressureSamples, pressureMetric: pressureMetric, now: previousEnd, calendar: calendar)
        var ids = Set<UUID>()
        let recentActivities = activities.filter {
            $0.isValid(at: now) && $0.completedAt >= currentTrend.startDate && $0.completedAt <= now
        }.filter { ids.insert($0.id).inserted }
        workoutCount = recentActivities.filter { $0.kind == .workout }.count
        breathingCount = recentActivities.filter { $0.kind == .breathing }.count
        feelingCount = recentActivities.filter { $0.feeling != nil }.count
        completedActivitySeconds = recentActivities.reduce(0) { $0 + $1.durationSeconds }
        activityDayCount = Set(recentActivities.map { calendar.startOfDay(for: $0.completedAt) }).count
        batteryObservationCount = Set(batteryTimeline.filter {
            $0.date >= currentTrend.startDate && $0.date <= now && $0.level.isFinite && (0...100).contains($0.level)
        }.map(\.date)).count
    }

    func difference(for metric: InsightMetric) -> Double? {
        guard current.validDayCount(for: metric) >= 3, previous.validDayCount(for: metric) >= 3,
              let recent = current.average(for: metric), let earlier = previous.average(for: metric) else { return nil }
        return recent - earlier
    }
}
