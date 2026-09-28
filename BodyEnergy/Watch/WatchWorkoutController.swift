import Combine
import Foundation
import HealthKit

@MainActor
final class WatchWorkoutController: NSObject, ObservableObject {
    @Published private(set) var isStarting = false
    @Published private(set) var isSaving = false
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var heartRateBPM: Double?
    @Published private(set) var activeEnergyKcal: Double?

    var hasSession: Bool { session != nil }
    var canRetrySave: Bool {
        guard !isStarting, !isSaving else { return false }
        let pendingConfirmation = saveNeedsConfirmation && externalID != nil && store?.active?.id == activityID
        return pendingConfirmation || (builder != nil && endedAt != nil)
    }

    private weak var store: ActivityStore?
    private let healthStore: HKHealthStore
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var activityID: UUID?
    private var externalID: String?
    private var endedAt: Date?
    private var collectionEnded = false
    private var saveNeedsConfirmation = false
    private var pendingFeeling: BodyFeeling?
    private var finishContinuation: CheckedContinuation<ActivityRecord?, Never>?
    private var saveTask: Task<Void, Never>?
    private let confirmationKey = "watch.workout.awaitingConfirmation.v1"

    init(store: ActivityStore, healthStore: HKHealthStore = HKHealthStore()) {
        self.store = store
        self.healthStore = healthStore
        super.init()
        if let active = store.active, active.kind == .workout {
            let pending = UserDefaults.standard.dictionary(forKey: confirmationKey)
            let legacyID = UserDefaults.standard.string(forKey: confirmationKey)
            let pendingID = pending?["activityID"] as? String ?? legacyID
            let pendingExternalID = pending?["externalID"] as? String ?? legacyID
            if pendingID == active.id.uuidString, let pendingExternalID, !pendingExternalID.isEmpty {
                activityID = active.id
                externalID = pendingExternalID
                saveNeedsConfirmation = true
                isPaused = true
                store.pause()
                errorMessage = "运动保存结果待确认，请解锁设备后重试确认。"
            }
        }
    }

