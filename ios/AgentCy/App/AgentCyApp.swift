import SwiftUI
import SwiftData

@main
struct AgentCyApp: App {
    private let container: ModelContainer
    @State private var appModel: AppModel

    init() {
        #if DEBUG
        let usesPreviewData = ProcessInfo.processInfo.arguments.contains("-agentCyPreviewData")
        #else
        let usesPreviewData = false
        #endif
        container = usesPreviewData
            ? ModelContainerFactory.make(isStoredInMemoryOnly: true)
            : ModelContainerFactory.make()
        if usesPreviewData {
            PreviewData.seed(container.mainContext)
        }
        let credentialStore = DeviceOnlyKeychainCredentialStore.shared
        let liveAI = APIConfiguration.useLiveAI
        let creativeService: any CreativeServicing
        let subscriptionService = SubscriptionServiceFactory.runtime(useLiveAI: liveAI)
        if liveAI {
            creativeService = RemoteCreativeService(
                client: AgentCyAPIClient(baseURL: APIConfiguration.baseURL, store: credentialStore)
            )
        } else {
            creativeService = PreviewCreativeService()
        }
        _appModel = State(
            initialValue: AppModel(
                creativeService: creativeService,
                subscriptionService: subscriptionService,
                credentialStore: credentialStore,
                installationRedemptionClient: InstallationRedemptionClient(baseURL: APIConfiguration.baseURL, store: credentialStore),
                privacyDeletionService: PrivacyDeletionClient(baseURL: APIConfiguration.baseURL),
                requiresInstallationInvite: liveAI,
                allowsOfflinePrivacyErase: !liveAI
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .modelContainer(container)
                .tint(.actionAccent)
        }
    }
}
