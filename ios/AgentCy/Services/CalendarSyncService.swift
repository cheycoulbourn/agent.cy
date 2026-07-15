import EventKit
import Foundation
import SwiftData

enum AgentCalendarAuthorization: Equatable {
    case notDetermined
    case restricted
    case denied
    case writeOnly
    case fullAccess
}

struct AgentCalendarChoice: Identifiable, Equatable {
    let id: String
    let title: String
    let sourceTitle: String
    let isDefault: Bool

    var displayTitle: String {
        sourceTitle.isEmpty || sourceTitle == title ? title : "\(title) · \(sourceTitle)"
    }
}

enum CalendarIntegrationPreferences {
    static let selectedCalendarIdentifierKey = "agentCy.calendar.selectedIdentifier"
    static let selectedCalendarTitleKey = "agentCy.calendar.selectedTitle"
    static let syncScheduledPostsKey = "agentCy.calendar.syncScheduledPosts"
    static let syncTasksKey = "agentCy.calendar.syncTasks"
    static let eventLinksKey = "agentCy.calendar.eventLinks.v1"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        !selectedCalendarIdentifier(defaults: defaults).isEmpty &&
            (defaults.bool(forKey: syncScheduledPostsKey) || defaults.bool(forKey: syncTasksKey))
    }

    static func selectedCalendarIdentifier(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: selectedCalendarIdentifierKey) ?? ""
    }

    static func clear(defaults: UserDefaults = .standard) {
        disable(preservingEventLinks: false, defaults: defaults)
    }

    /// Disconnects the visible integration while retaining any event identifiers
    /// that still need deletion after calendar permission is restored.
    static func disable(preservingEventLinks: Bool, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: selectedCalendarIdentifierKey)
        defaults.removeObject(forKey: selectedCalendarTitleKey)
        defaults.removeObject(forKey: syncScheduledPostsKey)
        defaults.removeObject(forKey: syncTasksKey)
        if !preservingEventLinks {
            defaults.removeObject(forKey: eventLinksKey)
        }
    }
}

enum CalendarSyncError: LocalizedError {
    case accessDenied
    case calendarUnavailable
    case cleanupRequiresAccess

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Calendar access is off. Allow access in Settings to keep your agenda connected."
        case .calendarUnavailable:
            "That calendar is no longer available on this iPhone. Choose another calendar in Settings."
        case .cleanupRequiresAccess:
            "Calendar access must be restored before agent.cy can delete its linked calendar events."
        }
    }
}

enum CalendarSyncPolicy {
    static func shouldSyncPost(
        status: PlatformOutputStatus,
        hasTargetDate: Bool,
        briefIsArchived: Bool,
        syncEnabled: Bool
    ) -> Bool {
        syncEnabled && hasTargetDate && !briefIsArchived && [.scheduled, .posted].contains(status)
    }

    static func shouldSyncTask(
        hasTargetDate: Bool,
        isSubtask: Bool,
        linkedBriefIsArchived: Bool,
        syncEnabled: Bool
    ) -> Bool {
        syncEnabled && hasTargetDate && !isSubtask && !linkedBriefIsArchived
    }

    static func postTiming(
        targetDate: Date,
        includesTime: Bool,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date, isAllDay: Bool) {
        if includesTime {
            return (targetDate, targetDate.addingTimeInterval(15 * 60), false)
        }
        let start = calendar.startOfDay(for: targetDate)
        return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? start, true)
    }

    static func taskTiming(
        targetDate: Date,
        estimatedMinutes: Int?,
        includesTime: Bool,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date, isAllDay: Bool) {
        guard includesTime else {
            let start = calendar.startOfDay(for: targetDate)
            return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? start, true)
        }
        let minutes = max(estimatedMinutes ?? 30, 15)
        return (
            targetDate,
            calendar.date(byAdding: .minute, value: minutes, to: targetDate) ?? targetDate,
            false
        )
    }
}

enum CalendarEventLinkCleanup {
    static func requireFullAccess(
        authorization: AgentCalendarAuthorization,
        hasPendingLinks: Bool
    ) throws {
        guard hasPendingLinks, authorization != .fullAccess else { return }
        throw CalendarSyncError.cleanupRequiresAccess
    }

    /// Removes links only after their corresponding event deletion succeeds.
    /// A caller can persist the remaining dictionary and safely retry later.
    static func removeAll(
        links: inout [String: String],
        removeEvent: (String) throws -> Void
    ) throws {
        for key in links.keys.sorted() {
            guard let identifier = links[key] else { continue }
            try removeEvent(identifier)
            links.removeValue(forKey: key)
        }
    }
}

