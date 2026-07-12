import Foundation
import UserNotifications

@MainActor
protocol ReminderServicing {
    func apply(_ settings: ReminderSettings) async throws
    func cancelAll() async
}

@MainActor
final class LocalReminderService: ReminderServicing {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func apply(_ settings: ReminderSettings) async throws {
        center.removePendingNotificationRequests(withIdentifiers: ["agentcy.daily", "agentcy.weekly"])
        guard settings.dailyEnabled || settings.weeklyEnabled else { return }
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else { return }

        if settings.dailyEnabled {
            let content = UNMutableNotificationContent()
            content.title = "Ready to make something?"
            content.body = "Open agent.cy and choose one next step."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: settings.dailyHour), repeats: true)
            try await center.add(UNNotificationRequest(identifier: "agentcy.daily", content: content, trigger: trigger))
        }

        if settings.weeklyEnabled {
            let content = UNMutableNotificationContent()
            content.title = "Plan your week"
            content.body = "Review your content and move anything that no longer fits."
            content.sound = .default
            let components = DateComponents(hour: settings.weeklyHour, weekday: settings.weeklyWeekday)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try await center.add(UNNotificationRequest(identifier: "agentcy.weekly", content: content, trigger: trigger))
        }
    }

    func cancelAll() async {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}

@MainActor
final class PreviewReminderService: ReminderServicing {
    private(set) var lastSettings: ReminderSettings?

    func apply(_ settings: ReminderSettings) async throws {
        lastSettings = settings
    }

    func cancelAll() async {
        lastSettings = nil
    }
}
