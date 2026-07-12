import SwiftData
import SwiftUI

struct RootView: View {
    @Query private var profiles: [CreatorProfile]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasProfile: Bool {
        !profiles.isEmpty
    }

    var body: some View {
        Group {
            if hasProfile {
                AppShellView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: hasProfile)
        .agentScreen()
    }
}

#Preview("Onboarding") {
    RootView()
        .environment(AppModel(reminderService: PreviewReminderService()))
        .modelContainer(ModelContainerFactory.make(isStoredInMemoryOnly: true))
}
