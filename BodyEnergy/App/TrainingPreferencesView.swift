import SwiftUI

struct TrainingPreferencesView: View {
    @ObservedObject var store: PreferencesStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("今天可用时间") {
                    Picker("分钟", selection: Binding(
                        get: { store.settings.training.availableMinutes },
                        set: { minutes in store.update { $0.training.availableMinutes = minutes } }
                    )) {
                        ForEach([10, 20, 30, 45, 60], id: \.self) { minutes in
                            Text("\(minutes) 分钟").tag(minutes)
                        }
                    }
                }
                Section {
                    ForEach(TrainingActivity.allCases) { activity in
                        Toggle(activity.title, isOn: Binding(
                            get: { store.settings.training.preferredActivities.contains(activity) },
                            set: { selected in
                                store.update {
                                    if selected { $0.training.preferredActivities.insert(activity) }
                                    else { $0.training.preferredActivities.remove(activity) }
                                }
                            }
                        ))
                    }
                } header: {
                    Text("喜欢的活动")
                } footer: {
                    Text("可选择多个，建议会结合当前电量与恢复安排。")
                }
                Section("可用器械") {
                    Picker("器械条件", selection: Binding(
                        get: { store.settings.training.equipment },
                        set: { equipment in store.update { $0.training.equipment = equipment } }
                    )) {
                        Text("无需器械").tag(TrainingEquipment.none)
                        Text("哑铃").tag(TrainingEquipment.dumbbells)
                        Text("健身房").tag(TrainingEquipment.gym)
                    }
                }
            }
            .navigationTitle("训练偏好")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

}