@MainActor
protocol CalendarSyncServicing: AnyObject {
    var authorization: AgentCalendarAuthorization { get }
    func requestFullAccess() async throws -> Bool
    func availableCalendars() -> [AgentCalendarChoice]
    func reconcile(context: ModelContext) throws
    func disconnect() throws
}

@MainActor
final class EventKitCalendarSyncService: CalendarSyncServicing {
    static let shared = EventKitCalendarSyncService()

    private let eventStore: EKEventStore
    private let defaults: UserDefaults

    init(eventStore: EKEventStore = EKEventStore(), defaults: UserDefaults = .standard) {
        self.eventStore = eventStore
        self.defaults = defaults
    }

    var authorization: AgentCalendarAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .writeOnly: .writeOnly
        case .fullAccess: .fullAccess
        @unknown default: .denied
        }
    }

    func requestFullAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    func availableCalendars() -> [AgentCalendarChoice] {
        guard authorization == .fullAccess else { return [] }
        let defaultID = eventStore.defaultCalendarForNewEvents?.calendarIdentifier
        return eventStore.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map { calendar in
                AgentCalendarChoice(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    sourceTitle: calendar.source.title,
                    isDefault: calendar.calendarIdentifier == defaultID
                )
            }
            .sorted {
                if $0.isDefault != $1.isDefault { return $0.isDefault }
                if $0.sourceTitle != $1.sourceTitle {
                    return $0.sourceTitle.localizedCaseInsensitiveCompare($1.sourceTitle) == .orderedAscending
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    func reconcile(context: ModelContext) throws {
        guard CalendarIntegrationPreferences.isEnabled(defaults: defaults) else {
            try removeAllLinkedEvents(clearPreferences: false)
            return
        }
        guard authorization == .fullAccess else { throw CalendarSyncError.accessDenied }

        let calendarID = CalendarIntegrationPreferences.selectedCalendarIdentifier(defaults: defaults)
        guard let destinationCalendar = eventStore.calendar(withIdentifier: calendarID),
              destinationCalendar.allowsContentModifications else {
            throw CalendarSyncError.calendarUnavailable
        }

        let syncPosts = defaults.bool(forKey: CalendarIntegrationPreferences.syncScheduledPostsKey)
        let syncTasks = defaults.bool(forKey: CalendarIntegrationPreferences.syncTasksKey)
        let briefs = try context.fetch(FetchDescriptor<CreativeBrief>())
        let briefsByID = Dictionary(uniqueKeysWithValues: briefs.map { ($0.id, $0) })
        let outputs = try context.fetch(FetchDescriptor<PlatformOutput>())
        let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
        var links = eventLinks()
        var activeKeys = Set<String>()

        for output in outputs {
            let key = Self.postKey(output.id)
            let brief = briefsByID[output.briefID]
            let shouldSync = CalendarSyncPolicy.shouldSyncPost(
                status: output.status,
                hasTargetDate: output.targetDate != nil,
                briefIsArchived: brief?.status == .archived || brief == nil,
                syncEnabled: syncPosts
            )
            guard shouldSync, let targetDate = output.targetDate, let brief else {
                try removeLinkedEvent(for: key, links: &links)
                continue
            }

            let event = links[key].flatMap(eventStore.event(withIdentifier:)) ?? EKEvent(eventStore: eventStore)
            let timing = CalendarSyncPolicy.postTiming(
                targetDate: targetDate,
                includesTime: output.includesTargetTime
            )
            event.calendar = destinationCalendar
            event.title = output.status == .posted
                ? "Posted: \(resolvedPostTitle(output: output, brief: brief))"
                : "Post: \(resolvedPostTitle(output: output, brief: brief))"
            event.startDate = timing.start
            event.endDate = timing.end
            event.isAllDay = timing.isAllDay
            event.notes = postNotes(output: output)
            event.url = AgentCyDeepLink.brief(brief.id).url
            try eventStore.save(event, span: .thisEvent, commit: true)
            if let identifier = event.eventIdentifier { links[key] = identifier }
            activeKeys.insert(key)
        }

        for task in tasks {
            let key = Self.taskKey(task.id)
            let linkedBriefIsArchived = task.briefID.flatMap { briefsByID[$0]?.status } == .archived
                || (task.briefID != nil && task.briefID.flatMap { briefsByID[$0] } == nil)
            let shouldSync = CalendarSyncPolicy.shouldSyncTask(
                hasTargetDate: task.targetDate != nil,
                isSubtask: task.parentTaskID != nil,
                linkedBriefIsArchived: linkedBriefIsArchived,
                syncEnabled: syncTasks
            )
            guard shouldSync, let targetDate = task.targetDate else {
                try removeLinkedEvent(for: key, links: &links)
                continue
            }

            let event = links[key].flatMap(eventStore.event(withIdentifier:)) ?? EKEvent(eventStore: eventStore)
            let timing = CalendarSyncPolicy.taskTiming(
                targetDate: targetDate,
                estimatedMinutes: task.estimatedMinutes,
                includesTime: task.includesTargetTime
            )
            event.calendar = destinationCalendar
            event.title = task.isCompleted ? "Completed: \(task.title)" : "Task: \(task.title)"
            event.startDate = timing.start
            event.endDate = timing.end
            event.isAllDay = timing.isAllDay
            event.notes = taskNotes(task)
            if let briefID = task.briefID {
                event.url = AgentCyDeepLink.brief(briefID).url
            } else {
                event.url = AgentCyDeepLink.tasks.url
            }
            try eventStore.save(event, span: .thisEvent, commit: true)
            if let identifier = event.eventIdentifier { links[key] = identifier }
            activeKeys.insert(key)
        }

        for staleKey in Set(links.keys).subtracting(activeKeys) {
            try removeLinkedEvent(for: staleKey, links: &links)
        }
        saveEventLinks(links)
    }

    func disconnect() throws {
        try removeAllLinkedEvents(clearPreferences: true)
    }

    private func removeAllLinkedEvents(clearPreferences: Bool) throws {
        var links = eventLinks()
        guard authorization == .fullAccess else {
            saveEventLinks(links)
            if clearPreferences {
                CalendarIntegrationPreferences.disable(
                    preservingEventLinks: !links.isEmpty,
                    defaults: defaults
                )
            }
            try CalendarEventLinkCleanup.requireFullAccess(
                authorization: authorization,
                hasPendingLinks: !links.isEmpty
            )
            return
        }

        do {
            try CalendarEventLinkCleanup.removeAll(links: &links) { identifier in
                guard let event = eventStore.event(withIdentifier: identifier) else { return }
                try eventStore.remove(event, span: .thisEvent, commit: true)
            }
        } catch {
            saveEventLinks(links)
            if clearPreferences {
                CalendarIntegrationPreferences.disable(
                    preservingEventLinks: !links.isEmpty,
                    defaults: defaults
                )
            }
            throw error
        }
        saveEventLinks(links)
        if clearPreferences {
            CalendarIntegrationPreferences.disable(preservingEventLinks: false, defaults: defaults)
        }
    }

    private func removeLinkedEvent(for key: String, links: inout [String: String]) throws {
        guard let identifier = links[key] else { return }
        if let event = eventStore.event(withIdentifier: identifier) {
            try eventStore.remove(event, span: .thisEvent, commit: true)
        }
        links.removeValue(forKey: key)
    }

    private func eventLinks() -> [String: String] {
        defaults.dictionary(forKey: CalendarIntegrationPreferences.eventLinksKey) as? [String: String] ?? [:]
    }

    private func saveEventLinks(_ links: [String: String]) {
        defaults.set(links, forKey: CalendarIntegrationPreferences.eventLinksKey)
    }

    private func resolvedPostTitle(output: PlatformOutput, brief: CreativeBrief) -> String {
        let override = output.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty { return override }
        let title = brief.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled post" : title
    }

    private func postNotes(output: PlatformOutput) -> String {
        let status = output.status == .posted ? "Posted" : "Scheduled"
        return "Platform: \(output.platform.title)\nStatus: \(status)\n\nManaged by agent.cy."
    }

    private func taskNotes(_ task: CreatorTask) -> String {
        var lines = ["Focus: \(task.kind.title)", "Status: \(task.isCompleted ? "Completed" : "Open")"]
        let notes = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { lines.append("\n\(notes)") }
        lines.append("\nManaged by agent.cy.")
        return lines.joined(separator: "\n")
    }

    private static func postKey(_ id: UUID) -> String { "post:\(id.uuidString.lowercased())" }
    private static func taskKey(_ id: UUID) -> String { "task:\(id.uuidString.lowercased())" }
}
