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

@MainActor
enum SeriesEpisodePlanner {
    struct ConversionResult {
        let brief: CreativeBrief
        let output: PlatformOutput
    }

    static func previewDates(
        startingAt firstDate: Date,
        frequency: PostRecurrenceFrequency,
        weekdays: Set<PillarWeekday> = [],
        monthDay: Int? = nil,
        endDate: Date? = nil,
        count: Int = RecurringPostSchedule.defaultFutureOccurrenceCount,
        calendar: Calendar = .current
    ) -> [Date] {
        guard count > 0 else { return [] }
        guard frequency != .none else { return [firstDate] }
        let future = RecurringPostSchedule.futureDates(
            after: firstDate,
            frequency: frequency,
            weekdays: weekdays,
            monthDay: monthDay,
            endDate: endDate,
            calendar: calendar
        )
        return Array(([firstDate] + future).prefix(count))
    }

    static func nextEpisodeDate(
        after date: Date,
        series: ContentSeries,
        calendar: Calendar = .current
    ) -> Date {
        let frequency = series.cadence == .none ? PostRecurrenceFrequency.weekly : series.cadence
        return RecurringPostSchedule.futureDates(
            after: date,
            frequency: frequency,
            weekdays: series.cadenceWeekdays,
            monthDay: series.cadenceMonthDay,
            endDate: nil,
            includesTime: series.cadenceIncludesTime,
            calendar: calendar
        ).first
            ?? calendar.date(byAdding: .weekOfYear, value: 1, to: date)
            ?? date
    }

    @discardableResult
    static func plan(
        series: ContentSeries,
        dates: [Date],
        includesTime: Bool,
        context: ModelContext,
        calendar: Calendar = .current
    ) throws -> [SeriesEpisodeSlot] {
        let allSlots = try context.fetch(FetchDescriptor<SeriesEpisodeSlot>())
        let existing = allSlots.filter {
            $0.workspaceID == series.workspaceID && $0.seriesID == series.id
        }
        var planned: [SeriesEpisodeSlot] = []

        for date in dates {
            let normalized = RecurringPostSchedule.normalizedTargetDate(
                date,
                includesTime: includesTime,
                calendar: calendar
            )
            let duplicate = (existing + planned).contains { slot in
                if includesTime {
                    return abs(slot.plannedDate.timeIntervalSince(normalized)) < 1
                }
                return calendar.isDate(slot.plannedDate, inSameDayAs: normalized)
            }
            guard !duplicate else { continue }

            let slot = SeriesEpisodeSlot(
                workspaceID: series.workspaceID,
                seriesID: series.id,
                plannedDate: normalized,
                includesTime: includesTime
            )
            context.insert(slot)
            planned.append(slot)
        }

        series.cadenceIncludesTime = includesTime
        if series.cadenceStartDate == nil, let firstDate = dates.min() {
            series.cadenceStartDate = RecurringPostSchedule.normalizedTargetDate(
                firstDate,
                includesTime: includesTime,
                calendar: calendar
            )
        }
        series.updatedAt = Date()
        try context.save()
        return planned
    }

