import Foundation

enum AgentNotificationAuthorization: String, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    var canSchedule: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: true
        case .notDetermined, .denied: false
        }
    }
}

enum AgentNotificationKind: String, Codable, CaseIterable, Sendable {
    case daily
    case weekly
    case scheduledPost
    case missedPost
    case draftPreparation
    case timedTask
    case focus
    case access
}

enum AgentNotificationCategory {
    static let daily = "AGENTCY_DAILY"
    static let weekly = "AGENTCY_WEEKLY"
    static let post = "AGENTCY_POST"
    static let missedPost = "AGENTCY_MISSED_POST"
    static let draft = "AGENTCY_DRAFT"
    static let task = "AGENTCY_TASK"
    static let focus = "AGENTCY_FOCUS"
    static let access = "AGENTCY_ACCESS"
}

enum AgentNotificationAction {
    static let planWithCy = "AGENTCY_PLAN_WITH_CY"
    static let markPosted = "AGENTCY_MARK_POSTED"
    static let reschedulePost = "AGENTCY_RESCHEDULE_POST"
    static let finishDraft = "AGENTCY_FINISH_DRAFT"
    static let moveDraft = "AGENTCY_MOVE_DRAFT"
    static let completeTask = "AGENTCY_COMPLETE_TASK"
    static let moveTask = "AGENTCY_MOVE_TASK"
    static let pauseTask = "AGENTCY_PAUSE_TASK"
    static let openTask = "AGENTCY_OPEN_TASK"
    static let openAccess = "AGENTCY_OPEN_ACCESS"
}

enum AgentNotificationMetadataKey {
    static let kind = "kind"
    static let briefID = "briefID"
    static let outputID = "outputID"
    static let taskID = "taskID"
    static let focusDetailID = "focusDetailID"
    static let date = "date"
    static let route = "route"
}

struct AgentNotificationPlanItem: Identifiable, Equatable, Sendable {
    let id: String
    let kind: AgentNotificationKind
    let fireDate: Date
    let title: String
    let body: String
    let reason: String
    let categoryIdentifier: String
    let playsSound: Bool
    let isCreatorRequested: Bool
    let priority: Int
    let metadata: [String: String]
}

struct AgentNotificationPreview: Identifiable, Equatable, Sendable {
    let id: String
    let fireDate: Date
    let reason: String
    let relatedTitle: String?
    let kind: AgentNotificationKind
    let metadata: [String: String]
}

struct NotificationSettingsSnapshot: Equatable, Sendable {
    let masterEnabled: Bool
    let dailyEnabled: Bool
    let dailyHour: Int
    let dailyMinute: Int
    let weeklyEnabled: Bool
    let weeklyWeekday: Int
    let weeklyHour: Int
    let weeklyMinute: Int
    let postRemindersEnabled: Bool
    let missedPostRemindersEnabled: Bool
    let taskRemindersEnabled: Bool
    let draftPrepRemindersEnabled: Bool
    let accessRemindersEnabled: Bool
    let draftPrepHour: Int
    let draftPrepMinute: Int
    let dateOnlyDeadlineHour: Int
    let dateOnlyDeadlineMinute: Int
    let quietHoursEnabled: Bool
    let quietHoursStartHour: Int
    let quietHoursStartMinute: Int
    let quietHoursEndHour: Int
    let quietHoursEndMinute: Int
    let showTitles: Bool
}

struct NotificationBriefSnapshot: Equatable, Sendable {
    let id: UUID
    let title: String
    let status: BriefStatus
    let updatedAt: Date
}

struct NotificationOutputSnapshot: Equatable, Sendable {
    let id: UUID
    let briefID: UUID
    let status: PlatformOutputStatus
    let targetDate: Date?
    let includesTargetTime: Bool
    let destinationID: UUID?
    let destinationName: String
    let accountID: UUID?
}

struct NotificationTaskSnapshot: Equatable, Sendable {
    let id: UUID
    let briefID: UUID?
    let title: String
    let priority: TaskPriority
    let isCompleted: Bool
    let targetDate: Date?
    let includesTargetTime: Bool
    let parentTaskID: UUID?
}

