import Foundation

enum PostDatePlanPolicy {
    static func isChronologicallyValid(
        workDate: Date?,
        scheduledDate: Date?,
        calendar: Calendar = .current
    ) -> Bool {
        guard let workDate, let scheduledDate else { return true }
        return calendar.startOfDay(for: scheduledDate) >= calendar.startOfDay(for: workDate)
    }

    static func preferredTaskDate(workDate: Date?, scheduledDate: Date?) -> Date? {
        workDate ?? scheduledDate
    }
}

enum PostWorkDateStatusPolicy {
    static func isLate(
        workDate: Date?,
        briefStatus: BriefStatus,
        outputStatus: PlatformOutputStatus,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let workDate,
              briefStatus != .archived,
              briefStatus != .scheduled,
              briefStatus != .posted,
              outputStatus != .scheduled,
              outputStatus != .posted else {
            return false
        }

        return calendar.startOfDay(for: workDate) < calendar.startOfDay(for: now)
    }
}

struct CyNoticedReconciliationSummary: Equatable {
    let lateWorkCount: Int
    let overduePostCount: Int

    var needsAttention: Bool { lateWorkCount > 0 || overduePostCount > 0 }

    var message: String {
        switch (lateWorkCount, overduePostCount) {
        case let (lateWork, overduePosts) where lateWork > 0 && overduePosts > 0:
            return "\(lateWork) late work item\(lateWork == 1 ? "" : "s") and \(overduePosts) overdue post\(overduePosts == 1 ? "" : "s") need attention."
        case let (lateWork, _) where lateWork > 0:
            return "\(lateWork) work item\(lateWork == 1 ? " needs" : "s need") a new date."
        case let (_, overduePosts) where overduePosts > 0:
            return "\(overduePosts) post\(overduePosts == 1 ? " missed" : "s missed") the scheduled date."
        default:
            return ""
        }
    }
}

/// One shared definition drives the Cy Noticed widget and the list it opens.
/// This prevents a notice from surviving after every actionable item is cleared.
enum CyNoticedReconciliationPolicy {
    static func includes(
        brief: CreativeBrief,
        output: PlatformOutput,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard brief.status != .archived else { return false }
        return isOverduePost(output: output, now: now, calendar: calendar)
            || PostWorkDateStatusPolicy.isLate(
                workDate: brief.workDate,
                briefStatus: brief.status,
                outputStatus: output.status,
                now: now,
                calendar: calendar
            )
    }

    static func summary(
        briefs: [CreativeBrief],
        outputs: [PlatformOutput],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CyNoticedReconciliationSummary {
        let briefsByID = DuplicateSafeIndex.firstValues(briefs.map { ($0.id, $0) })
        var lateBriefIDs = Set<UUID>()
        var overdueOutputIDs = Set<UUID>()

        for output in outputs {
            guard let brief = briefsByID[output.briefID], brief.status != .archived else { continue }
            if isOverduePost(output: output, now: now, calendar: calendar) {
                overdueOutputIDs.insert(output.id)
            } else if PostWorkDateStatusPolicy.isLate(
                workDate: brief.workDate,
                briefStatus: brief.status,
                outputStatus: output.status,
                now: now,
                calendar: calendar
            ) {
                lateBriefIDs.insert(brief.id)
            }
        }

        return CyNoticedReconciliationSummary(
            lateWorkCount: lateBriefIDs.count,
            overduePostCount: overdueOutputIDs.count
        )
    }

    private static func isOverduePost(
        output: PlatformOutput,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard output.status != .posted, let targetDate = output.targetDate else { return false }
        return calendar.startOfDay(for: targetDate) < calendar.startOfDay(for: now)
    }
}

enum PostTaskReschedulePolicy {
    static func isLinked(
        taskBriefID: UUID?,
        taskOutputID: UUID?,
        toOutputID outputID: UUID,
        briefID: UUID
    ) -> Bool {
        taskOutputID == outputID || (taskOutputID == nil && taskBriefID == briefID)
    }

    /// Keep a linked task on its post's preferred work day while preserving
    /// the task's own time of day when it has one.
    static func alignedDate(
        _ taskDate: Date?,
        to postDate: Date,
        includesTime: Bool,
        calendar: Calendar = .current
    ) -> Date {
        guard includesTime, let taskDate else {
            return calendar.startOfDay(for: postDate)
        }

        let time = calendar.dateComponents([.hour, .minute, .second], from: taskDate)
        return calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: postDate
        ) ?? postDate
    }

    static func scheduledPostDate(
        briefID: UUID?,
        outputID: UUID?,
        outputs: [PlatformOutput]
    ) -> Date? {
        if let outputID,
           let output = outputs.first(where: {
               $0.id == outputID && $0.status == .scheduled && $0.targetDate != nil
           }) {
            return output.targetDate
        }

        guard let briefID else { return nil }
        return outputs
            .filter { $0.briefID == briefID && $0.status == .scheduled && $0.targetDate != nil }
            .compactMap(\.targetDate)
            .min()
    }

    static func resolvedDueDate(
        requestedDate: Date?,
        includesTime: Bool,
        briefID: UUID?,
        outputID: UUID?,
        workDate: Date? = nil,
        outputs: [PlatformOutput],
        calendar: Calendar = .current
    ) -> Date? {
        let preferredDate = workDate ?? scheduledPostDate(
            briefID: briefID,
            outputID: outputID,
            outputs: outputs
        )
        guard let preferredDate else { return requestedDate }

        return alignedDate(
            requestedDate,
            to: preferredDate,
            includesTime: includesTime,
            calendar: calendar
        )
    }

    @discardableResult
    static func alignOpenTasks(
        _ tasks: [CreatorTask],
        to output: PlatformOutput,
        on postDate: Date,
        calendar: Calendar = .current
    ) -> Int {
        var movedCount = 0
        for task in tasks where !task.isCompleted {
            guard isLinked(
                taskBriefID: task.briefID,
                taskOutputID: task.platformOutputID,
                toOutputID: output.id,
                briefID: output.briefID
            ) else { continue }

            task.targetDate = alignedDate(
                task.targetDate,
                to: postDate,
                includesTime: task.includesTargetTime,
                calendar: calendar
            )
            if task.dailyFocusDate != nil {
                task.dailyFocusDate = calendar.startOfDay(for: postDate)
            }
            movedCount += 1
        }
        return movedCount
    }

    @discardableResult
    static func clearOpenTaskDates(
        _ tasks: [CreatorTask],
        for output: PlatformOutput
    ) -> Int {
        var clearedCount = 0
        for task in tasks where !task.isCompleted {
            guard isLinked(
                taskBriefID: task.briefID,
                taskOutputID: task.platformOutputID,
                toOutputID: output.id,
                briefID: output.briefID
            ) else { continue }

            task.targetDate = nil
            task.includesTargetTime = false
            task.dailyFocusDate = nil
            clearedCount += 1
        }
        return clearedCount
    }
}
