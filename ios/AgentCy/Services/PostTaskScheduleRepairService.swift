import Foundation
import SwiftData

@MainActor
enum PostTaskScheduleRepairService {
    static let migrationKey = "agentcy.postTaskScheduleRepair.allPostTasks.v2"

    /// Repairs post tasks that were left on an old day or without a due date.
    /// This deliberately runs once so later creator edits are never overwritten
    /// during app launch.
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
        let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
        var repairedCount = 0

        for task in tasks where !task.isCompleted {
            let output = task.platformOutputID.flatMap { outputByID[$0] }
                ?? task.briefID.flatMap { briefID in
                    outputsByBriefID[briefID]?
                        .filter { $0.status == .scheduled && $0.targetDate != nil }
                        .min { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
                }
            guard let output,
                  output.status != .posted,
                  let postDate = output.targetDate
            else { continue }

            let taskIsOnPostDay = task.targetDate.map {
                calendar.isDate($0, inSameDayAs: postDate)
            } ?? false
            let focusIsOnPostDay = task.dailyFocusDate.map {
                calendar.isDate($0, inSameDayAs: postDate)
            } ?? true
            guard !taskIsOnPostDay || !focusIsOnPostDay else { continue }

            task.targetDate = PostTaskReschedulePolicy.alignedDate(
                task.targetDate,
                to: postDate,
                includesTime: task.includesTargetTime,
                calendar: calendar
            )
            if task.dailyFocusDate != nil {
                task.dailyFocusDate = calendar.startOfDay(for: postDate)
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
