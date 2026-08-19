import Foundation
import SwiftData
import UIKit
import UserNotifications

@Model
final class AgentActivityRecord {
    var id: UUID = UUID()
    var notificationID: String = ""
    var workspaceID: UUID?
    var kindRaw: String = AgentNotificationKind.daily.rawValue
    var availableAt: Date = Date()
    var title: String = ""
    var body: String = ""
    var reason: String = ""
    var priority: Int = 0
    var briefID: UUID?
    var outputID: UUID?
    var taskID: UUID?
    var focusDetailID: UUID?
    var routeRaw: String = AgentNotificationRouteKind.day.rawValue
    var eventDate: Date?
    var readAt: Date?
    var resolvedAt: Date?
    var archivedAt: Date?
    /// Creator-initiated "Clear all". Unlike `archivedAt`, reconcile leaves it
    /// standing while a live seed persists; only a genuinely new occurrence
    /// resets it. Optional for additive CloudKit migration safety.
    var clearedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        notificationID: String,
        workspaceID: UUID?,
        kind: AgentNotificationKind,
        availableAt: Date,
        title: String,
        body: String,
        reason: String,
        priority: Int,
        briefID: UUID? = nil,
        outputID: UUID? = nil,
        taskID: UUID? = nil,
        focusDetailID: UUID? = nil,
        route: AgentNotificationRouteKind,
        eventDate: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.notificationID = notificationID
        self.workspaceID = workspaceID
        self.kindRaw = kind.rawValue
        self.availableAt = availableAt
        self.title = title
        self.body = body
        self.reason = reason
        self.priority = priority
        self.briefID = briefID
        self.outputID = outputID
        self.taskID = taskID
        self.focusDetailID = focusDetailID
        self.routeRaw = route.rawValue
        self.eventDate = eventDate
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var kind: AgentNotificationKind {
        AgentNotificationKind(rawValue: kindRaw) ?? .daily
    }

    var route: AgentNotificationRoute {
        let routeKind = AgentNotificationRouteKind(rawValue: routeRaw) ?? .day
        let objectID: UUID? = switch routeKind {
        case .brief, .draft: briefID
        case .task: taskID
        default: nil
        }
        return AgentNotificationRoute(kind: routeKind, objectID: objectID, date: eventDate)
    }
}

extension AgentActivityRecord: WorkspaceScopedRecord {}

enum AgentActivityPresentationPolicy {
    static func isVisible(availableAt: Date, archivedAt: Date?, clearedAt: Date?, now: Date) -> Bool {
        archivedAt == nil && clearedAt == nil && availableAt <= now
    }

    static func requiresResolution(_ kind: AgentNotificationKind) -> Bool {
        switch kind {
        case .lateWork, .scheduledPost, .missedPost, .draftPreparation, .timedTask:
            true
        case .daily, .weekly, .focus, .access:
            false
        }
    }

    static func needsAttention(
        kind: AgentNotificationKind,
        readAt: Date?,
        resolvedAt: Date?
    ) -> Bool {
        guard resolvedAt == nil else { return false }
        return readAt == nil || requiresResolution(kind)
    }
}

private struct AgentActivitySeed {
    let notificationID: String
    let workspaceID: UUID?
    let kind: AgentNotificationKind
    let availableAt: Date
    let title: String
    let body: String
    let reason: String
    let priority: Int
    let briefID: UUID?
    let outputID: UUID?
    let taskID: UUID?
    let focusDetailID: UUID?
    let route: AgentNotificationRouteKind
    let eventDate: Date?
}

