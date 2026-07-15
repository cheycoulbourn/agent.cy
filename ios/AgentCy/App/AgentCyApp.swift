import SwiftUI
import SwiftData

@main
struct AgentCyApp: App {
    @UIApplicationDelegateAdaptor(AgentCyApplicationDelegate.self) private var applicationDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer
    @State private var appModel: AppModel

    init() {
        #if DEBUG
        let usesPreviewData = ProcessInfo.processInfo.arguments.contains("-agentCyPreviewData")
        container = usesPreviewData
            ? ModelContainerFactory.make(isStoredInMemoryOnly: true)
            : ModelContainerFactory.shared
        if usesPreviewData {
            PreviewData.seed(container.mainContext)
        }
        #else
        container = ModelContainerFactory.shared
        #endif
        do {
            try StoreBootstrapService.run(context: container.mainContext)
        } catch {
            assertionFailure("The local store could not be prepared: \(error.localizedDescription)")
        }
        let credentialStore = DeviceOnlyKeychainCredentialStore.shared
        let liveAI = APIConfiguration.useLiveAI
        #if DEBUG
        let requiresInstallationInvite = !usesPreviewData && liveAI
        #else
        let requiresInstallationInvite = liveAI
        #endif
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
            requiresInstallationInvite: requiresInstallationInvite,
            allowsOfflinePrivacyErase: !liveAI
        )
        if let profile = try? container.mainContext.fetch(FetchDescriptor<CreatorProfile>()).first {
            model.appearancePreference = AppearancePreference(rawValue: profile.appearanceRaw) ?? .system
        }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if usesPreviewData,
           let marker = arguments.firstIndex(of: "-agentCyPreviewTab"),
           arguments.indices.contains(marker + 1),
           let tab = AppTab(rawValue: arguments[marker + 1]) {
            model.selectedTab = tab
        }
        if usesPreviewData,
           let marker = arguments.firstIndex(of: "-agentCyPreviewSheet"),
           arguments.indices.contains(marker + 1),
           let sheet = AppSheet(rawValue: arguments[marker + 1]) {
            model.presentedSheet = sheet
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
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    try? FocusTaskRecurrenceService.reconcile(context: container.mainContext)
                    appModel.applyPendingWidgetTaskCompletions(context: container.mainContext)
                    WidgetSnapshotService.refresh(context: container.mainContext)
                    Task { await appModel.refreshReminderSchedule(context: container.mainContext) }
                }
        }
    }
}