    @discardableResult
    static func convert(
        slot: SeriesEpisodeSlot,
        series: ContentSeries,
        context: ModelContext
    ) throws -> ConversionResult {
        try validate(slot: slot, series: series)
        if let converted = try existingConversion(for: slot, context: context) {
            return converted
        }
        try validateOpen(slot)

        let episodeNumber = try episodeNumber(for: slot, series: series, context: context)

        let brief = CreativeBrief(title: "Untitled episode", status: .spark)
        brief.workspaceID = series.workspaceID
        brief.ideaBankPlacement = .post
        brief.pillarID = series.pillarID
        brief.seriesID = series.id
        brief.episodeNumber = episodeNumber
        brief.workDate = slot.plannedDate
        brief.includesWorkTime = slot.includesTime
        brief.agendaDate = slot.plannedDate
        if let duration = series.defaultDurationSeconds {
            brief.durationSeconds = duration
        }
        context.insert(brief)

        let output = PlatformOutput(
            briefID: brief.id,
            platform: series.defaultPlatform ?? .instagramReels,
            destinationID: series.defaultDestinationID,
            formatID: series.defaultFormatID,
            socialAccountID: series.defaultSocialAccountID,
            durationSeconds: series.defaultDurationSeconds ?? brief.durationSeconds,
            status: .draft
        )
        output.workspaceID = series.workspaceID
        context.insert(output)

        for item in series.taskTemplate {
            let task = CreatorTask(
                briefID: brief.id,
                pillarID: series.pillarID,
                platformOutputID: output.id,
                title: item.title,
                kind: item.kind,
                lane: .production,
                priority: item.priority,
                notes: item.notes,
                estimatedMinutes: item.estimatedMinutes,
                targetDate: slot.plannedDate,
                includesTargetTime: slot.includesTime,
                sortOrder: item.sortOrder
            )
            task.workspaceID = series.workspaceID
            context.insert(task)
        }

        slot.convertedBriefID = brief.id
        slot.status = .converted
        try context.save()
        return ConversionResult(brief: brief, output: output)
    }

    @discardableResult
    static func convert(
        slot: SeriesEpisodeSlot,
        series: ContentSeries,
        using brief: CreativeBrief,
        output existingOutput: PlatformOutput? = nil,
        context: ModelContext
    ) throws -> ConversionResult {
        try validate(slot: slot, series: series)

        if let converted = try existingConversion(for: slot, context: context) {
            return converted
        }
        try validateOpen(slot)

        let reusableOutput = try reusableIdeaOutput(
            for: brief,
            preferred: existingOutput,
            context: context
        )

        let episodeNumber = try episodeNumber(for: slot, series: series, context: context)
        brief.workspaceID = series.workspaceID
        brief.ideaBankPlacement = .post
        brief.status = .spark
        brief.seriesID = series.id
        brief.episodeNumber = episodeNumber
        brief.episodeLabel = brief.episodeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        brief.workDate = slot.plannedDate
        brief.includesWorkTime = slot.includesTime
        brief.agendaDate = slot.plannedDate
        if brief.pillarID == nil { brief.pillarID = series.pillarID }
        if let duration = series.defaultDurationSeconds {
            brief.durationSeconds = duration
        }

        let output: PlatformOutput
        if let reusableOutput {
            output = reusableOutput
            output.workspaceID = series.workspaceID
            output.status = .draft
            output.targetDate = nil
            output.postedAt = nil
            output.publishedURLString = ""
            output.recurrence = .none
            output.seriesRootOutputID = nil
            if output.destinationID == nil { output.destinationID = series.defaultDestinationID }
            if output.formatID == nil { output.formatID = series.defaultFormatID }
            if output.socialAccountID == nil {
                output.socialAccountID = series.defaultSocialAccountID
            }
        } else {
            output = PlatformOutput(
                briefID: brief.id,
                platform: series.defaultPlatform ?? .instagramReels,
                destinationID: series.defaultDestinationID,
                formatID: series.defaultFormatID,
                socialAccountID: series.defaultSocialAccountID,
                durationSeconds: series.defaultDurationSeconds ?? brief.durationSeconds,
                status: .draft
            )
            output.workspaceID = series.workspaceID
            context.insert(output)
        }

        try instantiateTaskTemplate(
            series: series,
            slot: slot,
            brief: brief,
            output: output,
            context: context
        )
        slot.convertedBriefID = brief.id
        slot.status = .converted
        try context.save()
        return ConversionResult(brief: brief, output: output)
    }

