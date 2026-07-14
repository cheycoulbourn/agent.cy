import Foundation
import SwiftData

enum RecurringPostSchedule {
    static let defaultFutureOccurrenceCount = 12
    static let maximumOccurrenceCount = 500

    static func normalizedTargetDate(
        _ date: Date,
        includesTime: Bool,
        calendar: Calendar = .current
    ) -> Date {
        guard !includesTime else { return date }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }

    static func futureDates(
        after firstDate: Date,
        frequency: PostRecurrenceFrequency,
        weekdays: Set<PillarWeekday> = [],
        monthDay: Int? = nil,
        endDate: Date? = nil,
        includesTime: Bool = true,
        calendar: Calendar = .current
    ) -> [Date] {
        guard frequency != .none else { return [] }

        let first = normalizedTargetDate(firstDate, includesTime: includesTime, calendar: calendar)
        let inclusiveEnd = endDate.map { calendar.startOfDay(for: $0) }
        let limit = endDate == nil ? defaultFutureOccurrenceCount : maximumOccurrenceCount

        func isWithinEnd(_ candidate: Date) -> Bool {
            guard let inclusiveEnd else { return true }
            return calendar.startOfDay(for: candidate) <= inclusiveEnd
        }

        switch frequency {
        case .none:
            return []
        case .daily:
            var dates: [Date] = []
            var candidate = first
            while dates.count < limit,
                  let next = calendar.date(byAdding: .day, value: 1, to: candidate) {
                candidate = normalizedTargetDate(next, includesTime: includesTime, calendar: calendar)
                guard isWithinEnd(candidate) else { break }
                dates.append(candidate)
            }
            return dates

        case .weekly:
            let fallbackWeekday = PillarWeekday(rawValue: calendar.component(.weekday, from: first))
            let selectedWeekdays = weekdays.isEmpty ? Set(fallbackWeekday.map { [$0] } ?? []) : weekdays
            var dates: [Date] = []
            var candidate = first
            while dates.count < limit,
                  let next = calendar.date(byAdding: .day, value: 1, to: candidate) {
                candidate = normalizedTargetDate(next, includesTime: includesTime, calendar: calendar)
                guard isWithinEnd(candidate) else { break }
                guard let weekday = PillarWeekday(rawValue: calendar.component(.weekday, from: candidate)),
                      selectedWeekdays.contains(weekday) else { continue }
                dates.append(candidate)
            }
            return dates

        case .monthly:
            let desiredDay = min(max(monthDay ?? calendar.component(.day, from: first), 1), 31)
            let time = calendar.dateComponents([.hour, .minute, .second], from: first)
            var dates: [Date] = []
            var monthOffset = 1
            while dates.count < limit,
                  let month = calendar.date(byAdding: .month, value: monthOffset, to: first) {
                monthOffset += 1
                var components = calendar.dateComponents([.year, .month], from: month)
                let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? desiredDay
                components.day = min(desiredDay, daysInMonth)
                components.hour = includesTime ? time.hour : 12
                components.minute = includesTime ? time.minute : 0
                components.second = includesTime ? time.second : 0
                guard let candidate = calendar.date(from: components) else { continue }
                guard isWithinEnd(candidate) else { break }
                dates.append(candidate)
            }
            return dates
        }
    }
}

enum RecurringTaskSchedule {
    static func nextDate(
        after date: Date,
        frequency: TaskRecurrenceFrequency,
        calendar: Calendar = .current
    ) -> Date? {
        switch frequency {
        case .none: nil
        case .daily: calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly: calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly: calendar.date(byAdding: .month, value: 1, to: date)
        }
    }
}