    @discardableResult
    func start(_ recommendation: WorkoutRecommendation) async -> Bool {
        guard !isStarting, !isSaving, session == nil, let store, store.active == nil else {
            errorMessage = "已有活动记录，请继续或完成当前活动。"
            return false
        }
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }
        do {
            try await requestAuthorization()
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = workoutType(for: recommendation.activityType)
            configuration.locationType = .unknown
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            configure(session: session, builder: builder)
            let start = Date.now
            guard store.startWorkout(recommendation, now: start), let active = store.active else {
                clearSession(discard: true)
                errorMessage = "已有活动记录，请继续或完成当前活动。"
                return false
            }
            activityID = active.id
            externalID = active.id.uuidString
            try await addExternalID(to: builder, id: active.id.uuidString)
            session.startActivity(with: start)
            try await beginCollection(builder, at: start)
            updateStatistics(builder)
            return true
        } catch {
            if store.active?.id == activityID { store.discardActive() }
            clearSession(discard: true)
            errorMessage = (error as? WorkoutFailure)?.message ?? "运动测量未能开始，请检查设备状态后重试。"
            return false
        }
    }

    func pause() {
        guard let session, session.state == .running, !isSaving else { return }
        session.pause()
    }

    func resume() {
        guard let session, session.state == .paused, !isSaving, endedAt == nil else { return }
        session.resume()
    }

    func finish(feeling: BodyFeeling? = nil) async -> ActivityRecord? {
        guard !isStarting, !isSaving, let session, builder != nil else {
            if !hasSession { errorMessage = "当前没有可保存的系统运动。请恢复上次运动或放弃中断的记录。" }
            return nil
        }
        isSaving = true
        errorMessage = nil
        pendingFeeling = feeling ?? pendingFeeling
        if endedAt == nil { endedAt = Date.now }
        return await withCheckedContinuation { continuation in
            finishContinuation = continuation
            if session.state == .stopped || session.state == .ended {
                launchSave()
            } else {
                session.stopActivity(with: endedAt)
            }
        }
    }

    func retrySave(feeling: BodyFeeling? = nil) async -> ActivityRecord? {
        guard canRetrySave else { return nil }
        if saveNeedsConfirmation { return await confirmSavedRecord(feeling: feeling) }
        return await finish(feeling: feeling)
    }

    private func confirmSavedRecord(feeling: BodyFeeling?) async -> ActivityRecord? {
        guard saveNeedsConfirmation, externalID != nil, store?.active?.id == activityID, !isSaving else { return nil }
        isSaving = true
        pendingFeeling = feeling ?? pendingFeeling
        do {
            guard let workout = try await savedWorkout() else {
                errorMessage = "运动保存结果仍待确认。解锁设备并允许读取运动记录后，可再次重试。"
                completeSave(nil)
                return nil
            }
            let savedRecord = record(for: workout)
            completeSave(savedRecord)
            return savedRecord
        } catch {
            errorMessage = "暂时无法确认健康中的运动记录，请解锁设备后重试。"
            completeSave(nil)
            return nil
        }
    }

    func discard() {
        guard !isStarting, !isSaving else { return }
        if store?.active?.id == activityID || (session == nil && store?.active?.kind == .workout) {
            store?.discardActive()
        }
        clearSession(discard: true)
        errorMessage = nil
    }

    func recoverActiveSession() async {
        guard session == nil, !isStarting, !isSaving else { return }
        isStarting = true
        defer { isStarting = false }
        let result: (HKWorkoutSession?, Error?) = await withCheckedContinuation { continuation in
            healthStore.recoverActiveWorkoutSession { session, error in
                continuation.resume(returning: (session, error))
            }
        }
        guard let recovered = result.0 else {
            if saveNeedsConfirmation, store?.active?.id == activityID {
                store?.pause()
                isPaused = true
                errorMessage = "系统运动已结束，保存结果仍待确认。请解锁设备后重试确认。"
            } else if store?.active?.kind == .workout {
                store?.pause()
                errorMessage = "上次运动已中断，没有可恢复的系统测量。可放弃本地计时后重新开始。"
            }
            return
        }
        let builder = recovered.associatedWorkoutBuilder()
        configure(session: recovered, builder: builder)
        if store?.active == nil {
            var recommendation = WorkoutRecommendation.generalActivity
            recommendation.title = "恢复的运动"
            _ = store?.startWorkout(recommendation, now: recovered.startDate ?? .now)
        }
        guard let active = store?.active, active.kind == .workout else {
            errorMessage = "已恢复系统运动，请先处理当前本地活动，再保存或放弃运动。"
            return
        }
        activityID = active.id
        externalID = builder.metadata[HKMetadataKeyExternalUUID] as? String ?? active.id.uuidString
        saveNeedsConfirmation = confirmationMatchesExternalID()
        isRunning = recovered.state == .running && builder.endDate == nil
        isPaused = recovered.state == .paused || builder.endDate != nil
        store?.synchronizeWorkoutTiming(elapsed: builder.elapsedTime, isPaused: !isRunning, now: builder.endDate ?? .now)
        updateStatistics(builder)
        errorMessage = nil
        if builder.endDate != nil || recovered.state == .stopped || recovered.state == .ended {
            endedAt = builder.endDate ?? recovered.endDate ?? .now
            errorMessage = saveNeedsConfirmation ? "运动保存结果待确认，请重试确认。" : "运动已结束，请保存到 Apple 健康或放弃。"
        }
    }

    private func configure(session: HKWorkoutSession, builder: HKLiveWorkoutBuilder) {
        self.session = session
        self.builder = builder
        collectionEnded = builder.endDate != nil
        endedAt = builder.endDate
        saveNeedsConfirmation = false
        heartRateBPM = nil
        activeEnergyKcal = nil
        session.delegate = self
        builder.delegate = self
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                    workoutConfiguration: session.workoutConfiguration)
    }

    private func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable(),
              let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) else { throw WorkoutFailure.unavailable }
        let workout = HKObjectType.workoutType()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [workout, energy], read: [workout, energy, heartRate]) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: WorkoutFailure.authorization) }
            }
        }
        guard healthStore.authorizationStatus(for: workout) == .sharingAuthorized,
              healthStore.authorizationStatus(for: energy) == .sharingAuthorized else { throw WorkoutFailure.authorization }
    }

    private func workoutType(for activity: TrainingActivity?) -> HKWorkoutActivityType {
        switch activity {
        case .walking: return .walking
        case .running: return .running
        case .cycling: return .cycling
        case .strength: return .traditionalStrengthTraining
        case .mobility: return .flexibility
        case nil: return .other
        }
    }

    private func addExternalID(to builder: HKLiveWorkoutBuilder, id: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.addMetadata([HKMetadataKeyExternalUUID: id]) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: WorkoutFailure.start) }
            }
        }
    }

    private func beginCollection(_ builder: HKLiveWorkoutBuilder, at date: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.beginCollection(withStart: date) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: WorkoutFailure.start) }
            }
        }
    }

    private func launchSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            await self?.saveWorkout()
            self?.saveTask = nil
        }
    }

    private func saveWorkout() async {
        guard let builder, let endedAt else { completeSave(nil); return }
        do {
            if let existing = try await savedWorkout() {
                completeSave(record(for: existing, builder: builder))
                return
            }
            if saveNeedsConfirmation {
                errorMessage = "保存结果暂未确认。解锁设备并允许读取运动记录后重试确认。"
                completeSave(nil)
                return
            }
            if !collectionEnded {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    builder.endCollection(withEnd: endedAt) { success, error in
                        if let error { continuation.resume(throwing: error) }
                        else if success { continuation.resume() }
                        else { continuation.resume(throwing: WorkoutFailure.end) }
                    }
                }
                collectionEnded = true
            }
            let result: (HKWorkout?, Error?) = await withCheckedContinuation { continuation in
                builder.finishWorkout { workout, error in continuation.resume(returning: (workout, error)) }
            }
            if let workout = result.0 {
                completeSave(record(for: workout, builder: builder))
            } else if let error = result.1 {
                throw error
            } else {
                // HealthKit may save successfully while locked without returning the
                // workout. Confirm by external ID; never call finish again blindly.
                saveNeedsConfirmation = true
                if let activityID, let externalID {
                    UserDefaults.standard.set(["activityID": activityID.uuidString, "externalID": externalID], forKey: confirmationKey)
                }
                errorMessage = "设备锁定时无法确认运动记录，请解锁后重试确认。"
                completeSave(nil)
            }
        } catch {
            store?.pause()
            errorMessage = "运动尚未确认保存到 Apple 健康。记录已保留，可重试或放弃。"
            completeSave(nil)
        }
    }

    private func savedWorkout() async throws -> HKWorkout? {
        guard let externalID else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [externalID])
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 1,
                                      sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.first as? HKWorkout) }
            }
            healthStore.execute(query)
        }
    }

    private func record(for workout: HKWorkout, builder: HKLiveWorkoutBuilder? = nil) -> ActivityRecord? {
        guard store?.active?.id == activityID else {
            errorMessage = "运动已保存到 Apple 健康，本地活动记录需要重新核对。"
            return nil
        }
        store?.synchronizeWorkoutTiming(elapsed: workout.duration, isPaused: true, now: workout.endDate)
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)
        let averageHeartRate = heartRateType.flatMap { (workout.statistics(for: $0) ?? builder?.statistics(for: $0))?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) }
        let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        let energy = energyType.flatMap { (workout.statistics(for: $0) ?? builder?.statistics(for: $0))?.sumQuantity()?.doubleValue(for: .kilocalorie()) }
        let metrics = WorkoutMetrics(averageHeartRate: averageHeartRate.flatMap { $0.isFinite && $0 > 0 ? $0 : nil },
                                     activeEnergyKcal: energy.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil },
                                     healthWorkoutID: workout.uuid)
        return store?.finish(feeling: pendingFeeling, now: workout.endDate, workoutMetrics: metrics)
    }

    private func completeSave(_ record: ActivityRecord?) {
        isSaving = false
        if record != nil {
            if confirmationMatchesExternalID() {
                UserDefaults.standard.removeObject(forKey: confirmationKey)
            }
            errorMessage = nil
            clearSession(discard: false)
        }
        let continuation = finishContinuation
        finishContinuation = nil
        continuation?.resume(returning: record)
    }

    private func updateStatistics(_ builder: HKLiveWorkoutBuilder) {
        if let type = HKObjectType.quantityType(forIdentifier: .heartRate),
           let quantity = builder.statistics(for: type)?.mostRecentQuantity() {
            let value = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            if value.isFinite && value > 0 { heartRateBPM = value }
        }
        if let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
           let quantity = builder.statistics(for: type)?.sumQuantity() {
            let value = quantity.doubleValue(for: .kilocalorie())
            if value.isFinite && value >= 0 { activeEnergyKcal = value }
        }
    }

    private func clearSession(discard: Bool) {
        if discard, confirmationMatchesExternalID() {
            UserDefaults.standard.removeObject(forKey: confirmationKey)
        }
        session?.delegate = nil
        builder?.delegate = nil
        if discard { builder?.discardWorkout() }
        session?.end()
        session = nil
        builder = nil
        activityID = nil
        externalID = nil
        endedAt = nil
        collectionEnded = false
        saveNeedsConfirmation = false
        isRunning = false
        isPaused = false
    }

    private func confirmationMatchesExternalID() -> Bool {
        guard let externalID else { return false }
        let pending = UserDefaults.standard.dictionary(forKey: confirmationKey)
        return (pending?["externalID"] as? String ?? UserDefaults.standard.string(forKey: confirmationKey)) == externalID
    }
}

