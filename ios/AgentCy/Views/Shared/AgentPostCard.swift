import SwiftUI

struct AgentPostCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let pillar: String
    let accent: Color
    let status: PlatformOutputStatus
    let metadata: String
    let timeText: String?
    var statusTextOverride: String? = nil
    var destination: AnyView? = nil
    var footerActionTitle: String? = nil
    var footerAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            if let destination {
                NavigationLink {
                    destination
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }

            if let footerActionTitle, let footerAction {
                AgentInlinePostAction(
                    title: footerActionTitle,
                    isAlert: isAlertStatus,
                    action: footerAction
                )
            }
        }
        .foregroundStyle(Color.agentText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AgentSpacing.x4)
        .padding(.vertical, AgentSpacing.x4)
        .background(cardBackground, in: .rect(cornerRadius: AgentRadius.card))
        .agentSurfaceChrome(cornerRadius: AgentRadius.card, borderColor: cardBorder)
        .agentHoverRow(cornerRadius: AgentRadius.card)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            HStack(alignment: .top, spacing: AgentSpacing.x3) {
                HStack(spacing: AgentSpacing.x2) {
                    PillarColorMark(color: accent, diameter: 7)
                    Text(pillar.uppercased())
                        .font(.agentMetadata)
                        .tracking(0.7)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(statusTitle)
                    .font(.agentMetadata)
                    .tracking(0.6)
                    .padding(.horizontal, AgentSpacing.x2)
                    .frame(minHeight: 24)
                    .background(statusBadgeBackground, in: .rect(cornerRadius: 6))
                    .foregroundStyle(statusBadgeForeground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(statusBadgeBorder, lineWidth: 1)
                    )
            }

            Text(title)
                .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                .tracking(-0.17)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x3) {
                Text(metadata.uppercased())
                    .font(.agentMetadata)
                    .tracking(0.7)
                    .lineLimit(2)
                Spacer(minLength: AgentSpacing.x3)
                if let timeText {
                    Text(timeText)
                        .font(.agentMetadata)
                        .fixedSize()
                }
                AgentIconView(.forward, size: 13)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var cardBackground: Color {
        if status == .draft { return .agentSurface }
        return accent.opacity(colorScheme == .dark ? 0.30 : 0.16)
    }

    private var cardBorder: Color {
        if status == .draft { return Color.agentText.opacity(0.28) }
        return PillarVisualContrast.cardBorderColor(for: accent, colorScheme: colorScheme)
    }

    private var statusTitle: String {
        if let statusTextOverride { return statusTextOverride.uppercased() }
        return switch status {
        case .draft: "DRAFT"
        case .ready: "READY"
        case .scheduled: "SCHEDULED"
        case .posted: "POSTED"
        }
    }

    private var isAlertStatus: Bool {
        statusTextOverride?.caseInsensitiveCompare("Missed") == .orderedSame
    }

    private var statusBadgeBackground: Color {
        if isAlertStatus { return .agentDestructive }
        return status == .posted ? .actionAccent : .clear
    }

    private var statusBadgeForeground: Color {
        if isAlertStatus { return .onCyAccent }
        return status == .posted ? .onAccent : .agentText
    }

    private var statusBadgeBorder: Color {
        if isAlertStatus || status == .posted { return .clear }
        return Color.agentText.opacity(0.20)
    }
}

struct AgentInlinePostAction: View {
    let title: String
    var isAlert = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.paperInter(size: 12, weight: .medium, relativeTo: .caption))
                .foregroundStyle(isAlert ? Color.agentDestructive : Color.agentText)
                .underline(pattern: .solid)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Choose a new posting date and time")
    }
}
