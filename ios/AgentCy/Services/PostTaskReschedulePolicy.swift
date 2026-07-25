import Foundation

enum PostTaskReschedulePolicy {
    static func isLinked(
        taskBriefID: UUID?,
        taskOutputID: UUID?,
        toOutputID outputID: UUID,
        briefID: UUID
    ) -> Bool {
        taskOutputID == outputID || (taskOutputID == nil && taskBriefID == briefID)
    }

    /// Keep a linked task on its post's scheduled day while preserving the
    /// task's own time of day when it has one.
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
        outputs: [PlatformOutput],
        calendar: Calendar = .current
    ) -> Date? {
        guard let postDate = scheduledPostDate(
            briefID: briefID,
            outputID: outputID,
            outputs: outputs
        ) else { return requestedDate }

        return alignedDate(
            requestedDate,
            to: postDate,
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