@MainActor
enum RecurringTaskMaterializer {
    @discardableResult
    static func createNextOccurrence(
        after task: CreatorTask,
        context: ModelContext,
        calendar: Calendar = .current
    ) throws -> CreatorTask? {
        guard task.parentTaskID == nil,
              task.recurrence != .none,
              let targetDate = task.targetDate,
              let nextDate = RecurringTaskSchedule.nextDate(
                after: targetDate,
                frequency: task.recurrence,
                calendar: calendar
              ) else { return nil }

        let rootID = task.recurrenceRootTaskID ?? task.id
        task.recurrenceRootTaskID = rootID
        let allTasks = try context.fetch(FetchDescriptor<CreatorTask>())
        let alreadyExists = allTasks.contains { candidate in
            candidate.id != task.id &&
                candidate.recurrenceRootTaskID == rootID &&
                candidate.targetDate.map { abs($0.timeIntervalSince(nextDate)) < 1 } == true
        }
        guard !alreadyExists else { return nil }

        let next = CreatorTask(
            briefID: task.briefID,
            pillarID: task.pillarID,
            platformOutputID: task.platformOutputID,
            title: task.title,
            kind: task.kind,
            lane: task.lane,
            priority: task.priority,
            notes: task.notes,
            estimatedMinutes: task.estimatedMinutes,
            targetDate: nextDate,
            dailyFocusDate: task.dailyFocusDate.map {
                calendar.date(byAdding: .day, value: calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: targetDate),
                    to: calendar.startOfDay(for: nextDate)
                ).day ?? 0, to: $0) ?? nextDate
            },
            dailyFocusTitle: task.dailyFocusTitle,
            dailyFocusTemplateEntryID: task.dailyFocusTemplateEntryID,
            recurrence: task.recurrence,
            recurrenceRootTaskID: rootID,
            sortOrder: task.sortOrder,
            isRecordingMilestoneDesignated: false
        )
        context.insert(next)

        let subtasks = allTasks
            .filter { $0.parentTaskID == task.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        for subtask in subtasks {
            context.insert(CreatorTask(
                briefID: next.briefID,
                pillarID: next.pillarID,
                platformOutputID: next.platformOutputID,
                parentTaskID: next.id,
                title: subtask.title,
                kind: subtask.kind,
                lane: subtask.lane,
                priority: subtask.priority,
                notes: subtask.notes,
                estimatedMinutes: subtask.estimatedMinutes,
                dailyFocusDate: next.dailyFocusDate,
                dailyFocusTitle: next.dailyFocusTitle,
                dailyFocusTemplateEntryID: next.dailyFocusTemplateEntryID,
                sortOrder: subtask.sortOrder
            ))
        }
        return next
    }
}

@MainActor
enum RecurringPostMaterializer {
    static func createFutureOccurrences(
        rootBrief: CreativeBrief,
        rootOutput: PlatformOutput,
        firstDate: Date,
        context: ModelContext,
        calendar: Calendar = .current
    ) throws -> Int {
        guard rootOutput.recurrence != .none else { return 0 }
        rootOutput.seriesRootOutputID = rootOutput.id
        let futureDates = RecurringPostSchedule.futureDates(
            after: firstDate,
            frequency: rootOutput.recurrence,
            weekdays: rootOutput.recurrenceWeekdays,
            monthDay: rootOutput.recurrenceMonthDay,
            endDate: rootOutput.recurrenceEndDate,
            includesTime: rootOutput.includesTargetTime,
            calendar: calendar
        )
        guard !futureDates.isEmpty else { return 0 }
        let allOutputs = try context.fetch(FetchDescriptor<PlatformOutput>())
        let existing = allOutputs.filter {
            $0.id != rootOutput.id && $0.seriesRootOutputID == rootOutput.id
        }
        let sourceTasks = try context.fetch(FetchDescriptor<CreatorTask>())
            .filter { $0.briefID == rootBrief.id }

        var createdCount = 0
        for (index, occurrenceDate) in futureDates.enumerated() {
            let alreadyExists = existing.contains { candidate in
                guard let targetDate = candidate.targetDate else { return false }
                if rootOutput.includesTargetTime {
                    return abs(targetDate.timeIntervalSince(occurrenceDate)) < 1
                }
                return calendar.isDate(targetDate, inSameDayAs: occurrenceDate)
            }
            guard !alreadyExists else { continue }

            let occurrenceBrief = cloneBrief(
                rootBrief,
                occurrenceDate: occurrenceDate,
                createdAt: Date().addingTimeInterval(Double(index) / 100)
            )
            context.insert(occurrenceBrief)

            let occurrenceOutput = cloneOutput(
                rootOutput,
                briefID: occurrenceBrief.id,
                rootOutputID: rootOutput.id,
                occurrenceDate: occurrenceDate
            )
            context.insert(occurrenceOutput)
            _ = BriefLifecycle.schedule(occurrenceOutput, for: occurrenceDate, brief: occurrenceBrief)
            BriefLifecycle.synchronize(occurrenceBrief, outputs: [occurrenceOutput])
            cloneTasks(
                sourceTasks,
                from: firstDate,
                to: occurrenceDate,
                briefID: occurrenceBrief.id,
                outputID: occurrenceOutput.id,
                context: context,
                calendar: calendar
            )
            createdCount += 1
        }
        return createdCount
    }

