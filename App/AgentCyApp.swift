import SwiftUI
import SwiftData

@main
struct AgentCyApp: App {
    let modelContainer: ModelContainer

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("preferredColorScheme") private var preferredScheme = "system"

    init() {
        let schema = Schema([
            CreatorProfile.self,
            ContentPillar.self,
            ContentItem.self,
            Inspiration.self,
            InspirationBoard.self,
            BrandDeal.self,
            PlatformAccount.self,
            CalendarEvent.self,
        ])
        let config = ModelConfiguration(
            "AgentCy",
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier("group.app.agentcy")
        )
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                }
            }
            .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(modelContainer)
    }

    private var resolvedColorScheme: ColorScheme? {
        switch preferredScheme {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}
