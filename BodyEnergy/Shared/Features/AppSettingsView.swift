import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var store: PreferencesStore
    @Environment(\.dismiss) private var dismiss
    #if os(watchOS)
    @State private var showsCards = false
    #endif

    var body: some View {
        #if os(watchOS)
        settingsForm
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .bottom)
            .fullScreenCover(isPresented: $showsCards) { cards }
            .tint(store.settings.theme.tint)
        #else
        NavigationStack {
            settingsForm
                .navigationTitle("设置")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        }
        .tint(store.settings.theme.tint)
        #endif
    }

    private var settingsForm: some View {
        Form {
                Section("外观与首页") {
                    Picker("主题", selection: value(\.theme)) {
                        ForEach(AppTheme.allCases) { theme in Text(theme.title).tag(theme) }
                    }
                    Toggle("折叠最近记录", isOn: value(\.collapseRecentRecords))
                    #if os(watchOS)
                    Button("卡片顺序与显示") { showsCards = true }
                    #else
                    NavigationLink("卡片顺序与显示") { cards }
                    #endif
                }
                Section("训练偏好") {
                    Picker("可用时间", selection: Binding(get: { store.settings.training.availableMinutes }, set: { minutes in
                        store.update { $0.training.availableMinutes = minutes }
                    })) {
                        ForEach([10, 20, 30, 45, 60], id: \.self) { Text("\($0) 分钟").tag($0) }
                    }
                    Picker("器械", selection: Binding(get: { store.settings.training.equipment }, set: { equipment in
                        store.update { $0.training.equipment = equipment }
                    })) {
                        ForEach(TrainingEquipment.allCases) { Text($0.title).tag($0) }
                    }
                    ForEach(TrainingActivity.allCases) { activity in
                        Toggle(activity.title, isOn: Binding(get: { store.settings.training.preferredActivities.contains(activity) }, set: { selected in
                            store.update { settings in
                                if selected { settings.training.preferredActivities.insert(activity) }
                                else { settings.training.preferredActivities.remove(activity) }
                            }
                        }))
                    }
                    Text("偏好用于选择活动方式，今天的电量与恢复状态仍决定强度上限。").font(.caption).foregroundStyle(.secondary)
                }
                Section("恢复目标") {
                    #if os(watchOS)
                    compactGoal("走动目标", value: "\(store.settings.walkingGoalMinutes) 分钟",
                        canDecrease: store.settings.walkingGoalMinutes > 5, canIncrease: store.settings.walkingGoalMinutes < 60,
                        decrease: { store.update { $0.walkingGoalMinutes = max(5, $0.walkingGoalMinutes - 5) } },
                        increase: { store.update { $0.walkingGoalMinutes = min(60, $0.walkingGoalMinutes + 5) } })
                    compactGoal("放松目标", value: "\(store.settings.breathingGoalMinutes) 分钟",
                        canDecrease: store.settings.breathingGoalMinutes > 1, canIncrease: store.settings.breathingGoalMinutes < 10,
                        decrease: { store.update { $0.breathingGoalMinutes = max(1, $0.breathingGoalMinutes - 1) } },
                        increase: { store.update { $0.breathingGoalMinutes = min(10, $0.breathingGoalMinutes + 1) } })
                    compactGoal("睡眠目标", value: "\(store.settings.sleepGoalHours.formatted()) 小时",
                        canDecrease: store.settings.sleepGoalHours > 6, canIncrease: store.settings.sleepGoalHours < 10,
                        decrease: { store.update { $0.sleepGoalHours = max(6, $0.sleepGoalHours - 0.5) } },
                        increase: { store.update { $0.sleepGoalHours = min(10, $0.sleepGoalHours + 0.5) } })
                    #else
                    Stepper("走动 \(store.settings.walkingGoalMinutes) 分钟", value: value(\.walkingGoalMinutes), in: 5...60, step: 5)
                    Stepper("放松 \(store.settings.breathingGoalMinutes) 分钟", value: value(\.breathingGoalMinutes), in: 1...10)
                    Stepper("睡眠目标 \(store.settings.sleepGoalHours.formatted()) 小时", value: value(\.sleepGoalHours), in: 6...10, step: 0.5)
                    #endif
                    timePicker("准备入睡", key: \.bedtimeMinutes)
                    Text("目标可自由调整，休息日可暂停。睡眠目标用于习惯记录，评分仍使用原有模型。").font(.caption).foregroundStyle(.secondary)
                }
                Section("呼吸与手表反馈") {
                    Picker("呼吸时长", selection: value(\.breathingMinutes)) {
                        ForEach([1, 3, 5], id: \.self) { Text("\($0) 分钟").tag($0) }
                    }
                    Toggle("完成时振动", isOn: value(\.watchCompletionHaptics))
                    Toggle("呼吸节奏振动", isOn: value(\.watchRhythmHaptics))
                    Text("节奏提示在手表呼吸页打开时生效，吸气 4 秒、呼气 6 秒。").font(.caption).foregroundStyle(.secondary)
                }
                Section("通知") {
                    #if os(watchOS)
                    Button("开启通知") { store.refreshReminders(requestPermission: true) }
                    if let message = store.reminderMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                    #else
                    Text("在手表中允许通知后，压力状态提醒会自动生效。")
                        .font(.caption).foregroundStyle(.secondary)
                    #endif
                    Text("根据你的个人压力状态自动提醒放松或提示轻松；电量充足时提示元气足。免打扰时段内保持安静，并避免频繁重复提醒。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("定时提醒") {
                    Toggle("恢复与睡前提醒", isOn: value(\.remindersEnabled))
                    if store.settings.remindersEnabled {
                        #if !os(watchOS)
                        Button("检查通知权限") { store.refreshReminders(requestPermission: true) }
                        #endif
                        timePicker("恢复提醒", key: \.reminderMinutes)
                    }
                    Text("开启后按设定时间提醒恢复和准备入睡，提醒只在本机发送。").font(.caption).foregroundStyle(.secondary)
                    #if !os(watchOS)
                    if let message = store.reminderMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                    #endif
                }
                Section("共享免打扰时段") {
                    Toggle("免打扰时段", isOn: value(\.quietHoursEnabled))
                    if store.settings.quietHoursEnabled {
                        timePicker("开始", key: \.quietStartMinutes)
                        timePicker("结束", key: \.quietEndMinutes)
                    }
                    Text("压力状态、恢复与睡前提醒共用此时段。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("身体年龄参考") {
                    Text("在趋势页查看心肺适能年龄参考。需要 Apple 健康中的 VO₂ max、出生日期和生理性别；资料不足时不会生成年龄。").font(.caption).foregroundStyle(.secondary)
                }
            }
    }

    private var cards: some View {
        Form {
            ForEach(Array(store.settings.homeCards.enumerated()), id: \.element) { index, card in
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(card.title, isOn: Binding(get: { !store.settings.hiddenCards.contains(card) }, set: { visible in
                        store.update { settings in
                            if visible { settings.hiddenCards.remove(card) } else { settings.hiddenCards.insert(card) }
                        }
                    }))
                    HStack {
                        Button("上移") { move(index, by: -1) }.disabled(index == 0)
                        Spacer()
                        Button("下移") { move(index, by: 1) }.disabled(index == store.settings.homeCards.count - 1)
                    }.font(.caption).buttonStyle(.bordered)
                }
            }
        }
        #if os(watchOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .bottom)
        #else
        .navigationTitle("首页卡片")
        #endif
    }

    private func move(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard store.settings.homeCards.indices.contains(destination) else { return }
        store.update { $0.homeCards.swapAt(index, destination) }
    }

    private func value<Value>(_ key: WritableKeyPath<AppPreferences, Value>) -> Binding<Value> {
        Binding(get: { store.settings[keyPath: key] }, set: { next in store.update { $0[keyPath: key] = next } })
    }

    #if os(watchOS)
    private func compactGoal(_ title: String, value: String, canDecrease: Bool, canIncrease: Bool,
                             decrease: @escaping () -> Void, increase: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.callout.weight(.semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: decrease) {
                Image(systemName: "minus").font(.callout.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(store.settings.theme.tint.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain).foregroundStyle(store.settings.theme.tint)
            .disabled(!canDecrease).opacity(canDecrease ? 1 : 0.35)
            .accessibilityLabel("减少\(title)")
            Button(action: increase) {
                Image(systemName: "plus").font(.callout.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(store.settings.theme.tint.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain).foregroundStyle(store.settings.theme.tint)
            .disabled(!canIncrease).opacity(canIncrease ? 1 : 0.35)
            .accessibilityLabel("增加\(title)")
        }
        .accessibilityElement(children: .contain)
    }
    #endif

    private func timePicker(_ title: String, key: WritableKeyPath<AppPreferences, Int>) -> some View {
        #if os(watchOS)
        return VStack(alignment: .leading) {
            Text(title).font(.caption)
            HStack {
                Picker("时", selection: Binding(get: { store.settings[keyPath: key] / 60 }, set: { hour in
                    store.update { $0[keyPath: key] = hour * 60 + $0[keyPath: key] % 60 }
                })) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }
                Picker("分", selection: Binding(get: { store.settings[keyPath: key] % 60 }, set: { minute in
                    store.update { $0[keyPath: key] = $0[keyPath: key] / 60 * 60 + minute }
                })) { ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }
            }
        }
        #else
        return DatePicker(title, selection: Binding(get: {
            Calendar.current.date(bySettingHour: store.settings[keyPath: key] / 60, minute: store.settings[keyPath: key] % 60, second: 0, of: .now) ?? .now
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            store.update { $0[keyPath: key] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0) }
        }), displayedComponents: .hourAndMinute)
            .environment(\.locale, Locale(identifier: "zh_CN"))
        #endif
    }
}
