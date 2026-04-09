import SwiftUI

enum SocialPlatform: String, Codable, CaseIterable, Identifiable {
    case instagram
    case tiktok
    case youtube
    case pinterest
    case x
    case linkedin
    case facebook

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        case .pinterest: "Pinterest"
        case .x: "X"
        case .linkedin: "LinkedIn"
        case .facebook: "Facebook"
        }
    }

    var systemIcon: String {
        switch self {
        case .instagram: "camera"
        case .tiktok: "music.note"
        case .youtube: "play.rectangle"
        case .pinterest: "pin"
        case .x: "at"
        case .linkedin: "briefcase"
        case .facebook: "person.2"
        }
    }

    var brandColor: Color {
        switch self {
        case .instagram: Color(hex: "E4405F")
        case .tiktok: Color(hex: "000000")
        case .youtube: Color(hex: "FF0000")
        case .pinterest: Color(hex: "BD081C")
        case .x: Color(hex: "1DA1F2")
        case .linkedin: Color(hex: "0A66C2")
        case .facebook: Color(hex: "1877F2")
        }
    }
}

struct PlatformIcon: View {
    let platform: SocialPlatform
    var size: CGFloat = 24
    var showColor: Bool = true

    var body: some View {
        Image(systemName: platform.systemIcon)
            .font(.system(size: size * 0.6, weight: .medium))
            .foregroundStyle(showColor ? platform.brandColor : .secondary)
            .frame(width: size, height: size)
            .background(
                showColor
                    ? platform.brandColor.opacity(0.1)
                    : Color.secondary.opacity(0.1)
            )
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
    }
}

struct PlatformChip: View {
    let platform: SocialPlatform
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: platform.systemIcon)
                    .font(.system(size: 12))
                Text(platform.displayName)
                    .font(AppFont.caption(.medium))
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .foregroundStyle(isSelected ? .white : .secondary)
            .background(isSelected ? Color.brandBlack : Color.clear)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.clear : Color.borderLight,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        HStack {
            ForEach(SocialPlatform.allCases) { platform in
                PlatformIcon(platform: platform)
            }
        }
        HStack {
            PlatformChip(platform: .instagram, isSelected: true) {}
            PlatformChip(platform: .tiktok, isSelected: false) {}
        }
    }
}
