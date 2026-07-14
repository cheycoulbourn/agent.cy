import SwiftUI
import UIKit

struct CreatorAvatar: View {
    let profile: CreatorProfile?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(Color.agentSurface)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else if !initials.isEmpty {
                Text(initials)
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(Color.agentText)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(Color.agentText)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay { Circle().stroke(Color.agentBorder, lineWidth: 1) }
    }

    private var image: UIImage? {
        guard let data = profile?.avatarImageData else { return nil }
        return UIImage(data: data)
    }

    private var initials: String {
        guard let profile else { return "" }
        return profile.name
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

struct ProfileSettingsButton: View {
    let profile: CreatorProfile?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CreatorAvatar(profile: profile)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile and settings")
        .accessibilityHint("Opens Settings")
    }
}

struct AgentPageRail<Actions: View>: View {
    let breadcrumb: String
    let profile: CreatorProfile?
    let openSettings: () -> Void
    @ViewBuilder let actions: Actions

    init(
        breadcrumb: String,
        profile: CreatorProfile?,
        openSettings: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions
    ) {
        self.breadcrumb = breadcrumb
        self.profile = profile
        self.openSettings = openSettings
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .center, spacing: AgentSpacing.x1) {
            MetaLabel(breadcrumb)
                .frame(maxWidth: .infinity, alignment: .leading)
            actions
            ProfileSettingsButton(profile: profile, action: openSettings)
        }
        .frame(height: 44)
    }
}

extension AgentPageRail where Actions == EmptyView {
    init(
        breadcrumb: String,
        profile: CreatorProfile?,
        openSettings: @escaping () -> Void
    ) {
        self.init(
            breadcrumb: breadcrumb,
            profile: profile,
            openSettings: openSettings,
            actions: { EmptyView() }
        )
    }
}
