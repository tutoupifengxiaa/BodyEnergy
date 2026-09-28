import Foundation
import SwiftUI

struct ActivityHubView: View {
    @ObservedObject var store: ActivityStore
    @State private var showsSession = false
    @State private var showsCheckIn = false

    private var recentRecords: [ActivityRecord] {
        Array(store.records.sorted { $0.completedAt > $1.completedAt }.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("今日行动", systemImage: "leaf")
                .font(.headline)

            if let activity = store.active {
                Button { showsSession = true } label: {
                    Label("继续 · \(activity.title)", systemImage: "timer")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            } else {
                Button { showsSession = true } label: {
                    Label("呼吸 \(store.preferences.settings.breathingMinutes) 分钟", systemImage: "wind")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }

            Button { showsCheckIn = true } label: {
                Label("记录感受", systemImage: "face.smiling")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Divider()
            Button(store.preferences.settings.collapseRecentRecords ? "展开最近记录" : "最近记录 · 收起") {
                store.preferences.update { $0.collapseRecentRecords.toggle() }
            }.font(.caption.weight(.semibold)).buttonStyle(.plain)
            if store.preferences.settings.collapseRecentRecords {
                Text("可在全部记录中查看。").font(.caption).foregroundStyle(.secondary)
            } else if recentRecords.isEmpty {
                Text("完成活动或记录感受后，会保存在这里。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentRecords) { record in
                    ActivityRecordRow(record: record)
                }
            }
        }
        .activityCard()
        #if os(watchOS)
        .fullScreenCover(isPresented: $showsSession) {
            ActivitySessionView(store: store)
        }
        .fullScreenCover(isPresented: $showsCheckIn) {
            FeelingCheckInView(store: store)
        }
        #else
        .sheet(isPresented: $showsSession) {
            ActivitySessionView(store: store)
        }
        .sheet(isPresented: $showsCheckIn) {
            FeelingCheckInView(store: store)
        }
        #endif
    }
}

struct ActivitySessionView: View {
    @ObservedObject var store: ActivityStore
    var recommendation: WorkoutRecommendation? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsFinish = false
    @State private var savedRecord: ActivityRecord?
    @State private var startMessage: String?
    #if os(watchOS)
    @State private var showsWorkoutSteps = false
    #endif

    var body: some View {
        #if os(watchOS)
        sessionContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .bottom)
        #else
        NavigationStack {
            sessionContent
                .navigationTitle(sessionTitle)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                    }
                }
        }
        #endif
    }

    private var sessionTitle: String {
        store.active?.title ?? savedRecord?.title ?? (recommendation == nil ? "呼吸放松" : "训练计时")
    }

    private var sessionContent: some View {
        ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        #if os(watchOS)
                        Text(sessionTitle).font(.headline)
                        #endif
                        if let activity = store.active {
                            activeSession(activity)
                        } else if let savedRecord {
                            Label("记录已保存", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            ActivityRecordRow(record: savedRecord)
                            Text("可在首页的最近记录中查看。")
                                .font(.caption).foregroundStyle(.secondary)
                            #if !os(watchOS)
                            Button("完成") { dismiss() }
                                .buttonStyle(.borderedProminent)
                            #endif
                        } else {
                            startSession
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(activityPagePadding)
                    .id("activitySessionTop")
                }
                .onChange(of: store.active?.id) { _, _ in
                    proxy.scrollTo("activitySessionTop", anchor: .top)
                }
            }
            #if os(watchOS)
            .fullScreenCover(isPresented: $showsFinish) {
                ActivityFinishView(store: store) { record in
                    savedRecord = record
                    showsFinish = false
                }
            }
            #else
            .sheet(isPresented: $showsFinish) {
                ActivityFinishView(store: store) { record in
                    savedRecord = record
                    showsFinish = false
                }
            }
            #endif
    }

