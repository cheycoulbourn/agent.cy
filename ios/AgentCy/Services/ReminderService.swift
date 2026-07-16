import Foundation
import SwiftData
import UserNotifications

@MainActor
protocol ReminderServicing {
    func apply(_ settings: ReminderSettings) async throws
    func requestAuthorization() async throws -> Bool
    func authorizationStatus() async -> AgentNotificationAuthorization
    func reconcile(context: ModelContext, now: Date) async throws -> [AgentNotificationPreview]
    func applyFocusReminder(id: UUID, enabled: Bool, date: Date?, title: String, body: String) async throws
    func cancelAll() async
}

extension ReminderServicing {
    func requestAuthorization() async throws -> Bool { true }
    func authorizationStatus() async -> AgentNotificationAuthorization { .authorized }

    func reconcile(context: ModelContext, now: Date = Date()) async throws -> [AgentNotificationPreview] {
        guard let settings = try context.fetch(FetchDescriptor<ReminderSettings>()).first else { return [] }
        try await apply(settings)
        return []
    }
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
    static let managedIdentifierPrefixes = ["agentcy.v2.", "agentcy.daily", "agentcy.weekly", "agentcy.focus."]

    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    init(center: UNUserNotificationCenter = .current(), calendar: Calendar = .current) {
        self.center = center
        self.calendar = calendar
    }

    /// Kept for compatibility with tests and the privacy coordinator. Full scheduling uses reconcile.
    func apply(_ settings: ReminderSettings) async throws {
        guard settings.masterEnabled else {
            await removeManagedPendingRequests()
            return
        }
        let status = await authorizationStatus()
        if status == .denied { throw ReminderServiceError.permissionDenied }
    }

    func requestAuthorization() async throws -> Bool {
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else { throw ReminderServiceError.permissionDenied }
        return true
    }

