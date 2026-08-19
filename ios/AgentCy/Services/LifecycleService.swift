import Foundation

enum BriefLifecycle {
    static func beginDevelopment(_ brief: CreativeBrief, now: Date = Date()) {
        guard brief.status == .spark else { return }
        transition(brief, to: .developing, now: now)
    }

    static func approve(_ brief: CreativeBrief, now: Date = Date()) {
        guard brief.status != .archived else { return }
        brief.ideaBankPlacement = .post
        transition(brief, to: .ready, now: now)
    }

    static func synchronize(_ brief: CreativeBrief, outputs: [PlatformOutput], now: Date = Date()) {
        guard brief.status != .archived, brief.status != .spark, brief.status != .developing else { return }
        let nextStatus: BriefStatus?
        if outputs.contains(where: { $0.status == .posted }) {
            nextStatus = .posted
        } else if outputs.contains(where: { $0.targetDate != nil }) {
            nextStatus = .scheduled
        } else if brief.status == .scheduled || brief.status == .posted {
            nextStatus = .ready
        } else {
            nextStatus = nil
        }
        if let nextStatus { transition(brief, to: nextStatus, now: now) }
    }

    @discardableResult
    static func togglePosted(_ output: PlatformOutput, brief: CreativeBrief, now: Date = Date()) -> Bool {
        togglePosted(output, brief: brief, postedAt: now, currentDate: Date())
    }

    @discardableResult
    static func togglePosted(
        _ output: PlatformOutput,
        brief: CreativeBrief,
        postedAt: Date,
        currentDate: Date = Date()
    ) -> Bool {
        guard output.briefID == brief.id, canExecute(brief) else { return false }
        brief.ideaBankPlacement = .post
        if output.status == .posted {
            output.status = output.targetDate == nil ? .ready : .scheduled
            output.postedAt = nil
        } else {
            guard PostedDatePolicy.isValid(postedAt, now: currentDate) else { return false }
            output.status = .posted
            output.postedAt = postedAt
        }
        return true
    }

    @discardableResult
    static func schedule(_ output: PlatformOutput, for date: Date?, brief: CreativeBrief) -> Bool {
        guard output.briefID == brief.id, canExecute(brief) else { return false }
        brief.ideaBankPlacement = .post
        output.targetDate = date
        if output.status != .posted {
            output.status = date == nil ? .ready : .scheduled
        }
        return true
    }

    static func archive(_ brief: CreativeBrief, now: Date = Date()) {
        guard brief.status != .archived else { return }
        transition(brief, to: .archived, now: now)
        brief.archivedAt = now
    }

    @discardableResult
    static func toggleTask(_ task: CreatorTask, brief: CreativeBrief? = nil, now: Date = Date()) -> Bool {
        if let briefID = task.briefID {
            guard let brief, brief.id == briefID, brief.status != .archived else { return false }
        }
        task.isCompleted.toggle()
        task.completedAt = task.isCompleted ? now : nil
        let shouldEmit = task.isCompleted && task.kind == .filming && task.briefID != nil && task.isRecordingMilestoneDesignated && !task.recordingMilestoneEmitted
        if shouldEmit { task.recordingMilestoneEmitted = true }
        return shouldEmit
    }

    private static func canExecute(_ brief: CreativeBrief) -> Bool {
        brief.status == .ready || brief.status == .scheduled || brief.status == .posted
    }

    static func canPlan(_ brief: CreativeBrief) -> Bool {
        canExecute(brief)
    }

    private static func transition(_ brief: CreativeBrief, to status: BriefStatus, now: Date) {
        guard brief.status != status else { return }
        brief.status = status
        brief.updatedAt = now
        brief.appendLifecycleStatus(status, at: now)
    }
}

enum PillarUsageSchedulePolicy {
    struct SummaryItem: Equatable {
        let pillarID: UUID
        let scheduledPostCount: Int
        let percentage: Int
    }

    static func weekInterval(
        containing date: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        let day = calendar.startOfDay(for: date)
        let mondayOffset = (calendar.component(.weekday, from: day) + 5) % 7
        let start = calendar.date(byAdding: .day, value: -mondayOffset, to: day) ?? day
        let end = calendar.date(byAdding: .day, value: 7, to: start)
            ?? start.addingTimeInterval(7 * 24 * 60 * 60)
        return DateInterval(start: start, end: end)
    }

    static func scheduledBriefCountsByPillar(
        briefs: [CreativeBrief],
        outputs: [PlatformOutput],
        interval: DateInterval
    ) -> [UUID: Int] {
        var pillarByBriefID: [UUID: UUID] = [:]
        for brief in briefs where brief.status != .archived {
            guard let pillarID = brief.pillarID, pillarByBriefID[brief.id] == nil else { continue }
            pillarByBriefID[brief.id] = pillarID
        }

        let scheduledBriefIDs = Set(outputs.compactMap { output -> UUID? in
            guard output.status == .scheduled || output.status == .posted,
                  let targetDate = output.targetDate,
                  targetDate >= interval.start,
                  targetDate < interval.end,
                  pillarByBriefID[output.briefID] != nil else { return nil }
            return output.briefID
        })

        return scheduledBriefIDs.reduce(into: [UUID: Int]()) { counts, briefID in
            guard let pillarID = pillarByBriefID[briefID] else { return }
            counts[pillarID, default: 0] += 1
        }
    }