    @discardableResult
    static func duplicatePreviousEpisode(
        into slot: SeriesEpisodeSlot,
        series: ContentSeries,
        context: ModelContext
    ) throws -> ConversionResult {
        try validate(slot: slot, series: series)

        if let converted = try existingConversion(for: slot, context: context) {
            return converted
        }
        try validateOpen(slot)

        let briefs = try context.fetch(FetchDescriptor<CreativeBrief>())
        let outputs = try context.fetch(FetchDescriptor<PlatformOutput>())
        let candidates = briefs
            .filter {
                $0.workspaceID == series.workspaceID &&
                    $0.seriesID == series.id &&
                    ($0.workDate ?? $0.agendaDate ?? $0.updatedAt) < slot.plannedDate
            }
            .sorted {
                ($0.workDate ?? $0.agendaDate ?? $0.updatedAt) >
                    ($1.workDate ?? $1.agendaDate ?? $1.updatedAt)
            }
        guard let sourceBrief = candidates.first,
              let sourceOutput = outputs.first(where: { $0.briefID == sourceBrief.id }) else {
            throw SeriesEpisodePlannerError.noPreviousEpisode
        }

        let now = Date()
        let brief = CreativeBrief(
            title: sourceBrief.title,
            premise: sourceBrief.premise,
            source: sourceBrief.source,
            status: .spark,
            createdAt: now
        )
        brief.workspaceID = series.workspaceID
        brief.ideaBankPlacement = .post
        brief.seriesID = series.id
        brief.episodeNumber = try episodeNumber(for: slot, series: series, context: context)
        brief.episodeLabel = sourceBrief.episodeLabel
        brief.pillarID = sourceBrief.pillarID ?? series.pillarID
        brief.notes = sourceBrief.notes
        brief.scriptEnabled = sourceBrief.scriptEnabled
        brief.audience = sourceBrief.audience
        brief.creativeGoal = sourceBrief.creativeGoal
        brief.takeaway = sourceBrief.takeaway
        brief.durationSeconds = sourceBrief.durationSeconds
        brief.spokenHook = sourceBrief.spokenHook
        brief.firstFrameText = sourceBrief.firstFrameText
        brief.scriptBeatsText = sourceBrief.scriptBeatsText
        brief.close = sourceBrief.close
        brief.ctaIntent = sourceBrief.ctaIntent
        brief.filmingGuidance = sourceBrief.filmingGuidance
        brief.editingGuidance = sourceBrief.editingGuidance
        brief.assumptionsText = sourceBrief.assumptionsText
        brief.voiceConfidence = sourceBrief.voiceConfidence
        brief.readyBriefPayloadJSON = sourceBrief.readyBriefPayloadJSON
        brief.workDate = slot.plannedDate
        brief.includesWorkTime = slot.includesTime
        brief.agendaDate = slot.plannedDate
        context.insert(brief)

        let output = PlatformOutput(
            briefID: brief.id,
            platform: sourceOutput.platform,
            destinationID: sourceOutput.destinationID ?? series.defaultDestinationID,
            formatID: sourceOutput.formatID ?? series.defaultFormatID,
            socialAccountID: sourceOutput.socialAccountID ?? series.defaultSocialAccountID,
            durationSeconds: sourceOutput.durationSeconds,
            status: .draft,
            createdAt: now
        )
        output.workspaceID = series.workspaceID
        output.caption = sourceOutput.caption
        output.openingAdjustment = sourceOutput.openingAdjustment
        output.titleOverride = sourceOutput.titleOverride
        output.cta = sourceOutput.cta
        output.editChanges = sourceOutput.editChanges
        output.targetDate = nil
        output.postedAt = nil
        output.publishedURLString = ""
        output.recurrence = .none
        output.seriesRootOutputID = nil
        context.insert(output)

        let sourceTasks = try context.fetch(FetchDescriptor<CreatorTask>())
            .filter { $0.briefID == sourceBrief.id && $0.parentTaskID == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
        if sourceTasks.isEmpty {
            try instantiateTaskTemplate(
                series: series,
                slot: slot,
                brief: brief,
                output: output,
                context: context
            )
        } else {
            for sourceTask in sourceTasks {
                let task = CreatorTask(
                    briefID: brief.id,
                    pillarID: brief.pillarID,
                    platformOutputID: output.id,
                    title: sourceTask.title,
                    kind: sourceTask.kind,
                    lane: .production,
                    priority: sourceTask.priority,
                    notes: sourceTask.notes,
                    estimatedMinutes: sourceTask.estimatedMinutes,
                    targetDate: slot.plannedDate,
                    includesTargetTime: slot.includesTime,
                    sortOrder: sourceTask.sortOrder
                )
                task.workspaceID = series.workspaceID
                context.insert(task)
            }
        }

        slot.convertedBriefID = brief.id
        slot.status = .converted
        try context.save()
        return ConversionResult(brief: brief, output: output)
    }

    static func skip(_ slot: SeriesEpisodeSlot, context: ModelContext) throws {
        try validateOpen(slot)
        guard slot.convertedBriefID == nil else {
            throw SeriesEpisodePlannerError.incompleteConversion
        }
        slot.convertedBriefID = nil
        slot.status = .skipped
        try context.save()
    }

    private static func validate(slot: SeriesEpisodeSlot, series: ContentSeries) throws {
        guard slot.seriesID == series.id,
              slot.workspaceID == series.workspaceID else {
            throw SeriesEpisodePlannerError.seriesMismatch
        }
    }

    private static func validateOpen(_ slot: SeriesEpisodeSlot) throws {
        guard slot.status == .open else {
            throw SeriesEpisodePlannerError.slotUnavailable
        }
    }

    private static func existingConversion(
        for slot: SeriesEpisodeSlot,
        context: ModelContext
    ) throws -> ConversionResult? {
        guard let convertedBriefID = slot.convertedBriefID else { return nil }
        let briefID = convertedBriefID
        var briefDescriptor = FetchDescriptor<CreativeBrief>(
            predicate: #Predicate { $0.id == briefID }
        )
        briefDescriptor.fetchLimit = 1
        var outputDescriptor = FetchDescriptor<PlatformOutput>(
            predicate: #Predicate { $0.briefID == briefID },
            sortBy: [SortDescriptor(\PlatformOutput.createdAt)]
        )
        outputDescriptor.fetchLimit = 2
        guard let brief = try context.fetch(briefDescriptor).first else {
            throw SeriesEpisodePlannerError.incompleteConversion
        }
        let outputs = try context.fetch(outputDescriptor)
        guard outputs.count == 1, let output = outputs.first else {
            throw SeriesEpisodePlannerError.incompleteConversion
        }
        return ConversionResult(brief: brief, output: output)
    }

    private static func reusableIdeaOutput(
        for brief: CreativeBrief,
        preferred: PlatformOutput?,
        context: ModelContext
    ) throws -> PlatformOutput? {
        if let preferred, preferred.briefID != brief.id {
            throw SeriesEpisodePlannerError.outputMismatch
        }
        let briefID = brief.id
        var descriptor = FetchDescriptor<PlatformOutput>(
            predicate: #Predicate { $0.briefID == briefID },
            sortBy: [SortDescriptor(\PlatformOutput.createdAt)]
        )
        descriptor.fetchLimit = 2
        let outputs = try context.fetch(descriptor)
        guard outputs.count <= 1 else {
            throw SeriesEpisodePlannerError.ambiguousIdeaOutputs
        }
        if let preferred {
            guard outputs.first?.id == preferred.id else {
                throw SeriesEpisodePlannerError.outputMismatch
            }
            return preferred
        }
        return outputs.first
    }

    private static func episodeNumber(
        for slot: SeriesEpisodeSlot,
        series: ContentSeries,
        context: ModelContext
    ) throws -> Int {
        let slots = try context.fetch(FetchDescriptor<SeriesEpisodeSlot>())
            .filter { $0.seriesID == series.id && $0.workspaceID == series.workspaceID }
            .sorted {
                if $0.plannedDate != $1.plannedDate { return $0.plannedDate < $1.plannedDate }
                return $0.createdAt < $1.createdAt
            }
        let slotOrdinal = (slots.firstIndex(where: { $0.id == slot.id }) ?? 0) + 1
        let existingEpisodeNumbers = try context.fetch(FetchDescriptor<CreativeBrief>())
            .filter {
                $0.workspaceID == series.workspaceID &&
                    $0.seriesID == series.id &&
                    $0.id != slot.convertedBriefID
            }
            .compactMap(\.episodeNumber)
        let nextAfterExisting = (existingEpisodeNumbers.max() ?? 0) + 1
        return max(slotOrdinal, nextAfterExisting)
    }

    private static func instantiateTaskTemplate(
        series: ContentSeries,
        slot: SeriesEpisodeSlot,
        brief: CreativeBrief,
        output: PlatformOutput,
        context: ModelContext
    ) throws {
        let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
        guard !tasks.contains(where: { $0.briefID == brief.id }) else { return }

        for item in series.taskTemplate {
            let task = CreatorTask(
                briefID: brief.id,
                pillarID: brief.pillarID,
                platformOutputID: output.id,
                title: item.title,
                kind: item.kind,
                lane: .production,
                priority: item.priority,
                notes: item.notes,
                estimatedMinutes: item.estimatedMinutes,
                targetDate: slot.plannedDate,
                includesTargetTime: slot.includesTime,
                sortOrder: item.sortOrder
            )
            task.workspaceID = series.workspaceID
            context.insert(task)
        }
    }
}

enum SeriesEpisodePlannerError: Error {
    case seriesMismatch
    case noPreviousEpisode
    case slotUnavailable
    case incompleteConversion
    case outputMismatch
    case ambiguousIdeaOutputs
}

@MainActor
enum SeriesMigrationService {
    struct Result: Equatable {
        var createdSeriesCount = 0
        var convertedSlotCount = 0
        var preservedLegacyPostCount = 0
    }

