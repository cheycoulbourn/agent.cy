import SwiftUI

enum CreatorPostCopyField: String, CaseIterable, Identifiable {
    case hook
    case script
    case caption
    case callToAction

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hook: "Hook"
        case .script: "Script"
        case .caption: "Caption"
        case .callToAction: "Call to action"
        }
    }

    var editorTitle: String {
        self == .script ? "Script (optional)" : title
    }

    var minimumEditorHeight: CGFloat {
        switch self {
        case .script: 128
        case .caption: 112
        default: 72
        }
    }

    func value(brief: CreativeBrief, output: PlatformOutput) -> String {
        switch self {
        case .hook: brief.spokenHook
        case .script: brief.scriptBeatsText
        case .caption: output.caption
        case .callToAction: output.cta.isEmpty ? brief.ctaIntent : output.cta
        }
    }
}

enum PostDraftResumePolicy {
    static func shouldResume(briefStatus: BriefStatus) -> Bool {
        briefStatus == .spark || briefStatus == .developing
    }

    static func shouldResume(
        briefStatus: BriefStatus,
        outputStatus: PlatformOutputStatus
    ) -> Bool {
        if outputStatus == .posted { return false }
        return outputStatus == .draft || shouldResume(briefStatus: briefStatus)
    }

    static func outputStatus(briefStatus: BriefStatus, current: PlatformOutputStatus) -> PlatformOutputStatus {
        shouldResume(briefStatus: briefStatus, outputStatus: current) ? .draft : current
    }
}

enum PostBottomAction: Equatable {
    case schedule
    case markPosted
    case markPostedAndReschedule
    case markNotPosted
}

enum PostBottomActionPolicy {
    static func action(
        outputStatus: PlatformOutputStatus,
        scheduledDate: Date?,
        includesScheduledTime: Bool,
        hasPersistedScheduledDate: Bool = true,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PostBottomAction {
        if outputStatus == .posted { return .markNotPosted }
        guard hasPersistedScheduledDate, let scheduledDate else { return .schedule }

        let hasPassed: Bool
        if includesScheduledTime {
            hasPassed = scheduledDate < now
        } else {
            hasPassed = calendar.startOfDay(for: scheduledDate) < calendar.startOfDay(for: now)
        }

        return hasPassed ? .markPostedAndReschedule : .markPosted
    }
}

enum PostScheduleActionPresentation {
    static func title(
        suggestedDate: Date?,
        hasPersistedScheduledDate: Bool,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        guard !hasPersistedScheduledDate, let suggestedDate else { return "Schedule post" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE, MMM d"
        return "Schedule for \(formatter.string(from: suggestedDate))"
    }

    static func shouldScheduleImmediately(
        suggestedDate: Date?,
        hasPersistedScheduledDate: Bool
    ) -> Bool {
        suggestedDate != nil && !hasPersistedScheduledDate
    }
}

enum PostDraftDeletionPolicy {
    static func canDelete(
        briefStatus: BriefStatus,
        outputStatuses: [PlatformOutputStatus]
    ) -> Bool {
        guard briefStatus != .posted, briefStatus != .archived else { return false }

        if outputStatuses.isEmpty {
            return briefStatus == .spark || briefStatus == .developing
        }

        return outputStatuses.contains(.draft) && !outputStatuses.contains(.posted)
    }
}

struct BriefDisclosureLabel: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title).font(.agentHeadline).foregroundStyle(Color.agentText)
            Spacer()
            Text(detail).font(.agentMetadata).foregroundStyle(Color.agentSecondary)
        }
        .frame(minHeight: 44)
    }
}

struct BriefField: View {
    let label: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    private var visiblePlaceholder: String {
        label.localizedCaseInsensitiveContains("note") ? "" : label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            AgentInputHeader(title: label, isEditing: isFocused) { isFocused = false }
            TextField(visiblePlaceholder, text: $text, axis: .vertical)
                .font(.agentBody)
                .lineLimit(2...8)
                .padding(AgentSpacing.x4)
                .background(Color.agentSurface)
                .clipShape(.rect(cornerRadius: AgentRadius.control))
                .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).strokeBorder(Color.agentBorder, lineWidth: 1))
                .focused($isFocused)
        }
    }
}