    static func summary(
        pillars: [Pillar],
        briefs: [CreativeBrief],
        outputs: [PlatformOutput],
        interval: DateInterval
    ) -> [SummaryItem] {
        let activePillars = DuplicateSafeIndex
            .firstValues(pillars.filter { !$0.isArchived }.map { ($0.id, $0) })
            .values
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        guard let anchor = activePillars.first(where: { $0.parentPillarID == nil && $0.role == .anchor })
                ?? activePillars.first(where: { $0.parentPillarID == nil })
                ?? activePillars.first else { return [] }

        let otherPillars = activePillars.filter { $0.id != anchor.id }
        let orderedPillars = [anchor] + otherPillars
        let counts = scheduledBriefCountsByPillar(
            briefs: briefs,
            outputs: outputs,
            interval: interval
        )
        let weights = orderedPillars.map { counts[$0.id] ?? 0 }
        guard weights.contains(where: { $0 > 0 }) else { return [] }
        let percentages = percentages(weights: weights)

        return orderedPillars.enumerated().map { index, pillar in
            SummaryItem(
                pillarID: pillar.id,
                scheduledPostCount: weights[index],
                percentage: percentages[index]
            )
        }
    }

    static func percentages(weights: [Int]) -> [Int] {
        let normalized = weights.map { max(0, $0) }
        let total = normalized.reduce(0, +)
        guard total > 0 else { return Array(repeating: 0, count: normalized.count) }

        let exact = normalized.map { (Double($0) / Double(total)) * 100 }
        var percentages = exact.map { Int(floor($0)) }
        let remaining = 100 - percentages.reduce(0, +)
        let rankedIndices = exact.indices.sorted { lhs, rhs in
            let leftRemainder = exact[lhs] - floor(exact[lhs])
            let rightRemainder = exact[rhs] - floor(exact[rhs])
            if leftRemainder != rightRemainder { return leftRemainder > rightRemainder }
            return lhs < rhs
        }
        for index in rankedIndices.prefix(remaining) {
            percentages[index] += 1
        }
        return percentages
    }
}

enum PostedDatePolicy {
    static func isValid(_ postedAt: Date, now: Date = Date()) -> Bool {
        postedAt <= now
    }

    static func needsActualDateConfirmation(scheduledDate: Date?, now: Date = Date()) -> Bool {
        guard let scheduledDate else { return true }
        return scheduledDate > now
    }
}

enum AccessAction: Sendable {
    case createSpark
    case createTask
    case schedule
    case sparkDialogue
    case askCy
    case ideate
    case compose
    case extractVoiceProfile
    case revise
    case teachCy
    case editExisting
    case updatePosting
    case export
    case erase

    var isCyGeneration: Bool {
        switch self {
        case .sparkDialogue, .askCy, .ideate, .compose, .extractVoiceProfile, .revise, .teachCy:
            true
        default:
            false
        }
    }
}

enum AccessPolicy {
    static func allows(
        _ action: AccessAction,
        state: SubscriptionState?,
        at now: Date = Date()
    ) -> Bool {
        guard let state else { return false }
        let access = effectiveAccess(for: state, at: now)
        if access == .expired {
            switch action {
            case .editExisting, .updatePosting, .export, .erase: return true
            default: return false
            }
        } else if access == .freeJourney, state.freeBriefConsumed {
            switch action {
            case .createSpark, .createTask, .schedule: return true
            case .extractVoiceProfile: return true
            case .revise: return state.revisionRequestsUsed < 3
            case .teachCy: return state.teachCyUpdatesUsed < 1
            case .editExisting, .updatePosting, .export, .erase: return true
            default: return false
            }
        } else if access == .freeJourney {
            switch action {
            case .ideate: return state.ideationRequestsUsed < 3
            case .sparkDialogue: return true
            case .askCy: return false
            case .compose: return !state.freeBriefConsumed
            case .revise: return state.revisionRequestsUsed < 3
            case .teachCy: return state.teachCyUpdatesUsed < 1
            default: return true
            }
        } else {
            return true
        }
    }

    static func effectiveAccess(
        for state: SubscriptionState,
        at now: Date = Date()
    ) -> SubscriptionAccess {
        switch state.access {
        case .comped:
            guard let end = state.trialEnd else { return .comped }
            return end > now ? .comped : .expired
        case .trial:
            guard let end = state.trialEnd else { return .expired }
            return end > now ? .trial : .expired
        default:
            return state.access
        }
    }
}