    private static func cloneBrief(
        _ source: CreativeBrief,
        occurrenceDate: Date,
        createdAt: Date
    ) -> CreativeBrief {
        let clone = CreativeBrief(
            title: source.title,
            premise: source.premise,
            source: source.source,
            status: .ready,
            createdAt: createdAt
        )
        clone.notes = source.notes
        clone.scriptEnabled = source.scriptEnabled
        clone.audience = source.audience
        clone.creativeGoal = source.creativeGoal
        clone.takeaway = source.takeaway
        clone.durationSeconds = source.durationSeconds
        clone.spokenHook = source.spokenHook
        clone.firstFrameText = source.firstFrameText
        clone.scriptBeatsText = source.scriptBeatsText
        clone.close = source.close
        clone.ctaIntent = source.ctaIntent
        clone.filmingGuidance = source.filmingGuidance
        clone.editingGuidance = source.editingGuidance
        clone.assumptionsText = source.assumptionsText
        clone.voiceConfidence = source.voiceConfidence
        clone.readyBriefPayloadJSON = source.readyBriefPayloadJSON
        clone.pillarID = source.pillarID
        clone.isBrandCollaboration = source.isBrandCollaboration
        clone.brandName = source.brandName
        clone.compensationType = source.compensationType
        clone.compensationAmount = source.compensationAmount
        clone.compensationCurrencyCode = source.compensationCurrencyCode
        clone.giftedProductDescription = source.giftedProductDescription
        clone.giftedEstimatedValue = source.giftedEstimatedValue
        clone.promoCode = source.promoCode
        clone.promoLinkString = source.promoLinkString
        clone.agendaDate = occurrenceDate
        return clone
    }

    private static func cloneOutput(
        _ source: PlatformOutput,
        briefID: UUID,
        rootOutputID: UUID,
        occurrenceDate: Date
    ) -> PlatformOutput {
        let clone = PlatformOutput(
            briefID: briefID,
            platform: source.platform,
            destinationID: source.destinationID,
            formatID: source.formatID,
            socialAccountID: source.socialAccountID,
            durationSeconds: source.durationSeconds,
            status: .ready
        )
        clone.caption = source.caption
        clone.openingAdjustment = source.openingAdjustment
        clone.titleOverride = source.titleOverride
        clone.cta = source.cta
        clone.editChanges = source.editChanges
        clone.targetDate = occurrenceDate
        clone.seriesName = source.seriesName
        clone.recurrence = .none
        clone.recurrenceEndDate = nil
        clone.includesTargetTime = source.includesTargetTime
        clone.seriesRootOutputID = rootOutputID
        return clone
    }

    private static func cloneTasks(
        _ sourceTasks: [CreatorTask],
        from firstDate: Date,
        to occurrenceDate: Date,
        briefID: UUID,
        outputID: UUID,
        context: ModelContext,
        calendar: Calendar
    ) {
        let dayOffset = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: firstDate),
            to: calendar.startOfDay(for: occurrenceDate)
        ).day ?? 0
        var taskIDMap: [UUID: UUID] = [:]
        let sorted = sourceTasks.sorted {
            if ($0.parentTaskID == nil) != ($1.parentTaskID == nil) { return $0.parentTaskID == nil }
            return $0.sortOrder < $1.sortOrder
        }
        for source in sorted {
            let clone = CreatorTask(
                briefID: briefID,
                pillarID: source.pillarID,
                platformOutputID: source.platformOutputID == nil ? nil : outputID,
                parentTaskID: source.parentTaskID.flatMap { taskIDMap[$0] },
                title: source.title,
                kind: source.kind,
                lane: source.lane,
                priority: source.priority,
                notes: source.notes,
                estimatedMinutes: source.estimatedMinutes,
                targetDate: source.targetDate.flatMap { calendar.date(byAdding: .day, value: dayOffset, to: $0) },
                dailyFocusDate: source.dailyFocusDate.flatMap { calendar.date(byAdding: .day, value: dayOffset, to: $0) },
                dailyFocusTitle: source.dailyFocusTitle,
                dailyFocusTemplateEntryID: source.dailyFocusTemplateEntryID,
                sortOrder: source.sortOrder,
                isRecordingMilestoneDesignated: source.isRecordingMilestoneDesignated
            )
            taskIDMap[source.id] = clone.id
            context.insert(clone)
        }
    }
}
