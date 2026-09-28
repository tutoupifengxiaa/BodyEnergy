import SwiftUI

struct ActivityHistoryView: View {
    @ObservedObject var store: ActivityStore
    @State private var period = 7
    @State private var kind: ActivityKind?
    @Environment(\.dismiss) private var dismiss
    #if os(watchOS)
    @State private var selectedRecord: ActivityRecord?
    #endif

    private var records: [ActivityRecord] {
        let start = period == 0 ? Date.distantPast : Calendar.current.date(byAdding: .day, value: -(period - 1), to: Calendar.current.startOfDay(for: .now)) ?? .now
        return store.records.filter { $0.completedAt >= start && (kind == nil || $0.kind == kind) }
            .sorted { $0.completedAt > $1.completedAt }
    }
    private var dates: [Date] {
        Set(records.map { Calendar.current.startOfDay(for: $0.completedAt) }).sorted(by: >)
    }

    var body: some View {
        #if os(watchOS)
        historyList
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .bottom)
            .fullScreenCover(item: $selectedRecord) { record in
                ActivityRecordDetailView(record: record, samples: store.pressureSamples)
            }
            .tint(store.preferences.settings.theme.tint)
        #else
        NavigationStack {
            historyList
                .navigationTitle("全部记录")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }.tint(store.preferences.settings.theme.tint)
        #endif
    }

    private var historyList: some View {
        List {
                Section {
                    Picker("时间", selection: $period) {
                        Text("7 天").tag(7)
                        Text("30 天").tag(30)
                        Text("全部").tag(0)
                    }
                    Picker("类型", selection: $kind) {
                        Text("全部").tag(Optional<ActivityKind>.none)
                        Text("呼吸").tag(Optional(ActivityKind.breathing))
                        Text("运动").tag(Optional(ActivityKind.workout))
                        Text("感受").tag(Optional(ActivityKind.checkIn))
                    }
                    Text("\(records.count) 条记录 · 保留最近 \(ActivityRecord.maximumCount) 条完成记录")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if records.isEmpty {
                    Text("这段时间尚无此类记录。").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(dates, id: \.self) { date in
                    Section(AppDateTime.day(date)) {
                        ForEach(records.filter { Calendar.current.isDate($0.completedAt, inSameDayAs: date) }) { record in
                            #if os(watchOS)
                            Button { selectedRecord = record } label: { ActivityRecordRow(record: record) }
                            #else
                            NavigationLink {
                                ActivityRecordDetailView(record: record, samples: store.pressureSamples)
                            } label: { ActivityRecordRow(record: record) }
                            #endif
                        }
                    }
                }
            }
    }
}

private struct ActivityRecordDetailView: View {
    let record: ActivityRecord
    let samples: [EnergyPressureSample]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                #if os(watchOS)
                Text(record.title).font(.headline)
                #endif
                ActivityRecordRow(record: record)
                Text("来自 \(record.source == .appleWatch ? "Apple Watch" : "iPhone")")
                    .font(.caption).foregroundStyle(.secondary)
                if let metrics = record.workoutMetrics {
                    if let heartRate = metrics.averageHeartRate { Text("平均心率 \(Int(heartRate.rounded())) bpm").monospacedDigit() }
                    if let kcal = metrics.activeEnergyKcal { Text("活动能量 \(Int(kcal.rounded())) kcal").monospacedDigit() }
                    if metrics.healthWorkoutID != nil {
                        Label("运动已保存到 Apple 健康", systemImage: "checkmark.circle").font(.caption)
                    }
                }
                Divider()
                Text("与真实压力采样一起回看").font(.headline)
                let before = EnergyPressureSample.nearest(to: record.startedAt, in: samples)
                let after = EnergyPressureSample.nearest(to: record.completedAt, in: samples)
                if let before {
                    sample(before, title: record.kind == .checkIn ? "记录前最近采样" : "活动开始前最近采样")
                } else {
                    Text("开始前 2 小时内没有压力采样。").font(.caption).foregroundStyle(.secondary)
                }
                if let after, after.date > (before?.date ?? .distantPast) {
                    sample(after, title: "结束前最近采样")
                } else if record.kind != .checkIn {
                    Text("活动期间没有新的压力采样。").font(.caption).foregroundStyle(.secondary)
                }
                Text("仅关联此前 2 小时内的真实采样，不代表实时压力，也不能据此判断活动效果。")
                    .font(.caption).foregroundStyle(.secondary)
                if let sampledAt = (after ?? before)?.date {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("采集时间").font(.caption.weight(.semibold))
                        Text(AppDateTime.timestamp(sampledAt)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        #if os(watchOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .bottom)
        #else
        .navigationTitle(record.title)
        #endif
    }

    private func sample(_ sample: EnergyPressureSample, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title)：\(sample.score) 分").font(.subheadline)
            Text(sample.metric.title)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

}