extension WatchWorkoutController: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            self.isRunning = toState == .running
            self.isPaused = toState == .paused
            if self.store?.active?.id == self.activityID {
                if toState == .paused || toState == .stopped || toState == .ended { self.store?.pause(now: date) }
                else if toState == .running { self.store?.resume(now: date) }
            }
            if toState == .stopped || toState == .ended {
                if self.endedAt == nil { self.endedAt = date }
                if self.isSaving { self.launchSave() }
                else { self.errorMessage = "系统运动已结束，请保存或放弃。" }
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            self.store?.pause()
            self.isRunning = false
            self.isPaused = true
            self.endedAt = self.endedAt ?? .now
            self.errorMessage = "系统运动测量已中断。请重试保存或放弃当前记录。"
            if self.saveTask == nil { self.completeSave(nil) }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor [weak self] in
            guard let self, self.builder === workoutBuilder else { return }
            self.updateStatistics(workoutBuilder)
        }
    }
}

private enum WorkoutFailure: Error {
    case unavailable, authorization, start, end
    var message: String {
        switch self {
        case .unavailable: return "当前设备无法进行系统运动测量。"
        case .authorization: return "需要允许写入运动和活动能量，才能保存到 Apple 健康。"
        case .start: return "运动测量未能开始，请重试。"
        case .end: return "运动数据收集尚未结束，请重试保存。"
        }
    }
}