    func authorizationStatus() async -> AgentNotificationAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return AgentNotificationAuthorization.notDetermined
        case .denied: return AgentNotificationAuthorization.denied
        case .authorized: return AgentNotificationAuthorization.authorized
        case .provisional: return AgentNotificationAuthorization.provisional
        case .ephemeral: return AgentNotificationAuthorization.ephemeral
        @unknown default: return AgentNotificationAuthorization.notDetermined
        }
    }

    func reconcile(context: ModelContext, now: Date = Date()) async throws -> [AgentNotificationPreview] {
        let input = try makePlanningInput(context: context, now: now)
        let plan = AgentNotificationPlanBuilder.build(input)
        await removeManagedPendingRequests()

        let authorization = await authorizationStatus()
        guard input.settings.masterEnabled, authorization.canSchedule else {
            if authorization == .denied { throw ReminderServiceError.permissionDenied }
            return []
        }

        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.categoryIdentifier = item.categoryIdentifier
            content.sound = item.playsSound ? .default : nil
            content.badge = nil
            content.userInfo = item.metadata

            let interval = max(1, item.fireDate.timeIntervalSince(now))
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            try await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }

        return plan.prefix(3).map {
            AgentNotificationPreview(
                id: $0.id,
                fireDate: $0.fireDate,
                reason: $0.reason,
                relatedTitle: input.settings.showTitles ? $0.body : nil,
                kind: $0.kind,
                metadata: $0.metadata
            )
        }
    }

    func applyFocusReminder(
        id: UUID,
        enabled: Bool,
        date: Date?,
        title: String,
        body: String
    ) async throws {
        let identifier = "agentcy.v2.focus.\(id.uuidString.lowercased())"
        center.removePendingNotificationRequests(withIdentifiers: [identifier, "agentcy.focus.\(id.uuidString)"])
        guard enabled, let date else { return }
        guard date > Date() else { throw ReminderServiceError.reminderDatePassed }
        let status = await authorizationStatus()
        guard status.canSchedule else {
            if status == .notDetermined { _ = try await requestAuthorization() }
            else { throw ReminderServiceError.permissionDenied }
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Focus: \(title)"
        content.body = body.isEmpty ? "Start with one clear next step." : body
        content.sound = .default
        content.categoryIdentifier = AgentNotificationCategory.focus
        content.badge = nil
        content.userInfo = [
            AgentNotificationMetadataKey.kind: AgentNotificationKind.focus.rawValue,
            AgentNotificationMetadataKey.focusDetailID: id.uuidString,
            AgentNotificationMetadataKey.date: ISO8601DateFormatter().string(from: date),
            AgentNotificationMetadataKey.route: "day",
        ]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func cancelAll() async {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    static func registerCategories(center: UNUserNotificationCenter = .current()) {
        let foreground: UNNotificationActionOptions = [.foreground]
        let daily = UNNotificationCategory(
            identifier: AgentNotificationCategory.daily,
            actions: [
                UNNotificationAction(identifier: AgentNotificationAction.moveTask, title: "Move", options: foreground),
                UNNotificationAction(identifier: AgentNotificationAction.pauseTask, title: "Pause"),
                UNNotificationAction(identifier: AgentNotificationAction.completeTask, title: "Complete"),
            ],
            intentIdentifiers: []
        )
        let weekly = UNNotificationCategory(
            identifier: AgentNotificationCategory.weekly,
            actions: [UNNotificationAction(identifier: AgentNotificationAction.planWithCy, title: "Plan with Cy", options: foreground)],
            intentIdentifiers: []
        )
        let postActions = [
            UNNotificationAction(identifier: AgentNotificationAction.markPosted, title: "Mark Posted"),
            UNNotificationAction(identifier: AgentNotificationAction.reschedulePost, title: "Reschedule", options: foreground),
        ]
        let draft = UNNotificationCategory(
            identifier: AgentNotificationCategory.draft,
            actions: [
                UNNotificationAction(identifier: AgentNotificationAction.finishDraft, title: "Finish Draft", options: foreground),
                UNNotificationAction(identifier: AgentNotificationAction.moveDraft, title: "Move It", options: foreground),
            ],
            intentIdentifiers: []
        )
        let task = UNNotificationCategory(
            identifier: AgentNotificationCategory.task,
            actions: [
                UNNotificationAction(identifier: AgentNotificationAction.completeTask, title: "Complete"),
                UNNotificationAction(identifier: AgentNotificationAction.openTask, title: "Open Task", options: foreground),
            ],
            intentIdentifiers: []
        )
        let access = UNNotificationCategory(
            identifier: AgentNotificationCategory.access,
            actions: [UNNotificationAction(identifier: AgentNotificationAction.openAccess, title: "View Access", options: foreground)],
            intentIdentifiers: []
        )
        center.setNotificationCategories([
            daily,
            weekly,
            UNNotificationCategory(identifier: AgentNotificationCategory.post, actions: postActions, intentIdentifiers: []),
            UNNotificationCategory(identifier: AgentNotificationCategory.missedPost, actions: postActions, intentIdentifiers: []),
            draft,
            task,
            UNNotificationCategory(identifier: AgentNotificationCategory.focus, actions: [], intentIdentifiers: []),
            access,
        ])
    }

    private func removeManagedPendingRequests() async {
        let requests = await center.pendingNotificationRequests()
        let identifiers = requests.map(\.identifier).filter { identifier in
            Self.managedIdentifierPrefixes.contains { identifier.hasPrefix($0) }
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func makePlanningInput(context: ModelContext, now: Date) throws -> NotificationPlanningInput {
        let settings = try context.fetch(FetchDescriptor<ReminderSettings>()).first ?? ReminderSettings()
        let workspaces = try context.fetch(FetchDescriptor<CreatorWorkspace>())
        let activeID = WorkspaceScope.activeWorkspaceID(
            preferredID: CreatorWorkspacePreferences.activeWorkspaceID,
            workspaces: workspaces
        )
        let briefs = try context.fetch(FetchDescriptor<CreativeBrief>()).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }
        let outputs = try context.fetch(FetchDescriptor<PlatformOutput>()).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }
        let tasks = try context.fetch(FetchDescriptor<CreatorTask>()).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }
        let templates = try context.fetch(FetchDescriptor<DailyFocusTemplateEntry>()).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }
        let overrides = try context.fetch(FetchDescriptor<DailyFocusOverride>()).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }
        let details = try context.fetch(FetchDescriptor<DailyFocusDayDetail>()).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }
        let accounts = try context.fetch(FetchDescriptor<CreatorSocialAccount>()).filter {
            !$0.isArchived && WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }
        let destinations = try context.fetch(FetchDescriptor<PublishingDestination>()).filter { !$0.isArchived }
        let subscriptions = try context.fetch(FetchDescriptor<SubscriptionState>())
        let destinationByID = Dictionary(uniqueKeysWithValues: destinations.map { ($0.id, $0.name) })
        let horizonDays = 21
        let dayStart = calendar.startOfDay(for: now)
        let resolvedFocuses = (0...horizonDays).compactMap { offset -> NotificationFocusSnapshot? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: dayStart),
                  let focus = DailyFocusResolver.resolve(date: date, templates: templates, overrides: overrides, calendar: calendar) else {
                return nil
            }
            return NotificationFocusSnapshot(date: date, title: focus.title)
        }

        return NotificationPlanningInput(
            now: now,
            calendar: calendar,
            settings: NotificationSettingsSnapshot(
                masterEnabled: settings.masterEnabled,
                dailyEnabled: settings.dailyEnabled,
                dailyHour: settings.dailyHour,
                dailyMinute: settings.dailyMinute,
                weeklyEnabled: settings.weeklyEnabled,
                weeklyWeekday: settings.weeklyWeekday,
                weeklyHour: settings.weeklyHour,
                weeklyMinute: settings.weeklyMinute,
                postRemindersEnabled: settings.postRemindersEnabled,
                missedPostRemindersEnabled: settings.missedPostRemindersEnabled,
                taskRemindersEnabled: settings.taskRemindersEnabled,
                draftPrepRemindersEnabled: settings.draftPrepRemindersEnabled,
                accessRemindersEnabled: settings.accessRemindersEnabled,
                draftPrepHour: settings.draftPrepHour,
                draftPrepMinute: settings.draftPrepMinute,
                dateOnlyDeadlineHour: settings.dateOnlyDeadlineHour,
                dateOnlyDeadlineMinute: settings.dateOnlyDeadlineMinute,
                quietHoursEnabled: settings.quietHoursEnabled,
                quietHoursStartHour: settings.quietHoursStartHour,
                quietHoursStartMinute: settings.quietHoursStartMinute,
                quietHoursEndHour: settings.quietHoursEndHour,
                quietHoursEndMinute: settings.quietHoursEndMinute,
                showTitles: settings.showNotificationTitles
            ),
            briefs: briefs.map {
                NotificationBriefSnapshot(id: $0.id, title: $0.title, status: $0.status, updatedAt: $0.updatedAt)
            },
            outputs: outputs.map {
                NotificationOutputSnapshot(
                    id: $0.id,
                    briefID: $0.briefID,
                    status: $0.status,
                    targetDate: $0.targetDate,
                    includesTargetTime: $0.includesTargetTime,
                    destinationID: $0.destinationID,
                    destinationName: $0.destinationID.flatMap { destinationByID[$0] } ?? $0.platform.shortTitle,
                    accountID: $0.socialAccountID
                )
            },
            tasks: tasks.filter { !$0.isSkipped }.map {
                NotificationTaskSnapshot(
                    id: $0.id,
                    briefID: $0.briefID,
                    title: $0.title,
                    priority: $0.priority,
                    isCompleted: $0.isCompleted,
                    targetDate: $0.targetDate,
                    includesTargetTime: $0.includesTargetTime,
                    parentTaskID: $0.parentTaskID
                )
            },
            focuses: resolvedFocuses,
            focusReminders: details.compactMap { detail in
                guard detail.reminderEnabled, let reminderDate = detail.reminderDate else { return nil }
                let focus = DailyFocusResolver.resolve(date: detail.date, templates: templates, overrides: overrides, calendar: calendar)
                return NotificationFocusReminderSnapshot(
                    id: detail.id,
                    date: reminderDate,
                    title: focus?.title ?? "Your focus",
                    note: detail.note
                )
            },
            accounts: accounts.map {
                NotificationAccountSnapshot(id: $0.id, destinationID: $0.destinationID, label: $0.label)
            },
            accessEndDate: subscriptions.first.flatMap { state in
                switch AccessPolicy.effectiveAccess(for: state, at: now) {
                case .trial, .comped: state.trialEnd
                default: nil
                }
            },
            horizonDays: horizonDays
        )
    }
}

@MainActor
final class PreviewReminderService: ReminderServicing {
    private(set) var lastSettings: ReminderSettings?
    private(set) var requestedAuthorization = false
    var previewAuthorization: AgentNotificationAuthorization = .authorized
    var previews: [AgentNotificationPreview] = []

    func apply(_ settings: ReminderSettings) async throws {
        lastSettings = settings
    }

    func requestAuthorization() async throws -> Bool {
        requestedAuthorization = true
        guard previewAuthorization != .denied else { throw ReminderServiceError.permissionDenied }
        return true
    }

    func authorizationStatus() async -> AgentNotificationAuthorization { previewAuthorization }

    func reconcile(context: ModelContext, now: Date = Date()) async throws -> [AgentNotificationPreview] {
        if let settings = try context.fetch(FetchDescriptor<ReminderSettings>()).first {
            lastSettings = settings
        }
        return previews
    }

    func applyFocusReminder(id: UUID, enabled: Bool, date: Date?, title: String, body: String) async throws {}

    func cancelAll() async {
        lastSettings = nil
        previews = []
    }
}
