import Combine
import Foundation
#if os(watchOS)
import WatchKit
#endif

@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var active: ActiveActivity?
    @Published private(set) var records: [ActivityRecord]
    @Published private(set) var pressureSamples: [EnergyPressureSample] = []
    var onRecordsChanged: (([ActivityRecord]) -> Void)?
    let preferences: PreferencesStore
    private var subscriptions = Set<AnyCancellable>()
    #if os(watchOS)
    lazy var workoutController: WatchWorkoutController = {
        let controller = WatchWorkoutController(store: self)
        controller.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        return controller
    }()
    private var lastBreathingCue: String?
    private var completionCueID: UUID?
    #endif

    private let defaults: UserDefaults
    private let source: ActivityRecordSource
    private let activeKey = "activities.active.v1"
    private let recordsKey = "activities.records.v1"

    init(defaults: UserDefaults = .standard, source: ActivityRecordSource = .current, preferences: PreferencesStore? = nil) {
        self.defaults = defaults
        self.source = source
        self.preferences = preferences ?? PreferencesStore(defaults: defaults)
        let restored = defaults.data(forKey: recordsKey)
            .flatMap { try? JSONDecoder().decode([ActivityRecord].self, from: $0) } ?? []
        records = Self.normalized(restored, now: .now)
        if let data = defaults.data(forKey: activeKey),
           let restored = try? JSONDecoder().decode(ActiveActivity.self, from: data),
           restored.kind != .checkIn, restored.accumulatedSeconds.isFinite,
           restored.accumulatedSeconds >= 0, restored.accumulatedSeconds <= ActivityRecord.maximumDuration,
           !restored.title.isEmpty, restored.title.utf8.count <= 160,
           restored.startedAt.timeIntervalSince1970.isFinite,
           restored.startedAt <= Date.now.addingTimeInterval(300),
           restored.runningSince.map({ $0 >= restored.startedAt && $0 <= Date.now.addingTimeInterval(300) }) ?? true,
           (restored.kind == .breathing && [60, 180, 300].contains(restored.targetSeconds ?? 0)) ||
                (restored.kind == .workout && restored.targetSeconds == nil && restored.recommendation != nil) {
            active = restored
        }
        self.preferences.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
    }

    @discardableResult
    func startBreathing(minutes: Int? = nil, now: Date = .now) -> Bool {
        let duration = minutes ?? preferences.settings.breathingMinutes
        guard [1, 3, 5].contains(duration) else { return false }
        return start(kind: .breathing, title: "呼吸 \(duration) 分钟", recommendation: nil, targetSeconds: duration * 60, now: now)
    }

    @discardableResult
    func startWorkout(_ recommendation: WorkoutRecommendation, now: Date = .now) -> Bool {
        start(kind: .workout, title: recommendation.title, recommendation: recommendation, targetSeconds: nil, now: now)
    }

    func pause(now: Date = .now) {
        guard var activity = active, !activity.isPaused else { return }
        activity.accumulatedSeconds = activity.elapsed(at: now)
        activity.runningSince = nil
        active = activity
        saveActive()
    }

    func resume(now: Date = .now) {
        guard var activity = active, activity.isPaused,
              activity.elapsed(at: now) < Double(activity.targetSeconds ?? Int(ActivityRecord.maximumDuration)) else { return }
        activity.runningSince = now
        active = activity
        saveActive()
    }

    @discardableResult
    func finish(feeling: BodyFeeling? = nil, now: Date = .now, workoutMetrics: WorkoutMetrics? = nil) -> ActivityRecord? {
        guard let activity = active else { return nil }
        let record = ActivityRecord(id: activity.id, kind: activity.kind, title: activity.title,
            startedAt: activity.startedAt, completedAt: now,
            durationSeconds: Int(activity.elapsed(at: now).rounded(.down)), feeling: feeling, source: source,
            activityType: activity.recommendation?.activityType, workoutMetrics: workoutMetrics)
        guard record.isValid(at: now) else { return nil }
        active = nil
        saveActive()
        append(record, now: now)
        #if os(watchOS)
        completionCue(for: activity.id)
        #endif
        return record
    }

    func discardActive() {
        active = nil
        saveActive()
    }

    func synchronizeWorkoutTiming(elapsed: TimeInterval, isPaused: Bool, now: Date = .now) {
        guard var current = active, current.kind == .workout, elapsed.isFinite, elapsed >= 0 else { return }
        current.accumulatedSeconds = min(elapsed, ActivityRecord.maximumDuration)
        current.runningSince = isPaused ? nil : now
        active = current
        saveActive()
    }

    func updatePressureSamples(_ samples: [EnergyPressureSample]) {
        guard pressureSamples != samples else { return }
        pressureSamples = samples
    }

    #if os(watchOS)
    func breathingCue(at now: Date) {
        guard let current = active, current.kind == .breathing, !current.isPaused else { return }
        let elapsed = Int(current.elapsed(at: now))
        if elapsed >= (current.targetSeconds ?? 60) { completionCue(for: current.id); return }
        guard preferences.settings.watchRhythmHaptics else { return }
        let phase = elapsed % 10 < 4 ? 0 : 1
        let key = "\(current.id)-\(elapsed / 10)-\(phase)"
        guard key != lastBreathingCue else { return }
        lastBreathingCue = key
        WKInterfaceDevice.current().play(phase == 0 ? .directionUp : .directionDown)
    }

    private func completionCue(for id: UUID) {
        guard completionCueID != id, preferences.settings.watchCompletionHaptics else { return }
        completionCueID = id
        WKInterfaceDevice.current().play(.success)
    }
    #endif

    @discardableResult
    func recordFeeling(_ feeling: BodyFeeling, now: Date = .now) -> ActivityRecord {
        let record = ActivityRecord(id: UUID(), kind: .checkIn, title: "身体感受",
            startedAt: now, completedAt: now, durationSeconds: 0, feeling: feeling, source: source)
        append(record, now: now)
        return record
    }

    @discardableResult
    func merge(_ incoming: [ActivityRecord]) -> Bool {
        let merged = Self.normalized(records + incoming, now: .now)
        guard merged != records else { return false }
        records = merged
        saveRecords()
        return true
    }

    private func start(kind: ActivityKind, title: String, recommendation: WorkoutRecommendation?,
                       targetSeconds: Int?, now: Date) -> Bool {
        guard active == nil, !title.isEmpty, title.utf8.count <= 160 else { return false }
        active = ActiveActivity(id: UUID(), kind: kind, title: title, startedAt: now,
            recommendation: recommendation, targetSeconds: targetSeconds, accumulatedSeconds: 0, runningSince: now)
        saveActive()
        return true
    }

    private func append(_ record: ActivityRecord, now: Date) {
        records = Self.normalized(records + [record], now: now)
        saveRecords()
        onRecordsChanged?(records)
    }

    private func saveActive() {
        if let active, let data = try? JSONEncoder().encode(active) {
            defaults.set(data, forKey: activeKey)
        } else {
            defaults.removeObject(forKey: activeKey)
        }
    }

    private func saveRecords() {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: recordsKey)
        }
    }

    private static func normalized(_ records: [ActivityRecord], now: Date) -> [ActivityRecord] {
        var ids = Set<UUID>()
        return Array(records.filter { $0.isValid(at: now) }
            .filter { ids.insert($0.id).inserted }
            .sorted {
                $0.completedAt == $1.completedAt ? $0.id.uuidString < $1.id.uuidString : $0.completedAt > $1.completedAt
            }
            .prefix(ActivityRecord.maximumCount))
    }
}
