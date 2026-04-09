import SwiftUI

struct StatusBadge: View {
    let status: ContentStatus

    var body: some View {
        Text(status.displayName)
            .font(AppFont.caption(.medium))
            .foregroundStyle(status.color)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxxs)
            .background(status.color.opacity(0.1))
            .clipShape(Capsule())
    }
}

enum ContentStatus: String, Codable, CaseIterable {
    case captured
    case developing
    case drafted
    case planned
    case scheduled
    case published
    case archived

    var displayName: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .captured: .brandBrown
        case .developing: .brandPink
        case .drafted: .textTertiary
        case .planned: .blue
        case .scheduled: .orange
        case .published: .success
        case .archived: .textTertiary
        }
    }

    var icon: String {
        switch self {
        case .captured: "lightbulb"
        case .developing: "sparkles"
        case .drafted: "doc.text"
        case .planned: "calendar.badge.clock"
        case .scheduled: "clock"
        case .published: "checkmark.circle"
        case .archived: "archivebox"
        }
    }
}

#Preview {
    HStack(spacing: Spacing.xs) {
        ForEach(ContentStatus.allCases, id: \.self) { status in
            StatusBadge(status: status)
        }
    }
}