@MainActor
enum AgentActivityCenterService {
    static func reconcile(
        plan: [AgentNotificationPlanItem],
        context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws {
        let workspaces = try context.fetch(FetchDescriptor<CreatorWorkspace>())
        let workspaceID = WorkspaceScope.activeWorkspaceID(
            preferredID: CreatorWorkspacePreferences.activeWorkspaceID,
            workspaces: workspaces
        )
        let briefs = try context.fetch(FetchDescriptor<CreativeBrief>()).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: workspaceID, workspaces: workspaces)
        }
        let outputs = try context.fetch(FetchDescriptor<PlatformOutput>()).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: workspaceID, workspaces: workspaces)
        }
        let tasks = try context.fetch(FetchDescriptor<CreatorTask>()).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: workspaceID, workspaces: workspaces)
        }
        let briefByID = DuplicateSafeIndex.firstValues(briefs.map { ($0.id, $0) })
        let planSeeds = plan.map { seed(from: $0, workspaceID: workspaceID) }
        let liveSeeds = liveActionSeeds(
            workspaceID: workspaceID,
            briefs: briefs,
            outputs: outputs,
            tasks: tasks,
            briefByID: briefByID,
            now: now,
            calendar: calendar
        )
        let seeds = DuplicateSafeIndex.firstValues((planSeeds + liveSeeds).map { ($0.notificationID, $0) })
        let stored = try context.fetch(FetchDescriptor<AgentActivityRecord>())
            .filter { WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: workspaceID, workspaces: workspaces) }
        var storedByNotificationID: [String: AgentActivityRecord] = [:]
        for record in stored {
            if storedByNotificationID[record.notificationID] == nil {
                storedByNotificationID[record.notificationID] = record
            } else {
                context.delete(record)
            }
        }

        for seed in seeds.values {
            if let record = storedByNotificationID[seed.notificationID] {
                let wasAlreadyAvailable = record.availableAt <= now
                let movedToASeparateOccurrence = wasAlreadyAvailable &&
                    abs(record.availableAt.timeIntervalSince(seed.availableAt)) > 60
                apply(seed, to: record, now: now, resetsState: movedToASeparateOccurrence)
            } else {
                let record = AgentActivityRecord(
                    notificationID: seed.notificationID,
                    workspaceID: seed.workspaceID,
                    kind: seed.kind,
                    availableAt: seed.availableAt,
                    title: seed.title,
                    body: seed.body,
                    reason: seed.reason,
                    priority: seed.priority,
                    briefID: seed.briefID,
                    outputID: seed.outputID,
                    taskID: seed.taskID,
                    focusDetailID: seed.focusDetailID,
                    route: seed.route,
                    eventDate: seed.eventDate,
                    createdAt: now
                )
                context.insert(record)
                storedByNotificationID[seed.notificationID] = record
            }
        }

        for record in stored where seeds[record.notificationID] == nil && record.availableAt > now {
            record.archivedAt = now
            record.updatedAt = now
        }

        resolveCompletedRecords(
            storedByNotificationID.values,
            briefByID: briefByID,
            outputs: outputs,
            tasks: tasks,
            now: now,
            calendar: calendar
        )
        archiveOldResolvedRecords(storedByNotificationID.values, now: now, calendar: calendar)
        try context.save()
    }

    static func markRead(_ record: AgentActivityRecord, context: ModelContext, now: Date = Date()) throws {
        guard record.readAt == nil else { return }
        record.readAt = now
        record.updatedAt = now
        try context.save()
    }

    static func markUnread(_ record: AgentActivityRecord, context: ModelContext, now: Date = Date()) throws {
        record.readAt = nil
        record.updatedAt = now
        try context.save()
    }

    static func markAllRead(
        _ records: [AgentActivityRecord],
        context: ModelContext,
        now: Date = Date()
    ) throws {
        for record in records where record.readAt == nil {
            record.readAt = now
            record.updatedAt = now
        }
        try context.save()
    }

    static func archive(_ record: AgentActivityRecord, context: ModelContext, now: Date = Date()) throws {
        record.archivedAt = now
        record.updatedAt = now
        try context.save()
    }

    static func clearAll(
        _ records: [AgentActivityRecord],
        context: ModelContext,
        now: Date = Date()
    ) throws {
        for record in records where record.clearedAt == nil {
            record.clearedAt = now
            if record.readAt == nil {
                record.readAt = now
            }
            record.updatedAt = now
        }
        try context.save()
    }

    static func markRead(notificationID: String, context: ModelContext, now: Date = Date()) throws {
        guard let record = try context.fetch(FetchDescriptor<AgentActivityRecord>())
            .first(where: { $0.notificationID == notificationID }) else { return }
        try markRead(record, context: context, now: now)
    }

    private static func seed(
        from item: AgentNotificationPlanItem,
        workspaceID: UUID?
    ) -> AgentActivitySeed {
        AgentActivitySeed(
            notificationID: item.id,
            workspaceID: workspaceID,
            kind: item.kind,
            availableAt: item.fireDate,
            title: item.title,
            body: item.body,
            reason: item.reason,
            priority: item.priority,
            briefID: uuid(item.metadata[AgentNotificationMetadataKey.briefID]),
            outputID: uuid(item.metadata[AgentNotificationMetadataKey.outputID]),
            taskID: uuid(item.metadata[AgentNotificationMetadataKey.taskID]),
            focusDetailID: uuid(item.metadata[AgentNotificationMetadataKey.focusDetailID]),
            route: routeKind(item.metadata[AgentNotificationMetadataKey.route]),
            eventDate: item.metadata[AgentNotificationMetadataKey.date].flatMap {
                ISO8601DateFormatter().date(from: $0)
            }
        )
    }

    private static func liveActionSeeds(
        workspaceID: UUID?,
        briefs: [CreativeBrief],
        outputs: [PlatformOutput],
        tasks: [CreatorTask],
        briefByID: [UUID: CreativeBrief],
        now: Date,
        calendar: Calendar
    ) -> [AgentActivitySeed] {
        var seeds: [AgentActivitySeed] = []
        let dayStart = calendar.startOfDay(for: now)

        for output in outputs where output.status != .posted {
            guard let brief = briefByID[output.briefID], brief.status != .archived else { continue }
            if PostWorkDateStatusPolicy.isLate(
                workDate: brief.workDate,
                briefStatus: brief.status,
                outputStatus: output.status,
                now: now,
                calendar: calendar
            ), let workDate = brief.workDate {
                seeds.append(AgentActivitySeed(
                    notificationID: "agentcy.v2.late-work.\(brief.id.uuidString.lowercased())",
                    workspaceID: workspaceID,
                    kind: .lateWork,
                    availableAt: calendar.startOfDay(for: workDate),
                    title: "Work on this post is late",
                    body: brief.title,
                    reason: "Late work",
                    priority: 85,
                    briefID: brief.id,
                    outputID: output.id,
                    taskID: nil,
                    focusDetailID: nil,
                    route: .draft,
                    eventDate: workDate
                ))
            }

            if let targetDate = output.targetDate,
               calendar.startOfDay(for: targetDate) < dayStart {
                seeds.append(AgentActivitySeed(
                    notificationID: "agentcy.v2.missed.\(output.id.uuidString.lowercased())",
                    workspaceID: workspaceID,
                    kind: .missedPost,
                    availableAt: calendar.startOfDay(for: targetDate),
                    title: "Scheduled post still open",
                    body: brief.title,
                    reason: "Missed post check-in",
                    priority: 80,
                    briefID: brief.id,
                    outputID: output.id,
                    taskID: nil,
                    focusDetailID: nil,
                    route: .brief,
                    eventDate: targetDate
                ))
            }
        }

        for task in tasks where !task.isCompleted && !task.isSkipped && task.parentTaskID == nil {
            guard let targetDate = task.targetDate else { continue }
            let isOverdue = task.includesTargetTime
                ? targetDate < now
                : calendar.startOfDay(for: targetDate) < dayStart
            guard isOverdue else { continue }
            seeds.append(AgentActivitySeed(
                notificationID: "agentcy.v2.task.\(task.id.uuidString.lowercased())",
                workspaceID: workspaceID,
                kind: .timedTask,
                availableAt: targetDate,
                title: "Task needs attention",
                body: task.title,
                reason: "Overdue task",
                priority: 90,
                briefID: task.briefID,
                outputID: nil,
                taskID: task.id,
                focusDetailID: nil,
                route: .task,
                eventDate: targetDate
            ))
        }
        return seeds
    }

    private static func apply(
        _ seed: AgentActivitySeed,
        to record: AgentActivityRecord,
        now: Date,
        resetsState: Bool
    ) {
        record.workspaceID = seed.workspaceID
        record.kindRaw = seed.kind.rawValue
        record.availableAt = seed.availableAt
        record.title = seed.title
        record.body = seed.body
        record.reason = seed.reason
        record.priority = seed.priority
        record.briefID = seed.briefID
        record.outputID = seed.outputID
        record.taskID = seed.taskID
        record.focusDetailID = seed.focusDetailID
        record.routeRaw = seed.route.rawValue
        record.eventDate = seed.eventDate
        record.archivedAt = nil
        if resetsState {
            record.readAt = nil
            record.resolvedAt = nil
            record.clearedAt = nil
            record.createdAt = now
        }
        record.updatedAt = now
    }

    private static func resolveCompletedRecords(
        _ records: Dictionary<String, AgentActivityRecord>.Values,
        briefByID: [UUID: CreativeBrief],
        outputs: [PlatformOutput],
        tasks: [CreatorTask],
        now: Date,
        calendar: Calendar
    ) {
        let outputByID = DuplicateSafeIndex.firstValues(outputs.map { ($0.id, $0) })
        let taskByID = DuplicateSafeIndex.firstValues(tasks.map { ($0.id, $0) })
        for record in records where record.archivedAt == nil {
            let resolved: Bool
            if let taskID = record.taskID {
                resolved = taskByID[taskID].map { $0.isCompleted || $0.isSkipped } ?? true
            } else if let outputID = record.outputID {
                guard let output = outputByID[outputID] else {
                    record.resolvedAt = record.resolvedAt ?? now
                    continue
                }
                if record.kind == .lateWork, let brief = briefByID[output.briefID] {
                    resolved = !PostWorkDateStatusPolicy.isLate(
                        workDate: brief.workDate,
                        briefStatus: brief.status,
                        outputStatus: output.status,
                        now: now,
                        calendar: calendar
                    )
                } else if record.kind == .missedPost {
                    resolved = output.status == .posted ||
                        output.targetDate.map { calendar.startOfDay(for: $0) >= calendar.startOfDay(for: now) } == true
                } else {
                    resolved = output.status == .posted
                }
            } else if let briefID = record.briefID {
                resolved = briefByID[briefID].map { $0.status == .archived || $0.status == .posted } ?? true
            } else {
                resolved = false
            }
            if resolved {
                record.resolvedAt = record.resolvedAt ?? now
                record.updatedAt = now
            }
        }
    }

    private static func archiveOldResolvedRecords(
        _ records: Dictionary<String, AgentActivityRecord>.Values,
        now: Date,
        calendar: Calendar
    ) {
        guard let cutoff = calendar.date(byAdding: .day, value: -30, to: now) else { return }
        for record in records where record.resolvedAt.map({ $0 < cutoff }) == true {
            record.archivedAt = record.archivedAt ?? now
            record.updatedAt = now
        }
    }

    private static func uuid(_ value: String?) -> UUID? {
        value.flatMap(UUID.init(uuidString:))
    }

    private static func routeKind(_ rawValue: String?) -> AgentNotificationRouteKind {
        switch rawValue {
        case "week": .week
        case "brief": .brief
        case "draft": .draft
        case "task": .task
        case "access": .access
        default: .day
        }
    }
}

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
        if BridgePushRegistrationPolicy.shouldRegisterOnCurrentPlatform {
            UIApplication.shared.registerForRemoteNotifications()
        }
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
        try AgentActivityCenterService.reconcile(
            plan: plan,
            context: context,
            now: now,
            calendar: calendar
        )
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
        let mcpReview = UNNotificationCategory(
            identifier: AgentNotificationCategory.mcpReview,
            actions: [UNNotificationAction(identifier: AgentNotificationAction.openMCPReview, title: "Review", options: foreground)],
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
            mcpReview,
        ])
    }

    private func removeManagedPendingRequests() async {
        let requests = await center.pendingNotificationRequests()
        let identifiers = requests.map(\.identifier).filter { identifier in
            Self.managedIdentifierPrefixes.contains { identifier.hasPrefix($0) }
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func makePlanningInput(context: ModelContext, now: Date) throws -> NotificationPlanningInput {
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
        let destinationByID = DuplicateSafeIndex.firstValues(destinations.map { ($0.id, $0.name) })
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
                NotificationBriefSnapshot(
                    id: $0.id,
                    title: $0.title,
                    status: $0.status,
                    workDate: $0.workDate,
                    updatedAt: $0.updatedAt,
                    isSavedIdea: IdeaBankPlacementPolicy.includes($0)
                )
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
