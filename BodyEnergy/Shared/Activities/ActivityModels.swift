import Foundation

enum ActivityKind: String, Codable, Equatable, Sendable {
    case breathing, workout, checkIn
}

enum BodyFeeling: String, CaseIterable, Identifiable, Codable, Sendable {
    case relaxed, okay, tired, tense

    var id: String { rawValue }
    var title: String {
        switch self {
        case .relaxed: return "放松"
        case .okay: return "还不错"
        case .tired: return "疲惫"
        case .tense: return "紧绷"
        }
    }
    var symbol: String {
        switch self {
        case .relaxed: return "leaf"
        case .okay: return "face.smiling"
        case .tired: return "moon.zzz"
        case .tense: return "bolt.heart"
        }
    }
}

enum ActivityRecordSource: String, Codable, Equatable, Sendable {
    case iPhone, appleWatch

    static var current: Self {
        #if os(watchOS)
        return .appleWatch
        #else
        return .iPhone
        #endif
    }
}

struct ActiveActivity: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var kind: ActivityKind
    var title: String
    var startedAt: Date
    var recommendation: WorkoutRecommendation?
    var targetSeconds: Int?
    var accumulatedSeconds: TimeInterval
    var runningSince: Date?

    var isPaused: Bool { runningSince == nil }

    func elapsed(at date: Date) -> TimeInterval {
        let running = runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0
        let limit = targetSeconds.map(TimeInterval.init) ?? ActivityRecord.maximumDuration
        return min(limit, max(0, accumulatedSeconds + running))
    }
}

struct ActivityRecord: Codable, Equatable, Identifiable, Sendable {
    static let maximumCount = 100
    static let maximumDuration: TimeInterval = 7 * 24 * 60 * 60

    var id: UUID
    var kind: ActivityKind
    var title: String
    var startedAt: Date
    var completedAt: Date
    var durationSeconds: Int
    var feeling: BodyFeeling?
    var source: ActivityRecordSource
    var activityType: TrainingActivity? = nil
    var workoutMetrics: WorkoutMetrics? = nil

    func isValid(at now: Date) -> Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.utf8.count <= 160,
              startedAt.timeIntervalSince1970.isFinite,
              completedAt.timeIntervalSince1970.isFinite,
              startedAt >= Date(timeIntervalSince1970: 946_684_800),
              completedAt >= startedAt, completedAt <= now.addingTimeInterval(300),
              durationSeconds >= 0, Double(durationSeconds) <= Self.maximumDuration,
              Double(durationSeconds) <= completedAt.timeIntervalSince(startedAt) + 1 else { return false }
        switch kind {
        case .breathing: return (1...300).contains(durationSeconds) && workoutMetrics == nil
        case .workout: return durationSeconds >= 1 && (workoutMetrics?.isValid ?? true)
        case .checkIn: return durationSeconds == 0 && feeling != nil && startedAt == completedAt
        }
    }
}

struct WorkoutMetrics: Codable, Equatable, Sendable {
    var averageHeartRate: Double?
    var activeEnergyKcal: Double?
    var healthWorkoutID: UUID?

    var isValid: Bool {
        (averageHeartRate.map { $0.isFinite && (20...300).contains($0) } ?? true) &&
        (activeEnergyKcal.map { $0.isFinite && (0...100_000).contains($0) } ?? true)
    }
}

enum ActivityRecordsMessage {
    static let key = "activityRecordsV1"

    static func applicationContext(records: [ActivityRecord]) -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard records.count <= ActivityRecord.maximumCount,
              let data = try? encoder.encode(records), data.count <= 60 * 1024 else { return [:] }
        return [key: data]
    }

    static func records(from context: [String: Any]) -> [ActivityRecord]? {
        guard let data = context[key] as? Data, data.count <= 60 * 1024,
              let records = try? JSONDecoder().decode([ActivityRecord].self, from: data),
              records.count <= ActivityRecord.maximumCount else { return nil }
        return records
    }
}
