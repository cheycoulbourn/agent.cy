import SwiftUI
import SwiftData

@main
struct AgentCyApp: App {
    @UIApplicationDelegateAdaptor(AgentCyApplicationDelegate.self) private var applicationDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer
    @State private var appModel: AppModel

    init() {
        RootLaunchDiagnostics.begin()
        AgentNavigationAppearance.configure()
        #if DEBUG
        let usesPreviewData = ProcessInfo.processInfo.arguments.contains("-agentCyPreviewData")
        let rootFixture = RootRuntimeFixture.resolve()
        container = usesPreviewData || rootFixture != nil
            ? ModelContainerFactory.make(isStoredInMemoryOnly: true)
            : ModelContainerFactory.shared
        if usesPreviewData {
            PreviewData.seed(container.mainContext)
        }
        #else
        container = ModelContainerFactory.shared
        #endif
        RootLaunchDiagnostics.mark("store_ready")
        do {
            try StoreBootstrapService.run(context: container.mainContext)
            if try MCPBridgeService.migrateStructuredPostFields(context: container.mainContext) {
                try container.mainContext.save()
            }
        } catch {
            assertionFailure("The local store could not be prepared: \(error.localizedDescription)")
        }
        RootLaunchDiagnostics.mark("bootstrap_complete")
        let credentialStore: any InstallationCredentialStoring
        #if DEBUG
        if let rootFixture {
            credentialStore = PreviewCredentialStore(identity: rootFixture.identity)
        } else {
            credentialStore = DeviceOnlyKeychainCredentialStore.shared
        }
        #else
        credentialStore = DeviceOnlyKeychainCredentialStore.shared
        #endif
        let liveAI = APIConfiguration.useLiveAI
        #if DEBUG
        let requiresInstallationInvite = rootFixture != nil || (!usesPreviewData && liveAI)
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
        if usesPreviewData,
           AppShellRuntimeFixture.requestsFirstPreviewTask(arguments: arguments) {
            let tasks = (try? container.mainContext.fetch(FetchDescriptor<CreatorTask>(
                sortBy: [SortDescriptor(\.createdAt)]
            ))) ?? []
            model.requestedTaskID = AppShellRuntimeFixture.firstPreviewTask(in: tasks)?.id
        }
        if usesPreviewData,
           AppShellRuntimeFixture.requestsPreviewAgendaDay(arguments: arguments) {
            model.selectedTab = .today
            model.widgetAgendaDay = Calendar.current.startOfDay(for: Date())
        }
        #endif
        _appModel = State(initialValue: model)
        RootLaunchDiagnostics.mark("app_model_ready")
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

#if DEBUG
enum AppShellRuntimeFixture {
    static func firstPreviewTask(in tasks: [CreatorTask]) -> CreatorTask? {
        tasks.first(where: { $0.parentTaskID == nil })
    }

    static func requestsFirstPreviewTask(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains("-agentCyPreviewTaskRoute")
    }

    static func requestsPreviewAgendaDay(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains("-agentCyPreviewAgendaDay")
    }
}
#endif
