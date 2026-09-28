import Combine
import Foundation
import SwiftUI
import UserNotifications
#if os(watchOS)
import WatchKit
#endif

enum TrainingActivity: String, CaseIterable, Identifiable, Codable, Sendable {
    case walking, running, cycling, strength, mobility
    var id: String { rawValue }
    var title: String {
        switch self {
        case .walking: return "步行"
        case .running: return "跑步"
        case .cycling: return "骑行"
        case .strength: return "力量"
        case .mobility: return "舒展"
        }
    }
}

enum TrainingEquipment: String, CaseIterable, Identifiable, Codable, Sendable {
    case none, dumbbells, gym
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "无器械"
        case .dumbbells: return "哑铃"
        case .gym: return "健身房"
        }
    }
}

struct TrainingPreferences: Codable, Equatable, Sendable {
    var availableMinutes = 30
    var preferredActivities: Set<TrainingActivity> = []
    var equipment: TrainingEquipment = .none
}

enum HomeCard: String, CaseIterable, Identifiable, Codable, Sendable {
    case recommendation, actions, habits, dataState, hourlyStress, metrics, battery, stressTrend
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recommendation: return "今日建议"
        case .actions: return "今日行动"
        case .habits: return "恢复习惯"
        case .dataState: return "数据状态"
        case .hourlyStress: return "今日压力"
        case .metrics: return "健康指标"
        case .battery: return "电量趋势"
        case .stressTrend: return "压力趋势"
        }
    }
    var symbol: String {
        switch self {
        case .recommendation: return "figure.walk"
        case .actions: return "leaf"
        case .habits: return "checkmark.circle"
        case .dataState: return "info.circle"
        case .hourlyStress: return "waveform.path.ecg"
        case .metrics: return "heart"
        case .battery: return "battery.75percent"
        case .stressTrend: return "chart.xyaxis.line"
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case forest, ocean, sunset, lavender, rose, graphite
    var id: String { rawValue }
    var title: String {
        switch self {
        case .forest: return "森林"
        case .ocean: return "海洋"
        case .sunset: return "落日"
        case .lavender: return "薰衣草"
        case .rose: return "玫瑰"
        case .graphite: return "石墨"
        }
    }
    var tint: Color {
        switch self {
        case .forest: return .mint
        case .ocean: return .blue
        case .sunset: return .orange
        case .lavender: return .purple
        case .rose: return .pink
        case .graphite: return .gray
        }
    }
    var background: Color { tint.opacity(0.06) }
}

struct AppPreferences: Codable, Equatable, Sendable {
    var training = TrainingPreferences()
    var homeCards: [HomeCard] = HomeCard.allCases
    var hiddenCards: Set<HomeCard> = []
    var theme: AppTheme = .forest
    var collapseRecentRecords = false
    var breathingMinutes = 1
    var watchCompletionHaptics = true
    var watchRhythmHaptics = false
    var walkingGoalMinutes = 10
    var breathingGoalMinutes = 1
    var sleepGoalHours = 8.0
    var bedtimeMinutes = 22 * 60 + 30
    var remindersEnabled = false
    var reminderMinutes = 18 * 60
    var quietHoursEnabled = true
    var quietStartMinutes = 23 * 60
    var quietEndMinutes = 8 * 60
    var modifiedAt: Date = .distantPast
    var revision = UUID()

    func isQuiet(atMinutes minute: Int) -> Bool {
        guard quietHoursEnabled, quietStartMinutes != quietEndMinutes else { return false }
        if quietStartMinutes < quietEndMinutes {
            return minute >= quietStartMinutes && minute < quietEndMinutes
        }
        return minute >= quietStartMinutes || minute < quietEndMinutes
    }

    var normalized: Self {
        var result = self
        result.training.availableMinutes = min(60, max(10, training.availableMinutes))
        var seen = Set<HomeCard>()
        result.homeCards = (homeCards + HomeCard.allCases).filter { seen.insert($0).inserted }
        result.breathingMinutes = [1, 3, 5].contains(breathingMinutes) ? breathingMinutes : 1
        result.walkingGoalMinutes = min(60, max(5, walkingGoalMinutes))
        result.breathingGoalMinutes = min(10, max(1, breathingGoalMinutes))
        result.sleepGoalHours = sleepGoalHours.isFinite ? min(10, max(6, sleepGoalHours)) : 8
        result.bedtimeMinutes = min(1439, max(0, bedtimeMinutes))
        result.reminderMinutes = min(1439, max(0, reminderMinutes))
        result.quietStartMinutes = min(1439, max(0, quietStartMinutes))
        result.quietEndMinutes = min(1439, max(0, quietEndMinutes))
        return result
    }
}

@MainActor
final class PreferencesStore: ObservableObject {
    @Published private(set) var settings: AppPreferences
    @Published private(set) var reminderMessage: String?
    var onChanged: ((AppPreferences) -> Void)?
    private let defaults: UserDefaults
    private let key = "preferences.user.v1"
    private var reminderTask: Task<Void, Never>?
    private var authorizationTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) }?.normalized ?? AppPreferences()
    }

    func update(_ change: (inout AppPreferences) -> Void) {
        var next = settings
        change(&next)
        next = next.normalized
        guard next != settings else { return }
        let notificationChanged = next.remindersEnabled != settings.remindersEnabled ||
            next.reminderMinutes != settings.reminderMinutes || next.bedtimeMinutes != settings.bedtimeMinutes ||
            next.quietHoursEnabled != settings.quietHoursEnabled || next.quietStartMinutes != settings.quietStartMinutes ||
            next.quietEndMinutes != settings.quietEndMinutes
        let requestPermission = next.remindersEnabled && !settings.remindersEnabled
        next.modifiedAt = .now
        next.revision = UUID()
        settings = next
        persist()
        onChanged?(next)
        if notificationChanged { refreshReminders(requestPermission: requestPermission) }
    }

    @discardableResult
    func merge(_ incoming: AppPreferences) -> Bool {
        guard incoming.modifiedAt.timeIntervalSince1970.isFinite,
              incoming.modifiedAt <= Date.now.addingTimeInterval(300) else { return false }
        let next = incoming.normalized
        guard next.modifiedAt > settings.modifiedAt ||
                (next.modifiedAt == settings.modifiedAt && next.revision.uuidString > settings.revision.uuidString) else { return false }
        settings = next
        persist()
        refreshReminders(requestPermission: false)
        return true
    }

    func refreshReminders(requestPermission: Bool = false) {
        if requestPermission, hasLocalNotificationFeature { requestNotificationPermission() }
        reminderTask?.cancel()
        reminderTask = Task { [weak self] in
            guard let self else { return }
            let center = UNUserNotificationCenter.current()
            let ids = ["bodyenergy.habit", "bodyenergy.bedtime"]
            center.removePendingNotificationRequests(withIdentifiers: ids)
            guard self.hasLocalNotificationFeature else { self.reminderMessage = nil; return }
            let notificationSettings = await center.notificationSettings()
            guard !Task.isCancelled, self.hasLocalNotificationFeature else { return }
            let allowed = [.authorized, .provisional].contains(notificationSettings.authorizationStatus)
            guard allowed else {
                if notificationSettings.authorizationStatus == .notDetermined {
                    self.reminderMessage = self.authorizationTask == nil ? "尚未允许通知，可在此开启。" : "正在确认通知权限。"
                } else { self.reminderMessage = "通知未获允许，可在系统设置中开启。" }
                return
            }
            guard self.settings.remindersEnabled else {
                #if os(watchOS)
                self.reminderMessage = "通知已允许，将按个人压力状态自动提醒，并遵循免打扰时段。"
                #else
                self.reminderMessage = nil
                #endif
                return
            }
            let reminders: [(String, Int, String, String)] = [
                (ids[0], self.settings.reminderMinutes, "留一点恢复时间", "按今天的感受走动、放松，或选择休息日。"),
                (ids[1], self.settings.bedtimeMinutes, "准备放松入睡", "可以开始睡前放松，让作息更规律。")
            ]
            var scheduled = 0
            for (id, minutes, title, body) in reminders where !self.settings.isQuiet(atMinutes: minutes) {
                guard !Task.isCancelled else { return }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: minutes / 60, minute: minutes % 60), repeats: true)
                do {
                    try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                    scheduled += 1
                } catch { self.reminderMessage = "提醒未能保存，请稍后重试。"; return }
            }
            #if os(watchOS)
            self.reminderMessage = scheduled == 0 ? "通知已允许；定时提醒处于免打扰时段，压力状态自动提醒。" : "通知已允许；每天 \(scheduled) 次定时提醒，压力状态自动提醒。"
            #else
            self.reminderMessage = scheduled == 0 ? "提醒时间处于免打扰时段，已暂停提醒。" : "每天 \(scheduled) 次提醒，免打扰时段内保持安静。"
            #endif
        }
    }

    private var hasLocalNotificationFeature: Bool {
        #if os(watchOS)
        true
        #else
        settings.remindersEnabled
        #endif
    }

    private func requestNotificationPermission() {
        guard authorizationTask == nil else { return }
        authorizationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.authorizationTask = nil
                self.refreshReminders()
            }
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            #if os(watchOS)
            guard WKApplication.shared().applicationState == .active else { return }
            #endif
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: key) }
    }
}
