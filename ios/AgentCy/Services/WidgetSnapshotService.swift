import Foundation
import SwiftData
import WidgetKit

@MainActor
enum WidgetSnapshotService {
    static func refresh(
        context: ModelContext,
        now: Date = Date(),
        workspaceID: UUID? = CreatorWorkspacePreferences.activeWorkspaceID
    ) {
        do {
            let snapshot = try makeSnapshot(context: context, now: now, workspaceID: workspaceID)
            try AgentCyWidgetSnapshotStore.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            #if DEBUG
            print("Widget snapshot refresh skipped: \(error.localizedDescription)")
            #endif
        }
    }

    static func makeSnapshot(
        context: ModelContext,
        now: Date = Date(),
        workspaceID: UUID? = CreatorWorkspacePreferences.activeWorkspaceID
    ) throws -> AgentCyWidgetSnapshot {
        let workspaces = try context.fetch(FetchDescriptor<CreatorWorkspace>())
        let activeID = WorkspaceScope.activeWorkspaceID(preferredID: workspaceID, workspaces: workspaces)
        let profiles = try context.fetch(FetchDescriptor<CreatorProfile>())
        let briefs = try context.fetch(FetchDescriptor<CreativeBrief>())
            .filter {
                $0.status != .archived &&
                    WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
            }
        let outputs = try context.fetch(FetchDescriptor<PlatformOutput>()).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }
        let tasks = try context.fetch(FetchDescriptor<CreatorTask>()).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }
        let pillars = try context.fetch(FetchDescriptor<Pillar>())
            .filter {
                !$0.isArchived &&
                    WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
            }
        let destinations = try context.fetch(FetchDescriptor<PublishingDestination>())
            .filter { !$0.isArchived }
        let formats = try context.fetch(FetchDescriptor<PublishingFormat>())
            .filter { !$0.isArchived }
        let focusTemplates = try context.fetch(FetchDescriptor<DailyFocusTemplateEntry>()).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }
        let focusOverrides = try context.fetch(FetchDescriptor<DailyFocusOverride>()).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }

        let briefByID = Dictionary(uniqueKeysWithValues: briefs.map { ($0.id, $0) })
        let pillarByID = Dictionary(uniqueKeysWithValues: pillars.map { ($0.id, $0) })
        let destinationByID = Dictionary(uniqueKeysWithValues: destinations.map { ($0.id, $0) })
        let formatByID = Dictionary(uniqueKeysWithValues: formats.map { ($0.id, $0) })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        let topLevelTasks = tasks.filter { $0.parentTaskID == nil }
        let todayTasks = topLevelTasks
            .filter { !$0.isSkipped }
            .filter { $0.targetDate.map { calendar.isDate($0, inSameDayAs: today) } == true }
            .sorted(by: taskSort)
        let openTodayTasks = todayTasks.filter { !$0.isCompleted }

        let resolvedFocus = DailyFocusResolver.resolve(
            date: today,
            templates: focusTemplates,
            overrides: focusOverrides,
            calendar: calendar
        )
        let focusSnapshot = resolvedFocus.map { focus in
            WidgetFocusSnapshot(
                title: focus.title,
                directive: focus.note,
                durationMinutes: focus.durationMinutes,
                startDate: focus.time,
                completedTaskCount: todayTasks.filter(\.isCompleted).count,
                taskCount: todayTasks.count
            )
        }

        let todayOutputs = outputs.filter { output in
            guard let brief = briefByID[output.briefID] else { return false }
            guard output.status != .posted, brief.status != .posted else { return false }
            return output.targetDate.map { calendar.isDate($0, inSameDayAs: today) } == true
        }
        let nextOutput = todayOutputs.sorted { lhs, rhs in
            let lhsIsDraft = lhs.status == .draft || briefByID[lhs.briefID].map {
                $0.status == .spark || $0.status == .developing
            } == true
            let rhsIsDraft = rhs.status == .draft || briefByID[rhs.briefID].map {
                $0.status == .spark || $0.status == .developing
            } == true
            if lhsIsDraft != rhsIsDraft { return !lhsIsDraft }
            return (lhs.targetDate ?? .distantFuture) < (rhs.targetDate ?? .distantFuture)
        }.first

        let nextPost = nextOutput.flatMap { output -> WidgetPostSnapshot? in
            guard let brief = briefByID[output.briefID] else { return nil }
            let pillar = brief.pillarID.flatMap { pillarByID[$0] }
            let titleOverride = output.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            let destination = output.destinationID.flatMap { destinationByID[$0]?.name }
            let format = output.formatID.flatMap { formatByID[$0]?.name }
            let label = [destination, format].compactMap { $0 }.joined(separator: " · ")
            return WidgetPostSnapshot(
                id: brief.id,
                title: titleOverride.isEmpty ? brief.title : titleOverride,
                pillarName: pillar?.name ?? "Unfiled",
                pillarColorHex: pillar?.resolvedColorHex(in: pillars),
                platformLabel: label.isEmpty ? output.platform.title : label,
                targetDate: output.targetDate,
                status: output.status == .draft || brief.status == .spark || brief.status == .developing
                    ? "Draft"
                    : output.status.rawValue.capitalized
            )
        }

        let mondayOffset = (calendar.component(.weekday, from: today) + 5) % 7
        let weekStart = calendar.date(byAdding: .day, value: -mondayOffset, to: today) ?? today
        let week = (0..<7).compactMap { offset -> WidgetDaySnapshot? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let focus = DailyFocusResolver.resolve(
                date: day,
                templates: focusTemplates,
                overrides: focusOverrides,
                calendar: calendar
            )
            let dayOutput = outputs
                .filter { output in
                    output.targetDate.map { calendar.isDate($0, inSameDayAs: day) } == true && briefByID[output.briefID] != nil
                }
                .sorted { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
                .first
            let outputPillar = dayOutput
                .flatMap { briefByID[$0.briefID]?.pillarID }
                .flatMap { pillarByID[$0] }
            let weekday = PillarWeekday(rawValue: calendar.component(.weekday, from: day))
            let assignedPillar = weekday.flatMap { weekday in
                pillars.first { $0.assignedWeekdays.contains(weekday) }
            }
            let pillar = outputPillar ?? assignedPillar
            return WidgetDaySnapshot(
                date: day,
                focusTitle: focus?.title ?? "Rest",
                pillarColorHex: pillar?.resolvedColorHex(in: pillars)
            )
        }

        let latestIdea = briefs
            .filter(IdeaBankPlacementPolicy.includes)
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
            .map { brief in
                let pillar = brief.pillarID.flatMap { pillarByID[$0] }
                return WidgetIdeaSnapshot(
                    id: brief.id,
                    title: brief.title,
                    pillarName: pillar?.name,
                    pillarColorHex: pillar?.resolvedColorHex(in: pillars),
                    capturedAt: brief.updatedAt
                )
            }

        let widgetTasks = WidgetTaskLane.allCases.flatMap { lane in
            todayTasks
                .filter { $0.lane.rawValue == lane.rawValue }
                .sorted(by: taskSort)
                .prefix(5)
                .map(taskSnapshot)
        }

        let identity = ActiveCreatorIdentity.resolve(
            profile: profiles.first,
            workspaces: workspaces,
            preferredWorkspaceID: activeID
        )
        let name = identity.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return AgentCyWidgetSnapshot(
            generatedAt: now,
            creatorName: name.isEmpty ? "Creator" : name,
            focus: focusSnapshot,
            todayTasks: openTodayTasks.prefix(4).map(taskSnapshot),
            nextPost: nextPost,
            week: week,
            latestIdea: latestIdea,
            productionTasks: widgetTasks
        )
    }

    private static func taskSnapshot(_ task: CreatorTask) -> WidgetTaskSnapshot {
        WidgetTaskSnapshot(
            id: task.id,
            title: task.title,
            kind: task.kind.title,
            targetDate: task.targetDate,
            isCompleted: task.isCompleted,
            lane: WidgetTaskLane(rawValue: task.lane.rawValue)
        )
    }

    private static func taskSort(_ lhs: CreatorTask, _ rhs: CreatorTask) -> Bool {
        if lhs.priority == .urgent, rhs.priority != .urgent { return true }
        if rhs.priority == .urgent, lhs.priority != .urgent { return false }
        if lhs.targetDate != rhs.targetDate {
            return (lhs.targetDate ?? .distantFuture) < (rhs.targetDate ?? .distantFuture)
        }
        return lhs.createdAt < rhs.createdAt
    }
}