struct NotificationFocusSnapshot: Equatable, Sendable {
    let date: Date
    let title: String
}

struct NotificationFocusReminderSnapshot: Equatable, Sendable {
    let id: UUID
    let date: Date
    let title: String
    let note: String
}

struct NotificationAccountSnapshot: Equatable, Sendable {
    let id: UUID
    let destinationID: UUID
    let label: String
}

struct NotificationPlanningInput: Sendable {
    let now: Date
    let calendar: Calendar
    let settings: NotificationSettingsSnapshot
    let briefs: [NotificationBriefSnapshot]
    let outputs: [NotificationOutputSnapshot]
    let tasks: [NotificationTaskSnapshot]
    let focuses: [NotificationFocusSnapshot]
    let focusReminders: [NotificationFocusReminderSnapshot]
    let accounts: [NotificationAccountSnapshot]
    let accessEndDate: Date?
    let horizonDays: Int
}

enum AgentNotificationPlanBuilder {
    static func build(_ input: NotificationPlanningInput) -> [AgentNotificationPlanItem] {
        guard input.settings.masterEnabled else { return [] }

        let calendar = input.calendar
        let dayStart = calendar.startOfDay(for: input.now)
        let horizonEnd = calendar.date(byAdding: .day, value: input.horizonDays, to: dayStart)
            ?? input.now.addingTimeInterval(TimeInterval(input.horizonDays * 86_400))
        let briefByID = Dictionary(uniqueKeysWithValues: input.briefs.map { ($0.id, $0) })
        var automatic: [AgentNotificationPlanItem] = []

        if input.settings.postRemindersEnabled || input.settings.missedPostRemindersEnabled || input.settings.draftPrepRemindersEnabled {
            for output in input.outputs where output.status != .posted {
                guard let targetDate = output.targetDate,
                      targetDate <= horizonEnd,
                      let brief = briefByID[output.briefID],
                      brief.status != .archived else { continue }

                if input.settings.postRemindersEnabled,
                   output.status == .scheduled,
                   output.includesTargetTime {
                    let fireDate = targetDate.addingTimeInterval(-30 * 60)
                    if fireDate > input.now {
                        automatic.append(postReminder(
                            output: output,
                            brief: brief,
                            fireDate: fireDate,
                            input: input
                        ))
                    }
                }

                if input.settings.missedPostRemindersEnabled, output.status == .scheduled {
                    let missedDate = output.includesTargetTime
                        ? targetDate.addingTimeInterval(60 * 60)
                        : date(
                            on: targetDate,
                            hour: input.settings.dateOnlyDeadlineHour,
                            minute: input.settings.dateOnlyDeadlineMinute,
                            calendar: calendar
                        )
                    let fireDate = adjustedForQuietHours(missedDate, input: input)
                    if fireDate > input.now, fireDate <= horizonEnd {
                        automatic.append(missedPostReminder(
                            output: output,
                            brief: brief,
                            fireDate: fireDate,
                            input: input
                        ))
                    }
                }
            }

            if input.settings.draftPrepRemindersEnabled {
                let draftGroups = Dictionary(grouping: input.outputs.filter { output in
                    guard let target = output.targetDate,
                          target > input.now,
                          target <= horizonEnd,
                          let brief = briefByID[output.briefID],
                          brief.status != .archived else { return false }
                    return output.status == .draft || brief.status == .spark || brief.status == .developing
                }, by: \.briefID)

                for (briefID, outputs) in draftGroups {
                    guard let brief = briefByID[briefID],
                          let target = outputs.compactMap(\.targetDate).min(),
                          let previousDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: target)) else {
                        continue
                    }
                    let proposed = date(
                        on: previousDay,
                        hour: input.settings.draftPrepHour,
                        minute: input.settings.draftPrepMinute,
                        calendar: calendar
                    )
                    let fireDate = adjustedForQuietHours(proposed, input: input)
                    if fireDate > input.now, fireDate <= horizonEnd {
                        automatic.append(draftReminder(brief: brief, fireDate: fireDate, input: input))
                    }
                }
            }
        }

        if input.settings.taskRemindersEnabled {
            for task in input.tasks where !task.isCompleted && task.parentTaskID == nil {
                guard task.includesTargetTime,
                      let targetDate = task.targetDate,
                      targetDate <= horizonEnd else { continue }
                let fireDate = targetDate.addingTimeInterval(-15 * 60)
                guard fireDate > input.now else { continue }
                automatic.append(taskReminder(task: task, fireDate: fireDate, input: input))
            }
        }

        let activeBriefs = input.briefs.filter { $0.status != .archived }
        let savedIdeas = activeBriefs
            .filter { $0.status == .spark || $0.status == .developing }
            .sorted { $0.updatedAt > $1.updatedAt }

        for offset in 0...input.horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: dayStart) else { continue }
            let focus = input.focuses.first { calendar.isDate($0.date, inSameDayAs: day) }
            let isRest = focus?.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "rest"
                || focus == nil
            let weekday = calendar.component(.weekday, from: day)

            if input.settings.weeklyEnabled, weekday == input.settings.weeklyWeekday, !isRest {
                let proposed = date(on: day, hour: input.settings.weeklyHour, minute: input.settings.weeklyMinute, calendar: calendar)
                let fireDate = adjustedForQuietHours(proposed, input: input)
                if fireDate > input.now, fireDate <= horizonEnd {
                    automatic.append(weeklyReminder(
                        day: day,
                        focus: focus,
                        ideas: savedIdeas,
                        fireDate: fireDate,
                        input: input
                    ))
                }
                continue
            }

            guard input.settings.dailyEnabled, !isRest else { continue }
            let proposed = date(on: day, hour: input.settings.dailyHour, minute: input.settings.dailyMinute, calendar: calendar)
            let fireDate = adjustedForQuietHours(proposed, input: input)
            guard fireDate > input.now, fireDate <= horizonEnd else { continue }
            automatic.append(dailyReminder(day: day, focus: focus, fireDate: fireDate, input: input))
        }

        if input.settings.accessRemindersEnabled,
           let accessEnd = input.accessEndDate {
            let proposed = accessEnd.addingTimeInterval(-24 * 60 * 60)
            let fireDate = adjustedForQuietHours(proposed, input: input)
            if fireDate > input.now, fireDate <= horizonEnd {
                automatic.append(accessReminder(accessEnd: accessEnd, fireDate: fireDate, input: input))
            }
        }

        let capped = cappedAutomaticNotifications(automatic, calendar: calendar)
        let manual = input.focusReminders.compactMap { reminder -> AgentNotificationPlanItem? in
            guard reminder.date > input.now, reminder.date <= horizonEnd else { return nil }
            let title = input.settings.showTitles ? "Focus: \(reminder.title)" : "Your focus reminder"
            let body = reminder.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Start with one clear next step."
                : reminder.note
            return AgentNotificationPlanItem(
                id: "agentcy.v2.focus.\(reminder.id.uuidString.lowercased())",
                kind: .focus,
                fireDate: reminder.date,
                title: title,
                body: body,
                reason: "Focus reminder",
                categoryIdentifier: AgentNotificationCategory.focus,
                playsSound: true,
                isCreatorRequested: true,
                priority: 1_000,
                metadata: metadata(
                    kind: .focus,
                    date: reminder.date,
                    focusDetailID: reminder.id,
                    route: "day"
                )
            )
        }

        return (capped + manual).sorted {
            if $0.fireDate == $1.fireDate { return $0.priority > $1.priority }
            return $0.fireDate < $1.fireDate
        }
    }

    private static func postReminder(
        output: NotificationOutputSnapshot,
        brief: NotificationBriefSnapshot,
        fireDate: Date,
        input: NotificationPlanningInput
    ) -> AgentNotificationPlanItem {
        let title = "Post in 30 minutes"
        let account = accountLabel(for: output, input: input)
        let platform = output.destinationName.isEmpty ? "your selected platform" : output.destinationName
        let body: String
        if input.settings.showTitles {
            body = ["\(brief.title) is scheduled for \(platform).", account].compactMap { $0 }.joined(separator: " ")
        } else {
            body = ["Your post is scheduled for \(platform).", account].compactMap { $0 }.joined(separator: " ")
        }
        return AgentNotificationPlanItem(
            id: "agentcy.v2.post.\(output.id.uuidString.lowercased())",
            kind: .scheduledPost,
            fireDate: fireDate,
            title: title,
            body: body,
            reason: "Scheduled post",
            categoryIdentifier: AgentNotificationCategory.post,
            playsSound: true,
            isCreatorRequested: false,
            priority: 100,
            metadata: metadata(kind: .scheduledPost, date: output.targetDate, briefID: brief.id, outputID: output.id, route: "brief")
        )
    }

    private static func missedPostReminder(
        output: NotificationOutputSnapshot,
        brief: NotificationBriefSnapshot,
        fireDate: Date,
        input: NotificationPlanningInput
    ) -> AgentNotificationPlanItem {
        AgentNotificationPlanItem(
            id: "agentcy.v2.missed.\(output.id.uuidString.lowercased())",
            kind: .missedPost,
            fireDate: fireDate,
            title: "Still planning to post this?",
            body: input.settings.showTitles ? "\(brief.title). Mark it posted or choose another time." : "Mark it posted or choose another time.",
            reason: "Missed post check-in",
            categoryIdentifier: AgentNotificationCategory.missedPost,
            playsSound: true,
            isCreatorRequested: false,
            priority: 80,
            metadata: metadata(kind: .missedPost, date: output.targetDate, briefID: brief.id, outputID: output.id, route: "brief")
        )
    }

    private static func draftReminder(
        brief: NotificationBriefSnapshot,
        fireDate: Date,
        input: NotificationPlanningInput
    ) -> AgentNotificationPlanItem {
        AgentNotificationPlanItem(
            id: "agentcy.v2.draft.\(brief.id.uuidString.lowercased())",
            kind: .draftPreparation,
            fireDate: fireDate,
            title: "Tomorrow’s post is still a draft",
            body: input.settings.showTitles ? "\(brief.title). Finish it tonight or move it." : "Finish it tonight or move it.",
            reason: "Draft preparation",
            categoryIdentifier: AgentNotificationCategory.draft,
            playsSound: false,
            isCreatorRequested: false,
            priority: 70,
            metadata: metadata(kind: .draftPreparation, date: fireDate, briefID: brief.id, route: "draft")
        )
    }

    private static func taskReminder(
        task: NotificationTaskSnapshot,
        fireDate: Date,
        input: NotificationPlanningInput
    ) -> AgentNotificationPlanItem {
        AgentNotificationPlanItem(
            id: "agentcy.v2.task.\(task.id.uuidString.lowercased())",
            kind: .timedTask,
            fireDate: fireDate,
            title: "Task in 15 minutes",
            body: input.settings.showTitles ? task.title : "Your scheduled task is coming up.",
            reason: "Timed task",
            categoryIdentifier: AgentNotificationCategory.task,
            playsSound: true,
            isCreatorRequested: false,
            priority: 90,
            metadata: metadata(kind: .timedTask, date: task.targetDate, briefID: task.briefID, taskID: task.id, route: "task")
        )
    }

    private static func dailyReminder(
        day: Date,
        focus: NotificationFocusSnapshot?,
        fireDate: Date,
        input: NotificationPlanningInput
    ) -> AgentNotificationPlanItem {
        let calendar = input.calendar
        let dayTasks = input.tasks.filter {
            !$0.isCompleted && $0.parentTaskID == nil && $0.targetDate.map { calendar.isDate($0, inSameDayAs: day) } == true
        }
        let dayOutputs = input.outputs.filter {
            $0.status != .posted && $0.targetDate.map { calendar.isDate($0, inSameDayAs: day) } == true
        }
        let startOfDay = calendar.startOfDay(for: day)
        let previousDay = calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay.addingTimeInterval(-86_400)
        let overdue = input.tasks.filter {
            guard calendar.isDate(day, inSameDayAs: input.now),
                  !$0.isCompleted,
                  $0.parentTaskID == nil,
                  let target = $0.targetDate else { return false }
            // An overdue commitment is folded into one morning overview, not repeated indefinitely.
            return target >= previousDay && target < startOfDay
        }.sorted { ($0.targetDate ?? .distantPast) < ($1.targetDate ?? .distantPast) }
        let nextTitle: String? = {
            let posts = dayOutputs.compactMap { output -> (Date, String)? in
                guard let date = output.targetDate,
                      let brief = input.briefs.first(where: { $0.id == output.briefID }) else { return nil }
                return (date, brief.title)
            }
            let tasks = dayTasks.compactMap { task -> (Date, String)? in
                task.targetDate.map { ($0, task.title) }
            }
            return (posts + tasks).sorted { $0.0 < $1.0 }.first?.1
        }()
        let remaining = dayTasks.count + dayOutputs.count
        var parts: [String] = []
        if input.settings.showTitles, let nextTitle { parts.append(nextTitle) }
        if remaining > 0 { parts.append("\(remaining) \(remaining == 1 ? "item" : "items") planned.") }
        if dayTasks.contains(where: { $0.priority.normalized == .high || $0.priority.normalized == .urgent }) {
            parts.append("A high-priority task is in today’s plan.")
        }
        if !overdue.isEmpty { parts.append("\(overdue.count) \(overdue.count == 1 ? "task is" : "tasks are") ready to replan.") }
        if parts.isEmpty { parts.append("Choose one clear next step.") }
        var info = metadata(kind: .daily, date: day, route: "day")
        if let overdueTask = overdue.first { info[AgentNotificationMetadataKey.taskID] = overdueTask.id.uuidString }
        return AgentNotificationPlanItem(
            id: "agentcy.v2.daily.\(dayKey(day, calendar: calendar))",
            kind: .daily,
            fireDate: fireDate,
            title: input.settings.showTitles ? "Today: \(focus?.title ?? "Your plan")" : "Today’s plan",
            body: parts.joined(separator: " "),
            reason: "Daily overview",
            categoryIdentifier: AgentNotificationCategory.daily,
            playsSound: false,
            isCreatorRequested: false,
            priority: 60,
            metadata: info
        )
    }

    private static func weeklyReminder(
        day: Date,
        focus: NotificationFocusSnapshot?,
        ideas: [NotificationBriefSnapshot],
        fireDate: Date,
        input: NotificationPlanningInput
    ) -> AgentNotificationPlanItem {
        let calendar = input.calendar
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: day)) ?? day.addingTimeInterval(7 * 86_400)
        let plannedPosts = input.outputs.filter {
            guard $0.status != .posted, let target = $0.targetDate else { return false }
            return target >= day && target < weekEnd
        }.count
        let plannedTasks = input.tasks.filter {
            guard !$0.isCompleted, $0.parentTaskID == nil, let target = $0.targetDate else { return false }
            return target >= day && target < weekEnd
        }.count
        var parts = ["Start with \(focus?.title ?? "Planning"). You have \(ideas.count) saved \(ideas.count == 1 ? "idea" : "ideas")."]
        if plannedPosts + plannedTasks > 0 {
            parts.append("This week has \(plannedPosts) \(plannedPosts == 1 ? "post" : "posts") and \(plannedTasks) \(plannedTasks == 1 ? "task" : "tasks") planned.")
        }
        if input.settings.showTitles, !ideas.isEmpty {
            let titles = ideas.prefix(2).map { "“\($0.title)”" }
            parts.append("Consider \(titles.joined(separator: " or ")).")
        }
        return AgentNotificationPlanItem(
            id: "agentcy.v2.weekly.\(dayKey(day, calendar: input.calendar))",
            kind: .weekly,
            fireDate: fireDate,
            title: "A new week is here",
            body: parts.joined(separator: " "),
            reason: "Weekly planning",
            categoryIdentifier: AgentNotificationCategory.weekly,
            playsSound: false,
            isCreatorRequested: false,
            priority: 60,
            metadata: metadata(kind: .weekly, date: day, route: "week")
        )
    }

    private static func accessReminder(
        accessEnd: Date,
        fireDate: Date,
        input: NotificationPlanningInput
    ) -> AgentNotificationPlanItem {
        let formatted = accessEnd.formatted(date: .abbreviated, time: .shortened)
        return AgentNotificationPlanItem(
            id: "agentcy.v2.access.\(Int(accessEnd.timeIntervalSince1970))",
            kind: .access,
            fireDate: fireDate,
            title: "Your access changes tomorrow",
            body: "Your access ends or renews on \(formatted). The monthly price is $8.99.",
            reason: "Access reminder",
            categoryIdentifier: AgentNotificationCategory.access,
            playsSound: false,
            isCreatorRequested: false,
            priority: 50,
            metadata: metadata(kind: .access, date: accessEnd, route: "access")
        )
    }

    private static func accountLabel(
        for output: NotificationOutputSnapshot,
        input: NotificationPlanningInput
    ) -> String? {
        guard let destinationID = output.destinationID,
              input.accounts.filter({ $0.destinationID == destinationID }).count > 1,
              let accountID = output.accountID,
              let account = input.accounts.first(where: { $0.id == accountID }) else { return nil }
        return account.label
    }

    private static func cappedAutomaticNotifications(
        _ items: [AgentNotificationPlanItem],
        calendar: Calendar
    ) -> [AgentNotificationPlanItem] {
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.fireDate) }
        return grouped.values.flatMap { dayItems in
            dayItems.sorted {
                if $0.priority == $1.priority { return $0.fireDate < $1.fireDate }
                return $0.priority > $1.priority
            }.prefix(3)
        }
    }

    private static func adjustedForQuietHours(
        _ proposed: Date,
        input: NotificationPlanningInput
    ) -> Date {
        guard input.settings.quietHoursEnabled else { return proposed }
        let calendar = input.calendar
        let minutes = calendar.component(.hour, from: proposed) * 60 + calendar.component(.minute, from: proposed)
        let start = input.settings.quietHoursStartHour * 60 + input.settings.quietHoursStartMinute
        let end = input.settings.quietHoursEndHour * 60 + input.settings.quietHoursEndMinute
        let isQuiet = start < end ? (minutes >= start && minutes < end) : (minutes >= start || minutes < end)
        guard isQuiet else { return proposed }

        let day = calendar.startOfDay(for: proposed)
        if start < end || minutes < end {
            return date(on: day, hour: input.settings.quietHoursEndHour, minute: input.settings.quietHoursEndMinute, calendar: calendar)
        }
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        return date(on: nextDay, hour: input.settings.quietHoursEndHour, minute: input.settings.quietHoursEndMinute, calendar: calendar)
    }

    private static func date(on day: Date, hour: Int, minute: Int, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func metadata(
        kind: AgentNotificationKind,
        date: Date?,
        briefID: UUID? = nil,
        outputID: UUID? = nil,
        taskID: UUID? = nil,
        focusDetailID: UUID? = nil,
        route: String
    ) -> [String: String] {
        var result = [
            AgentNotificationMetadataKey.kind: kind.rawValue,
            AgentNotificationMetadataKey.route: route,
        ]
        if let date { result[AgentNotificationMetadataKey.date] = ISO8601DateFormatter().string(from: date) }
        if let briefID { result[AgentNotificationMetadataKey.briefID] = briefID.uuidString }
        if let outputID { result[AgentNotificationMetadataKey.outputID] = outputID.uuidString }
        if let taskID { result[AgentNotificationMetadataKey.taskID] = taskID.uuidString }
        if let focusDetailID { result[AgentNotificationMetadataKey.focusDetailID] = focusDetailID.uuidString }
        return result
    }
}
