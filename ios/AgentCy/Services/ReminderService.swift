import Foundation
import UserNotifications

@MainActor
protocol ReminderServicing {
    func apply(_ settings: ReminderSettings) async throws
    func applyFocusReminder(id: UUID, enabled: Bool, date: Date?, title: String, body: String) async throws
    func cancelAll() async
}

enum ReminderServiceError: LocalizedError {
    case permissionDenied
    case reminderDatePassed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Notifications are turned off for agent.cy in iPhone Settings."
        case .reminderDatePassed:
            "Choose a reminder time that has not passed."
        }
    }
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
        guard granted else { throw ReminderServiceError.permissionDenied }

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
            content.title = "A new week is here"
            content.body = "Open Cy when you're ready to shape a calm plan for the week."
            content.sound = .default
            let components = DateComponents(hour: settings.weeklyHour, weekday: 2)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try await center.add(UNNotificationRequest(identifier: "agentcy.weekly", content: content, trigger: trigger))
        }
    }

    func applyFocusReminder(
        id: UUID,
        enabled: Bool,
        date: Date?,
        title: String,
        body: String
    ) async throws {
        let identifier = "agentcy.focus.\(id.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard enabled, let date else { return }
        guard date > Date() else { throw ReminderServiceError.reminderDatePassed }

        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else { throw ReminderServiceError.permissionDenied }

        let content = UNMutableNotificationContent()
        content.title = "Focus: \(title)"
        content.body = body.isEmpty ? "Open agent.cy and start with one clear next step." : body
        content.sound = .default
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
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

    func applyFocusReminder(id: UUID, enabled: Bool, date: Date?, title: String, body: String) async throws {}

    func cancelAll() async {
        lastSettings = nil
    }
}
