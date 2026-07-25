import SwiftUI
import UIKit

struct CreatorAvatar: View {
    let identity: ActiveCreatorIdentity
    var size: CGFloat = 44

    init(identity: ActiveCreatorIdentity, size: CGFloat = 44) {
        self.identity = identity
        self.size = size
    }

    init(profile: CreatorProfile?, size: CGFloat = 44) {
        self.init(
            identity: ActiveCreatorIdentity(
                name: profile?.name ?? "",
                avatarImageData: profile?.avatarImageData
            ),
            size: size
        )
    }

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
                    .font(.agentInter(size: size * 0.34, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Color.agentText)
            } else {
                AgentIconView(.profile, size: size * 0.42)
                    .foregroundStyle(Color.agentText)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay { Circle().stroke(Color.agentBorder, lineWidth: 1) }
    }

    private var image: UIImage? {
        guard let data = identity.avatarImageData else { return nil }
        return UIImage(data: data)
    }

    private var initials: String {
        identity.name
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

struct ProfileSettingsButton: View {
    let identity: ActiveCreatorIdentity
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CreatorAvatar(identity: identity)
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
    let identity: ActiveCreatorIdentity
    let openSettings: () -> Void
    @ViewBuilder let actions: Actions

    init(
        breadcrumb: String,
        identity: ActiveCreatorIdentity,
        openSettings: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions
    ) {
        self.breadcrumb = breadcrumb
        self.identity = identity
        self.openSettings = openSettings
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .center, spacing: AgentSpacing.x1) {
            MetaLabel(breadcrumb)
                .frame(maxWidth: .infinity, alignment: .leading)
            actions
            ProfileSettingsButton(identity: identity, action: openSettings)
        }
        .frame(height: 44)
    }
}

extension AgentPageRail where Actions == EmptyView {
    init(
        breadcrumb: String,
        identity: ActiveCreatorIdentity,
        openSettings: @escaping () -> Void
    ) {
        self.init(
            breadcrumb: breadcrumb,
            identity: identity,
            openSettings: openSettings,
            actions: { EmptyView() }
        )
    }
}