    private var startSession: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let recommendation {
                Text(recommendation.title).font(.headline)
                Text(recommendation.summary)
                    .font(.caption).foregroundStyle(.secondary)
                recommendationSteps(recommendation)
                #if os(watchOS)
                Text("开始后测量心率与活动能量，完成后保存到 Apple 健康。")
                    .font(.caption).foregroundStyle(.secondary)
                #else
                Text("手机记录活动时长；在手表开始运动可测量心率与活动能量。")
                    .font(.caption).foregroundStyle(.secondary)
                #endif
            } else {
                Text("跟随提示轻柔吸气 4 秒、呼气 6 秒，不屏息。")
                Text("以舒适为准，不必勉强跟随节奏。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if recommendation == nil {
                Picker("时长", selection: Binding(get: { store.preferences.settings.breathingMinutes }, set: { minutes in
                    store.preferences.update { $0.breathingMinutes = minutes }
                })) { ForEach([1, 3, 5], id: \.self) { Text("\($0) 分钟").tag($0) } }
            }
            Button(recommendation == nil ? "开始 \(store.preferences.settings.breathingMinutes) 分钟呼吸" : "开始运动") {
                Task { @MainActor in
                    let started: Bool
                    if let recommendation {
                        #if os(watchOS)
                        started = await store.workoutController.start(recommendation)
                        startMessage = started ? nil : store.workoutController.errorMessage
                        #else
                        started = store.startWorkout(recommendation)
                        startMessage = started ? nil : "已有进行中的活动，请继续或完成当前活动。"
                        #endif
                    } else {
                        started = store.startBreathing()
                        startMessage = started ? nil : "已有进行中的活动，请继续或完成当前活动。"
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            #if os(watchOS)
            .disabled(store.workoutController.isStarting || store.workoutController.isSaving)
            #endif
            if let startMessage {
                Text(startMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func activeSession(_ activity: ActiveActivity) -> some View {
        let refreshInterval: TimeInterval
        switch activity.kind {
        case .breathing: refreshInterval = 0.1
        case .workout, .checkIn: refreshInterval = 1
        }
        return VStack(alignment: .leading, spacing: 14) {
            if !matchesRequestedActivity(activity) {
                Text("已有进行中的活动，先继续或完成当前记录。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            TimelineView(.animation(minimumInterval: refreshInterval, paused: activity.isPaused)) { context in
                let elapsed = max(0, activity.elapsed(at: context.date))
                let breathingComplete = breathingHasFinished(activity, elapsed: elapsed)
                VStack(spacing: 12) {
                    if case .breathing = activity.kind {
                        breathingGuide(elapsed: elapsed, paused: activity.isPaused, completed: breathingComplete)
                        let remaining = max(0, Double(activity.targetSeconds ?? 60) - elapsed)
                        Text(activityTime(ceil(remaining)))
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Text(remaining > 0 ? "剩余时间" : "呼吸已完成，可保存记录")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(activityTime(elapsed))
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Text(activity.isPaused ? "计时已暂停" : "已累计")
                            .font(.caption).foregroundStyle(.secondary)
                        #if os(watchOS)
                        if let heartRate = store.workoutController.heartRateBPM {
                            Text("心率 \(Int(heartRate.rounded())) bpm").font(.headline).monospacedDigit()
                        }
                        if let energy = store.workoutController.activeEnergyKcal {
                            Text("活动能量 \(Int(energy.rounded())) kcal").font(.caption).monospacedDigit()
                        }
                        if let error = store.workoutController.errorMessage {
                            Text(error).font(.caption).foregroundStyle(.secondary)
                        }
                        #endif
                    }

                    if !breathingComplete {
                        #if os(watchOS)
                        if activity.kind == .workout && !store.workoutController.hasSession && !store.workoutController.canRetrySave {
                            Button("恢复系统运动") { Task { await store.workoutController.recoverActiveSession() } }
                                .buttonStyle(.bordered).disabled(store.workoutController.isStarting)
                        } else {
                            Button(activity.isPaused ? "继续计时" : "暂停") { pauseOrResume(activity) }
                                .buttonStyle(.bordered)
                                .disabled(activity.kind == .workout && (store.workoutController.canRetrySave || store.workoutController.isSaving))
                        }
                        #else
                        Button(activity.isPaused ? "继续计时" : "暂停") {
                            pauseOrResume(activity)
                        }
                        .buttonStyle(.bordered)
                        #endif
                    }

                    Button("完成并记录") {
                        #if os(watchOS)
                        if activity.kind == .workout { store.workoutController.pause() } else { store.pause() }
                        #else
                        store.pause()
                        #endif
                        showsFinish = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(elapsed < 1)
                    #if os(watchOS)
                    .disabled(activity.kind == .workout && (!store.workoutController.hasSession && !store.workoutController.canRetrySave))
                    #endif
                }
                .frame(maxWidth: .infinity)
                #if os(watchOS)
                .onChange(of: Int(elapsed)) { _, _ in store.breathingCue(at: context.date) }
                #endif
            }

            if case .breathing = activity.kind {
                Text("自然呼吸，不屏息；感觉不适时暂停或结束。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let capturedRecommendation = activity.recommendation {
                recommendationSteps(capturedRecommendation)
            }
            Text("关闭页面后计时仍保留，可从首页继续。")
                .font(.caption).foregroundStyle(.secondary)
            Button("放弃本次活动", role: .destructive) {
                #if os(watchOS)
                if activity.kind == .workout { store.workoutController.discard() } else { store.discardActive() }
                #else
                store.discardActive()
                #endif
                dismiss()
            }.font(.caption).buttonStyle(.bordered)
        }
    }

    private func pauseOrResume(_ activity: ActiveActivity) {
        #if os(watchOS)
        if activity.kind == .workout {
            if activity.isPaused { store.workoutController.resume() } else { store.workoutController.pause() }
            return
        }
        #endif
        if activity.isPaused { store.resume() } else { store.pause() }
    }

    private func breathingHasFinished(_ activity: ActiveActivity, elapsed: TimeInterval) -> Bool {
        guard case .breathing = activity.kind else { return false }
        return elapsed >= Double(activity.targetSeconds ?? 60)
    }

    private func breathingGuide(elapsed: TimeInterval, paused: Bool, completed: Bool) -> some View {
        let phase = elapsed.truncatingRemainder(dividingBy: 10)
        let expansion = completed ? 0.5 : (phase < 4 ? phase / 4 : 1 - (phase - 4) / 6)
        return VStack(spacing: 8) {
            Circle()
                .fill(store.preferences.settings.theme.tint.opacity(0.22))
                .overlay(Circle().stroke(store.preferences.settings.theme.tint.opacity(0.7), lineWidth: 2))
                .frame(width: activityBreathingDiameter, height: activityBreathingDiameter)
                .scaleEffect(reduceMotion ? 1 : 0.72 + expansion * 0.28)
                .accessibilityHidden(true)
            Text(completed ? "已完成" : (paused ? "已暂停" : (phase < 4 ? "轻柔吸气" : "缓缓呼气")))
                .font(.headline)
        }
    }

    private func matchesRequestedActivity(_ activity: ActiveActivity) -> Bool {
        switch activity.kind {
        case .breathing: return recommendation == nil
        case .workout: return recommendation != nil
        case .checkIn: return false
        }
    }

    private func recommendationSteps(_ recommendation: WorkoutRecommendation) -> some View {
        let steps = VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(recommendation.steps.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !recommendation.cautionText.isEmpty {
                Text(recommendation.cautionText)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 8)
        #if os(watchOS)
        return VStack(alignment: .leading, spacing: 8) {
            Button(showsWorkoutSteps ? "收起步骤" : "展开活动步骤") {
                showsWorkoutSteps.toggle()
            }
            .buttonStyle(.plain)
            if showsWorkoutSteps { steps }
        }
        .font(.caption.weight(.semibold))
        #else
        return DisclosureGroup("活动步骤") { steps }
        .font(.caption.weight(.semibold))
        #endif
    }
}

struct FeelingCheckInView: View {
    @ObservedObject var store: ActivityStore
    @Environment(\.dismiss) private var dismiss
    @State private var savedRecord: ActivityRecord?
    @State private var saveMessage: String?

    var body: some View {
        #if os(watchOS)
        checkInContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .bottom)
        #else
        NavigationStack {
            checkInContent
                .navigationTitle("记录感受")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(savedRecord == nil ? "取消" : "关闭") { dismiss() }
                    }
                }
        }
        #endif
    }

    private var checkInContent: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    #if os(watchOS)
                    Text("记录感受").font(.headline)
                    #endif
                    if let savedRecord {
                        Label("感受已保存", systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(.green)
                        ActivityRecordRow(record: savedRecord)
                        #if !os(watchOS)
                        Button("完成") { dismiss() }
                            .buttonStyle(.borderedProminent)
                        #endif
                    } else {
                        Text("此刻身体感觉如何？")
                            .font(.headline)
                        Text("记录自己的感受，便于之后回看。")
                            .font(.caption).foregroundStyle(.secondary)
                        FeelingChoices { feeling in
                            guard savedRecord == nil else { return }
                            let previousIDs = Set(store.records.map(\.id))
                            store.recordFeeling(feeling)
                            savedRecord = store.records.first { !previousIDs.contains($0.id) }
                            saveMessage = savedRecord == nil ? "记录暂未保存，请重试。" : nil
                        }
                        if let saveMessage {
                            Text(saveMessage).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(activityPagePadding)
            }
    }
}

private struct ActivityFinishView: View {
    @ObservedObject var store: ActivityStore
    let onSaved: (ActivityRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var saveMessage: String?

    var body: some View {
        #if os(watchOS)
        finishContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .bottom)
        #else
        NavigationStack {
            finishContent
                .navigationTitle("完成活动")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("返回计时") { dismiss() }
                    }
                }
        }
        #endif
    }

    private var finishContent: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    #if os(watchOS)
                    Text("完成活动").font(.headline)
                    #endif
                    Text("计时已暂停，记录结束时的感受。")
                        .font(.caption).foregroundStyle(.secondary)
                    FeelingChoices { save(feeling: $0) }
                    Button("跳过感受并完成") { save(feeling: nil) }
                        .buttonStyle(.bordered)
                    if let saveMessage {
                        Text(saveMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    if isSaving { ProgressView("正在保存记录…").font(.caption) }
                }
                .disabled(isSaving)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(activityPagePadding)
            }
    }

    private func save(feeling: BodyFeeling?) {
        guard !isSaving else { return }
        isSaving = true
        Task { @MainActor in
        let record: ActivityRecord?
        #if os(watchOS)
        if store.active?.kind == .workout {
            record = store.workoutController.canRetrySave ? await store.workoutController.retrySave(feeling: feeling) :
                await store.workoutController.finish(feeling: feeling)
        } else { record = store.finish(feeling: feeling) }
        #else
        record = store.finish(feeling: feeling)
        #endif
        guard let record else {
            isSaving = false
            #if os(watchOS)
            saveMessage = store.workoutController.errorMessage ?? "尚无可保存的计时，请返回继续活动。"
            #else
            saveMessage = "尚无可保存的计时，请返回继续活动。"
            #endif
            return
        }
        onSaved(record)
        }
    }
}

private struct FeelingChoices: View {
    let onSelect: (BodyFeeling) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(BodyFeeling.allCases) { feeling in
                Button { onSelect(feeling) } label: {
                    Label(feeling.title, systemImage: feeling.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct ActivityRecordRow: View {
    let record: ActivityRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.title).font(.caption.weight(.semibold))
            HStack(spacing: 6) {
                if case .checkIn = record.kind {
                    Text("感受记录")
                } else {
                    Text(activityTime(Double(record.durationSeconds)))
                        .monospacedDigit()
                }
                if let feeling = record.feeling {
                    Label(feeling.title, systemImage: feeling.symbol)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            Text(AppDateTime.timestamp(record.completedAt))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

private func activityTime(_ duration: TimeInterval) -> String {
    let seconds = max(0, Int(duration.rounded(.down)))
    if seconds >= 3600 {
        return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

private var activityPagePadding: CGFloat {
    #if os(watchOS)
    8
    #else
    20
    #endif
}

private var activityBreathingDiameter: CGFloat {
    #if os(watchOS)
    48
    #else
    112
    #endif
}

private extension View {
    func activityCard() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(activityPagePadding)
            .background(activityCardColor, in: RoundedRectangle(cornerRadius: 20))
    }

    var activityCardColor: Color {
        #if os(watchOS)
        Color.white.opacity(0.075)
        #else
        Color(.secondarySystemGroupedBackground)
        #endif
    }
}
