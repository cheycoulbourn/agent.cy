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

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            HStack(alignment: .top, spacing: AgentSpacing.x3) {
                HStack(spacing: AgentSpacing.x2) {
                    Circle()
                        .fill(accent)
                        .frame(width: 7, height: 7)
                    Text(pillar.uppercased())
                        .font(.agentMono)
                        .tracking(0.7)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(statusTitle)
                    .font(.agentMono)
                    .tracking(0.6)
                    .padding(.horizontal, AgentSpacing.x2)
                    .frame(minHeight: 24)
                    .background(status == .posted ? Color.actionAccent : Color.clear, in: .rect(cornerRadius: 6))
                    .foregroundStyle(status == .posted ? Color.onAccent : Color.agentText)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(status == .posted ? Color.clear : Color.agentText.opacity(0.20), lineWidth: 1)
                    )
            }

            Text(title)
                .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                .tracking(-0.17)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x3) {
                Text(metadata.uppercased())
                    .font(.agentMono)
                    .tracking(0.7)
                    .lineLimit(2)
                Spacer(minLength: AgentSpacing.x3)
                if let timeText {
                    Text(timeText)
                        .font(.agentMono)
                        .fixedSize()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .foregroundStyle(Color.agentText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AgentSpacing.x4)
        .padding(.vertical, AgentSpacing.x4)
        .background(cardBackground, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    private var cardBackground: Color {
        if status == .draft { return .agentSurface }
        return accent.opacity(colorScheme == .dark ? 0.24 : 0.10)
    }

    private var cardBorder: Color {
        if status == .draft { return Color.agentText.opacity(0.28) }
        return accent.opacity(colorScheme == .dark ? 0.82 : 0.68)
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
}
