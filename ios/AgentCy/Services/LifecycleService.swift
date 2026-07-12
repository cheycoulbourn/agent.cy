import Foundation

enum BriefLifecycle {
    static func beginDevelopment(_ brief: CreativeBrief, now: Date = Date()) {
        guard brief.status == .spark else { return }
        transition(brief, to: .developing, now: now)
    }

    static func approve(_ brief: CreativeBrief, now: Date = Date()) {
        guard brief.status != .archived else { return }
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
        guard output.briefID == brief.id, canExecute(brief) else { return false }
        if output.status == .posted {
            output.status = output.targetDate == nil ? .ready : .scheduled
            output.postedAt = nil
        } else {
            output.status = .posted
            output.postedAt = now
        }
        return true
    }

    @discardableResult
    static func schedule(_ output: PlatformOutput, for date: Date?, brief: CreativeBrief) -> Bool {
        guard output.briefID == brief.id, canExecute(brief) else { return false }
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
}

enum AccessPolicy {
    static func allows(_ action: AccessAction, state: SubscriptionState?) -> Bool {
        guard let state else { return false }
        if state.access == .expired {
            switch action {
            case .editExisting, .updatePosting, .export, .erase: return true
            default: return false
            }
        } else if state.access == .freeJourney, state.freeBriefConsumed {
            switch action {
            case .extractVoiceProfile: return true
            case .revise: return state.revisionRequestsUsed < 3
            case .teachCy: return state.teachCyUpdatesUsed < 1
            case .editExisting, .updatePosting, .export, .erase: return true
            default: return false
            }
        } else if state.access == .freeJourney {
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
}
