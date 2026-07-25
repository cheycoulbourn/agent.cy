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
