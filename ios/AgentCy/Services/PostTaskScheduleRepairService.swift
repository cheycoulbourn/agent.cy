import Foundation
import SwiftData

@MainActor
enum PostTaskScheduleRepairService {
    static let migrationKey = "agentcy.postTaskScheduleRepair.workDateFirst.v3"

    /// Moves automatically dated post tasks from the posting day to the work
    /// day. Posts without a work day retain the posting-day fallback. This
    /// deliberately runs once so later creator edits are never overwritten.
    @discardableResult
    static func reconcileOnce(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) throws -> Int {
        guard !defaults.bool(forKey: migrationKey) else { return 0 }

        let outputs = try context.fetch(FetchDescriptor<PlatformOutput>())
        let outputByID = Dictionary(uniqueKeysWithValues: outputs.map { ($0.id, $0) })
        let outputsByBriefID = Dictionary(grouping: outputs, by: \.briefID)
        let briefs = try context.fetch(FetchDescriptor<CreativeBrief>())
        let briefByID = Dictionary(uniqueKeysWithValues: briefs.map { ($0.id, $0) })
        let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
        var repairedCount = 0

        for task in tasks where !task.isCompleted {
            let output = task.platformOutputID.flatMap { outputByID[$0] }
                ?? task.briefID.flatMap { briefID in
                    outputsByBriefID[briefID]?
                        .filter { $0.status == .scheduled && $0.targetDate != nil }
                        .min { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
                }
            guard let output, output.status != .posted else { continue }

            let brief = briefByID[output.briefID]
            let postDate = output.targetDate
            guard let preferredDate = brief?.workDate ?? postDate else { continue }

            let taskIsOnPreferredDay = task.targetDate.map {
                calendar.isDate($0, inSameDayAs: preferredDate)
            } ?? false
            let focusIsOnPreferredDay = task.dailyFocusDate.map {
                calendar.isDate($0, inSameDayAs: preferredDate)
            } ?? true
            guard !taskIsOnPreferredDay || !focusIsOnPreferredDay else { continue }

            if brief?.workDate != nil, let taskDate = task.targetDate {
                let wasAutomaticallyOnPostDay = postDate.map {
                    calendar.isDate(taskDate, inSameDayAs: $0)
                } ?? false
                guard wasAutomaticallyOnPostDay else { continue }
            }

            task.targetDate = PostTaskReschedulePolicy.alignedDate(
                task.targetDate,
                to: preferredDate,
                includesTime: task.includesTargetTime,
                calendar: calendar
            )
            if task.dailyFocusDate != nil {
                task.dailyFocusDate = calendar.startOfDay(for: preferredDate)
            }
            repairedCount += 1
        }

        if repairedCount > 0 {
            try context.save()
        }
        defaults.set(true, forKey: migrationKey)
        return repairedCount
    }
}

@MainActor
enum AccidentalRecurringPostRepairService {
    static let migrationKey = "agentcy.accidentalRecurringPostRepair.thirteenPostBatch.v1"

    /// Removes the twelve future posts created by the July 2026 single-post
    /// scheduling regression. The match is intentionally narrow so legitimate
    /// recurring series are never treated as repair candidates.
    @discardableResult
    static func reconcileOnce(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) throws -> Int {
        guard !defaults.bool(forKey: migrationKey) else { return 0 }

        let outputs = try context.fetch(FetchDescriptor<PlatformOutput>())
        let seriesOutputs = outputs.filter { $0.seriesRootOutputID != nil }
        let grouped = Dictionary(grouping: seriesOutputs) { $0.seriesRootOutputID! }
        let recentCutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)

        let candidate = grouped.compactMap { rootID, members -> (PlatformOutput, [PlatformOutput], Date)? in
            guard let root = members.first(where: { $0.id == rootID }) else { return nil }
            let clones = members.filter { $0.id != rootID }
            guard clones.count == RecurringPostSchedule.defaultFutureOccurrenceCount,
                  clones.allSatisfy({ $0.status != .posted }),
                  let earliestCreatedAt = clones.map(\.createdAt).min(),
                  let latestCreatedAt = clones.map(\.createdAt).max(),
                  earliestCreatedAt >= recentCutoff,
                  latestCreatedAt.timeIntervalSince(earliestCreatedAt) <= 5
            else { return nil }
            return (root, clones, latestCreatedAt)
        }
        .max { $0.2 < $1.2 }

        guard let (root, clones, _) = candidate else { return 0 }

        let cloneBriefIDs = Set(clones.map(\.briefID))
        let cloneOutputIDs = Set(clones.map(\.id))

        let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
        tasks.filter {
            $0.briefID.map(cloneBriefIDs.contains) == true ||
                $0.platformOutputID.map(cloneOutputIDs.contains) == true
        }
        .forEach(context.delete)

        let attachments = try context.fetch(FetchDescriptor<CreatorAttachment>())
        attachments.filter {
            cloneBriefIDs.contains($0.briefID) ||
                $0.platformOutputID.map(cloneOutputIDs.contains) == true
        }
        .forEach(context.delete)

        let proposals = try context.fetch(FetchDescriptor<PendingBriefProposal>())
        proposals.filter { cloneBriefIDs.contains($0.briefID) }.forEach(context.delete)

        let threads = try context.fetch(FetchDescriptor<ConversationThread>())
            .filter { $0.briefID.map(cloneBriefIDs.contains) == true }
        let threadIDs = Set(threads.map(\.id))
        let messages = try context.fetch(FetchDescriptor<ConversationMessage>())
            .filter { threadIDs.contains($0.threadID) }
        messages.forEach(context.delete)
        threads.forEach(context.delete)

        clones.forEach(context.delete)
        let briefs = try context.fetch(FetchDescriptor<CreativeBrief>())
        briefs.filter { cloneBriefIDs.contains($0.id) }.forEach(context.delete)

        root.recurrence = .none
        root.recurrenceWeekdays = []
        root.recurrenceMonthDay = nil
        root.recurrenceEndDate = nil
        root.seriesRootOutputID = nil

        try context.save()
        defaults.set(true, forKey: migrationKey)
        return clones.count
    }
}
