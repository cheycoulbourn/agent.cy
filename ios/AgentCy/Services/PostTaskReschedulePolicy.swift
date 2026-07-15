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
}
