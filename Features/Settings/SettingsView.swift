import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("preferredColorScheme") private var preferredScheme = "system"
    @Query private var profiles: [CreatorProfile]

    private var profile: CreatorProfile? { profiles.first }

    var body: some View {
        List {
            profileSection
            brandSection
            appearanceSection
            subscriptionSection
            aboutSection
        }
        .navigationTitle("Settings")
    }

    private var profileSection: some View {
        Section {
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(Color.brandBeige)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Text(String(profile?.displayName.prefix(1) ?? "?"))
                            .font(AppFont.title3())
                            .foregroundStyle(Color.brandBrown)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile?.displayName ?? "Creator")
                        .font(AppFont.headline())
                    Text(profile?.niche ?? "Set up your profile")
                        .font(AppFont.caption())
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.vertical, Spacing.xxs)
        }
    }

    private var brandSection: some View {
        Section("Brand") {
            NavigationLink("Content Pillars") {
                PillarsView()
            }
            NavigationLink("Brand Voice") {
                // TODO: Brand voice editor
                Text("Brand Voice Editor")
            }
            NavigationLink("Connected Platforms") {
                // TODO: Platform connections
                Text("Platform Connections")
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $preferredScheme) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
        }
    }

    private var subscriptionSection: some View {
        Section("Subscription") {
            HStack {
                Text("Current Plan")
                Spacer()
                Text("Free")
                    .foregroundStyle(Color.textSecondary)
            }
            Button("Upgrade to Pro") {
                // TODO: Show paywall
            }
            .foregroundStyle(Color.brandPink)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text("0.1.0")
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