    @discardableResult
    static func run(context: ModelContext) throws -> Result {
        let briefs = try context.fetch(FetchDescriptor<CreativeBrief>())
        let outputs = try context.fetch(FetchDescriptor<PlatformOutput>())
        let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
        let attachments = try context.fetch(FetchDescriptor<CreatorAttachment>())
        var seriesRecords = try context.fetch(FetchDescriptor<ContentSeries>())
        var result = Result()

        let briefByID = DuplicateSafeIndex.firstValues(briefs.map { ($0.id, $0) })
        let outputByID = DuplicateSafeIndex.firstValues(outputs.map { ($0.id, $0) })
        let tasksByBriefID = Dictionary(grouping: tasks.compactMap { task in
            task.briefID.map { ($0, task) }
        }, by: \.0).mapValues { $0.map(\.1) }
        let attachmentBriefIDs = Set(attachments.map(\.briefID))

        func normalizedName(_ raw: String) -> String {
            raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func findOrCreateSeries(
            named name: String,
            output: PlatformOutput,
            brief: CreativeBrief
        ) -> ContentSeries {
            // Capturing the @Model itself makes this closure main-actor
            // isolated under Release whole-module checking; the plain value
            // keeps the lookup nonisolated.
            let briefWorkspaceID = brief.workspaceID
            if let existing = seriesRecords.first(where: {
                $0.workspaceID == briefWorkspaceID &&
                    $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                return existing
            }

            let series = ContentSeries(
                workspaceID: brief.workspaceID,
                name: name,
                pillarID: brief.pillarID,
                platform: output.platform,
                destinationID: output.destinationID,
                formatID: output.formatID,
                socialAccountID: output.socialAccountID,
                durationSeconds: output.durationSeconds,
                createdAt: min(brief.createdAt, output.createdAt)
            )
            series.cadence = output.recurrence
            series.cadenceStartDate = output.targetDate ?? brief.workDate ?? brief.agendaDate
            series.cadenceWeekdays = output.recurrenceWeekdays
            series.cadenceMonthDay = output.recurrenceMonthDay
            series.cadenceEndDate = output.recurrenceEndDate
            series.cadenceIncludesTime = output.includesTargetTime
            context.insert(series)
            seriesRecords.append(series)
            result.createdSeriesCount += 1
            return series
        }

        // First establish stable account-scoped series membership for every
        // named legacy series. This is non-destructive and idempotent.
        for output in outputs {
            guard let brief = briefByID[output.briefID] else { continue }
            let name = normalizedName(output.seriesName)
            guard !name.isEmpty else { continue }
            let series = findOrCreateSeries(named: name, output: output, brief: brief)
            if brief.seriesID == nil { brief.seriesID = series.id }
        }

        let legacyClones = outputs.filter { $0.seriesRootOutputID != nil }
        for cloneOutput in legacyClones {
            guard let rootID = cloneOutput.seriesRootOutputID,
                  let rootOutput = outputByID[rootID],
                  let rootBrief = briefByID[rootOutput.briefID],
                  let cloneBrief = briefByID[cloneOutput.briefID],
                  let targetDate = cloneOutput.targetDate
            else {
                result.preservedLegacyPostCount += 1
                continue
            }

            let name = normalizedName(
                cloneOutput.seriesName.isEmpty ? rootOutput.seriesName : cloneOutput.seriesName
            )
            guard !name.isEmpty,
                  isUntouchedGeneratedClone(
                    rootBrief: rootBrief,
                    rootOutput: rootOutput,
                    rootTasks: tasksByBriefID[rootBrief.id] ?? [],
                    cloneBrief: cloneBrief,
                    cloneOutput: cloneOutput,
                    cloneTasks: tasksByBriefID[cloneBrief.id] ?? [],
                    hasAttachment: attachmentBriefIDs.contains(cloneBrief.id)
                  )
            else {
                result.preservedLegacyPostCount += 1
                continue
            }

            let series = findOrCreateSeries(named: name, output: rootOutput, brief: rootBrief)
            rootBrief.seriesID = series.id
            let existingSlots = try context.fetch(FetchDescriptor<SeriesEpisodeSlot>())
            let alreadyPlanned = existingSlots.contains {
                $0.workspaceID == series.workspaceID &&
                    $0.seriesID == series.id &&
                    abs($0.plannedDate.timeIntervalSince(targetDate)) < 1
            }
            if !alreadyPlanned {
                context.insert(SeriesEpisodeSlot(
                    workspaceID: series.workspaceID,
                    seriesID: series.id,
                    plannedDate: targetDate,
                    includesTime: cloneOutput.includesTargetTime
                ))
                result.convertedSlotCount += 1
            }

            for task in tasksByBriefID[cloneBrief.id] ?? [] { context.delete(task) }
            context.delete(cloneOutput)
            context.delete(cloneBrief)
        }

        try context.save()
        return result
    }

    private static func isUntouchedGeneratedClone(
        rootBrief: CreativeBrief,
        rootOutput: PlatformOutput,
        rootTasks: [CreatorTask],
        cloneBrief: CreativeBrief,
        cloneOutput: PlatformOutput,
        cloneTasks: [CreatorTask],
        hasAttachment: Bool
    ) -> Bool {
        guard !hasAttachment,
              cloneOutput.status != .posted,
              cloneOutput.postedAt == nil,
              cloneOutput.publishedURLString.isEmpty,
              cloneBrief.resolvedCustomStatusLabel == nil,
              !cloneBrief.isBrandCollaboration,
              cloneBrief.brandPartnerID == nil,
              !cloneBrief.moodBoardEnabled,
              cloneBrief.archivedAt == nil,
              cloneBrief.title == rootBrief.title,
              cloneBrief.premise == rootBrief.premise,
              cloneBrief.notes == rootBrief.notes,
              cloneBrief.scriptEnabled == rootBrief.scriptEnabled,
              cloneBrief.audience == rootBrief.audience,
              cloneBrief.creativeGoal == rootBrief.creativeGoal,
              cloneBrief.takeaway == rootBrief.takeaway,
              cloneBrief.durationSeconds == rootBrief.durationSeconds,
              cloneBrief.spokenHook == rootBrief.spokenHook,
              cloneBrief.firstFrameText == rootBrief.firstFrameText,
              cloneBrief.scriptBeatsText == rootBrief.scriptBeatsText,
              cloneBrief.close == rootBrief.close,
              cloneBrief.ctaIntent == rootBrief.ctaIntent,
              cloneBrief.filmingGuidance == rootBrief.filmingGuidance,
              cloneBrief.editingGuidance == rootBrief.editingGuidance,
              cloneBrief.assumptionsText == rootBrief.assumptionsText,
              cloneBrief.pillarID == rootBrief.pillarID,
              cloneOutput.platform == rootOutput.platform,
              cloneOutput.destinationID == rootOutput.destinationID,
              cloneOutput.formatID == rootOutput.formatID,
              cloneOutput.socialAccountID == rootOutput.socialAccountID,
              cloneOutput.durationSeconds == rootOutput.durationSeconds,
              cloneOutput.caption == rootOutput.caption,
              cloneOutput.openingAdjustment == rootOutput.openingAdjustment,
              cloneOutput.titleOverride == rootOutput.titleOverride,
              cloneOutput.cta == rootOutput.cta,
              cloneOutput.editChanges == rootOutput.editChanges
        else { return false }

        guard rootTasks.count == cloneTasks.count,
              cloneTasks.allSatisfy({
                  !$0.isCompleted &&
                      !$0.isSkipped &&
                      !$0.isFocusTemplateCustomized &&
                      $0.recurrence == .none
              })
        else { return false }

        func signatures(_ source: [CreatorTask]) -> [String] {
            source.map {
                [
                    $0.parentTaskID == nil ? "root" : "child",
                    $0.title,
                    $0.notes,
                    $0.kindRaw,
                    $0.laneRaw,
                    $0.priorityRaw,
                    $0.estimatedMinutes.map(String.init) ?? "",
                    String($0.sortOrder),
                    $0.isRecordingMilestoneDesignated ? "recording" : ""
                ].joined(separator: "\u{1F}")
            }.sorted()
        }
        return signatures(rootTasks) == signatures(cloneTasks)
    }
}

enum PostDeletionScope: Equatable, Sendable {
    case thisPost
    case thisAndFuture
}

enum PostSeriesDeletionPolicy {
    static func seriesRootID(for output: PlatformOutput) -> UUID? {
        if let rootID = output.seriesRootOutputID { return rootID }
        return output.recurrence == .none ? nil : output.id
    }

    static func outputsToDelete(
        selected: PlatformOutput,
        from outputs: [PlatformOutput],
        scope: PostDeletionScope
    ) -> [PlatformOutput] {
        guard scope == .thisAndFuture,
              let rootID = seriesRootID(for: selected)
        else { return [selected] }

        return outputs.filter { candidate in
            if candidate.id == selected.id { return true }
            guard candidate.status != .posted,
                  seriesRootID(for: candidate) == rootID
            else { return false }

            guard let selectedDate = selected.targetDate else { return true }
            guard let candidateDate = candidate.targetDate else { return false }
            return candidateDate >= selectedDate
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
              task.focusTaskTemplateID == nil,
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
            includesTargetTime: task.includesTargetTime,
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
                includesTargetTime: subtask.includesTargetTime,
                dailyFocusDate: next.dailyFocusDate,
                dailyFocusTitle: next.dailyFocusTitle,
                dailyFocusTemplateEntryID: next.dailyFocusTemplateEntryID,
                sortOrder: subtask.sortOrder
            ))
        }
        return next
    }
}
