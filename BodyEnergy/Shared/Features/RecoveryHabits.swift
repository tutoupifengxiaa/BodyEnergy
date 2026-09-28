import Combine
import Foundation
import SwiftUI

enum RecoveryHabit: String, CaseIterable, Identifiable, Codable, Sendable {
    case walking, breathing, sleepRoutine
    var id: String { rawValue }
    var title: String {
        switch self {
        case .walking: return "轻松走动"
        case .breathing: return "放松呼吸"
        case .sleepRoutine: return "按时准备入睡"
        }
    }
    var symbol: String {
        switch self {
        case .walking: return "figure.walk"
        case .breathing: return "wind"
        case .sleepRoutine: return "moon"
        }
    }
}

struct HabitDay: Codable, Equatable, Identifiable, Sendable {
    var date: Date
    var completed: Set<RecoveryHabit>
    var isRestDay: Bool
    var modifiedAt: Date
    var id: Date { date }
}

@MainActor
final class RecoveryHabitStore: ObservableObject {
    @Published private(set) var days: [HabitDay]
    @Published private(set) var feedback: String?
    let preferences: PreferencesStore
    var onChanged: (([HabitDay]) -> Void)?
    private let defaults: UserDefaults
    private let key = "habits.days.v1"
    private var subscriptions = Set<AnyCancellable>()

    init(defaults: UserDefaults = .standard, preferences: PreferencesStore) {
        self.defaults = defaults
        self.preferences = preferences
        days = Self.normalized(defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([HabitDay].self, from: $0) } ?? [])
        preferences.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
    }

    func day(on date: Date = .now) -> HabitDay {
        let start = Calendar.current.startOfDay(for: date)
        return days.first { Calendar.current.isDate($0.date, inSameDayAs: start) } ??
            HabitDay(date: start, completed: [], isRestDay: false, modifiedAt: .distantPast)
    }

    func toggle(_ habit: RecoveryHabit, on date: Date = .now) {
        var current = day(on: date)
        if current.completed.contains(habit) { current.completed.remove(habit); feedback = "已取消完成标记。" }
        else { current.completed.insert(habit); feedback = "\(habit.title)已完成，给今天留了一点恢复时间。" }
        current.modifiedAt = .now
        save(current)
    }

    func setRestDay(_ resting: Bool, on date: Date = .now) {
        var current = day(on: date)
        current.isRestDay = resting
        current.modifiedAt = .now
        feedback = resting ? "今天按休息日安排，目标可以暂停。" : "已恢复今天的轻量目标。"
        save(current)
    }

    func markCompleted(_ habit: RecoveryHabit, on date: Date) {
        var current = day(on: date)
        guard !current.completed.contains(habit) else { return }
        current.completed.insert(habit)
        current.modifiedAt = .now
        feedback = "\(habit.title)目标已完成。"
        save(current)
    }

    @discardableResult
    func merge(_ incoming: [HabitDay]) -> Bool {
        let next = Self.normalized(days + incoming)
        guard next != days else { return false }
        days = next
        persist()
        return true
    }

    private func save(_ day: HabitDay) {
        days = Self.normalized(days.filter { !Calendar.current.isDate($0.date, inSameDayAs: day.date) } + [day])
        persist()
        onChanged?(days)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(days) { defaults.set(data, forKey: key) }
    }

    private static func normalized(_ values: [HabitDay]) -> [HabitDay] {
        let calendar = Calendar.current
        let oldest = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: .now)) ?? .distantPast
        var result: [Date: HabitDay] = [:]
        for value in values where value.date.timeIntervalSince1970.isFinite && value.modifiedAt.timeIntervalSince1970.isFinite &&
            value.date >= oldest && value.date <= Date.now.addingTimeInterval(300) && value.modifiedAt <= Date.now.addingTimeInterval(300) {
            var day = value
            day.date = calendar.startOfDay(for: value.date)
            if let previous = result[day.date] {
                let previousSignature = previous.completed.map(\.rawValue).sorted().joined() + String(previous.isRestDay)
                let signature = day.completed.map(\.rawValue).sorted().joined() + String(day.isRestDay)
                if previous.modifiedAt > day.modifiedAt || (previous.modifiedAt == day.modifiedAt && previousSignature >= signature) { continue }
            }
            result[day.date] = day
        }
        return result.values.sorted { $0.date < $1.date }
    }
}

struct RecoveryHabitsView: View {
    @ObservedObject var store: RecoveryHabitStore
    @State private var showsGoals = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let today = store.day(on: context.date)
            VStack(alignment: .leading, spacing: 12) {
                Label("恢复习惯", systemImage: "leaf.circle").font(.headline)
                Toggle("今天休息", isOn: Binding(get: { today.isRestDay }, set: { store.setRestDay($0) }))
                if today.isRestDay {
                    Text("休息也是恢复，今天没有必须完成的目标。").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(RecoveryHabit.allCases) { habit in
                        Button { store.toggle(habit) } label: {
                            HStack {
                                Image(systemName: today.completed.contains(habit) ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading) {
                                    Text(habit.title)
                                    Text(goal(for: habit)).font(.caption).foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }
                if let feedback = store.feedback { Text(feedback).font(.caption).foregroundStyle(.secondary) }
                Text("近 7 天：\(weekCompleted(on: context.date)) 天完成目标或安排休息").font(.caption).foregroundStyle(.secondary)
                Button("调整目标") { showsGoals = true }.font(.caption)
            }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        .sheet(isPresented: $showsGoals) { AppSettingsView(store: store.preferences) }
    }

    private func goal(for habit: RecoveryHabit) -> String {
        let settings = store.preferences.settings
        switch habit {
        case .walking: return "\(settings.walkingGoalMinutes) 分钟，可手动记录或完成步行计时"
        case .breathing: return "\(settings.breathingGoalMinutes) 分钟，呼吸记录会计入目标"
        case .sleepRoutine: return "\(String(format: "%02d:%02d", settings.bedtimeMinutes / 60, settings.bedtimeMinutes % 60)) 准备入睡 · 睡眠目标 \(settings.sleepGoalHours.formatted()) 小时"
        }
    }

    private func weekCompleted(on now: Date) -> Int {
        let oldest = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: now)) ?? now
        return store.days.filter { $0.date >= oldest && $0.date <= now && ($0.isRestDay || $0.completed.count == RecoveryHabit.allCases.count) }.count
    }
}
