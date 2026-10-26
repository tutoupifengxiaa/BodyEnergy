import Foundation

enum SleepStage: String, CaseIterable, Codable, Equatable, Sendable {
    case awake, core, deep, rem, unspecified

    var title: String {
        switch self {
        case .awake: return "清醒"
        case .core: return "核心睡眠"
        case .deep: return "深度睡眠"
        case .rem: return "REM 睡眠"
        case .unspecified: return "未分期睡眠"
        }
    }
}

struct SleepSegment: Codable, Equatable, Identifiable, Sendable {
    var start: Date
    var end: Date
    var stage: SleepStage
    var id: String { "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)-\(stage.rawValue)" }
    var durationSeconds: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

struct SleepDetails: Codable, Equatable, Sendable {
    var segments: [SleepSegment]
    var sourceTitle: String
    var startedAt: Date
    var endedAt: Date

    var totalSleepSeconds: TimeInterval {
        segments.filter { $0.stage != .awake }.reduce(0) { $0 + $1.durationSeconds }
    }
    var hasStages: Bool { segments.contains { [.core, .deep, .rem].contains($0.stage) } }
    func duration(for stage: SleepStage) -> TimeInterval {
        segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.durationSeconds }
    }
}

enum FitnessBiologicalSex: String, Codable, Equatable, Sendable {
    case female, male, other
}

struct FitnessContext: Codable, Equatable, Sendable {
    var vo2MaxMLKgMin: Double?
    var sampledAt: Date?
    var dateOfBirth: DateComponents?
    var biologicalSex: FitnessBiologicalSex?
    var sourceTitle: String?
}

// Transient observations stay on the collecting device. Only the small summaries
// below are persisted and sent through WatchConnectivity.
struct TimedHealthValue: Hashable, Sendable {
    var start: Date
    var end: Date
    var value: Double
}

struct MainSleep: Equatable, Sendable {
    var intervals: [DateInterval]
    var start: Date { intervals[0].start }
    var end: Date { intervals[intervals.count - 1].end }
    var hours: Double { intervals.reduce(0) { $0 + $1.duration } / 3600 }
}

struct SleepHistorySummary: Codable, Equatable, Sendable {
    var windowStart: Date
    var asOf: Date
    var targetSleepHours: Double
    var windowDays: Int
    var recordedDays: Int
    var debtHours: Double?
    var carriedDebtHours: Double?
    var regularityScore: Int?
    var timingShiftMinutes: Double?
    var recoveryPenalty: Double
}

struct MorningRecovery: Codable, Equatable, Sendable {
    var sleepStart: Date
    var sleepEnd: Date
    var sleepHours: Double
    var hrvMS: Double
    var sleepingHeartRateBPM: Double
    var hrvBaselineMS: Double?
    var heartRateBaselineBPM: Double?
    var baselineNightCount: Int
    var score: Int
    var sleepHistory: SleepHistorySummary? = nil

    var validUntil: Date { sleepEnd.addingTimeInterval(36 * 3600) }
    func isValid(at date: Date) -> Bool {
        sleepStart < sleepEnd && sleepEnd <= date && validUntil >= date
            && (0...100).contains(score) && sleepHours.isFinite && (3...16).contains(sleepHours)
            && EnergyConfig.default.hrvValidRange.contains(hrvMS)
            && EnergyConfig.default.restingHeartRateValidRange.contains(sleepingHeartRateBPM)
    }
}

struct TrainingLoad: Codable, Equatable, Sendable {
    var dayStart: Date
    var measuredThrough: Date
    var workoutSeconds: Double
    var observedSeconds: Double
    var weightedMinutes: Double
    var score: Int?
    var referenceMaxHeartRate: Double

    var coverage: Double { workoutSeconds > 0 ? (observedSeconds / workoutSeconds).clamped(to: 0...1) : 1 }
}
