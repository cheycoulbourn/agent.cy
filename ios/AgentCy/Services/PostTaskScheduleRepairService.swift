import Foundation
import SwiftData

@MainActor
enum PostTaskScheduleRepairService {
    static let migrationKey = "agentcy.postTaskScheduleRepair.explicitOutput.v1"

    /// Repairs post tasks that were left on an old day by builds that moved the
    /// post without moving its explicitly linked tasks. This deliberately runs
    /// once so later creator edits are never overwritten during app launch.
    @discardableResult
    static func reconcileOnce(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) throws -> Int {
        guard !defaults.bool(forKey: migrationKey) else { return 0 }

        let outputs = try context.fetch(FetchDescriptor<PlatformOutput>())
        let outputByID = Dictionary(uniqueKeysWithValues: outputs.map { ($0.id, $0) })
        let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
        var repairedCount = 0

        for task in tasks where !task.isCompleted {
            guard let outputID = task.platformOutputID,
                  let output = outputByID[outputID],
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
