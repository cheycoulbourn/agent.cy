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
        let model = AppModel(
            creativeService: creativeService,
            subscriptionService: subscriptionService,
            credentialStore: credentialStore,
            installationRedemptionClient: InstallationRedemptionClient(baseURL: APIConfiguration.baseURL, store: credentialStore),
            privacyDeletionService: PrivacyDeletionClient(baseURL: APIConfiguration.baseURL),
            requiresInstallationInvite: liveAI,
            allowsOfflinePrivacyErase: !liveAI
        )
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if usesPreviewData,
           let marker = arguments.firstIndex(of: "-agentCyPreviewTab"),
           arguments.indices.contains(marker + 1),
           let tab = AppTab(rawValue: arguments[marker + 1]) {
            model.selectedTab = tab
        }
        #endif
        _appModel = State(initialValue: model)
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
