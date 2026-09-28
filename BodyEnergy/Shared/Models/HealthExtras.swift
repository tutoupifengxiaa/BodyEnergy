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
