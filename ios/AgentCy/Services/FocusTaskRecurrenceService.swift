import Foundation
import SwiftData

@MainActor
enum FocusTaskRecurrenceService {
    /// Keeps a rolling set of weekly focus tasks available without relying on a
    /// creator to complete the previous occurrence first.
    static func reconcile(
        context: ModelContext,
        workspaceID requestedWorkspaceID: UUID? = nil,
        from requestedStart: Date = Date(),
        weekCount: Int = 4,
        calendar: Calendar = .current
    ) throws {
        let requestedDay = calendar.startOfDay(for: requestedStart)
        let weekday = calendar.component(.weekday, from: requestedDay)
        let daysSinceMonday = (weekday + 5) % 7
        let weekStart = calendar.date(
            byAdding: .day,
            value: -daysSinceMonday,
            to: requestedDay
        ) ?? requestedDay
        let start = requestedDay
        guard let end = calendar.date(
            byAdding: .weekOfYear,
            value: max(1, weekCount),
            to: weekStart
        ) else {
            return
        }

        let workspaces = try context.fetch(FetchDescriptor<CreatorWorkspace>())
        let workspaceID = WorkspaceScope.activeWorkspaceID(
            preferredID: requestedWorkspaceID ?? CreatorWorkspacePreferences.activeWorkspaceID,
            workspaces: workspaces
        )
        let templates = try context.fetch(FetchDescriptor<DailyFocusTemplateEntry>())
        let scopedTemplates = templates.filter {
            WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: workspaceID,
                workspaces: workspaces
            )
        }
        let activeTemplateByWeekday = DailyFocusTemplateIndex.canonicalByWeekday(scopedTemplates)
            .filter { $0.value.isActive }
        let tasks = try context.fetch(FetchDescriptor<CreatorTask>(
            predicate: #Predicate {
                $0.focusTaskTemplateID != nil && $0.parentTaskID == nil
            }
        ))
        let generated = tasks.filter {
            WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: workspaceID,
                workspaces: workspaces
            )
        }

        var desired: [OccurrenceKey: DesiredOccurrence] = [:]
        var day = start
        while day < end {
            guard let weekday = PillarWeekday(rawValue: calendar.component(.weekday, from: day)) else {
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? end
                continue
            }
            if let template = activeTemplateByWeekday[weekday] {
                let selectedKinds = Set(DailyFocusResolver.normalizedKinds(
                    primary: template.kind,
                    secondary: template.secondaryKind,
                    storedTitle: template.title
                ))
                for definition in template.focusTaskTemplates
                    .filter({ selectedKinds.contains($0.focusKind) })
                    .sorted(by: definitionOrder) {
                    let title = definition.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { continue }
                    let key = OccurrenceKey(templateID: definition.id, day: day)
                    desired[key] = DesiredOccurrence(
                        definition: definition,
                        focusEntry: template,
                        day: day,
                        title: title
                    )
                }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? end
        }

        var existingByKey: [OccurrenceKey: CreatorTask] = [:]
        for task in generated {
            guard let templateID = task.focusTaskTemplateID,
                  let taskDay = task.dailyFocusDate ?? task.targetDate
            else { continue }
            let normalizedDay = calendar.startOfDay(for: taskDay)
            guard normalizedDay >= start, normalizedDay < end else { continue }
            let key = OccurrenceKey(templateID: templateID, day: normalizedDay)
            if existingByKey[key] == nil {
                existingByKey[key] = task
            } else if !task.isFocusTemplateCustomized && !task.isCompleted && !task.isSkipped {
                context.delete(task)
            }
        }

        for (key, task) in existingByKey where desired[key] == nil {
            if task.isFocusTemplateCustomized || task.isCompleted || task.isSkipped {
                task.focusTaskTemplateID = nil
            } else {
                context.delete(task)
            }
        }

        for (key, occurrence) in desired {
            if let task = existingByKey[key] {
                guard !task.isFocusTemplateCustomized, !task.isCompleted, !task.isSkipped else { continue }
                apply(occurrence, to: task)
            } else {
                let task = CreatorTask(
                    title: occurrence.title,
                    kind: occurrence.definition.focusKind.taskKind ?? .planning,
                    lane: .production,
                    priority: occurrence.definition.priority,
                    targetDate: occurrence.day,
                    includesTargetTime: false,
                    dailyFocusDate: occurrence.day,
                    dailyFocusTitle: occurrence.focusEntry.title,
                    dailyFocusTemplateEntryID: occurrence.focusEntry.id,
                    focusTaskTemplateID: occurrence.definition.id,
                    sortOrder: occurrence.definition.sortOrder
                )
                task.workspaceID = workspaceID
                context.insert(task)
            }
        }

        try context.save()
    }

    private static func apply(_ occurrence: DesiredOccurrence, to task: CreatorTask) {
        task.title = occurrence.title
        task.kind = occurrence.definition.focusKind.taskKind ?? .planning
        task.lane = .production
        task.priority = occurrence.definition.priority.normalized
        task.targetDate = occurrence.day
        task.includesTargetTime = false
        task.dailyFocusDate = occurrence.day
        task.dailyFocusTitle = occurrence.focusEntry.title
        task.dailyFocusTemplateEntryID = occurrence.focusEntry.id
        task.sortOrder = occurrence.definition.sortOrder
    }

    private static func definitionOrder(
        _ lhs: DailyFocusTaskTemplateDefinition,
        _ rhs: DailyFocusTaskTemplateDefinition
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

private struct OccurrenceKey: Hashable {
    let templateID: UUID
    let day: Date
}

private struct DesiredOccurrence {
    let definition: DailyFocusTaskTemplateDefinition
    let focusEntry: DailyFocusTemplateEntry
    let day: Date
    let title: String
}
