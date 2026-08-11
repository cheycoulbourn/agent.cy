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
            if try MCPBridgeService.migrateStructuredPostFields(context: container.mainContext) {
                try container.mainContext.save()
            }
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
        let inspirationShapingService: any InspirationShapingServicing
        let inspirationContentAnalysisService: any InspirationContentAnalyzing
        let subscriptionService = SubscriptionServiceFactory.runtime(useLiveAI: liveAI)
        if liveAI {
            let client = AgentCyAPIClient(baseURL: APIConfiguration.baseURL, store: credentialStore)
            creativeService = RemoteCreativeService(client: client)
            inspirationShapingService = RemoteInspirationShapingService(client: client)
            inspirationContentAnalysisService = RuntimeInspirationContentAnalysisService()
        } else {
            creativeService = PreviewCreativeService()
            inspirationShapingService = PreviewInspirationShapingService()
            inspirationContentAnalysisService = PreviewInspirationContentAnalysisService()
        }
        let model = AppModel(
            creativeService: creativeService,
            inspirationShapingService: inspirationShapingService,
            inspirationContentAnalysisService: inspirationContentAnalysisService,
            subscriptionService: subscriptionService,
            credentialStore: credentialStore,
            installationRedemptionClient: InstallationRedemptionClient(baseURL: APIConfiguration.baseURL, store: credentialStore),
            privacyDeletionService: PrivacyDeletionClient(baseURL: APIConfiguration.baseURL),
            requiresInstallationInvite: requiresInstallationInvite,
            allowsOfflinePrivacyErase: !liveAI
        )
        let legacyAppearance = (try? container.mainContext.fetch(FetchDescriptor<CreatorProfile>()).first?.appearance)
            ?? .system
        model.appearancePreference = DeviceAppearancePreferences.load(legacyFallback: legacyAppearance)
        let workspaces = (try? container.mainContext.fetch(FetchDescriptor<CreatorWorkspace>())) ?? []
        model.activeWorkspaceID = WorkspaceScope.activeWorkspaceID(
            preferredID: CreatorWorkspacePreferences.activeWorkspaceID,
            workspaces: workspaces
        )
        CreatorWorkspacePreferences.activeWorkspaceID = model.activeWorkspaceID
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
                .font(.agentBody)
                .environment(appModel)
                .modelContainer(container)
                .tint(.actionAccent)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    try? FocusTaskRecurrenceService.reconcile(context: container.mainContext)
                    appModel.applyPendingWidgetTaskCompletions(context: container.mainContext)
                    WidgetSnapshotService.refresh(context: container.mainContext)
                    appModel.refreshInspirationShareCreatorSnapshot(context: container.mainContext)
                    try? MCPBridgeService.sync(context: container.mainContext)
                    Task { await appModel.refreshReminderSchedule(context: container.mainContext) }
                }
        }
    }
}
