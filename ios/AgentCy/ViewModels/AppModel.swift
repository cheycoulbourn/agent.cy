import Foundation
import Observation
import SwiftData
import os

enum AppSheet: String, Identifiable, Equatable {
    case creationHub
    case quickCapture
    case voiceSpark
    case creatorSession
    case askCy
    case settings
    case weeklyFocus
    case activityCenter

    var id: String { rawValue }
}

enum AppNotice: Equatable {
    case info(String)
    case error(String)

    var message: String {
        switch self {
        case .info(let message), .error(let message): message
        }
    }
}

enum InstallationInviteStatus: Equatable {
    case idle
    case progress(String)
    case error(String)

    var message: String? {
        switch self {
        case .idle: nil
        case .progress(let message), .error(let message): message
        }
    }

    var showsProgress: Bool {
        if case .progress = self { return true }
        return false
    }

    var isUrgent: Bool {
        if case .error = self { return true }
        return false
    }
}

enum InstallationInviteRedemptionOutcome: Equatable {
    case redeemed
    case validationFailed
    case failed
    case duplicateIgnored
}

enum InstallationInviteErrorMapper {
    static func message(for error: Error) -> String {
        if error is CredentialStoreError || error is InspirationShareBridgeError {
            return "Cy couldn’t save this device connection. Your invitation can be retried safely."
        }
        if let urlError = error as? URLError,
           urlError.code == .notConnectedToInternet ||
            urlError.code == .networkConnectionLost ||
            urlError.code == .cannotConnectToHost ||
            urlError.code == .cannotFindHost {
            return "Cy couldn’t reach the invitation service. Check your connection and try again."
        }
        if let apiError = error as? AgentCyAPIError {
            switch apiError {
            case .invalidRequest(let message):
                return message
            case .server(let wireError) where wireError.code == .installationInvalid:
                if wireError.message.localizedCaseInsensitiveContains("expired") {
                    return "That invitation has expired. Ask for a new code."
                }
                return "That invitation is invalid or has already been used. Check the code or ask for a new one."
            case .server(let wireError) where wireError.code == .rateLimited:
                guard let retryAfterSeconds = wireError.retryAfterSeconds else {
                    return "Too many invitation attempts. Wait a moment and try again."
                }
                let minutes = max(1, Int(ceil(Double(retryAfterSeconds) / 60)))
                return "Too many invitation attempts. Try again in \(minutes) \(minutes == 1 ? "minute" : "minutes")."
            default:
                break
            }
        }
        return "Cy couldn’t check that invitation right now. Try again."
    }
}

@MainActor
enum InstallationRedemptionDiagnostics {
    private static let logger = Logger(subsystem: "com.agentcy.app", category: "InvitationRedemption")
    private static let signposter = OSSignposter(logger: logger)
    private static var intervalState: OSSignpostIntervalState?
    private static var signpostID: OSSignpostID?
    private static var startedAt: TimeInterval?

    static func begin() {
        let id = signposter.makeSignpostID()
        signpostID = id
        startedAt = ProcessInfo.processInfo.systemUptime
        intervalState = signposter.beginInterval("Invitation Redemption", id: id)
    }

    static func duplicateIgnored() {
        guard let signpostID else { return }
        signposter.emitEvent("Duplicate Ignored", id: signpostID)
    }

    static func finish(outcome: String) {
        guard let intervalState else { return }
        let elapsedMilliseconds = startedAt.map {
            (ProcessInfo.processInfo.systemUptime - $0) * 1_000
        } ?? 0
        signposter.endInterval(
            "Invitation Redemption",
            intervalState,
            "outcome=\(outcome, privacy: .public) elapsed_ms=\(elapsedMilliseconds, format: .fixed(precision: 1))"
        )
        logger.notice(
            "outcome=\(outcome, privacy: .public) elapsed_ms=\(elapsedMilliseconds, format: .fixed(precision: 1))"
        )
        self.intervalState = nil
        signpostID = nil
        startedAt = nil
    }
}

@MainActor
enum AccountAuthorizationDiagnostics {
    private static let logger = Logger(subsystem: "com.agentcy.app", category: "AccountAuthorization")
    private static let signposter = OSSignposter(logger: logger)
    private static var intervalState: OSSignpostIntervalState?
    private static var signpostID: OSSignpostID?
    private static var startedAt: TimeInterval?

    static func begin() {
        let id = signposter.makeSignpostID()
        signpostID = id
        startedAt = ProcessInfo.processInfo.systemUptime
        intervalState = signposter.beginInterval("Apple Account Authorization", id: id)
    }

    static func markRoute(_ route: String) {
        guard let signpostID else { return }
        signposter.emitEvent(
            "Account Authorization Route",
            id: signpostID,
            "route=\(route, privacy: .public)"
        )
    }

    static func duplicateIgnored() {
        logger.notice("duplicate_request=ignored")
    }

    static func finish(outcome: String) {
        guard let intervalState, let startedAt else { return }
        let elapsedMilliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        signposter.endInterval(
            "Apple Account Authorization",
            intervalState,
            "outcome=\(outcome, privacy: .public) elapsed_ms=\(elapsedMilliseconds, format: .fixed(precision: 1))"
        )
        logger.notice(
            "outcome=\(outcome, privacy: .public) elapsed_ms=\(elapsedMilliseconds, format: .fixed(precision: 1))"
        )
        self.intervalState = nil
        self.signpostID = nil
        self.startedAt = nil
    }
}

enum RequestedSettingsPage: String, Identifiable, Hashable {
    case notifications
    case access
    case mcpBridge
    case switchAccount
    case addAccount

    var id: String { rawValue }
}

enum IdeaSuggestionOutcome {
    case success([IdeaDirection])
    case unavailable(message: String, requiresUpgrade: Bool)
    case cancelled
}

enum QuickCaptureLaunchMode: Sendable {
    case idea
    case post
    case task
    case cyIdeas
}

enum AppWalkthroughStep: Int, CaseIterable, Identifiable {
    case dashboard
    case quickAdd
    case agenda
    case tasks
    case pillars
    case ideaBank
    case cy

    var id: Int { rawValue }
}

enum AppWalkthrough {
    static let currentVersion = 2
    static let completedVersionStorageKey = "agentcy.walkthrough.completedVersion"
}

struct TaskCompletionUndoState: Identifiable, Equatable {
    let taskID: UUID
    let taskTitle: String
    let generatedTaskID: UUID?

    var id: UUID { taskID }
}

struct InspirationReviewRoute: Identifiable, Equatable {
    let id: UUID
}

@MainActor
@Observable
final class AppModel {
    var selectedTab: AppTab = .home {
        didSet { selectedTabRevision &+= 1 }
    }
    var selectedTabRevision = 0
    var appearancePreference: AppearancePreference = .system
    var activeWorkspaceID: UUID? = CreatorWorkspacePreferences.activeWorkspaceID
    var workspaceRevision = 0
    var presentedSheet: AppSheet? {
        didSet {
            if presentedSheet != nil, inspirationReviewRoute != nil {
                inspirationReviewRoute = nil
            }
        }
    }
    var notice: AppNotice?
    var isWorking = false
    var recordingMilestones = 0
    var exportURL: URL?
    var quickCaptureStartsWithIdeas = false
    var quickCaptureStartsWithTask = false
    var quickCaptureStartsWithPost = false
    var quickCaptureTargetDate: Date?
    var quickCapturePillarID: UUID?
    var quickCaptureTaskLane: TaskLane?
    var quickCaptureTaskFocus: DailyFocusTaskAssignment?
    var widgetAgendaDay: Date?
    var widgetBriefID: UUID?
    var widgetBriefOpensEditor = false
    var requestedTaskID: UUID?
    var requestedIdeaID: UUID?
    var inspirationReviewRoute: InspirationReviewRoute? {
        didSet {
            if inspirationReviewRoute != nil, presentedSheet != nil {
                presentedSheet = nil
            }
        }
    }
    var requestedPlanMode: PlanMode?
    var requestedPlanWeekOffset: Int?
    var requestedPlanNavigationReset = 0
    var requestedOpenPostsList = 0
    var requestedLateWorkList = 0
    var requestedCreatorSessionPostID: UUID?
    var requestedCreatorSessionPostTitle: String?
    var requestedSettingsPage: RequestedSettingsPage?
    var pendingCyPrompt: String?
    var walkthroughStep: AppWalkthroughStep?
    var taskCompletionUndo: TaskCompletionUndoState?
    var notificationAuthorization: AgentNotificationAuthorization = .notDetermined
    var nextNotificationPreviews: [AgentNotificationPreview] = []
    var briefProposals: [UUID: BriefProposal] = [:]
    var revisionProposals: [UUID: BriefRevisionProposal] = [:]
    var voiceProfileChangeProposal: VoiceProfileChangeProposal?
    var hasInstallationCredential = false
    var hasLinkedAccount = false
    var isInstallationCredentialStatusResolved = false
    var installationInviteStatus: InstallationInviteStatus = .idle
    var isRedeemingInvite: Bool { installationInviteStatus.showsProgress }
    var isAuthorizingAccount = false

    var hasGlobalPresentation: Bool {
        presentedSheet != nil || inspirationReviewRoute != nil
    }

    func dismissGlobalPresentation() {
        presentedSheet = nil
        inspirationReviewRoute = nil
    }

    func consumeRequestedTaskRoute() -> UUID? {
        guard let requestedTaskID else { return nil }
        dismissGlobalPresentation()
        self.requestedTaskID = nil
        return requestedTaskID
    }

    func prepareShellForWorkspaceSwitch() {
        quickCapturePillarID = nil
        widgetAgendaDay = nil
        widgetBriefID = nil
        requestedTaskID = nil
        inspirationReviewRoute = nil
        if presentedSheet != .settings {
            presentedSheet = nil
        }
    }

    func setQuickCaptureMode(_ mode: QuickCaptureLaunchMode) {
        quickCaptureStartsWithIdeas = mode == .cyIdeas
        quickCaptureStartsWithPost = mode == .post
        quickCaptureStartsWithTask = mode == .task
    }

    func prepareInstallationInviteEntry() {
        guard !isRedeemingInvite else { return }
        installationInviteStatus = .idle
    }

    func resetInstallationInviteState() {
        guard !isRedeemingInvite else { return }
        installationInviteStatus = .idle
    }

    func startWalkthrough() {
        dismissGlobalPresentation()
        selectedTab = .home
        walkthroughStep = .dashboard
    }

    func routeToWeeklyAgenda() {
        dismissGlobalPresentation()
        requestedPlanNavigationReset &+= 1
        requestedPlanMode = .week
        selectedTab = .today
    }

    func routeToOpenPostsList() {
        dismissGlobalPresentation()
        requestedPlanNavigationReset &+= 1
        requestedOpenPostsList &+= 1
        selectedTab = .today
    }

    func routeToLateWorkList() {
        dismissGlobalPresentation()
        requestedPlanNavigationReset &+= 1
        requestedLateWorkList &+= 1
        selectedTab = .today
    }

    func presentMCPReview() {
        requestedSettingsPage = nil
        presentedSheet = .askCy
    }

    func presentCreatorSession(linkedPostID: UUID? = nil, linkedPostTitle: String? = nil) {
        guard CreatorSessionFeatureAvailability.isEnabled else { return }
        requestedCreatorSessionPostID = linkedPostID
        requestedCreatorSessionPostTitle = linkedPostTitle
        presentedSheet = .creatorSession
    }

    func consumeCreatorSessionRequest() -> (postID: UUID?, postTitle: String?) {
        let request = (requestedCreatorSessionPostID, requestedCreatorSessionPostTitle)
        requestedCreatorSessionPostID = nil
        requestedCreatorSessionPostTitle = nil
        return request
    }

    func presentCreatorError(_ error: Error, action: String? = nil) {
        let presentation = CreatorFacingErrorMapper.presentation(for: error, action: action)
        notice = .error(presentation.message)
        if presentation.requiresUpgrade {
            requestedSettingsPage = .access
            presentedSheet = .settings
        }
    }

    @ObservationIgnored let requiresInstallationInvite: Bool

    @ObservationIgnored private let creativeService: any CreativeServicing
    @ObservationIgnored private let inspirationShapingService: any InspirationShapingServicing
    @ObservationIgnored private let inspirationContentAnalysisService: any InspirationContentAnalyzing
    @ObservationIgnored private let reminderService: any ReminderServicing
    @ObservationIgnored private let calendarSyncService: any CalendarSyncServicing
    @ObservationIgnored private let subscriptionService: any SubscriptionServicing
    @ObservationIgnored private let exportService: any ExportServicing
    @ObservationIgnored private let credentialStore: any InstallationCredentialStoring
    @ObservationIgnored private let installationRedemptionClient: any InstallationRedeeming
    @ObservationIgnored private let accountAuthorizationClient: any AccountAuthorizing
    @ObservationIgnored private let privacyEraseCoordinator: PrivacyEraseCoordinator
    @ObservationIgnored private let contentResetService: any ContentResetServicing
    @ObservationIgnored private var taskCompletionUndoDismissTask: Task<Void, Never>?

    init(
        creativeService: any CreativeServicing = PreviewCreativeService(),
        inspirationShapingService: any InspirationShapingServicing = PreviewInspirationShapingService(),
        inspirationContentAnalysisService: any InspirationContentAnalyzing = PreviewInspirationContentAnalysisService(),
        reminderService: any ReminderServicing = LocalReminderService(),
        calendarSyncService: any CalendarSyncServicing = EventKitCalendarSyncService.shared,
        subscriptionService: any SubscriptionServicing = PreviewSubscriptionService(),
        exportService: any ExportServicing = LocalExportService(),
        credentialStore: any InstallationCredentialStoring = DeviceOnlyKeychainCredentialStore.shared,
        installationRedemptionClient: (any InstallationRedeeming)? = nil,
        accountAuthorizationClient: (any AccountAuthorizing)? = nil,
        privacyDeletionService: (any PrivacyDeletionServicing)? = nil,
        privacyEraseProgressStore: any PrivacyEraseProgressStoring = UserDefaultsPrivacyEraseProgressStore(),
        localDataEraser: any LocalCreatorDataErasing = SwiftDataLocalCreatorDataEraser(),
        exportArchiveCleaner: any ExportArchiveCleaning = LocalExportArchiveCleaner(),
        contentResetService: any ContentResetServicing = ContentResetService(),
        requiresInstallationInvite: Bool = false,
        allowsOfflinePrivacyErase: Bool = true
    ) {
        self.creativeService = creativeService
        self.inspirationShapingService = inspirationShapingService
        self.inspirationContentAnalysisService = inspirationContentAnalysisService
        self.reminderService = reminderService
        self.calendarSyncService = calendarSyncService
        self.subscriptionService = subscriptionService
        self.exportService = exportService
        self.credentialStore = credentialStore
        self.installationRedemptionClient = installationRedemptionClient ?? InstallationRedemptionClient(store: credentialStore)
        self.accountAuthorizationClient = accountAuthorizationClient ?? AccountAuthorizationClient(store: credentialStore)
        self.requiresInstallationInvite = requiresInstallationInvite
        self.contentResetService = contentResetService
        self.privacyEraseCoordinator = PrivacyEraseCoordinator(
            credentialStore: credentialStore,
            privacyDeletionService: privacyDeletionService,
            progressStore: privacyEraseProgressStore,
            localDataEraser: localDataEraser,
            reminderService: reminderService,
            calendarSyncService: calendarSyncService,
            archiveCleaner: exportArchiveCleaner,
            allowsOfflineErase: allowsOfflinePrivacyErase
        )
    }

    func resolvedWorkspaceID(context: ModelContext) -> UUID? {
        let workspaces = (try? context.fetch(FetchDescriptor<CreatorWorkspace>())) ?? []
        let resolved = WorkspaceScope.activeWorkspaceID(
            preferredID: activeWorkspaceID,
            workspaces: workspaces
        )
        if activeWorkspaceID != resolved {
            activeWorkspaceID = resolved
            CreatorWorkspacePreferences.activeWorkspaceID = resolved
        }
        return resolved
    }

    func switchWorkspace(to workspaceID: UUID, context: ModelContext) {
        let workspaces = (try? context.fetch(FetchDescriptor<CreatorWorkspace>())) ?? []
        guard workspaces.contains(where: { $0.id == workspaceID && !$0.isArchived }) else { return }
        activeWorkspaceID = workspaceID
        CreatorWorkspacePreferences.activeWorkspaceID = workspaceID
        prepareShellForWorkspaceSwitch()
        workspaceRevision &+= 1
        try? FocusTaskRecurrenceService.reconcile(context: context, workspaceID: workspaceID)
        try? MCPBridgeService.sync(context: context, workspaceID: workspaceID)
        WidgetSnapshotService.refresh(context: context, workspaceID: workspaceID)
        refreshInspirationShareCreatorSnapshot(context: context)
        queueCalendarSync(context: context)
        Task { await refreshReminderSchedule(context: context) }
    }

    func refreshInspirationShareCreatorSnapshot(context: ModelContext) {
        guard let profile = fetchOne(CreatorProfile.self, context: context),
              let creatorContext = creatorContextWire(profile: profile, context: context),
              let contextJSON = try? JSONEncoder.agentCy.encode(creatorContext) else {
            return
        }
        let sharedPillarIDs = Set(creatorContext.pillars.map(\.pillarId))
        let sharedPillarColors = DuplicateSafeIndex.firstValues(
            ((try? context.fetch(FetchDescriptor<Pillar>())) ?? [])
                .filter { sharedPillarIDs.contains($0.id) }
                .compactMap { pillar -> (String, String)? in
                    guard let color = AgentOKLCH(hex: pillar.colorHex) else { return nil }
                    return (pillar.id.uuidString.lowercased(), color.hexString)
                }
        )
        try? InspirationShareCreatorSnapshotStore.save(
            InspirationShareCreatorSnapshot(
                assistanceMode: profile.assistanceMode.rawValue,
                creatorContextJSON: contextJSON,
                pillarColorHexByID: sharedPillarColors
            )
        )
    }

    func refreshInstallationCredentialStatus(context: ModelContext? = nil) async {
        defer { isInstallationCredentialStatusResolved = true }
        if let context {
            let eraseOutcome = await privacyEraseCoordinator.resumeIfNeeded(
                context: context,
                currentExportURL: exportURL
            )
            if applyPrivacyEraseOutcome(eraseOutcome) { return }
        }
        guard requiresInstallationInvite else {
            hasInstallationCredential = true
            return
        }
        do {
            guard let identity = try await credentialStore.load() else {
                hasInstallationCredential = false
                hasLinkedAccount = false
                return
            }
            hasInstallationCredential = identity.credentialExpiresAt.map { $0 > Date() } ?? true
            hasLinkedAccount = identity.accountID != nil
            if let context {
                synchronizeSubscriptionAccess(with: identity, context: context)
            }
        } catch {
            hasInstallationCredential = false
            hasLinkedAccount = false
            presentCreatorError(error, action: "The connection")
        }
    }

    @discardableResult
    func redeemInstallationInvite(
        _ code: String,
        context: ModelContext? = nil
    ) async -> InstallationInviteRedemptionOutcome {
        defer { isInstallationCredentialStatusResolved = true }
        guard requiresInstallationInvite else {
            hasInstallationCredential = true
            return .redeemed
        }
        guard !isRedeemingInvite else {
            InstallationRedemptionDiagnostics.duplicateIgnored()
            return .duplicateIgnored
        }
        switch InstallationInviteInput.resolve(code) {
        case .invalid(let message):
            installationInviteStatus = .error(message)
            return .validationFailed
        case .valid:
            break
        }
        installationInviteStatus = .progress("Checking your invitation…")
        InstallationRedemptionDiagnostics.begin()
        do {
            let identity = try await installationRedemptionClient.redeem(inviteCode: code)
            hasInstallationCredential = true
            hasLinkedAccount = identity.accountID != nil
            if let context {
                synchronizeSubscriptionAccess(with: identity, context: context)
            }
            installationInviteStatus = .idle
            InstallationRedemptionDiagnostics.finish(outcome: "success")
            return .redeemed
        } catch is CancellationError {
            installationInviteStatus = .idle
            InstallationRedemptionDiagnostics.finish(outcome: "cancelled")
            return .failed
        } catch let urlError as URLError where urlError.code == .cancelled {
            installationInviteStatus = .idle
            InstallationRedemptionDiagnostics.finish(outcome: "cancelled")
            return .failed
        } catch {
            installationInviteStatus = .error(InstallationInviteErrorMapper.message(for: error))
            InstallationRedemptionDiagnostics.finish(outcome: "error")
            return .failed
        }
    }

    @discardableResult
    func authorizeAppleAccount(
        _ material: AppleAuthorizationMaterial,
        context: ModelContext? = nil
    ) async -> Bool {
        guard !isAuthorizingAccount else {
            AccountAuthorizationDiagnostics.duplicateIgnored()
            return false
        }
        isAuthorizingAccount = true
        AccountAuthorizationDiagnostics.begin()
        var authorizationOutcome = "failure"
        defer {
            isAuthorizingAccount = false
            isInstallationCredentialStatusResolved = true
            AccountAuthorizationDiagnostics.finish(outcome: authorizationOutcome)
        }
        do {
            let existingIdentity = try await credentialStore.load()
            let identity: InstallationIdentity
            if let existingIdentity {
                AccountAuthorizationDiagnostics.markRoute("link")
                identity = try await accountAuthorizationClient.link(
                    material,
                    to: existingIdentity
                )
            } else {
                AccountAuthorizationDiagnostics.markRoute("sign_in")
                identity = try await accountAuthorizationClient.signIn(material)
            }
            hasInstallationCredential = true
            hasLinkedAccount = identity.accountID != nil
            if let context {
                synchronizeSubscriptionAccess(with: identity, context: context)
            }
            notice = .info("Your Apple account is connected. Your local work is still here.")
            authorizationOutcome = "success"
            return true
        } catch {
            presentCreatorError(error, action: "Sign in with Apple")
            return false
        }
    }

    func signOutOfAccount(
        successMessage: String = "Signed out. Your work is still stored on this device."
    ) async {
        do {
            try await credentialStore.delete()
            hasInstallationCredential = false
            hasLinkedAccount = false
            isInstallationCredentialStatusResolved = true
            notice = .info(successMessage)
        } catch {
            presentCreatorError(error, action: "Sign out")
        }
    }

    private func synchronizeSubscriptionAccess(
        with identity: InstallationIdentity,
        context: ModelContext
    ) {
        guard let state = subscriptionState(context) else { return }
        if let entitlementEnd = identity.promotionalEntitlementEndsAt,
           entitlementEnd <= Date(),
           identity.access == .comped {
            state.access = .expired
        } else {
            state.access = identity.access
        }
        state.trialEnd = identity.access == .comped
            ? identity.promotionalEntitlementEndsAt
            : nil
        state.updatedAt = Date()
        try? context.save()
    }

    func voiceExampleDrafts(context: ModelContext) -> [VoiceExampleDraft] {
        guard let profile = fetchOne(CreatorProfile.self, context: context) else { return [] }
        return ((try? context.fetch(FetchDescriptor<VoiceExample>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? [])
            .filter { $0.profileID == profile.id }
            .prefix(5)
            .map {
                VoiceExampleDraft(
                    id: $0.id,
                    text: $0.text,
                    source: $0.source,
                    sourceURLString: $0.sourceURLString
                )
            }
    }

    @discardableResult
    func saveVoiceExamples(_ drafts: [VoiceExampleDraft], context: ModelContext) -> Bool {
        guard let profile = fetchOne(CreatorProfile.self, context: context) else {
            notice = .error("Your creator profile is unavailable.")
            return false
        }

        let retained = Array(drafts.filter { $0.isUsableEvidence || $0.hasLocalReference }.prefix(5))
        if let issue = VoiceExampleEvidenceLimits.issue(in: retained) {
            notice = .info(issue)
            return false
        }
        if drafts.contains(where: {
            !$0.sourceURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                InstagramPostReference.canonicalURL(from: $0.sourceURLString) == nil
        }) {
            notice = .info("Check the Instagram link. Use a full HTTPS post or Reel URL.")
            return false
        }

        let normalizedTexts = retained
            .map(\.trimmedText)
            .filter { !$0.isEmpty }
            .map(normalizedExampleText)
        guard Set(normalizedTexts).count == normalizedTexts.count else {
            notice = .info("Two examples contain the same text. Keep one and use a different piece for the other.")
            return false
        }
        let normalizedURLs = retained.compactMap { InstagramPostReference.canonicalURL(from: $0.sourceURLString)?.absoluteString }
        guard Set(normalizedURLs).count == normalizedURLs.count else {
            notice = .info("That Instagram post is already included in another example.")
            return false
        }

        do {
            let stored = try context.fetch(FetchDescriptor<VoiceExample>()).filter { $0.profileID == profile.id }
            let previousEvidenceFingerprint = VoiceExampleFingerprint.make(from: stored)
            let retainedEvidenceFingerprint = VoiceExampleFingerprint.make(from: retained)
            let retainedIDs = Set(retained.map(\.id))
            for existing in stored where !retainedIDs.contains(existing.id) { context.delete(existing) }

            for (index, draft) in retained.enumerated() {
                let canonicalURL = InstagramPostReference.canonicalURL(from: draft.sourceURLString)?.absoluteString ?? ""
                if let existing = stored.first(where: { $0.id == draft.id }) {
                    existing.text = draft.trimmedText
                    existing.sortOrder = index
                    existing.source = draft.source
                    existing.sourceURLString = canonicalURL
                    existing.creatorConfirmed = true
                    existing.updatedAt = Date()
                } else {
                    context.insert(VoiceExample(
                        id: draft.id,
                        profileID: profile.id,
                        text: draft.trimmedText,
                        sortOrder: index,
                        source: draft.source,
                        sourceURLString: canonicalURL,
                        creatorConfirmed: true
                    ))
                }
            }
            if previousEvidenceFingerprint != retainedEvidenceFingerprint {
                try deletePendingVoiceProposals(kind: "initial", context: context)
            }
            try context.save()
            return true
        } catch {
            presentCreatorError(error, action: "Your examples")
            return false
        }
    }

    func prepareInitialVoiceProfile(context: ModelContext) async -> InitialVoiceProfileProposal? {
        guard await canUseCy(.extractVoiceProfile, context: context) else { return nil }
        guard let profile = fetchOne(CreatorProfile.self, context: context),
              let creatorContext = creatorContextWire(profile: profile, context: context, includeDormantVoiceData: true),
              creatorContext.voiceExamples.count >= 3 else {
            notice = .info("Add and review at least three real examples before Cy builds your voice profile.")
            return nil
        }
        if let issue = voiceEvidenceIssue(in: creatorContext) {
            notice = .info(issue)
            return nil
        }
        let requestEvidenceFingerprint = VoiceExampleFingerprint.make(from: creatorContext.voiceExamples)
        if let existing = initialVoiceProfileProposal(context: context),
           existing.profileID == profile.id,
           existing.evidenceFingerprint == requestEvidenceFingerprint {
            return existing
        }

        isWorking = true
        defer { isWorking = false }
        do {
            let extraction = try await creativeService.extractVoiceProfile(context: creatorContext, mode: profile.assistanceMode)
            try deletePendingVoiceProposals(kind: "initial", context: context)
            let proposal = InitialVoiceProfileProposal(
                profileID: profile.id,
                edited: VoiceProfileDraft(extraction.canonical),
                evidenceFingerprint: requestEvidenceFingerprint
            )
            try persist(initialVoiceProposal: proposal, context: context)
            try context.save()
            return proposal
        } catch {
            presentCreatorError(error, action: "The voice profile")
            return nil
        }
    }

    func initialVoiceProfileProposal(context: ModelContext) -> InitialVoiceProfileProposal? {
        let descriptor = FetchDescriptor<PendingVoiceProfileProposal>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        guard let record = try? context.fetch(descriptor).first(where: { $0.proposalKindRaw == "initial" }),
              let data = record.payloadJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(InitialVoiceProfileProposal.self, from: data)
    }

    func acceptInitialVoiceProfile(_ proposal: InitialVoiceProfileProposal, context: ModelContext) {
        guard let staged = initialVoiceProfileProposal(context: context), staged.id == proposal.id,
              let profile = fetchOne(CreatorProfile.self, context: context),
              profile.id == proposal.profileID,
              validVoiceDraft(proposal.edited) else {
            notice = .error("This voice-profile proposal is no longer valid.")
            return
        }
        let examples = ((try? context.fetch(FetchDescriptor<VoiceExample>())) ?? [])
            .filter { $0.profileID == profile.id && $0.creatorConfirmed && !$0.text.isEmpty }
        guard VoiceExampleFingerprint.make(from: examples) == proposal.evidenceFingerprint else {
            notice = .info("Your examples changed after this profile was prepared. Build it again from the current examples.")
            discardInitialVoiceProfile(context: context)
            return
        }

        do {
            let related = try context.fetch(FetchDescriptor<VoiceProfile>()).filter { $0.profileID == profile.id }
            related.forEach { $0.isApproved = false }
            let wire = proposal.edited.wire
            context.insert(VoiceProfile(
                profileID: profile.id,
                summary: wire.summary,
                traitsText: (wire.tone + wire.signatureQualities).joined(separator: ", "),
                avoidText: wire.phrasesToAvoid.joined(separator: ", "),
                isApproved: true,
                version: (related.map(\.version).max() ?? 0) + 1,
                canonicalPayloadJSON: try encodeJSONString(wire),
                evidenceFingerprint: proposal.evidenceFingerprint
            ))
            try deletePendingVoiceProposals(kind: "initial", context: context)
            try context.save()
        } catch {
            presentCreatorError(error, action: "The voice profile")
        }
    }

    func discardInitialVoiceProfile(context: ModelContext) {
        do {
            try deletePendingVoiceProposals(kind: "initial", context: context)
            try context.save()
        } catch {
            presentCreatorError(error, action: "The voice profile")
        }
    }

    func isVoiceProfileStale(_ voiceProfile: VoiceProfile, context: ModelContext) -> Bool {
        guard !voiceProfile.evidenceFingerprint.isEmpty else { return false }
        let examples = ((try? context.fetch(FetchDescriptor<VoiceExample>())) ?? [])
            .filter { $0.profileID == voiceProfile.profileID && $0.creatorConfirmed && !$0.text.isEmpty }
        return VoiceExampleFingerprint.make(from: examples) != voiceProfile.evidenceFingerprint
    }

    @discardableResult
    func completeOnboarding(_ draft: OnboardingDraft, context: ModelContext) async -> Bool {
        if fetchOne(CreatorProfile.self, context: context) != nil { return true }
        guard !isWorking else { return false }

        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let goal = draft.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft.adultConfirmed, !name.isEmpty, !goal.isEmpty else {
            notice = .info("Add your name, goal, and age confirmation before finishing setup.")
            return false
        }

        let retainedExamples = Array(draft.voiceExamples.filter { $0.isUsableEvidence || $0.hasLocalReference }.prefix(5))
        if let issue = VoiceExampleEvidenceLimits.issue(in: retainedExamples) {
            notice = .info(issue)
            return false
        }

        let selectedPlatforms = draft.platforms.sorted { $0.rawValue < $1.rawValue }
        let selectedDestinations = Set(selectedPlatforms.map { PublishingCatalog.identifiers(for: $0).destination })
        let accountInputs: [(kind: BuiltInDestinationKind, destinationID: UUID, rawHandle: String)] = [
            (.instagram, PublishingCatalog.instagramID, draft.accountHandles[.instagram, default: ""]),
            (.tiktok, PublishingCatalog.tiktokID, draft.accountHandles[.tiktok, default: ""]),
            (.youtube, PublishingCatalog.youtubeID, draft.accountHandles[.youtube, default: ""]),
        ].filter { selectedDestinations.contains($0.destinationID) && !$0.rawHandle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        for input in accountInputs where CreatorSocialAccount.profileURLString(forHandle: input.rawHandle, destination: input.kind) == nil {
            notice = .info("Check the \(input.kind.title) handle. Use only the account name, with or without @.")
            return false
        }

        isWorking = true
        defer { isWorking = false }
        let installationIdentity = try? await credentialStore.load()
        let profile = CreatorProfile(
            name: name,
            goal: goal,
            selectedPlatforms: selectedPlatforms,
            assistanceMode: .collaborate,
            adultConfirmed: draft.adultConfirmed,
            telemetryConsent: draft.telemetryConsent,
            onboardingCompleted: true,
            showsBrandDealsInPostEditor: draft.brandPartnershipsEnabled
        )
        profile.vibePalette = draft.vibePalette
        profile.selectedDestinationIDs = selectedDestinations.sorted { $0.uuidString < $1.uuidString }
        context.insert(profile)

        let workspaceName = accountInputs.first.map { input -> String in
            var handle = input.rawHandle.trimmingCharacters(in: .whitespacesAndNewlines)
            while handle.hasPrefix("@") { handle.removeFirst() }
            return handle.isEmpty ? name : "@\(handle)"
        } ?? name
        let workspace = CreatorWorkspace(
            profileID: profile.id,
            name: workspaceName.isEmpty ? "My account" : workspaceName,
            creatorName: name,
            avatarImageData: profile.avatarImageData,
            hasCustomIdentity: true
        )
        workspace.vibePalette = draft.vibePalette
        workspace.weeklyPostingGoal = draft.weeklyPostingGoal.map(WeeklyConsistencyPolicy.clampedGoal)
        context.insert(workspace)

        let retainedPillars = Array(draft.pillars.prefix(4))
        let anchorID = retainedPillars.first?.id
        for (index, pillar) in retainedPillars.enumerated() {
            let model = Pillar(
                id: pillar.id,
                parentPillarID: index == 0 ? nil : anchorID,
                role: index == 0 ? .anchor : .supporting,
                name: pillar.name.trimmingCharacters(in: .whitespacesAndNewlines),
                detail: "",
                colorHex: pillar.colorHex,
                assignedWeekdays: pillar.assignedWeekdays
            )
            model.workspaceID = workspace.id
            context.insert(model)
        }

        for (index, example) in retainedExamples.enumerated() {
            context.insert(VoiceExample(
                id: example.id,
                profileID: profile.id,
                text: example.trimmedText,
                sortOrder: index,
                source: example.source,
                sourceURLString: InstagramPostReference.canonicalURL(from: example.sourceURLString)?.absoluteString ?? "",
                creatorConfirmed: true
            ))
        }

        for (index, input) in accountInputs.enumerated() {
            guard let profileURL = CreatorSocialAccount.profileURLString(forHandle: input.rawHandle, destination: input.kind) else { continue }
            var handle = input.rawHandle.trimmingCharacters(in: .whitespacesAndNewlines)
            while handle.hasPrefix("@") { handle.removeFirst() }
            let account = CreatorSocialAccount(
                profileID: profile.id,
                destinationID: input.destinationID,
                label: "@\(handle)",
                profileURLString: profileURL,
                isPrimary: true,
                sortOrder: index
            )
            account.workspaceID = workspace.id
            context.insert(account)
        }

        if fetchOne(ReminderSettings.self, context: context) == nil {
            context.insert(ReminderSettings(
                masterEnabled: true,
                dailyEnabled: draft.dailyReminderEnabled,
                dailyHour: draft.dailyReminderHour,
                dailyMinute: draft.dailyReminderMinute,
                weeklyEnabled: draft.weeklyReminderEnabled,
                weeklyWeekday: draft.weeklyReminderWeekday,
                weeklyHour: draft.weeklyReminderHour,
                weeklyMinute: draft.weeklyReminderMinute
            ))
        }
        if fetchOne(SubscriptionState.self, context: context) == nil {
            context.insert(SubscriptionState(
                access: installationIdentity?.access ?? .freeJourney,
                trialEnd: installationIdentity?.promotionalEntitlementEndsAt
            ))
        }

        do {
            try context.save()
            activeWorkspaceID = workspace.id
            CreatorWorkspacePreferences.activeWorkspaceID = workspace.id
            appearancePreference = draft.appearance ?? .system
            DeviceAppearancePreferences.save(appearancePreference)
            LocalCyPreferences.isEnabled = draft.aiProvider == .claudeOrCodex
            if MCPBridgePreferences.isConnected {
                try? MCPBridgeService.sync(context: context, workspaceID: workspace.id)
            }
            await refreshReminderSchedule(context: context)
            return true
        } catch {
            context.rollback()
            presentCreatorError(error, action: "Setup")
            return false
        }
    }

    func applyReminderSettings(
        _ settings: ReminderSettings,
        context: ModelContext,
        requestPermission: Bool = false
    ) async {
        settings.updatedAt = Date()
        do {
            try context.save()
            if requestPermission, settings.masterEnabled {
                _ = try await reminderService.requestAuthorization()
            }
            nextNotificationPreviews = try await reminderService.reconcile(context: context, now: Date())
            notificationAuthorization = await reminderService.authorizationStatus()
        } catch {
            notificationAuthorization = await reminderService.authorizationStatus()
            presentCreatorError(error, action: "Notification settings")
        }
    }

    func refreshReminderSchedule(context: ModelContext) async {
        notificationAuthorization = await reminderService.authorizationStatus()
        do {
            nextNotificationPreviews = try await reminderService.reconcile(context: context, now: Date())
        } catch {
            nextNotificationPreviews = []
        }
    }

    @discardableResult
    func requestNotificationPermission(context: ModelContext) async -> Bool {
        do {
            let granted = try await reminderService.requestAuthorization()
            notificationAuthorization = await reminderService.authorizationStatus()
            nextNotificationPreviews = try await reminderService.reconcile(context: context, now: Date())
            return granted
        } catch {
            notificationAuthorization = await reminderService.authorizationStatus()
            presentCreatorError(error, action: "Notifications")
            return false
        }
    }

    var calendarAuthorization: AgentCalendarAuthorization {
        calendarSyncService.authorization
    }

    func requestCalendarAccess() async -> Bool {
        do {
            return try await calendarSyncService.requestFullAccess()
        } catch {
            presentCreatorError(error, action: "Calendar access")
            return false
        }
    }

    func availableCalendars() -> [AgentCalendarChoice] {
        calendarSyncService.availableCalendars()
    }

    func refreshCalendarSync(context: ModelContext, showConfirmation: Bool = false) {
        do {
            try calendarSyncService.reconcile(context: context)
            if showConfirmation {
                notice = .info("Your calendar is up to date.")
            }
        } catch {
            if showConfirmation {
                presentCreatorError(error, action: "Calendar sync")
            }
        }
    }

    func disconnectCalendar(context: ModelContext) {
        do {
            try calendarSyncService.disconnect()
            notice = .info("Calendar disconnected. Your agent.cy schedule is unchanged.")
        } catch {
            presentCreatorError(error, action: "Calendar disconnect")
        }
    }

    func queueCalendarSync(context: ModelContext) {
        // ModelContext is tied to its container and must not escape into an
        // unstructured task. In-memory stores used by tests (and stores being
        // reset in production) may be torn down before that task resumes.
        WidgetSnapshotService.refresh(context: context)
        refreshCalendarSync(context: context)
        if reminderService is LocalReminderService {
            Task { @MainActor [weak self] in
                await self?.refreshReminderSchedule(context: context)
            }
        }
    }

    @discardableResult
    func importPendingInspiration(
        context: ModelContext,
        presentsImportedSource: Bool = true
    ) -> InspirationImportResult? {
        guard let coordinator = try? InspirationImportCoordinator() else {
            return nil
        }
        return importPendingInspiration(
            context: context,
            coordinator: coordinator,
            presentsImportedSource: presentsImportedSource
        )
    }

    @discardableResult
    func importPendingInspiration(
        context: ModelContext,
        coordinator: InspirationImportCoordinator,
        presentsImportedSource: Bool
    ) -> InspirationImportResult? {
        guard let result = try? coordinator.importPending(
                  context: context,
                  preferredWorkspaceID: resolvedWorkspaceID(context: context)
              ) else {
            return nil
        }
        guard presentsImportedSource,
              inspirationReviewRoute == nil,
              presentedSheet == nil,
              let sourceID = (result.importedSourceIDs + result.reopenedSourceIDs).first else {
            return result
        }
        selectedTab = .ideaBank
        inspirationReviewRoute = InspirationReviewRoute(id: sourceID)
        return result
    }

    func openInspiration(_ source: InspirationSource) {
        guard SavedPostsScopePolicy.includes(
            recordWorkspaceID: source.workspaceID,
            activeWorkspaceID: activeWorkspaceID
        ) else { return }
        dismissGlobalPresentation()
        // The review sheet is shell-owned: presenting it must not relocate
        // the user's tab. On every shell the selected tab drives the page
        // visible beneath the sheet, so a tab switch here surfaces the Idea
        // Bank behind the review and strands the user there afterwards.
        inspirationReviewRoute = InspirationReviewRoute(id: source.id)
    }

    @discardableResult
    func analyzeInspiration(
        _ source: InspirationSource,
        context: ModelContext
    ) async -> InspirationShapeResultWire? {
        if let linkedBriefID = source.linkedBriefID,
           brief(id: linkedBriefID, context: context) != nil {
            return decodedInspirationResult(source)
        }
        if source.status == .ready, let result = decodedInspirationResult(source) {
            return result
        }
        guard can(.createSpark, context: context),
              await canUseCy(.ideate, context: context),
              let profile = fetchOne(CreatorProfile.self, context: context),
              let creatorContext = creatorContextWire(profile: profile, context: context) else {
            return nil
        }
        guard !Task.isCancelled else { return nil }

        let previousStatus = source.status
        let previousErrorCode = source.lastErrorCode
        let operationID = source.shapeOperationID ?? UUID()
        source.shapeOperationID = operationID
        source.status = .shaping
        source.lastAttemptAt = Date()
        source.lastErrorCode = nil
        source.updatedAt = Date()
        do {
            try context.save()
        } catch {
            presentCreatorError(error, action: "This inspiration")
            return nil
        }

        isWorking = true
        defer { isWorking = false }
        do {
            let sourceMaterial: InspirationSourceMaterialWire
            if let existing = existingSourceMaterial(source) {
                sourceMaterial = existing
            } else {
                guard let url = URL(string: source.canonicalURLString) else {
                    throw InspirationContentAnalysisError.insufficientSourceContent
                }
                let analysis = try await inspirationContentAnalysisService.analyze(
                    url: url,
                    platform: source.platform,
                    hostCaption: source.sourceCaption,
                    sharedVideoFilename: source.sharedVideoFilename,
                    existingThumbnailData: source.thumbnailData
                )
                try Task.checkCancellation()
                source.sourceTitle = analysis.title ?? ""
                source.sourceCaption = analysis.caption ?? ""
                source.sourceTranscript = analysis.transcript ?? ""
                source.visualObservations = analysis.visualObservations
                source.analyzedInputs = analysis.analyzedInputs
                source.sourceDurationSeconds = analysis.durationSeconds
                source.thumbnailData = analysis.thumbnailData
                if let assetStore = try? InspirationSharedAssetStore() {
                    assetStore.remove(filename: source.sharedVideoFilename)
                }
                source.sharedVideoFilename = nil
                source.updatedAt = Date()
                try context.save()
                sourceMaterial = analysis.sourceMaterial
            }
            let result = try await inspirationShapingService.shape(
                sourcePlatform: source.platform,
                sourceMaterial: sourceMaterial,
                creatorContext: creatorContext,
                assistanceMode: profile.assistanceMode,
                operationID: operationID
            )
            try Task.checkCancellation()
            try InspirationShapePersistenceCoordinator.stage(
                result,
                on: source,
                context: context
            )
            WidgetSnapshotService.refresh(context: context)
            try? MCPBridgeService.sync(context: context)
            return result
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                source.status = previousStatus
                source.lastErrorCode = previousErrorCode
                source.updatedAt = Date()
                try? context.save()
                return nil
            }
            source.status = .failed
            let isSourceContentError = error is InspirationContentAnalysisError ||
                (error as? InspirationShapingError) == .invalidSourceMaterial
            source.lastErrorCode = isSourceContentError ? "source_content_unavailable" : "shape_failed"
            source.updatedAt = Date()
            try? context.save()
            if !isSourceContentError {
                presentCreatorError(error, action: "This inspiration")
            }
            return nil
        }
    }

    func saveInspirationIdea(
        source: InspirationSource,
        result: InspirationShapeResultWire,
        draft: InspirationEditableIdea,
        context: ModelContext
    ) -> CreativeBrief? {
        guard can(.createSpark, context: context) else { return nil }
        do {
            let brief = try InspirationShapePersistenceCoordinator.save(
                draft,
                result: result,
                to: source,
                context: context
            )
            WidgetSnapshotService.refresh(context: context)
            try? MCPBridgeService.sync(context: context)
            notice = .info("Idea saved to your Idea Bank.")
            return brief
        } catch {
            presentCreatorError(error, action: "This idea")
            return nil
        }
    }

    func saveInspirationEdits(
        source: InspirationSource,
        result: InspirationShapeResultWire,
        draft: InspirationEditableIdea,
        context: ModelContext
    ) -> InspirationShapeResultWire? {
        do {
            let savedResult = try InspirationShapePersistenceCoordinator.persistEdits(
                draft,
                result: result,
                to: source,
                context: context
            )
            WidgetSnapshotService.refresh(context: context)
            try? MCPBridgeService.sync(context: context)
            return savedResult
        } catch {
            presentCreatorError(error, action: "This saved post")
            return nil
        }
    }

    func saveManualInspirationDraft(
        source: InspirationSource,
        draft: ManualInspirationIdeaDraft,
        context: ModelContext
    ) -> ManualInspirationIdeaDraft? {
        do {
            let savedDraft = try InspirationShapePersistenceCoordinator.persistManualDraft(
                draft,
                to: source,
                context: context
            )
            WidgetSnapshotService.refresh(context: context)
            try? MCPBridgeService.sync(context: context)
            return savedDraft
        } catch {
            presentCreatorError(error, action: "This saved post")
            return nil
        }
    }

    func saveManualInspirationIdea(
        source: InspirationSource,
        draft: ManualInspirationIdeaDraft,
        context: ModelContext
    ) -> CreativeBrief? {
        guard can(.createSpark, context: context) else { return nil }
        do {
            let brief = try InspirationShapePersistenceCoordinator.saveManual(
                draft,
                to: source,
                context: context
            )
            WidgetSnapshotService.refresh(context: context)
            try? MCPBridgeService.sync(context: context)
            notice = .info("Your idea was saved to the Idea Bank.")
            return brief
        } catch {
            presentCreatorError(error, action: "This idea")
            return nil
        }
    }

    @discardableResult
    func deleteInspiration(
        _ source: InspirationSource,
        context: ModelContext
    ) -> Bool {
        do {
            try InspirationDeletionCoordinator.delete(source, context: context)
            WidgetSnapshotService.refresh(context: context)
            try? MCPBridgeService.sync(context: context)
            notice = .info("Saved post deleted.")
            return true
        } catch {
            presentCreatorError(error, action: "This saved post")
            return false
        }
    }

    private func decodedInspirationResult(_ source: InspirationSource) -> InspirationShapeResultWire? {
        guard let data = source.shapePayloadJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder.agentCy.decode(InspirationShapeResultWire.self, from: data)
    }

    private func existingSourceMaterial(_ source: InspirationSource) -> InspirationSourceMaterialWire? {
        let material = InspirationSourceMaterialWire(
            title: source.sourceTitle.isEmpty ? nil : source.sourceTitle,
            caption: source.sourceCaption.isEmpty ? nil : source.sourceCaption,
            transcript: source.sourceTranscript.isEmpty ? nil : source.sourceTranscript,
            visualObservations: source.visualObservations,
            analyzedInputs: source.analyzedInputs,
            durationSeconds: source.sourceDurationSeconds
        )
        return (try? InspirationSourceMaterialValidator.validate(material)) == nil ? nil : material
    }

    func openIdea(_ brief: CreativeBrief, developsPost: Bool, context: ModelContext) {
        if developsPost {
            guard ensurePostDraft(for: brief, context: context) != nil else { return }
        }
        inspirationReviewRoute = nil
        requestedIdeaID = brief.id
        selectedTab = .ideaBank
    }

    @discardableResult
    func scheduleInspirationFilming(
        source: InspirationSource,
        brief: CreativeBrief,
        date: Date,
        includesTime: Bool,
        context: ModelContext
    ) -> Bool {
        guard can(.schedule, context: context), can(.createTask, context: context) else {
            return false
        }
        do {
            _ = try InspirationFilmingScheduler.schedule(
                source: source,
                brief: brief,
                date: date,
                includesTime: includesTime,
                context: context
            )
            queueCalendarSync(context: context)
            try? MCPBridgeService.sync(context: context)
            notice = .info("Filming added to your schedule.")
            return true
        } catch {
            presentCreatorError(error, action: "Filming")
            return false
        }
    }

    func applyFocusReminder(
        _ details: DailyFocusDayDetail,
        focusTitle: String,
        context: ModelContext
    ) async {
        details.updatedAt = Date()
        do {
            if details.reminderEnabled {
                guard let reminderDate = details.reminderDate, reminderDate > Date() else {
                    throw ReminderServiceError.reminderDatePassed
                }
                if await reminderService.authorizationStatus() == .notDetermined {
                    _ = try await reminderService.requestAuthorization()
                }
            }
            try context.save()
            nextNotificationPreviews = try await reminderService.reconcile(context: context, now: Date())
            notificationAuthorization = await reminderService.authorizationStatus()
        } catch {
            details.reminderEnabled = false
            details.updatedAt = Date()
            try? context.save()
            presentCreatorError(error, action: "Calendar sync")
        }
    }

    @discardableResult
    func createSpark(
        text: String,
        source: SparkSource,
        title explicitTitle: String? = nil,
        notes: String = "",
        pillarID: UUID? = nil,
        preferredDestinationID: UUID? = nil,
        preferredFormatID: UUID? = nil,
        targetDate: Date? = nil,
        placement: IdeaBankPlacement = .idea,
        context: ModelContext
    ) -> CreativeBrief? {
        guard can(.createSpark, context: context) else { return nil }
        let premise = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !premise.isEmpty else {
            notice = .error("Add an idea before saving.")
            return nil
        }
        let cleanedTitle = explicitTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = cleanedTitle.isEmpty ? titleFromSpark(premise) : cleanedTitle
        let brief = CreativeBrief(title: title, premise: premise, source: source)
        brief.workspaceID = resolvedWorkspaceID(context: context)
        brief.ideaBankPlacement = placement
        brief.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        brief.pillarID = pillarID
        brief.preferredDestinationID = preferredDestinationID
        brief.preferredFormatID = preferredFormatID
        brief.agendaDate = targetDate
        context.insert(brief)
        try? context.save()
        return brief
    }

    @discardableResult
    func ensurePostDraft(
        for brief: CreativeBrief,
        context: ModelContext
    ) -> PlatformOutput? {
        let briefID = brief.id
        let existingOutputs: [PlatformOutput]
        do {
            existingOutputs = try context.fetch(FetchDescriptor<PlatformOutput>(
                predicate: #Predicate { $0.briefID == briefID },
                sortBy: [SortDescriptor(\.createdAt)]
            ))
        } catch {
            notice = .error("That idea’s post drafts could not be loaded. Nothing new was created.")
            return nil
        }
        if let existing = existingOutputs.first {
            return existing
        }

        guard brief.status == .spark || brief.status == .developing else { return nil }
        let profile = try? context.fetch(FetchDescriptor<CreatorProfile>()).first
        var platform = profile?.selectedPlatforms.first ?? .instagramReels
        let catalogIDs = PublishingCatalog.identifiers(for: platform)
        var destinationID = catalogIDs.destination
        var formatID = catalogIDs.format
        // An idea tagged with a platform at capture time starts its draft there.
        if let preferredDestinationID = brief.preferredDestinationID,
           let destinations = try? context.fetch(FetchDescriptor<PublishingDestination>()),
           destinations.contains(where: { $0.id == preferredDestinationID && !$0.isArchived }),
           let formats = try? context.fetch(FetchDescriptor<PublishingFormat>()) {
            let available = IdeaPlatformChoicePolicy.availableFormats(
                destinationID: preferredDestinationID,
                formats: formats
            )
            if let preferredFormatID = available.first(where: { $0.id == brief.preferredFormatID })?.id
                ?? available.first?.id {
                destinationID = preferredDestinationID
                formatID = preferredFormatID
                platform = PublishingCatalog.legacyPlatform(destinationID: destinationID, formatID: formatID)
                    ?? platform
            }
        }
        let duration = platform.format.durationOptions.contains(brief.durationSeconds)
            ? brief.durationSeconds
            : platform.format.defaultDuration
        let output = PlatformOutput(
            briefID: brief.id,
            platform: platform,
            destinationID: destinationID,
            formatID: formatID,
            socialAccountID: preferredSocialAccountID(for: destinationID, context: context),
            durationSeconds: duration,
            status: .draft
        )
        output.workspaceID = brief.workspaceID ?? resolvedWorkspaceID(context: context)
        output.targetDate = brief.agendaDate
        output.includesTargetTime = false
        let previousNotes = brief.notes
        let previousDuration = brief.durationSeconds
        let previousUpdatedAt = brief.updatedAt
        let previousPlacement = brief.ideaBankPlacement
        if brief.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            brief.notes = brief.premise
        }
        brief.durationSeconds = duration
        brief.ideaBankPlacement = .post
        brief.updatedAt = Date()
        context.insert(output)

        do {
            try context.save()
            queueCalendarSync(context: context)
            return output
        } catch {
            context.delete(output)
            brief.notes = previousNotes
            brief.durationSeconds = previousDuration
            brief.ideaBankPlacement = previousPlacement
            brief.updatedAt = previousUpdatedAt
            notice = .error("That idea could not be opened as a post draft.")
            return nil
        }
    }

    @discardableResult
    func createPostDraftFromCyResponse(
        _ response: String,
        suggestedTitle: String? = nil,
        sourceBrief: CreativeBrief? = nil,
        pillarID: UUID?,
        context: ModelContext
    ) -> (brief: CreativeBrief, output: PlatformOutput)? {
        let cleanResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceProposal = sourceBrief.map { source in
            proposal(for: source, context: context)
                ?? storedCanonicalProposal(for: source)
                ?? localProposal(for: source, context: context)
        }
        let sourceOutput = sourceBrief.flatMap { outputs(for: $0, context: context).first }
        guard !cleanResponse.isEmpty,
              let brief = createSpark(
                text: cleanResponse,
                source: .cyDirection,
                title: suggestedTitle,
                notes: cleanResponse,
                pillarID: pillarID,
                placement: .post,
                context: context
              ) else { return nil }

        brief.premise = ""
        guard let output = ensurePostDraft(for: brief, context: context) else {
            context.delete(brief)
            try? context.save()
            return nil
        }

        var insertedTasks: [CreatorTask] = []
        if let sourceBrief, let sourceProposal {
            apply(sourceProposal.draft, to: brief)

            let canonicalTitle = sourceProposal.canonicalBrief?.title
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let proposalTitle = sourceProposal.draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackTitle = suggestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let sourceTitle = sourceBrief.title.trimmingCharacters(in: .whitespacesAndNewlines)
            brief.title = [canonicalTitle, proposalTitle, fallbackTitle, sourceTitle]
                .first(where: { !$0.isEmpty }) ?? brief.title
            brief.premise = ""
            brief.notes = cyPostNotes(
                response: cleanResponse,
                sourceBrief: sourceBrief,
                proposal: sourceProposal
            )
            brief.scriptEnabled = !sourceProposal.draft.scriptBeats.allSatisfy {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            brief.pillarID = pillarID ?? sourceBrief.pillarID
            brief.seriesID = sourceBrief.seriesID
            brief.episodeNumber = sourceBrief.episodeNumber
            brief.episodeLabel = sourceBrief.episodeLabel
            brief.brandPartnerID = sourceBrief.brandPartnerID
            brief.isBrandCollaboration = sourceBrief.isBrandCollaboration
            brief.brandName = sourceBrief.brandName
            brief.compensationTypeRaw = sourceBrief.compensationTypeRaw
            brief.compensationAmount = sourceBrief.compensationAmount
            brief.compensationCurrencyCode = sourceBrief.compensationCurrencyCode
            brief.brandHasNetTerms = sourceBrief.brandHasNetTerms
            brief.brandNetTermsDays = sourceBrief.brandNetTermsDays
            brief.giftedProductDescription = sourceBrief.giftedProductDescription
            brief.giftedEstimatedValue = sourceBrief.giftedEstimatedValue
            brief.promoCode = sourceBrief.promoCode
            brief.promoLinkString = sourceBrief.promoLinkString
            brief.moodBoardEnabled = sourceBrief.moodBoardEnabled
            brief.moodBoardURLString = sourceBrief.moodBoardURLString
            brief.workDate = nil
            brief.includesWorkTime = false
            brief.agendaDate = nil

            if let sourceOutput {
                output.platform = sourceOutput.platform
                output.destinationID = sourceOutput.destinationID
                output.formatID = sourceOutput.formatID
                output.socialAccountID = sourceOutput.socialAccountID
                output.durationSeconds = sourceOutput.durationSeconds
                output.seriesName = sourceOutput.seriesName
            } else {
                output.durationSeconds = sourceProposal.draft.durationSeconds
            }

            if let variant = sourceProposal.variants.first(where: { $0.platform == output.platform })
                ?? sourceProposal.variants.first {
                apply(variant, to: output)
            }
            output.status = .draft
            output.targetDate = nil
            output.postedAt = nil
            output.publishedURLString = ""

            let workspaceID = brief.workspaceID ?? resolvedWorkspaceID(context: context)
            var taskKeys = Set<String>()
            for (index, proposedTask) in sourceProposal.tasks.enumerated() {
                let taskTitle = proposedTask.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !taskTitle.isEmpty else { continue }
                let taskKey = "\(proposedTask.kind.rawValue)|\(taskTitle.lowercased())"
                guard taskKeys.insert(taskKey).inserted else { continue }

                let task = CreatorTask(
                    briefID: brief.id,
                    pillarID: brief.pillarID,
                    platformOutputID: output.id,
                    title: taskTitle,
                    kind: proposedTask.kind,
                    lane: .production,
                    priority: .none,
                    notes: proposedTask.notes,
                    estimatedMinutes: proposedTask.estimatedMinutes,
                    sortOrder: index,
                    isRecordingMilestoneDesignated: proposedTask.isRecordingMilestone
                )
                task.workspaceID = workspaceID
                context.insert(task)
                insertedTasks.append(task)
            }
        }

        do {
            try context.save()
            return (brief, output)
        } catch {
            insertedTasks.forEach(context.delete)
            context.delete(output)
            context.delete(brief)
            try? context.save()
            notice = .error("That post draft could not be created.")
            return nil
        }
    }

    private func storedCanonicalProposal(for brief: CreativeBrief) -> BriefProposal? {
        guard let data = brief.readyBriefPayloadJSON.data(using: .utf8),
              let canonical = try? JSONDecoder().decode(ReadyBriefWire.self, from: data) else {
            return nil
        }
        return canonical.proposal(for: brief.id)
    }

    private func cyPostNotes(
        response: String,
        sourceBrief: CreativeBrief,
        proposal: BriefProposal
    ) -> String {
        func cleaned(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func bulletList(_ values: [String]) -> String {
            values.map(cleaned).filter { !$0.isEmpty }.map { "• \($0)" }.joined(separator: "\n")
        }

        var sections: [String] = []
        let thoughtNotes = cleaned(sourceBrief.notes).isEmpty ? cleaned(response) : cleaned(sourceBrief.notes)
        if !thoughtNotes.isEmpty {
            sections.append("Thought notes\n\(thoughtNotes)")
        }

        if let filming = proposal.canonicalBrief?.filmingGuidance {
            let shots = bulletList(filming.shots)
            if !shots.isEmpty {
                sections.append("Shot list\n\(shots)")
            }

            var videoParts: [String] = []
            let setup = cleaned(filming.setup)
            if !setup.isEmpty { videoParts.append("Setup: \(setup)") }
            let bRoll = bulletList(filming.bRoll)
            if !bRoll.isEmpty { videoParts.append("B-roll:\n\(bRoll)") }
            let delivery = cleaned(filming.delivery)
            if !delivery.isEmpty { videoParts.append("Delivery: \(delivery)") }
            let editing = cleaned(filming.editing)
            if !editing.isEmpty { videoParts.append("Editing: \(editing)") }
            let audio = cleaned(filming.audio)
            if !audio.isEmpty { videoParts.append("Audio: \(audio)") }
            let onScreenText = bulletList(filming.onScreenText)
            if !onScreenText.isEmpty { videoParts.append("On-screen text:\n\(onScreenText)") }
            if !videoParts.isEmpty {
                sections.append("Video notes\n\(videoParts.joined(separator: "\n"))")
            }
        } else {
            let filming = cleaned(proposal.draft.filmingGuidance)
            let editing = cleaned(proposal.draft.editingGuidance)
            let videoNotes = [filming, editing].filter { !$0.isEmpty }.joined(separator: "\n")
            if !videoNotes.isEmpty {
                sections.append("Video notes\n\(videoNotes)")
            }
        }

        return sections.joined(separator: "\n\n")
    }

    @discardableResult
    func beginPostDraft(
        pillarID: UUID?,
        platform: CreatorPlatform,
        destinationID: UUID? = nil,
        formatID: UUID? = nil,
        socialAccountID: UUID? = nil,
        durationSeconds: Int,
        targetDate: Date?,
        includesTargetTime: Bool = false,
        context: ModelContext
    ) -> (brief: CreativeBrief, output: PlatformOutput)? {
        guard can(.createSpark, context: context) else { return nil }

        let normalizedDuration = platform.format.durationOptions.contains(durationSeconds)
            ? durationSeconds
            : platform.format.defaultDuration
        let brief = CreativeBrief(title: "", premise: "", source: .text, status: .spark)
        let workspaceID = brief.workspaceID ?? resolvedWorkspaceID(context: context)
        brief.workspaceID = workspaceID
        brief.ideaBankPlacement = .post
        brief.pillarID = pillarID
        brief.durationSeconds = normalizedDuration
        brief.agendaDate = targetDate
        context.insert(brief)

        let catalogIDs = PublishingCatalog.identifiers(for: platform)
        let resolvedDestinationID = destinationID ?? catalogIDs.destination
        let output = PlatformOutput(
            briefID: brief.id,
            platform: platform,
            destinationID: resolvedDestinationID,
            formatID: formatID ?? catalogIDs.format,
            socialAccountID: socialAccountID ?? preferredSocialAccountID(
                for: resolvedDestinationID,
                context: context
            ),
            durationSeconds: normalizedDuration,
            status: .draft
        )
        output.workspaceID = workspaceID
        output.targetDate = targetDate
        output.includesTargetTime = targetDate != nil && includesTargetTime
        context.insert(output)

        do {
            try context.save()
            queueCalendarSync(context: context)
            return (brief, output)
        } catch {
            context.delete(output)
            context.delete(brief)
            notice = .error("That draft could not be started.")
            return nil
        }
    }

    @discardableResult
    func duplicatePostDraft(
        brief: CreativeBrief,
        output: PlatformOutput,
        context: ModelContext
    ) -> (brief: CreativeBrief, output: PlatformOutput)? {
        guard can(.createSpark, context: context),
              PostDraftResumePolicy.shouldResume(
                briefStatus: brief.status,
                outputStatus: output.status
              ) else { return nil }

        let now = Date()
        let cleanTitle = brief.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let copy = CreativeBrief(
            title: cleanTitle.isEmpty ? "Untitled post copy" : "\(cleanTitle) copy",
            premise: brief.premise,
            source: brief.source,
            status: .spark,
            createdAt: now
        )
        copy.workspaceID = brief.workspaceID ?? resolvedWorkspaceID(context: context)
        copy.ideaBankPlacement = .post
        copy.customStatusLabel = brief.resolvedCustomStatusLabel
        copy.notes = brief.notes
        copy.scriptEnabled = brief.scriptEnabled
        copy.audience = brief.audience
        copy.creativeGoal = brief.creativeGoal
        copy.takeaway = brief.takeaway
        copy.durationSeconds = brief.durationSeconds
        copy.spokenHook = brief.spokenHook
        copy.firstFrameText = brief.firstFrameText
        copy.scriptBeatsText = brief.scriptBeatsText
        copy.close = brief.close
        copy.ctaIntent = brief.ctaIntent
        copy.filmingGuidance = brief.filmingGuidance
        copy.editingGuidance = brief.editingGuidance
        copy.assumptionsText = brief.assumptionsText
        copy.voiceConfidence = brief.voiceConfidence
        copy.readyBriefPayloadJSON = brief.readyBriefPayloadJSON
        copy.pillarID = brief.pillarID
        copy.isBrandCollaboration = brief.isBrandCollaboration
        copy.brandName = brief.brandName
        copy.compensationType = brief.compensationType
        copy.compensationAmount = brief.compensationAmount
        copy.compensationCurrencyCode = brief.compensationCurrencyCode
        copy.brandHasNetTerms = brief.brandHasNetTerms
        copy.brandNetTermsDays = brief.brandNetTermsDays
        copy.giftedProductDescription = brief.giftedProductDescription
        copy.giftedEstimatedValue = brief.giftedEstimatedValue
        copy.promoCode = brief.promoCode
        copy.promoLinkString = brief.promoLinkString
        copy.moodBoardEnabled = brief.moodBoardEnabled
        copy.moodBoardURLString = brief.moodBoardURLString
        copy.workDate = brief.workDate
        copy.includesWorkTime = brief.includesWorkTime
        copy.agendaDate = brief.agendaDate
        context.insert(copy)

        let outputCopy = PlatformOutput(
            briefID: copy.id,
            platform: output.platform,
            destinationID: output.destinationID,
            formatID: output.formatID,
            socialAccountID: output.socialAccountID,
            durationSeconds: output.durationSeconds,
            status: .draft,
            createdAt: now
        )
        outputCopy.workspaceID = copy.workspaceID
        outputCopy.caption = output.caption
        outputCopy.openingAdjustment = output.openingAdjustment
        outputCopy.titleOverride = output.titleOverride
        outputCopy.cta = output.cta
        outputCopy.editChanges = output.editChanges
        outputCopy.targetDate = output.targetDate
        outputCopy.seriesName = output.seriesName
        outputCopy.recurrence = output.recurrence
        outputCopy.recurrenceWeekdays = output.recurrenceWeekdays
        outputCopy.recurrenceMonthDay = output.recurrenceMonthDay
        outputCopy.recurrenceEndDate = output.recurrenceEndDate
        outputCopy.includesTargetTime = output.includesTargetTime
        outputCopy.publishedURLString = ""
        context.insert(outputCopy)

        let sourceBriefID = brief.id
        let sourceTasks = (try? context.fetch(FetchDescriptor<CreatorTask>(
            predicate: #Predicate { $0.briefID == sourceBriefID },
            sortBy: [SortDescriptor(\CreatorTask.sortOrder)]
        ))) ?? []
        var taskCopiesBySourceID: [UUID: CreatorTask] = [:]
        for task in sourceTasks {
            let taskCopy = CreatorTask(
                briefID: copy.id,
                pillarID: task.pillarID,
                platformOutputID: task.platformOutputID == output.id ? outputCopy.id : nil,
                title: task.title,
                kind: task.kind,
                lane: task.lane,
                priority: task.priority,
                notes: task.notes,
                estimatedMinutes: task.estimatedMinutes,
                targetDate: task.targetDate,
                includesTargetTime: task.includesTargetTime,
                dailyFocusDate: task.dailyFocusDate,
                dailyFocusTitle: task.dailyFocusTitle,
                dailyFocusTemplateEntryID: task.dailyFocusTemplateEntryID,
                sortOrder: task.sortOrder,
                isRecordingMilestoneDesignated: task.isRecordingMilestoneDesignated,
                createdAt: now
            )
            taskCopy.workspaceID = copy.workspaceID
            taskCopiesBySourceID[task.id] = taskCopy
            context.insert(taskCopy)
        }
        for task in sourceTasks {
            guard let parentID = task.parentTaskID,
                  let taskCopy = taskCopiesBySourceID[task.id] else { continue }
            taskCopy.parentTaskID = taskCopiesBySourceID[parentID]?.id
        }

        let sourceAttachments = (try? context.fetch(FetchDescriptor<CreatorAttachment>(
            predicate: #Predicate { $0.briefID == sourceBriefID },
            sortBy: [SortDescriptor(\CreatorAttachment.createdAt)]
        ))) ?? []
        var attachmentCopiesBySourceID: [UUID: CreatorAttachment] = [:]
        for attachment in sourceAttachments {
            let attachmentCopy = CreatorAttachment(
                ownerKind: attachment.ownerKind,
                briefID: copy.id,
                platformOutputID: attachment.platformOutputID == output.id ? outputCopy.id : nil,
                fileName: attachment.fileName,
                kind: attachment.kind,
                uniformTypeIdentifier: attachment.uniformTypeIdentifier,
                byteCount: attachment.byteCount,
                localRelativePath: attachment.localRelativePath,
                cloudData: attachment.cloudData,
                previewData: attachment.previewData,
                isCoverOnly: attachment.isCoverOnly,
                syncState: attachment.syncState,
                createdAt: now
            )
            attachmentCopy.workspaceID = copy.workspaceID
            attachmentCopiesBySourceID[attachment.id] = attachmentCopy
            context.insert(attachmentCopy)
        }
        if let coverAttachmentID = output.coverAttachmentID {
            outputCopy.coverAttachmentID = attachmentCopiesBySourceID[coverAttachmentID]?.id
        }

        do {
            try context.save()
            return (copy, outputCopy)
        } catch {
            context.delete(outputCopy)
            context.delete(copy)
            notice = .error("That post could not be duplicated.")
            return nil
        }
    }

    @discardableResult
    func movePostToIdeaBank(
        brief: CreativeBrief,
        output: PlatformOutput,
        showsNotice: Bool = true,
        context: ModelContext
    ) -> Bool {
        guard brief.status != .archived, output.briefID == brief.id else { return false }

        let briefID = brief.id
        let linkedOutputs = (try? context.fetch(FetchDescriptor<PlatformOutput>(
            predicate: #Predicate { $0.briefID == briefID }
        ))) ?? [output]

        guard brief.status != .posted,
              !linkedOutputs.contains(where: { $0.status == .posted }) else {
            notice = .info("Posted work stays in your post history.")
            return false
        }

        let linkedTasks = (try? context.fetch(FetchDescriptor<CreatorTask>(
            predicate: #Predicate { $0.briefID == briefID }
        ))) ?? []
        let now = Date()
        brief.status = .spark
        brief.customStatusLabel = nil
        brief.ideaBankPlacement = .idea
        brief.workDate = nil
        brief.includesWorkTime = false
        brief.agendaDate = nil
        brief.archivedAt = nil
        brief.updatedAt = now
        brief.appendLifecycleStatus(.spark, at: now)

        for linkedOutput in linkedOutputs {
            linkedOutput.status = .draft
            linkedOutput.targetDate = nil
            linkedOutput.includesTargetTime = false
            linkedOutput.recurrence = .none
            linkedOutput.recurrenceWeekdays = []
            linkedOutput.recurrenceMonthDay = nil
            linkedOutput.recurrenceEndDate = nil
            linkedOutput.postedAt = nil
        }
        linkedTasks.forEach(context.delete)

        do {
            try context.save()
            if showsNotice {
                notice = .info("Moved to your Idea Bank.")
            }
            queueCalendarSync(context: context)
            return true
        } catch {
            context.rollback()
            notice = .error("That post could not be moved to your Idea Bank.")
            return false
        }
    }

    @discardableResult
    func movePostDraftToIdeaBank(
        brief: CreativeBrief,
        output: PlatformOutput,
        context: ModelContext
    ) -> Bool {
        movePostToIdeaBank(brief: brief, output: output, context: context)
    }

    @discardableResult
    func createPost(
        title: String,
        notes: String,
        pillarID: UUID?,
        platform: CreatorPlatform,
        destinationID: UUID? = nil,
        formatID: UUID? = nil,
        socialAccountID: UUID? = nil,
        durationSeconds: Int,
        targetDate: Date?,
        includesTargetTime: Bool = false,
        context: ModelContext
    ) -> CreativeBrief? {
        guard can(.createSpark, context: context) else { return nil }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            notice = .error("Name the post before saving it.")
            return nil
        }

        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let brief = CreativeBrief(
            title: cleanTitle,
            premise: cleanNotes,
            source: .text,
            status: .spark
        )
        let workspaceID = resolvedWorkspaceID(context: context)
        brief.workspaceID = workspaceID
        brief.ideaBankPlacement = .post
        brief.notes = cleanNotes
        brief.pillarID = pillarID
        brief.durationSeconds = platform.format.durationOptions.contains(durationSeconds)
            ? durationSeconds
            : platform.format.defaultDuration
        brief.agendaDate = targetDate
        context.insert(brief)

        let catalogIDs = PublishingCatalog.identifiers(for: platform)
        let output = PlatformOutput(
            briefID: brief.id,
            platform: platform,
            destinationID: destinationID ?? catalogIDs.destination,
            formatID: formatID ?? catalogIDs.format,
            socialAccountID: socialAccountID ?? preferredSocialAccountID(
                for: destinationID ?? catalogIDs.destination,
                context: context
            ),
            durationSeconds: durationSeconds,
            status: .draft
        )
        output.workspaceID = workspaceID
        output.targetDate = targetDate
        output.includesTargetTime = targetDate != nil && includesTargetTime
        context.insert(output)

        do {
            try context.save()
            queueCalendarSync(context: context)
            return brief
        } catch {
            notice = .error("That post could not be saved.")
            return nil
        }
    }

    @discardableResult
    func plan(_ brief: CreativeBrief, on date: Date, context: ModelContext) -> Bool {
        guard can(.schedule, context: context), brief.status != .archived else { return false }
        brief.agendaDate = date
        brief.updatedAt = Date()
        do {
            try context.save()
            return true
        } catch {
            notice = .error("That content could not be added to \(date.formatted(.dateTime.weekday())).")
            return false
        }
    }

    @discardableResult
    func createTask(title: String, kind: CreatorTaskKind, lane: TaskLane = .pillar, priority: TaskPriority = .none, targetDate: Date?, includesTargetTime: Bool = false, focusAssignment: DailyFocusTaskAssignment? = nil, recurrence: TaskRecurrenceFrequency = .none, briefID: UUID? = nil, pillarID: UUID? = nil, platformOutputID: UUID? = nil, sourceConversationMessageID: UUID? = nil, context: ModelContext) -> CreatorTask? {
        guard can(.createTask, context: context) else { return nil }
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            notice = .error("Give the task a clear next action.")
            return nil
        }
        let linkedBrief = briefID.flatMap { brief(id: $0, context: context) }
        let resolvedTargetDate = PostTaskReschedulePolicy.resolvedDueDate(
            requestedDate: targetDate,
            includesTime: includesTargetTime,
            briefID: briefID,
            outputID: platformOutputID,
            workDate: linkedBrief?.workDate,
            outputs: (try? context.fetch(FetchDescriptor<PlatformOutput>())) ?? []
        )
        let task = CreatorTask(
            briefID: briefID,
            pillarID: pillarID,
            platformOutputID: platformOutputID,
            sourceConversationMessageID: sourceConversationMessageID,
            title: cleaned,
            kind: focusAssignment?.taskKind ?? kind,
            lane: focusAssignment == nil ? lane : .production,
            priority: priority.normalized,
            targetDate: resolvedTargetDate,
            includesTargetTime: includesTargetTime,
            dailyFocusDate: focusAssignment?.date,
            dailyFocusTitle: focusAssignment?.title,
            dailyFocusTemplateEntryID: focusAssignment?.templateEntryID,
            recurrence: recurrence
        )
        task.workspaceID = resolvedWorkspaceID(context: context)
        if recurrence != .none { task.recurrenceRootTaskID = task.id }
        context.insert(task)
        do {
            try context.save()
        } catch {
            notice = .error("That task could not be created.")
            return nil
        }
        queueCalendarSync(context: context)
        return task
    }

    @discardableResult
    func createLinkedPostTask(
        title: String,
        notes: String,
        priority: TaskPriority,
        targetDate: Date?,
        includesTargetTime: Bool,
        recurrence: TaskRecurrenceFrequency,
        briefID: UUID,
        outputID: UUID,
        subtasks: [TaskCreationSubtaskDraft],
        context: ModelContext
    ) -> CreatorTask? {
        guard can(.createTask, context: context) else { return nil }
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else {
            notice = .error("Give the task a clear next action.")
            return nil
        }
        guard recurrence == .none || targetDate != nil else {
            notice = .info("Choose a due date for a repeating task.")
            return nil
        }

        do {
            let workspaces = try context.fetch(FetchDescriptor<CreatorWorkspace>())
            let activeWorkspaceID = WorkspaceScope.activeWorkspaceID(
                preferredID: self.activeWorkspaceID,
                workspaces: workspaces
            )
            let matchingBriefs = try context.fetch(FetchDescriptor<CreativeBrief>(
                predicate: #Predicate { $0.id == briefID }
            ))
            let matchingOutputs = try context.fetch(FetchDescriptor<PlatformOutput>(
                predicate: #Predicate { $0.id == outputID }
            ))
            guard matchingBriefs.count == 1,
                  matchingOutputs.count == 1,
                  let brief = matchingBriefs.first,
                  let output = matchingOutputs.first,
                  output.briefID == brief.id,
                  output.status == .scheduled,
                  output.targetDate != nil,
                  brief.status != .archived,
                  WorkspaceScope.includes(
                    brief.workspaceID,
                    activeWorkspaceID: activeWorkspaceID,
                    workspaces: workspaces
                  ),
                  WorkspaceScope.includes(
                    output.workspaceID,
                    activeWorkspaceID: activeWorkspaceID,
                    workspaces: workspaces
                  ) else {
                notice = .info("That scheduled post is no longer available in this workspace.")
                return nil
            }

            let task = CreatorTask(
                briefID: brief.id,
                pillarID: brief.pillarID,
                platformOutputID: output.id,
                title: cleanedTitle,
                kind: .planning,
                lane: .production,
                priority: priority.normalized,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                targetDate: targetDate,
                includesTargetTime: targetDate != nil && includesTargetTime,
                recurrence: recurrence
            )
            task.workspaceID = activeWorkspaceID
            if recurrence != .none {
                task.recurrenceRootTaskID = task.id
            }
            context.insert(task)

            let completedAt = Date()
            let cleanedSubtasks = subtasks.compactMap { draft -> TaskCreationSubtaskDraft? in
                let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }
                return TaskCreationSubtaskDraft(title: title, isCompleted: draft.isCompleted)
            }
            for (index, draft) in cleanedSubtasks.enumerated() {
                let subtask = CreatorTask(
                    briefID: brief.id,
                    pillarID: brief.pillarID,
                    platformOutputID: output.id,
                    parentTaskID: task.id,
                    title: draft.title,
                    kind: task.kind,
                    lane: task.lane,
                    priority: task.priority,
                    sortOrder: index
                )
                subtask.workspaceID = activeWorkspaceID
                if draft.isCompleted {
                    subtask.isCompleted = true
                    subtask.completedAt = completedAt
                }
                context.insert(subtask)
            }

            try context.save()
            queueCalendarSync(context: context)
            return task
        } catch {
            context.rollback()
            notice = .error("Couldn’t save this task. Nothing was added.")
            return nil
        }
    }

    @discardableResult
    func createSubtask(
        title: String,
        parent: CreatorTask,
        context: ModelContext
    ) -> CreatorTask? {
        guard can(.createTask, context: context), parent.parentTaskID == nil else { return nil }
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            notice = .error("Name the subtask before adding it.")
            return nil
        }
        let siblings = subtasks(for: parent, context: context)
        let subtask = CreatorTask(
            briefID: parent.briefID,
            pillarID: parent.pillarID,
            platformOutputID: parent.platformOutputID,
            parentTaskID: parent.id,
            title: cleaned,
            kind: parent.kind,
            lane: parent.lane,
            priority: parent.priority,
            dailyFocusDate: parent.dailyFocusDate,
            dailyFocusTitle: parent.dailyFocusTitle,
            dailyFocusTemplateEntryID: parent.dailyFocusTemplateEntryID,
            sortOrder: siblings.count
        )
        subtask.workspaceID = parent.workspaceID ?? resolvedWorkspaceID(context: context)
        context.insert(subtask)
        try? context.save()
        return subtask
    }

    func findIdeas(context: ModelContext) async -> [IdeaDirection] {
        switch await findIdeaSuggestions(context: context) {
        case .success(let ideas):
            return ideas
        case .unavailable(let message, _):
            notice = .error(message)
            return []
        case .cancelled:
            return []
        }
    }

    func findIdeaSuggestions(context: ModelContext) async -> IdeaSuggestionOutcome {
        let localConnected = LocalCyPreferences.isEnabledAndConnected
        let state = subscriptionState(context)
        guard localConnected || state == nil || AccessPolicy.allows(.ideate, state: state) else {
            return .unavailable(
                message: state == nil
                    ? "Cy is offline. Open Claude or Codex on your Mac, or open Access in Settings to use hosted Agent Cy."
                    : "Your three free idea sessions have been used.",
                requiresUpgrade: state != nil
            )
        }
        guard let profile = fetchOne(CreatorProfile.self, context: context) else {
            return .unavailable(
                message: "Finish your creator profile before asking Cy for ideas.",
                requiresUpgrade: false
            )
        }
        isWorking = true
        defer { isWorking = false }
        do {
            guard let creatorContext = creatorContextWire(profile: profile, context: context) else {
                throw CreativeServiceError.invalidLiveResponse("the approved creator context is incomplete")
            }
            let execution = try await creativeService.findIdeasExecution(
                context: creatorContext,
                mode: profile.assistanceMode
            )
            if execution.provider == .hosted, let state {
                let previousUsage = state.ideationRequestsUsed
                state.ideationRequestsUsed += 1
                state.updatedAt = Date()
                do {
                    try context.save()
                } catch {
                    state.ideationRequestsUsed = previousUsage
                    throw error
                }
            } else {
                try context.save()
            }
            return .success(execution.value)
        } catch is CancellationError {
            Logger(subsystem: "com.agentcy.app", category: "cy-ideas")
                .error("findIdeaSuggestions cancelled (CancellationError) — task torn down mid-flight")
            return .cancelled
        } catch let error as URLError where error.code == .cancelled {
            Logger(subsystem: "com.agentcy.app", category: "cy-ideas")
                .error("findIdeaSuggestions cancelled (URLError.cancelled) — session task cancelled")
            return .cancelled
        } catch {
            // Field diagnosis needs the true failure, which the friendly
            // notice intentionally hides. No creator content is logged.
            Logger(subsystem: "com.agentcy.app", category: "cy-ideas")
                .error("findIdeaSuggestions failed: \(String(describing: error), privacy: .public)")
            let requiresUpgrade = ideaSuggestionsRequireUpgrade(for: error)
            return .unavailable(
                message: requiresUpgrade
                    ? "You’ve reached your included Cy ideas. Upgrade to Pro to keep generating personalized ideas."
                    : error.localizedDescription,
                requiresUpgrade: requiresUpgrade
            )
        }
    }

    private func ideaSuggestionsRequireUpgrade(for error: Error) -> Bool {
        guard let apiError = error as? AgentCyAPIError,
              case .server(let serverError) = apiError else { return false }
        return serverError.requiresSubscriptionUpgrade
    }

    @discardableResult
    func sendDialogueTurn(
        brief: CreativeBrief,
        answer: String,
        postContext: String? = nil,
        context: ModelContext
    ) async -> Bool {
        guard !isWorking else { return false }
        guard await canUseCy(.sparkDialogue, context: context) else { return false }
        guard !isWorking else { return false }
        let cleaned = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }
        let thread = developmentThread(for: brief, context: context)
        guard thread.turnCount < 8 else {
            notice = .info("You’ve reached eight turns. Build the post now or edit the idea yourself.")
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            guard let profile = fetchOne(CreatorProfile.self, context: context),
                  let creatorContext = creatorContextWire(profile: profile, context: context) else {
                throw CreativeServiceError.invalidLiveResponse("the approved creator context is incomplete")
            }
            var conversation = conversationWire(messages(for: thread, context: context))
            conversation.append(
                ConversationMessageWire(
                    messageId: UUID(),
                    role: .user,
                    content: cleaned
                )
            )
            let execution = try await creativeService.nextQuestionExecution(
                for: brief,
                turn: thread.turnCount,
                answer: cleaned,
                mode: profile.assistanceMode,
                context: creatorContext,
                conversation: conversation,
                postContext: postContext
            )
            try Task.checkCancellation()
            let response = execution.value
            context.insert(ConversationMessage(threadID: thread.id, role: .creator, text: cleaned))
            context.insert(ConversationMessage(threadID: thread.id, role: .cy, text: response))
            BriefLifecycle.beginDevelopment(brief)
            thread.turnCount += 1
            thread.updatedAt = Date()
            try context.save()
            return true
        } catch is CancellationError {
            return false
        } catch let error as URLError where error.code == .cancelled {
            return false
        } catch {
            presentCreatorError(error, action: "Cy")
            return false
        }
    }

    @discardableResult
    func compose(brief: CreativeBrief, context: ModelContext) async -> Bool {
        guard !isWorking else { return false }
        guard await canUseCy(.compose, context: context) else { return false }
        guard !isWorking else { return false }
        guard let profile = fetchOne(CreatorProfile.self, context: context) else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            guard let creatorContext = creatorContextWire(profile: profile, context: context) else {
                throw CreativeServiceError.invalidLiveResponse("the approved creator context is incomplete")
            }
            let thread = developmentThread(for: brief, context: context)
            let conversation = conversationWire(messages(for: thread, context: context))
            let execution = try await creativeService.composeProposalExecution(
                from: brief,
                mode: profile.assistanceMode,
                context: creatorContext,
                conversation: conversation
            )
            try Task.checkCancellation()
            var proposal = execution.value
            let sourceTitle = brief.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sourceTitle.isEmpty {
                proposal.draft.title = sourceTitle
            }
            try persist(proposal: proposal, context: context)
            BriefLifecycle.beginDevelopment(brief)
            try context.save()
            briefProposals[brief.id] = proposal
            if execution.provider == .hosted,
               let state = subscriptionState(context),
               state.access == .freeJourney {
                let wasConsumed = state.freeBriefConsumed
                state.freeBriefConsumed = true
                state.updatedAt = Date()
                do {
                    try context.save()
                } catch {
                    state.freeBriefConsumed = wasConsumed
                    throw error
                }
            }
            return true
        } catch is CancellationError {
            return false
        } catch let error as URLError where error.code == .cancelled {
            return false
        } catch {
            presentCreatorError(error, action: "The post")
            return false
        }
    }

    @discardableResult
    func acceptProposal(_ proposal: BriefProposal, for brief: CreativeBrief, context: ModelContext) -> Bool {
        guard let staged = self.proposal(for: brief, context: context),
              staged.id == proposal.id,
              proposal.briefID == brief.id else {
            notice = .error("This post is no longer the proposal waiting for review.")
            return false
        }
        guard !proposal.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            notice = .info("Name the post before accepting it.")
            return false
        }
        guard proposal.tasks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            notice = .info("Name every proposed task before accepting the post.")
            return false
        }
        let milestones = proposal.tasks.filter(\.isRecordingMilestone)
        guard milestones.count <= 1, milestones.allSatisfy({ $0.kind == .filming }) else {
            notice = .error("Choose at most one filming task as the recording milestone.")
            return false
        }
        guard Set(proposal.variants.map(\.platform)).count == proposal.variants.count else {
            notice = .error("Each platform can appear only once in a post proposal.")
            return false
        }

        do {
            apply(proposal.draft, to: brief)

            let existingOutputs = outputs(for: brief, context: context)
            for variant in proposal.variants {
                if let output = existingOutputs.first(where: { $0.platform == variant.platform }) {
                    if output.status == .draft || output.status == .ready {
                        apply(variant, to: output)
                    }
                } else {
                    let output = PlatformOutput(briefID: brief.id, platform: variant.platform, status: .ready)
                    output.workspaceID = brief.workspaceID ?? resolvedWorkspaceID(context: context)
                    apply(variant, to: output)
                    context.insert(output)
                }
            }

            let existingTasks = tasks(for: brief, context: context)
            for (index, proposed) in proposal.tasks.enumerated() where !existingTasks.contains(where: { $0.title == proposed.title && $0.kind == proposed.kind }) {
                let task = CreatorTask(
                    briefID: brief.id,
                    title: proposed.title,
                    kind: proposed.kind,
                    notes: proposed.notes,
                    estimatedMinutes: proposed.estimatedMinutes,
                    sortOrder: existingTasks.count + index,
                    isRecordingMilestoneDesignated: proposed.isRecordingMilestone
                )
                task.workspaceID = brief.workspaceID ?? resolvedWorkspaceID(context: context)
                context.insert(task)
            }

            let accepted = localProposal(for: brief, context: context)
            let canonical = (proposal.canonicalBrief ?? fallbackReadyBrief(from: accepted)).overlaying(accepted)
            brief.readyBriefPayloadJSON = try encodeJSONString(canonical)
            try deletePendingProposals(for: brief.id, kind: "composition", context: context)
            try context.save()
            briefProposals.removeValue(forKey: brief.id)
            return true
        } catch {
            context.rollback()
            presentCreatorError(error, action: "The post review")
            return false
        }
    }

    @discardableResult
    func discardProposal(for brief: CreativeBrief, context: ModelContext) -> Bool {
        do {
            try deletePendingProposals(for: brief.id, kind: "composition", context: context)
            try context.save()
            briefProposals.removeValue(forKey: brief.id)
            return true
        } catch {
            context.rollback()
            presentCreatorError(error, action: "The post review")
            return false
        }
    }

    func proposal(for brief: CreativeBrief, context: ModelContext) -> BriefProposal? {
        if let proposal = briefProposals[brief.id] { return proposal }
        let briefID = brief.id
        let descriptor = FetchDescriptor<PendingBriefProposal>(
            predicate: #Predicate { $0.briefID == briefID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let record = (try? context.fetch(descriptor))?.first(where: { $0.proposalKindRaw == "composition" }),
              let data = record.payloadJSON.data(using: .utf8),
              let proposal = try? JSONDecoder().decode(BriefProposal.self, from: data),
              proposal.briefID == brief.id else {
            return nil
        }
        return proposal
    }

    func requestRevision(
        for brief: CreativeBrief,
        scope: BriefRevisionFieldWire,
        instruction: String,
        context: ModelContext
    ) async {
        guard await canUseCy(.revise, context: context) else { return }
        guard proposal(for: brief, context: context) == nil else {
            notice = .info("Review or discard the current post proposal before asking for a revision.")
            return
        }
        guard revisionProposal(for: brief, context: context) == nil else {
            notice = .info("A revision proposal is already waiting for your review.")
            return
        }
        let cleaned = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            notice = .info("Tell Cy what should change before preparing a revision.")
            return
        }
        guard let profile = fetchOne(CreatorProfile.self, context: context),
              let creatorContext = creatorContextWire(profile: profile, context: context),
              let state = subscriptionState(context) else {
            notice = .error("Add the missing profile details to continue.")
            return
        }

        let baseline = localProposal(for: brief, context: context)
        let canonical = canonicalReadyBrief(for: brief, baseline: baseline)
        let sourceTasks = tasks(for: brief, context: context)
        let sourceUpdatedAt = brief.updatedAt
        isWorking = true
        defer { isWorking = false }
        do {
            let execution = try await creativeService.proposeRevisionExecution(
                of: canonical,
                localBriefID: brief.id,
                revisionNumber: state.revisionRequestsUsed + 1,
                scope: scope,
                instruction: cleaned,
                mode: profile.assistanceMode,
                context: creatorContext,
                baseline: baseline,
                sourceUpdatedAt: sourceUpdatedAt,
                sourceTaskIDs: sourceTasks.map(\.id)
            )
            let revision = execution.value
            guard revision.briefID == brief.id,
                  revision.sourceUpdatedAt == sourceUpdatedAt,
                  revision.requestedScope == scope,
                  revision.changedFields.contains(scope),
                  revision.edited != revision.baseline else {
                throw CreativeServiceError.invalidLiveResponse("the revision proposal failed local integrity checks")
            }
            try persist(revision: revision, context: context)
            if execution.provider == .hosted {
                let previousUsage = state.revisionRequestsUsed
                state.revisionRequestsUsed += 1
                state.updatedAt = Date()
                do {
                    try context.save()
                } catch {
                    state.revisionRequestsUsed = previousUsage
                    throw error
                }
            } else {
                try context.save()
            }
            revisionProposals[brief.id] = revision
        } catch {
            presentCreatorError(error, action: "The revision")
        }
    }

    func revisionProposal(for brief: CreativeBrief, context: ModelContext) -> BriefRevisionProposal? {
        if let proposal = revisionProposals[brief.id] { return proposal }
        let briefID = brief.id
        let descriptor = FetchDescriptor<PendingBriefProposal>(
            predicate: #Predicate { $0.briefID == briefID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let record = (try? context.fetch(descriptor))?.first(where: { $0.proposalKindRaw == "revision" }),
              let data = record.payloadJSON.data(using: .utf8),
              let proposal = try? JSONDecoder().decode(BriefRevisionProposal.self, from: data),
              proposal.briefID == brief.id else {
            return nil
        }
        return proposal
    }

    @discardableResult
    func acceptRevision(_ proposal: BriefRevisionProposal, for brief: CreativeBrief, context: ModelContext) -> Bool {
        guard let staged = revisionProposal(for: brief, context: context), staged.id == proposal.id else {
            notice = .error("This revision is no longer the proposal waiting for review.")
            return false
        }
        guard brief.updatedAt == proposal.sourceUpdatedAt else {
            notice = .info("The post changed after this revision was prepared. Keep your current post, discard this proposal, and ask Cy again if you still want help.")
            return false
        }
        let currentAccepted = localProposal(for: brief, context: context)
        guard currentAccepted.draft == proposal.baseline.draft,
              currentAccepted.variants == proposal.baseline.variants,
              currentAccepted.tasks == proposal.baseline.tasks else {
            notice = .info("The post changed after this revision was prepared. Keep your current edits, discard this proposal, and ask Cy again if you still want help.")
            return false
        }
        let milestones = proposal.edited.tasks.filter(\.isRecordingMilestone)
        guard milestones.count <= 1, milestones.allSatisfy({ $0.kind == .filming }) else {
            notice = .error("Choose at most one filming task as the recording milestone.")
            return false
        }
        guard !proposal.edited.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              proposal.edited.tasks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            notice = .info("Name the post and every proposed task before accepting the revision.")
            return false
        }
        guard Set(proposal.edited.variants.map(\.platform)).count == proposal.edited.variants.count else {
            notice = .error("Each platform can appear only once in a post proposal.")
            return false
        }

        do {
            let priorStatus = brief.status
            let priorArchivedAt = brief.archivedAt
            apply(proposal.edited.draft, to: brief)
            brief.status = priorStatus
            brief.archivedAt = priorArchivedAt

            let existingOutputs = outputs(for: brief, context: context)
            for variant in proposal.edited.variants {
                if let output = existingOutputs.first(where: { $0.platform == variant.platform }) {
                    apply(variant, to: output)
                } else {
                    let output = PlatformOutput(briefID: brief.id, platform: variant.platform, status: .ready)
                    output.workspaceID = brief.workspaceID ?? resolvedWorkspaceID(context: context)
                    apply(variant, to: output)
                    context.insert(output)
                }
            }
            reconcileTasks(for: brief, proposal: proposal, context: context)

            brief.readyBriefPayloadJSON = try encodeJSONString(proposal.canonicalBrief.overlaying(proposal.edited))
            try deletePendingProposals(for: brief.id, kind: "revision", context: context)
            try context.save()
            revisionProposals.removeValue(forKey: brief.id)
            return true
        } catch {
            context.rollback()
            presentCreatorError(error, action: "The revision")
            return false
        }
    }

    @discardableResult
    func discardRevision(for brief: CreativeBrief, context: ModelContext) -> Bool {
        do {
            try deletePendingProposals(for: brief.id, kind: "revision", context: context)
            try context.save()
            revisionProposals.removeValue(forKey: brief.id)
            return true
        } catch {
            context.rollback()
            presentCreatorError(error, action: "The revision")
            return false
        }
    }

    func requestTeachCy(instruction: String, context: ModelContext) async {
        guard await canUseCy(.teachCy, context: context) else { return }
        guard voiceProfileProposal(context: context) == nil else {
            notice = .info("A voice-profile proposal is already waiting for your review.")
            return
        }
        let cleaned = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            notice = .info("Teach Cy needs one specific instruction from you.")
            return
        }
        guard let creator = fetchOne(CreatorProfile.self, context: context),
              let profile = approvedVoiceProfile(context: context),
              let currentWire = voiceProfileWire(profile),
              let creatorContext = creatorContextWire(profile: creator, context: context, includeDormantVoiceData: true),
              let state = subscriptionState(context) else {
            notice = .error("The approved voice profile is incomplete.")
            return
        }
        let current = VoiceProfileDraft(currentWire)
        isWorking = true
        defer { isWorking = false }
        do {
            let execution = try await creativeService.proposeVoiceProfileChangeExecution(
                profileID: profile.profileID,
                sourceVersion: profile.version,
                sourceUpdatedAt: profile.updatedAt,
                current: current,
                instruction: cleaned,
                mode: creator.assistanceMode,
                context: creatorContext
            )
            let proposal = execution.value
            guard proposal.profileID == profile.profileID,
                  proposal.sourceVersion == profile.version,
                  proposal.sourceUpdatedAt == profile.updatedAt,
                  proposal.edited != proposal.baseline else {
                throw CreativeServiceError.invalidLiveResponse("Teach Cy did not produce a valid profile change")
            }
            try persist(voiceProposal: proposal, context: context)
            if execution.provider == .hosted {
                let previousUsage = state.teachCyUpdatesUsed
                state.teachCyUpdatesUsed += 1
                state.updatedAt = Date()
                do {
                    try context.save()
                } catch {
                    state.teachCyUpdatesUsed = previousUsage
                    throw error
                }
            } else {
                try context.save()
            }
            voiceProfileChangeProposal = proposal
        } catch {
            presentCreatorError(error, action: "Cy")
        }
    }

    func voiceProfileProposal(context: ModelContext) -> VoiceProfileChangeProposal? {
        if let voiceProfileChangeProposal { return voiceProfileChangeProposal }
        let descriptor = FetchDescriptor<PendingVoiceProfileProposal>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        guard let record = try? context.fetch(descriptor).first(where: { $0.proposalKindRaw == "teach" }),
              let data = record.payloadJSON.data(using: .utf8),
              let proposal = try? JSONDecoder().decode(VoiceProfileChangeProposal.self, from: data) else {
            return nil
        }
        return proposal
    }

    func acceptVoiceProfileChange(_ proposal: VoiceProfileChangeProposal, context: ModelContext) {
        guard let staged = voiceProfileProposal(context: context), staged.id == proposal.id,
              let current = approvedVoiceProfile(context: context),
              current.profileID == proposal.profileID,
              current.version == proposal.sourceVersion,
              current.updatedAt == proposal.sourceUpdatedAt else {
            notice = .info("The approved voice profile changed after this proposal was generated. Keep the current profile and teach Cy again if needed.")
            return
        }
        guard validVoiceDraft(proposal.edited), proposal.edited != proposal.baseline else {
            notice = .error("The proposed voice profile needs a visible, valid change before it can be accepted.")
            return
        }
        let profiles = (try? context.fetch(FetchDescriptor<VoiceProfile>())) ?? []
        let related = profiles.filter { $0.profileID == proposal.profileID }
        related.forEach { $0.isApproved = false }
        do {
            let nextVersion = (related.map(\.version).max() ?? 0) + 1
            let wire = proposal.edited.wire
            let newProfile = VoiceProfile(
                profileID: proposal.profileID,
                summary: wire.summary,
                traitsText: (wire.tone + wire.signatureQualities).joined(separator: ", "),
                avoidText: wire.phrasesToAvoid.joined(separator: ", "),
                isApproved: true,
                version: nextVersion,
                canonicalPayloadJSON: try encodeJSONString(wire),
                evidenceFingerprint: VoiceExampleFingerprint.make(from: ((try? context.fetch(FetchDescriptor<VoiceExample>())) ?? []).filter {
                    $0.profileID == proposal.profileID && $0.creatorConfirmed && !$0.text.isEmpty
                })
            )
            context.insert(newProfile)
            try deletePendingVoiceProposals(context: context)
            try context.save()
            voiceProfileChangeProposal = nil
        } catch {
            current.isApproved = true
            presentCreatorError(error, action: "The voice profile")
        }
    }

    func discardVoiceProfileChange(context: ModelContext) {
        do {
            try deletePendingVoiceProposals(context: context)
            try context.save()
            voiceProfileChangeProposal = nil
        } catch {
            presentCreatorError(error, action: "The voice profile")
        }
    }

    func approvedVoiceProfile(context: ModelContext) -> VoiceProfile? {
        ((try? context.fetch(FetchDescriptor<VoiceProfile>())) ?? [])
            .filter(\.isApproved)
            .sorted {
                if $0.version == $1.version { return $0.updatedAt > $1.updatedAt }
                return $0.version > $1.version
            }
            .first
    }

    func allows(_ action: AccessAction, context: ModelContext) -> Bool {
        AccessPolicy.allows(action, state: subscriptionState(context))
    }

    func approve(brief: CreativeBrief, context: ModelContext) {
        BriefLifecycle.approve(brief)
        if let profile = fetchOne(CreatorProfile.self, context: context), !profile.onboardingCompleted {
            profile.onboardingCompleted = true
        }
        try? context.save()
        queueCalendarSync(context: context)
    }

    func noteManualDevelopment(of brief: CreativeBrief, context: ModelContext) {
        guard brief.status == .spark else { return }
        BriefLifecycle.beginDevelopment(brief)
        try? context.save()
    }

    @discardableResult
    func markPostDraft(
        brief: CreativeBrief,
        output: PlatformOutput,
        context: ModelContext
    ) -> Bool {
        guard brief.status != .archived, output.briefID == brief.id else { return false }

        let now = Date()
        brief.customStatusLabel = nil
        brief.ideaBankPlacement = .post
        output.status = .draft
        output.postedAt = nil

        let siblingOutputs = outputs(for: brief, context: context).filter { $0.id != output.id }
        let nextBriefStatus: BriefStatus
        if siblingOutputs.contains(where: { $0.status == .posted }) {
            nextBriefStatus = .posted
        } else if siblingOutputs.contains(where: { $0.status == .scheduled }) {
            nextBriefStatus = .scheduled
        } else {
            nextBriefStatus = .ready
        }
        if brief.status != nextBriefStatus {
            brief.status = nextBriefStatus
            brief.appendLifecycleStatus(nextBriefStatus, at: now)
        }
        brief.updatedAt = now

        do {
            try context.save()
            queueCalendarSync(context: context)
            notice = .info("Status changed to Draft.")
            return true
        } catch {
            context.rollback()
            notice = .error("That post could not be changed to Draft.")
            return false
        }
    }

    @discardableResult
    func markPostInProgress(
        brief: CreativeBrief,
        output: PlatformOutput,
        date: Date,
        context: ModelContext
    ) -> Bool {
        guard can(.schedule, context: context) else { return false }
        guard brief.status != .archived,
              output.briefID == brief.id,
              output.status != .posted else {
            notice = .info("Posted work must be marked not posted before it can be In progress.")
            return false
        }

        let workDate = RecurringPostSchedule.normalizedTargetDate(
            date,
            includesTime: brief.includesWorkTime
        )
        brief.customStatusLabel = nil
        brief.ideaBankPlacement = .post
        let previousWorkDate = brief.workDate
        if brief.status != .developing {
            brief.status = .developing
            brief.appendLifecycleStatus(.developing, at: Date())
        }
        output.status = .draft
        brief.workDate = workDate
        brief.updatedAt = Date()
        rescheduleLinkedTasks(
            for: output,
            from: previousWorkDate ?? output.targetDate,
            to: workDate,
            context: context
        )

        do {
            try context.save()
            queueCalendarSync(context: context)
            notice = .info("Marked In progress.")
            return true
        } catch {
            context.rollback()
            notice = .error("That post could not be added to your agenda.")
            return false
        }
    }

    @discardableResult
    func schedule(
        output: PlatformOutput,
        date: Date?,
        includesTargetTime requestedIncludesTargetTime: Bool? = nil,
        context: ModelContext
    ) -> Bool {
        guard can(.schedule, context: context) else { return false }
        guard let brief = brief(id: output.briefID, context: context) else {
            notice = .error("That post is no longer available.")
            return false
        }
        let includesTargetTime = date != nil && (requestedIncludesTargetTime ?? output.includesTargetTime)
        let resolvedDate = date
        let previousDate = output.targetDate
        brief.ideaBankPlacement = .post
        if [.spark, .developing].contains(brief.status), output.status == .draft {
            rescheduleLinkedTasks(
                for: output,
                from: previousDate,
                to: resolvedDate,
                context: context
            )
            output.targetDate = resolvedDate
            output.includesTargetTime = includesTargetTime
            brief.agendaDate = outputs(for: brief, context: context).compactMap(\.targetDate).min()
            brief.updatedAt = Date()
            do {
                try context.save()
                queueCalendarSync(context: context)
                return true
            } catch {
                context.rollback()
                notice = .error("That new date could not be saved.")
                return false
            }
        }
        brief.customStatusLabel = nil
        guard BriefLifecycle.schedule(output, for: resolvedDate, brief: brief) else {
            notice = .info("Finish this post before adding tasks or a posting date.")
            return false
        }
        output.includesTargetTime = includesTargetTime
        rescheduleLinkedTasks(
            for: output,
            from: previousDate,
            to: resolvedDate,
            context: context
        )
        let linkedOutputs = outputs(for: brief, context: context)
        BriefLifecycle.synchronize(brief, outputs: linkedOutputs)
        brief.agendaDate = linkedOutputs.compactMap(\.targetDate).min()
        brief.updatedAt = Date()
        do {
            try context.save()
            queueCalendarSync(context: context)
            return true
        } catch {
            context.rollback()
            notice = .error("That new date could not be saved.")
            return false
        }
    }

    /// Updates planning dates without changing the post's workflow status.
    /// Work is the preferred task day; the scheduled date is the fallback.
    @discardableResult
    func updatePostPlanDates(
        brief: CreativeBrief,
        output: PlatformOutput,
        workDate: Date?,
        includesWorkTime: Bool,
        scheduledDate: Date?,
        includesScheduledTime: Bool,
        context: ModelContext
    ) -> Bool {
        guard brief.status != .archived,
              output.briefID == brief.id,
              output.status != .posted else {
            notice = .info("Posted work keeps its planning dates.")
            return false
        }
        guard PostDatePlanPolicy.isChronologicallyValid(
            workDate: workDate,
            scheduledDate: scheduledDate
        ) else {
            notice = .info("Choose a scheduled date on or after the work date.")
            return false
        }

        brief.workDate = workDate
        brief.includesWorkTime = workDate != nil && includesWorkTime
        output.targetDate = scheduledDate
        output.includesTargetTime = scheduledDate != nil && includesScheduledTime

        let scheduledDates = outputs(for: brief, context: context)
            .compactMap(\.targetDate)
            .sorted()
        brief.agendaDate = scheduledDates.first
        brief.updatedAt = Date()

        let allTasks = (try? context.fetch(FetchDescriptor<CreatorTask>())) ?? []
        if let preferredDate = PostDatePlanPolicy.preferredTaskDate(
            workDate: workDate,
            scheduledDate: scheduledDate
        ) {
            PostTaskReschedulePolicy.alignOpenTasks(
                allTasks,
                to: output,
                on: preferredDate
            )
        } else {
            PostTaskReschedulePolicy.clearOpenTaskDates(allTasks, for: output)
        }

        do {
            try context.save()
            queueCalendarSync(context: context)
            return true
        } catch {
            context.rollback()
            notice = .error("Those planning dates could not be saved.")
            return false
        }
    }

    @discardableResult
    func clearPostDate(
        output: PlatformOutput,
        context: ModelContext
    ) -> Bool {
        guard let brief = brief(id: output.briefID, context: context) else {
            notice = .error("That post is no longer available.")
            return false
        }
        return clearPostDate(brief: brief, output: output, context: context)
    }

    @discardableResult
    func clearPostDate(
        brief: CreativeBrief,
        output: PlatformOutput,
        context: ModelContext
    ) -> Bool {
        guard brief.status != .archived,
              output.briefID == brief.id,
              output.status != .posted else {
            notice = .info("Posted work keeps its posting date.")
            return false
        }

        let linkedTasks = tasksLinked(to: output, context: context)
        if let workDate = brief.workDate {
            PostTaskReschedulePolicy.alignOpenTasks(
                linkedTasks,
                to: output,
                on: workDate
            )
        } else {
            PostTaskReschedulePolicy.clearOpenTaskDates(linkedTasks, for: output)
        }
        output.targetDate = nil
        output.includesTargetTime = false
        output.recurrence = .none
        output.recurrenceWeekdays = []
        output.recurrenceMonthDay = nil
        output.recurrenceEndDate = nil
        if output.status == .scheduled {
            output.status = .ready
        }

        let remainingDates = outputs(for: brief, context: context)
            .filter { $0.id != output.id }
            .compactMap(\.targetDate)
            .sorted()
        brief.agendaDate = remainingDates.first
        BriefLifecycle.synchronize(brief, outputs: outputs(for: brief, context: context))
        brief.updatedAt = Date()

        do {
            try context.save()
            queueCalendarSync(context: context)
            notice = .info("Date cleared.")
            return true
        } catch {
            context.rollback()
            notice = .error("That date could not be cleared.")
            return false
        }
    }

    @discardableResult
    func scheduleSinglePost(output: PlatformOutput, date: Date, context: ModelContext) -> Bool {
        output.recurrence = .none
        output.recurrenceWeekdays = []
        output.recurrenceMonthDay = nil
        output.recurrenceEndDate = nil
        output.seriesRootOutputID = nil
        return schedulePostSeries(output: output, date: date, context: context)
    }

    @discardableResult
    func schedulePostSeries(output: PlatformOutput, date: Date, context: ModelContext) -> Bool {
        guard can(.schedule, context: context) else { return false }
        guard let brief = brief(id: output.briefID, context: context) else {
            notice = .error("That post is no longer available.")
            return false
        }

        let scheduledDate = RecurringPostSchedule.normalizedTargetDate(
            date,
            includesTime: output.includesTargetTime
        )
        brief.customStatusLabel = nil
        brief.ideaBankPlacement = .post
        let previousDate = output.targetDate
        if brief.status == .spark || brief.status == .developing {
            BriefLifecycle.approve(brief)
            if let profile = fetchOne(CreatorProfile.self, context: context), !profile.onboardingCompleted {
                profile.onboardingCompleted = true
            }
        }
        guard BriefLifecycle.schedule(output, for: scheduledDate, brief: brief) else {
            notice = .info("Finish this post before scheduling it.")
            return false
        }
        rescheduleLinkedTasks(
            for: output,
            from: previousDate,
            to: scheduledDate,
            context: context
        )
        brief.agendaDate = scheduledDate
        BriefLifecycle.synchronize(brief, outputs: outputs(for: brief, context: context))
        // Recurrence is retained as legacy metadata until existing series are
        // migrated, but scheduling never materializes future posts. Future
        // planning is represented by SeriesEpisodeSlot records instead.
        output.seriesRootOutputID = nil

        do {
            try context.save()
            queueCalendarSync(context: context)
            return output.status == .scheduled
        } catch {
            context.rollback()
            presentCreatorError(error, action: "The post")
            return false
        }
    }

    func togglePosted(output: PlatformOutput, postedAt: Date = Date(), context: ModelContext) {
        guard can(.updatePosting, context: context) else { return }
        guard let brief = brief(id: output.briefID, context: context),
              BriefLifecycle.togglePosted(output, brief: brief, postedAt: postedAt) else {
            notice = .info("Finish this post before updating its posting progress.")
            return
        }
        brief.customStatusLabel = nil
        BriefLifecycle.synchronize(brief, outputs: outputs(for: brief, context: context))
        try? context.save()
        queueCalendarSync(context: context)
    }

    @discardableResult
    func applyCustomPostStatus(
        _ rawValue: String,
        to brief: CreativeBrief,
        output: PlatformOutput,
        context: ModelContext
    ) -> Bool {
        guard brief.status != .archived,
              output.briefID == brief.id,
              output.status != .posted,
              let status = CustomPostStatusPolicy.normalized(rawValue) else {
            notice = .info("That custom status could not be applied.")
            return false
        }

        let workspaceID = resolvedWorkspaceID(context: context)
        let workspace = ((try? context.fetch(FetchDescriptor<CreatorWorkspace>())) ?? [])
            .first { $0.id == workspaceID && !$0.isArchived }
        if let workspace {
            _ = workspace.rememberCustomPostStatus(status)
        }

        let now = Date()
        brief.customStatusLabel = status
        brief.ideaBankPlacement = .post
        if brief.status != .developing {
            brief.status = .developing
            brief.appendLifecycleStatus(.developing, at: now)
        }
        output.status = .draft
        output.postedAt = nil
        brief.updatedAt = now

        do {
            try context.save()
            queueCalendarSync(context: context)
            notice = .info("Status changed to \(status).")
            return true
        } catch {
            context.rollback()
            notice = .error("That custom status could not be saved.")
            return false
        }
    }

    @discardableResult
    func deleteCustomPostStatus(
        _ rawValue: String,
        context: ModelContext
    ) -> Bool {
        guard let status = CustomPostStatusPolicy.normalized(rawValue),
              let workspaceID = resolvedWorkspaceID(context: context) else {
            notice = .info("That custom status could not be deleted.")
            return false
        }

        let workspaces = (try? context.fetch(FetchDescriptor<CreatorWorkspace>())) ?? []
        guard let workspace = workspaces.first(where: {
            $0.id == workspaceID && !$0.isArchived
        }),
        workspace.forgetCustomPostStatus(status) != nil else {
            notice = .info("That custom status is no longer available.")
            return false
        }

        let briefs = ((try? context.fetch(FetchDescriptor<CreativeBrief>())) ?? []).filter {
            WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: workspaceID,
                workspaces: workspaces
            ) &&
            $0.resolvedCustomStatusLabel?.localizedCaseInsensitiveCompare(status) == .orderedSame
        }
        let now = Date()

        for brief in briefs {
            brief.customStatusLabel = nil
            guard brief.status != .archived, brief.status != .posted else { continue }

            if brief.status != .developing {
                brief.status = .developing
                brief.appendLifecycleStatus(.developing, at: now)
            }
            brief.ideaBankPlacement = .post
            brief.updatedAt = now

            for output in outputs(for: brief, context: context) where output.status != .posted {
                output.status = .draft
                output.postedAt = nil
            }
        }

        do {
            try context.save()
            queueCalendarSync(context: context)
            if briefs.isEmpty {
                notice = .info("\(status) was deleted.")
            } else {
                let noun = briefs.count == 1 ? "post" : "posts"
                notice = .info("\(status) was deleted. \(briefs.count) \(noun) moved to In progress.")
            }
            return true
        } catch {
            context.rollback()
            notice = .error("That custom status could not be deleted.")
            return false
        }
    }

    @discardableResult
    func toggleTask(_ task: CreatorTask, context: ModelContext) -> Bool {
        guard !task.isSkipped else { return false }
        let wasCompleted = task.isCompleted
        let previousRecordingMilestones = recordingMilestones
        let linkedBrief = task.briefID.flatMap { brief(id: $0, context: context) }
        if task.briefID != nil, linkedBrief == nil || linkedBrief?.status == .archived {
            notice = .info("This task belongs to content that is no longer active.")
            return false
        }
        let previousMilestoneExists: Bool
        if let briefID = task.briefID {
            let descriptor = FetchDescriptor<CreatorTask>(predicate: #Predicate { $0.briefID == briefID })
            previousMilestoneExists = ((try? context.fetch(descriptor)) ?? []).contains { $0.id != task.id && $0.recordingMilestoneEmitted }
        } else {
            previousMilestoneExists = true
        }
        if BriefLifecycle.toggleTask(task, brief: linkedBrief), !previousMilestoneExists {
            recordingMilestones += 1
            notice = .info("Recording marked complete. The post stays in its current status until it is posted.")
        } else if previousMilestoneExists && task.recordingMilestoneEmitted {
            task.recordingMilestoneEmitted = false
        }
        do {
            var generatedTaskID: UUID?
            if task.isCompleted {
                generatedTaskID = try RecurringTaskMaterializer.createNextOccurrence(
                    after: task,
                    context: context
                )?.id
            }
            try context.save()
            queueCalendarSync(context: context)
            if !wasCompleted, task.isCompleted {
                presentTaskCompletionUndo(for: task, generatedTaskID: generatedTaskID)
            } else if wasCompleted, !task.isCompleted, taskCompletionUndo?.taskID == task.id {
                clearTaskCompletionUndo()
            }
            return true
        } catch {
            context.rollback()
            recordingMilestones = previousRecordingMilestones
            notice = .error("That task could not be updated.")
            return false
        }
    }

    func undoLastTaskCompletion(context: ModelContext) {
        guard let undo = taskCompletionUndo else { return }
        do {
            let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
            guard let task = tasks.first(where: { $0.id == undo.taskID }) else {
                clearTaskCompletionUndo()
                return
            }
            if task.isCompleted {
                let linkedBrief = task.briefID.flatMap { brief(id: $0, context: context) }
                _ = BriefLifecycle.toggleTask(task, brief: linkedBrief)
                if task.isRecordingMilestoneDesignated {
                    task.recordingMilestoneEmitted = false
                }
            }
            if let generatedTaskID = undo.generatedTaskID,
               let generated = tasks.first(where: { $0.id == generatedTaskID }) {
                let generatedSubtasks = tasks.filter { $0.parentTaskID == generated.id }
                generatedSubtasks.forEach(context.delete)
                context.delete(generated)
            }
            try context.save()
            clearTaskCompletionUndo()
            queueCalendarSync(context: context)
        } catch {
            notice = .error("That task completion could not be undone.")
        }
    }

    private func presentTaskCompletionUndo(
        for task: CreatorTask,
        generatedTaskID: UUID?
    ) {
        taskCompletionUndoDismissTask?.cancel()
        let undo = TaskCompletionUndoState(
            taskID: task.id,
            taskTitle: task.title,
            generatedTaskID: generatedTaskID
        )
        taskCompletionUndo = undo
        taskCompletionUndoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, self?.taskCompletionUndo == undo else { return }
            self?.taskCompletionUndo = nil
        }
    }

    private func clearTaskCompletionUndo() {
        taskCompletionUndoDismissTask?.cancel()
        taskCompletionUndoDismissTask = nil
        taskCompletionUndo = nil
    }

    @discardableResult
    func moveTaskToToday(_ task: CreatorTask, context: ModelContext, now: Date = Date()) -> Bool {
        guard !task.isCompleted, !task.isSkipped else { return false }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        if task.includesTargetTime, let currentTarget = task.targetDate {
            let time = calendar.dateComponents([.hour, .minute, .second], from: currentTarget)
            var components = calendar.dateComponents([.year, .month, .day], from: today)
            components.hour = time.hour
            components.minute = time.minute
            components.second = time.second
            task.targetDate = calendar.date(from: components) ?? today
        } else {
            task.targetDate = today
        }
        if task.dailyFocusDate != nil {
            task.dailyFocusDate = today
        }
        if task.focusTaskTemplateID != nil {
            task.isFocusTemplateCustomized = true
        }
        do {
            try context.save()
            queueCalendarSync(context: context)
            return true
        } catch {
            context.rollback()
            notice = .error("That task could not be moved.")
            return false
        }
    }

    @discardableResult
    func skipTask(_ task: CreatorTask, context: ModelContext, now: Date = Date()) -> Bool {
        guard !task.isCompleted, !task.isSkipped else { return false }
        task.isSkipped = true
        task.skippedAt = now
        do {
            try context.save()
            queueCalendarSync(context: context)
            return true
        } catch {
            task.isSkipped = false
            task.skippedAt = nil
            notice = .error("That task could not be skipped.")
            return false
        }
    }

    func applyPendingWidgetTaskCompletions(
        context: ModelContext,
        defaults: UserDefaults? = UserDefaults(suiteName: AgentCyWidgetShared.appGroupIdentifier),
        refreshWidgets: Bool = true
    ) {
        do {
            let actions = try WidgetTaskCompletionActionStore.pending(defaults: defaults)
            guard !actions.isEmpty else { return }

            let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
            let briefs = try context.fetch(FetchDescriptor<CreativeBrief>())
            let taskByID = DuplicateSafeIndex.firstValues(tasks.map { ($0.id, $0) })
            let briefByID = DuplicateSafeIndex.firstValues(briefs.map { ($0.id, $0) })
            var acknowledged: [WidgetTaskCompletionAction] = []

            for action in actions {
                guard let task = taskByID[action.taskID] else {
                    acknowledged.append(action)
                    continue
                }
                guard !task.isSkipped else {
                    acknowledged.append(action)
                    continue
                }
                guard task.isCompleted != action.isCompleted else {
                    acknowledged.append(action)
                    continue
                }

                let linkedBrief = task.briefID.flatMap { briefByID[$0] }
                if task.briefID != nil, linkedBrief == nil || linkedBrief?.status == .archived {
                    acknowledged.append(action)
                    continue
                }

                let previousMilestoneExists: Bool
                if let briefID = task.briefID {
                    previousMilestoneExists = tasks.contains {
                        $0.id != task.id && $0.briefID == briefID && $0.recordingMilestoneEmitted
                    }
                } else {
                    previousMilestoneExists = true
                }

                _ = BriefLifecycle.toggleTask(task, brief: linkedBrief)
                if previousMilestoneExists && task.recordingMilestoneEmitted {
                    task.recordingMilestoneEmitted = false
                }
                if task.isCompleted {
                    try RecurringTaskMaterializer.createNextOccurrence(after: task, context: context)
                }
                acknowledged.append(action)
            }

            try context.save()
            try WidgetTaskCompletionActionStore.remove(acknowledged, defaults: defaults)
            if refreshWidgets {
                queueCalendarSync(context: context)
            }
        } catch {
            notice = .error("That widget task could not be updated yet. Open agent.cy and try once more.")
        }
    }

    func archive(_ brief: CreativeBrief, context: ModelContext) {
        BriefLifecycle.archive(brief)
        try? context.save()
        queueCalendarSync(context: context)
    }

    @discardableResult
    func deletePost(
        brief: CreativeBrief,
        output: PlatformOutput,
        scope: PostDeletionScope,
        context: ModelContext
    ) -> Bool {
        guard can(.editExisting, context: context), output.briefID == brief.id else { return false }

        do {
            let allOutputs = try context.fetch(FetchDescriptor<PlatformOutput>())
            let selectedOutputs = PostSeriesDeletionPolicy.outputsToDelete(
                selected: output,
                from: allOutputs,
                scope: scope
            )
            let briefIDs = Set(selectedOutputs.map(\.briefID))
            let outputIDs = Set(allOutputs.lazy.filter { briefIDs.contains($0.briefID) }.map(\.id))

            let allTasks = try context.fetch(FetchDescriptor<CreatorTask>())
            allTasks
                .filter {
                    $0.briefID.map(briefIDs.contains) == true ||
                        $0.platformOutputID.map(outputIDs.contains) == true
                }
                .forEach(context.delete)

            let allAttachments = try context.fetch(FetchDescriptor<CreatorAttachment>())
            allAttachments
                .filter {
                    briefIDs.contains($0.briefID) ||
                        $0.platformOutputID.map(outputIDs.contains) == true
                }
                .forEach(context.delete)

            let proposals = try context.fetch(FetchDescriptor<PendingBriefProposal>())
            proposals.filter { briefIDs.contains($0.briefID) }.forEach(context.delete)

            let threads = try context.fetch(FetchDescriptor<ConversationThread>())
                .filter { $0.briefID.map(briefIDs.contains) == true }
            let threadIDs = Set(threads.map(\.id))
            let messages = try context.fetch(FetchDescriptor<ConversationMessage>())
                .filter { threadIDs.contains($0.threadID) }
            messages.forEach(context.delete)
            threads.forEach(context.delete)

            allOutputs.filter { outputIDs.contains($0.id) }.forEach(context.delete)
            let allBriefs = try context.fetch(FetchDescriptor<CreativeBrief>())
            allBriefs.filter { briefIDs.contains($0.id) }.forEach(context.delete)
            try context.save()

            for briefID in briefIDs {
                briefProposals.removeValue(forKey: briefID)
                revisionProposals.removeValue(forKey: briefID)
            }
            notice = .info(briefIDs.count == 1 ? "Post deleted." : "Future series posts deleted.")
            queueCalendarSync(context: context)
            return true
        } catch {
            context.rollback()
            notice = .error("That post could not be deleted.")
            return false
        }
    }

    @discardableResult
    func deleteDraft(_ brief: CreativeBrief, context: ModelContext) -> Bool {
        let briefID = brief.id
        do {
            let outputs = try context.fetch(FetchDescriptor<PlatformOutput>(
                predicate: #Predicate { $0.briefID == briefID }
            ))
            guard PostDraftDeletionPolicy.canDelete(
                briefStatus: brief.status,
                outputStatuses: outputs.map(\.status)
            ) else {
                notice = .info("Only draft posts can be deleted here.")
                return false
            }
            let tasks = try context.fetch(FetchDescriptor<CreatorTask>(
                predicate: #Predicate { $0.briefID == briefID }
            ))
            let attachments = try context.fetch(FetchDescriptor<CreatorAttachment>(
                predicate: #Predicate { $0.briefID == briefID }
            ))
            let proposals = try context.fetch(FetchDescriptor<PendingBriefProposal>(
                predicate: #Predicate { $0.briefID == briefID }
            ))
            let threads = try context.fetch(FetchDescriptor<ConversationThread>(
                predicate: #Predicate { $0.briefID == briefID }
            ))
            let threadIDs = Set(threads.map(\.id))
            let messages = try context.fetch(FetchDescriptor<ConversationMessage>())
                .filter { threadIDs.contains($0.threadID) }

            messages.forEach(context.delete)
            threads.forEach(context.delete)
            proposals.forEach(context.delete)
            attachments.forEach(context.delete)
            tasks.forEach(context.delete)
            outputs.forEach(context.delete)
            context.delete(brief)
            try context.save()

            briefProposals.removeValue(forKey: briefID)
            revisionProposals.removeValue(forKey: briefID)
            queueCalendarSync(context: context)
            return true
        } catch {
            context.rollback()
            notice = .error("That draft could not be deleted.")
            return false
        }
    }

    func replan(task: CreatorTask, choice: ReplanChoice, context: ModelContext) {
        switch choice {
        case .move:
            task.targetDate = Calendar.current.date(byAdding: .day, value: 1, to: task.targetDate ?? Date())
        case .pause:
            task.targetDate = nil
        case .archive:
            deleteTask(task, context: context)
            return
        }
        try? context.save()
        queueCalendarSync(context: context)
    }

    @discardableResult
    func deleteTask(_ task: CreatorTask, context: ModelContext) -> Bool {
        subtasks(for: task, context: context).forEach(context.delete)
        context.delete(task)
        do {
            try context.save()
            queueCalendarSync(context: context)
            return true
        } catch {
            context.rollback()
            notice = .error("That task could not be deleted.")
            return false
        }
    }

    func removeLegacySimplifyPrefixes(context: ModelContext) {
        let tasks = (try? context.fetch(FetchDescriptor<CreatorTask>())) ?? []
        var changed = false
        for task in tasks where task.title.hasPrefix("Simplify: ") {
            task.title = String(task.title.dropFirst("Simplify: ".count))
            changed = true
        }
        if changed { try? context.save() }
    }

    func replan(output: PlatformOutput, choice: ReplanChoice, context: ModelContext) {
        guard let brief = brief(id: output.briefID, context: context), brief.status != .archived else {
            notice = .info("That content is no longer active.")
            return
        }
        let previousDate = output.targetDate
        if output.status == .draft, [.spark, .developing].contains(brief.status) {
            switch choice {
            case .move:
                output.targetDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            case .pause:
                output.targetDate = nil
            case .archive:
                BriefLifecycle.archive(brief)
            }
            if choice == .move {
                rescheduleLinkedTasks(
                    for: output,
                    from: previousDate,
                    to: output.targetDate,
                    context: context
                )
            }
            if brief.agendaDate == nil || brief.agendaDate == previousDate {
                brief.agendaDate = output.targetDate
            }
            try? context.save()
            queueCalendarSync(context: context)
            return
        }
        guard BriefLifecycle.canPlan(brief) else {
            notice = .info("Finish this post before changing its posting date.")
            return
        }
        switch choice {
        case .move:
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            _ = BriefLifecycle.schedule(output, for: tomorrow, brief: brief)
            BriefLifecycle.synchronize(brief, outputs: outputs(for: brief, context: context))
        case .pause:
            _ = BriefLifecycle.schedule(output, for: nil, brief: brief)
            BriefLifecycle.synchronize(brief, outputs: outputs(for: brief, context: context))
        case .archive:
            BriefLifecycle.archive(brief)
        }
        if choice == .move {
            rescheduleLinkedTasks(
                for: output,
                from: previousDate,
                to: output.targetDate,
                context: context
            )
        }
        if (choice == .move || choice == .pause),
           (brief.agendaDate == nil || brief.agendaDate == previousDate) {
            brief.agendaDate = output.targetDate
        }
        try? context.save()
        queueCalendarSync(context: context)
    }

    @discardableResult
    func rescheduleLinkedTasks(
        for output: PlatformOutput,
        from previousDate: Date?,
        to newDate: Date?,
        context: ModelContext
    ) -> Int {
        let preferredDate =
            brief(id: output.briefID, context: context)?.workDate
            ?? newDate
            ?? output.targetDate
        guard let preferredDate else { return 0 }

        return PostTaskReschedulePolicy.alignOpenTasks(
            tasksLinked(to: output, context: context),
            to: output,
            on: preferredDate
        )
    }

    private func tasksLinked(
        to output: PlatformOutput,
        context: ModelContext
    ) -> [CreatorTask] {
        let outputID = output.id
        let briefID = output.briefID
        return (try? context.fetch(FetchDescriptor<CreatorTask>(
            predicate: #Predicate {
                $0.platformOutputID == outputID || $0.briefID == briefID
            }
        ))) ?? []
    }

    func createRepurposedSpark(from brief: CreativeBrief, context: ModelContext) -> CreativeBrief? {
        createSpark(text: "A new angle from \(brief.title): \(brief.takeaway)", source: .repurposedBrief, context: context)
    }

    func askCy(
        _ message: String,
        conversation: [ConversationMessageWire]? = nil,
        about brief: CreativeBrief? = nil,
        context: ModelContext
    ) async -> ChatTurnResultWire? {
        guard await canUseCy(.askCy, context: context) else { return nil }
        do {
            guard let profile = fetchOne(CreatorProfile.self, context: context),
                  let creatorContext = creatorContextWire(profile: profile, context: context) else {
                throw CreativeServiceError.invalidLiveResponse("the approved creator context is incomplete")
            }
            var resolvedConversation = conversation ?? []
            let latestMessageIsCurrent = resolvedConversation.last.map {
                $0.role == .user && $0.content.trimmingCharacters(in: .whitespacesAndNewlines) == message.trimmingCharacters(in: .whitespacesAndNewlines)
            } ?? false
            if !latestMessageIsCurrent {
                resolvedConversation.append(ConversationMessageWire(messageId: UUID(), role: .user, content: message))
            }
            resolvedConversation = Array(resolvedConversation.suffix(24))
            return try await creativeService.replyWithActions(
                to: message,
                mode: profile.assistanceMode,
                context: creatorContext,
                conversation: resolvedConversation,
                relevantBriefIDs: brief.map { [$0.id] } ?? []
            )
        } catch is CancellationError {
            return nil
        } catch {
            presentCreatorError(error, action: "The change")
            return nil
        }
    }

    func proposedPillars(context: ModelContext) -> [Pillar] {
        let workspaces = (try? context.fetch(FetchDescriptor<CreatorWorkspace>())) ?? []
        let briefs = ((try? context.fetch(FetchDescriptor<CreativeBrief>())) ?? []).filter {
            $0.status != .spark &&
                $0.status != .archived &&
                WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeWorkspaceID, workspaces: workspaces)
        }
        guard briefs.count >= 3 else { return [] }
        return Array(briefs.prefix(3)).enumerated().map { index, brief in
            let fallback = ["Practical shifts", "Behind the work", "Starting points"][index]
            let name = brief.title.split(separator: " ").prefix(3).joined(separator: " ")
            return Pillar(name: name.isEmpty ? fallback : name, detail: "A recurring pillar inferred from your posts.")
        }
    }

    func acceptPillar(_ proposal: Pillar, context: ModelContext) {
        let workspaces = (try? context.fetch(FetchDescriptor<CreatorWorkspace>())) ?? []
        let activePillarCount = ((try? context.fetch(FetchDescriptor<Pillar>())) ?? []).filter {
            !$0.isArchived &&
                WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeWorkspaceID, workspaces: workspaces)
        }.count
        guard PillarCollectionPolicy.canCreate(activeCount: activePillarCount) else {
            notice = .info("You can have up to six pillars.")
            return
        }
        let pillar = Pillar(name: proposal.name, detail: proposal.detail, colorHex: proposal.colorHex)
        pillar.workspaceID = resolvedWorkspaceID(context: context)
        context.insert(pillar)
        try? context.save()
    }

    func ensureWeek(startingAt requestedStart: Date, context: ModelContext) -> WeekPlan {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: requestedStart)?.start ?? calendar.startOfDay(for: requestedStart)
        let plans = (try? context.fetch(FetchDescriptor<WeekPlan>())) ?? []
        let workspaces = (try? context.fetch(FetchDescriptor<CreatorWorkspace>())) ?? []
        let workspaceID = resolvedWorkspaceID(context: context)
        if let current = plans.first(where: {
            calendar.isDate($0.weekStart, inSameDayAs: start) &&
                WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: workspaceID, workspaces: workspaces)
        }) { return current }
        let template = ((try? context.fetch(FetchDescriptor<RhythmTemplate>())) ?? []).first {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: workspaceID, workspaces: workspaces)
        }
        let plan = WeekPlan(weekStart: start, rhythmEntriesText: template?.entriesText ?? "")
        plan.workspaceID = resolvedWorkspaceID(context: context)
        context.insert(plan)
        try? context.save()
        return plan
    }

    func ensureCurrentWeek(context: ModelContext) -> WeekPlan {
        ensureWeek(startingAt: Date(), context: context)
    }

    func saveWeekToTemplate(_ plan: WeekPlan, context: ModelContext) {
        let workspaces = (try? context.fetch(FetchDescriptor<CreatorWorkspace>())) ?? []
        let workspaceID = resolvedWorkspaceID(context: context)
        let template = ((try? context.fetch(FetchDescriptor<RhythmTemplate>())) ?? []).first {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: workspaceID, workspaces: workspaces)
        } ?? RhythmTemplate()
        if template.modelContext == nil {
            template.workspaceID = resolvedWorkspaceID(context: context)
            context.insert(template)
        }
        template.entriesText = plan.rhythmEntriesText
        template.updatedAt = Date()
        try? context.save()
    }

    func export(context: ModelContext) {
        do {
            exportURL = try exportService.makeArchive(context: context)
        } catch {
            presentCreatorError(error, action: "The export")
        }
    }

    /// False until App Store verification ships (RevenueCat); the plan screen
    /// hides trial/restore actions rather than offering buttons that throw.
    var purchasesAvailable: Bool {
        subscriptionService.supportsPurchases
    }

    func startTrial(context: ModelContext) async {
        guard let state = subscriptionState(context) else { return }
        do {
            try await subscriptionService.startTrial(state: state)
            try? context.save()
        } catch {
            presentCreatorError(error, action: "The trial")
        }
    }

    func refreshAccess(context: ModelContext) async {
        guard let state = subscriptionState(context) else {
            notice = .error("Access state is unavailable. Existing data remains safe, but new creation is paused.")
            return
        }
        await subscriptionService.refresh(state: state)
        try? context.save()
    }

    func restorePurchases(context: ModelContext) async {
        guard let state = subscriptionState(context) else { return }
        do {
            try await subscriptionService.restore(state: state)
            try? context.save()
        } catch {
            presentCreatorError(error, action: "Purchase restoration")
        }
    }

    @discardableResult
    func saveWeeklyFocus(
        _ assignments: [PillarWeekday: [DailyFocusKind]],
        taskTemplates: [PillarWeekday: [DailyFocusTaskTemplateDefinition]]? = nil,
        context: ModelContext
    ) -> Bool {
        let workspaces = (try? context.fetch(FetchDescriptor<CreatorWorkspace>())) ?? []
        let workspaceID = resolvedWorkspaceID(context: context)
        let existing = ((try? context.fetch(FetchDescriptor<DailyFocusTemplateEntry>())) ?? []).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: workspaceID, workspaces: workspaces)
        }
        let existingByWeekday = DailyFocusTemplateIndex.canonicalByWeekday(existing)
        let now = Date()

        for weekday in PillarWeekday.mondayFirst {
            let selected = Array((assignments[weekday] ?? []).prefix(2))
            let entry = existingByWeekday[weekday]
                ?? DailyFocusTemplateEntry(weekday: weekday, kind: .custom, title: "Rest")
            if entry.modelContext == nil {
                entry.workspaceID = workspaceID
                context.insert(entry)
            }

            let previous = DailyFocusResolver.normalizedKinds(
                primary: entry.kind,
                secondary: entry.secondaryKind,
                storedTitle: entry.title
            )

            entry.weekday = weekday
            entry.kind = selected.first ?? .custom
            entry.secondaryKind = selected.count > 1 ? selected[1] : nil
            entry.title = DailyFocusKind.combinedTitle(selected)
            entry.isActive = !selected.isEmpty
            if let taskTemplates {
                let selectedSet = Set(selected)
                entry.focusTaskTemplates = (taskTemplates[weekday] ?? [])
                    .filter {
                        selectedSet.contains($0.focusKind) &&
                            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    .enumerated()
                    .map { index, definition in
                        var value = definition
                        value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        value.priority = value.priority.normalized
                        value.sortOrder = index
                        return value
                    }
            }
            if previous != selected {
                entry.note = ""
            }
            if selected.isEmpty {
                entry.note = ""
                entry.durationMinutes = nil
                entry.startMinutesFromMidnight = nil
            }
            entry.updatedAt = now
        }

        do {
            try FocusTaskRecurrenceService.reconcile(context: context, workspaceID: workspaceID)
            queueCalendarSync(context: context)
            WidgetSnapshotService.refresh(context: context)
            return true
        } catch {
            context.rollback()
            presentCreatorError(error, action: "Weekly focus")
            return false
        }
    }

    @discardableResult
    func saveDailyFocus(
        date: Date,
        scope: DailyFocusEditScope,
        selection: [DailyFocusKind],
        note: String,
        durationMinutes: Int?,
        startMinutesFromMidnight: Int?,
        context: ModelContext
    ) -> Bool {
        let calendar = Calendar.current
        guard let weekday = PillarWeekday(rawValue: calendar.component(.weekday, from: date)) else {
            notice = .error("That focus date could not be saved.")
            return false
        }
        let selected = selection.reduce(into: [DailyFocusKind]()) { result, kind in
            if result.count < 2, !result.contains(kind) { result.append(kind) }
        }
        let isRest = selected.isEmpty
        let trimmedNote = isRest ? "" : note.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDuration = isRest ? nil : durationMinutes
        let normalizedStartMinutes = isRest ? nil : startMinutesFromMidnight
        let workspaceID = resolvedWorkspaceID(context: context)
        let now = Date()

        do {
            let workspaces = try context.fetch(FetchDescriptor<CreatorWorkspace>())
            let templates = try context.fetch(FetchDescriptor<DailyFocusTemplateEntry>()).filter {
                WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: workspaceID, workspaces: workspaces)
            }
            let overrides = try context.fetch(FetchDescriptor<DailyFocusOverride>()).filter {
                WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: workspaceID, workspaces: workspaces)
            }
            switch scope {
            case .recurring:
                let entry = DailyFocusTemplateIndex.canonicalByWeekday(templates)[weekday]
                    ?? DailyFocusTemplateEntry(weekday: weekday, kind: .custom, title: "Rest")
                if entry.modelContext == nil {
                    entry.workspaceID = workspaceID
                    context.insert(entry)
                }
                entry.kind = selected.first ?? .custom
                entry.secondaryKind = selected.count > 1 ? selected[1] : nil
                entry.title = DailyFocusKind.combinedTitle(selected)
                entry.note = trimmedNote
                entry.durationMinutes = normalizedDuration
                entry.startMinutesFromMidnight = normalizedStartMinutes
                entry.isActive = !isRest
                entry.updatedAt = now

                overrides
                    .filter { calendar.isDate($0.date, inSameDayAs: date) }
                    .forEach(context.delete)
                try FocusTaskRecurrenceService.reconcile(
                    context: context,
                    workspaceID: workspaceID
                )
                queueCalendarSync(context: context)
            case .date:
                let item = DailyFocusOverrideIndex.canonical(
                    on: date,
                    from: overrides,
                    calendar: calendar
                ) ?? DailyFocusOverride(date: date)
                if item.modelContext == nil {
                    item.workspaceID = workspaceID
                    context.insert(item)
                }
                item.templateEntryID = DailyFocusTemplateIndex.canonicalByWeekday(templates)[weekday]?.id
                item.kind = selected.first ?? .custom
                item.secondaryKind = selected.count > 1 ? selected[1] : nil
                item.title = DailyFocusKind.combinedTitle(selected)
                item.note = trimmedNote
                item.durationMinutes = normalizedDuration
                item.startMinutesFromMidnight = normalizedStartMinutes
                item.isCleared = isRest
                item.updatedAt = now
                try context.save()
            }
            WidgetSnapshotService.refresh(context: context)
            return true
        } catch {
            context.rollback()
            presentCreatorError(error, action: "The focus")
            return false
        }
    }

    @discardableResult
    func resetPostsAndTasks(context: ModelContext) -> Bool {
        do {
            try contentResetService.reset(context: context)
            queueCalendarSync(context: context)
        } catch {
            presentCreatorError(error, action: "The reset")
            return false
        }

        briefProposals.removeAll()
        revisionProposals.removeAll()
        quickCaptureStartsWithIdeas = false
        quickCaptureStartsWithTask = false
        quickCaptureStartsWithPost = false
        quickCaptureTargetDate = nil
        quickCapturePillarID = nil
        quickCaptureTaskLane = nil
        quickCaptureTaskFocus = nil
        recordingMilestones = 0
        notice = .info("Posts and tasks were reset. Your pillars, profile, and settings were kept.")
        return true
    }

    @discardableResult
    func eraseAll(context: ModelContext) async -> Bool {
        let outcome = await privacyEraseCoordinator.eraseAll(
            context: context,
            currentExportURL: exportURL
        )
        _ = applyPrivacyEraseOutcome(outcome)
        if case .completed = outcome { return true }
        return false
    }

    @discardableResult
    private func applyPrivacyEraseOutcome(_ outcome: PrivacyEraseOutcome) -> Bool {
        switch outcome {
        case .notNeeded:
            return false
        case .completed(let reason, _):
            clearErasedLocalState()
            hasInstallationCredential = false
            isInstallationCredentialStatusResolved = true
            notice = .info(privacyEraseCompletionMessage(reason))
            return true
        case .paused(let reason, let deletedLocalData, let credentialPresent):
            if deletedLocalData || reason.followsLocalDeletion {
                clearErasedLocalState()
            }
            if let credentialPresent {
                hasInstallationCredential = credentialPresent
                isInstallationCredentialStatusResolved = true
            }
            notice = .error(privacyErasePauseMessage(reason))
            return true
        }
    }

    private func clearErasedLocalState() {
        exportURL = nil
        briefProposals.removeAll()
        revisionProposals.removeAll()
        voiceProfileChangeProposal = nil
    }

    private func privacyEraseCompletionMessage(_ reason: PrivacyEraseCompletionReason) -> String {
        switch reason {
        case .live:
            "Your agent.cy data was erased. A minimal record remains so the same invitation cannot be reused."
        case .resumed:
            "The interrupted erase finished successfully."
        case .localOnlyMissingService:
            "Your data on this iPhone was erased."
        case .localOnlyServerUnavailable:
            "Your data on this iPhone was erased."
        case .localOnlyMissingCredential:
            "Your data on this iPhone was erased."
        }
    }

    private func privacyErasePauseMessage(_ reason: PrivacyErasePauseReason) -> String {
        switch reason {
        case .unreadableCredential:
            "Erase paused because agent.cy could not verify this iPhone. Nothing was deleted. Try again."
        case .missingPrivacyService:
            "Erase paused because agent.cy could not finish the private account cleanup. Nothing was deleted. Try again."
        case .serverDeletionFailed:
            "Erase paused because agent.cy could not finish the private account cleanup. Your work is still here. Try again."
        case .missingCredential:
            "Erase paused because agent.cy could not verify this iPhone. Your work is still here. Restore access, then try again."
        case .localDeletionFailed:
            "Erase paused because this iPhone could not confirm that every item was removed. Try again."
        case .cleanupFailed:
            "Your content was erased, but agent.cy still has one private cleanup step to finish. It will try again safely."
        case .credentialDeletionFailed:
            "Your content was erased, but agent.cy still has one private cleanup step to finish. It will try again safely."
        }
    }

    func subscriptionState(_ context: ModelContext) -> SubscriptionState? {
        fetchOne(SubscriptionState.self, context: context)
    }

    func outputs(for brief: CreativeBrief, context: ModelContext) -> [PlatformOutput] {
        let id = brief.id
        let descriptor = FetchDescriptor<PlatformOutput>(predicate: #Predicate { $0.briefID == id }, sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func addPlatformOutput(
        to brief: CreativeBrief,
        platform: CreatorPlatform,
        context: ModelContext
    ) -> PlatformOutput? {
        guard can(.editExisting, context: context), brief.status != .archived else { return nil }
        let existing = outputs(for: brief, context: context)
        guard !existing.contains(where: { $0.platform == platform }) else {
            notice = .info("\(platform.title) is already part of this post.")
            return nil
        }
        let format: ContentFormat = existing.first?.platform.format
            ?? (brief.durationSeconds >= 300 ? .longForm : .shortForm)
        guard platform.format == format else {
            notice = .info("Choose a \(format.title.lowercased()) platform for this post.")
            return nil
        }

        let catalogIDs = PublishingCatalog.identifiers(for: platform)
        let output = PlatformOutput(
            briefID: brief.id,
            platform: platform,
            destinationID: catalogIDs.destination,
            formatID: catalogIDs.format,
            socialAccountID: preferredSocialAccountID(for: catalogIDs.destination, context: context),
            status: [.ready, .scheduled, .posted].contains(brief.status) ? .ready : .draft
        )
        output.workspaceID = brief.workspaceID ?? resolvedWorkspaceID(context: context)
        if let source = existing.first {
            output.caption = source.caption
            output.cta = source.cta
        } else {
            output.cta = brief.ctaIntent
        }
        if platform == .youtubeShorts || platform == .youtubeVideo {
            output.titleOverride = brief.title
        }
        context.insert(output)
        brief.updatedAt = Date()
        do {
            try context.save()
            return output
        } catch {
            context.delete(output)
            notice = .error("That platform could not be added.")
            return nil
        }
    }

    @discardableResult
    func addPublishingOutput(
        to brief: CreativeBrief,
        destination: PublishingDestination,
        format: PublishingFormat,
        context: ModelContext
    ) -> PlatformOutput? {
        guard can(.editExisting, context: context), brief.status != .archived else { return nil }
        let existing = outputs(for: brief, context: context)
        guard !existing.contains(where: { $0.destinationID == destination.id && $0.formatID == format.id }) else {
            notice = .info("That platform is already part of this post.")
            return nil
        }
        let legacy = PublishingCatalog.legacyPlatform(destinationID: destination.id, formatID: format.id)
            ?? (format.kind == .longVideo ? .youtubeVideo : .instagramReels)
        let output = PlatformOutput(
            briefID: brief.id,
            platform: legacy,
            destinationID: destination.id,
            formatID: format.id,
            socialAccountID: preferredSocialAccountID(for: destination.id, context: context),
            durationSeconds: format.kind.defaultDurationSeconds ?? brief.durationSeconds,
            status: [.ready, .scheduled, .posted].contains(brief.status) ? .ready : .draft
        )
        output.workspaceID = brief.workspaceID ?? resolvedWorkspaceID(context: context)
        if let source = existing.first { output.caption = source.caption; output.cta = source.cta }
        else { output.cta = brief.ctaIntent }
        output.titleOverride = brief.title
        context.insert(output)
        brief.updatedAt = Date()
        do { try context.save(); return output }
        catch { context.delete(output); notice = .error("That platform could not be added."); return nil }
    }

    func deletePlatformOutput(
        _ output: PlatformOutput,
        from brief: CreativeBrief,
        context: ModelContext
    ) {
        guard can(.editExisting, context: context),
              brief.status != .archived,
              output.briefID == brief.id else { return }

        let remaining = outputs(for: brief, context: context).filter { $0.id != output.id }
        if let removedTarget = output.targetDate, brief.agendaDate == removedTarget {
            brief.agendaDate = remaining.compactMap(\.targetDate).min()
        }
        context.delete(output)
        BriefLifecycle.synchronize(brief, outputs: remaining)
        brief.updatedAt = Date()
        do {
            try context.save()
            queueCalendarSync(context: context)
        } catch {
            notice = .error("That platform could not be deleted.")
        }
    }

    func tasks(for brief: CreativeBrief, context: ModelContext) -> [CreatorTask] {
        let id = brief.id
        let descriptor = FetchDescriptor<CreatorTask>(predicate: #Predicate { $0.briefID == id }, sortBy: [SortDescriptor(\.sortOrder)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func subtasks(for task: CreatorTask, context: ModelContext) -> [CreatorTask] {
        let parentID = task.id
        let descriptor = FetchDescriptor<CreatorTask>(
            predicate: #Predicate { $0.parentTaskID == parentID },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func messages(for thread: ConversationThread, context: ModelContext) -> [ConversationMessage] {
        let id = thread.id
        let descriptor = FetchDescriptor<ConversationMessage>(predicate: #Predicate { $0.threadID == id }, sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func developmentThread(for brief: CreativeBrief, context: ModelContext) -> ConversationThread {
        let briefID = brief.id
        let descriptor = FetchDescriptor<ConversationThread>(
            predicate: #Predicate { $0.briefID == briefID && !$0.isArchived }
        )
        if let existing = try? context.fetch(descriptor).first { return existing }
        let thread = ConversationThread(briefID: brief.id, title: "Develop \(brief.title)")
        thread.workspaceID = brief.workspaceID ?? resolvedWorkspaceID(context: context)
        context.insert(thread)
        let mode = fetchOne(CreatorProfile.self, context: context)?.assistanceMode ?? .collaborate
        switch mode {
        case .drive:
            break
        case .collaborate:
            context.insert(ConversationMessage(threadID: thread.id, role: .cy, text: "What is the one point you most want this video to make?"))
        case .lead:
            context.insert(ConversationMessage(
                threadID: thread.id,
                role: .cy,
                text: "Recommended first step: name the exact viewer and the one change you want for them. Assumption: this spark is strongest as one focused promise. What should that viewer understand or do afterward?"
            ))
        }
        try? context.save()
        return thread
    }

    /// Moves the post's current conversation into history so the next Spark
    /// opens fresh; the archived thread and its messages stay intact.
    func archiveDevelopmentThread(for brief: CreativeBrief, context: ModelContext) {
        let briefID = brief.id
        let descriptor = FetchDescriptor<ConversationThread>(
            predicate: #Predicate { $0.briefID == briefID && !$0.isArchived }
        )
        guard let thread = try? context.fetch(descriptor).first else { return }
        thread.isArchived = true
        thread.updatedAt = Date()
        do {
            try context.save()
        } catch {
            notice = .error("Couldn’t archive this conversation. Try again.")
        }
    }

    private func apply(_ draft: BriefDraft, to brief: CreativeBrief) {
        brief.title = draft.title
        brief.premise = draft.premise
        brief.audience = draft.audience
        brief.creativeGoal = draft.goal
        brief.takeaway = draft.takeaway
        brief.durationSeconds = draft.durationSeconds
        brief.spokenHook = draft.spokenHook
        brief.firstFrameText = draft.firstFrameText
        brief.scriptBeats = draft.scriptBeats
        brief.close = draft.close
        brief.ctaIntent = draft.ctaIntent
        brief.filmingGuidance = draft.filmingGuidance
        brief.editingGuidance = draft.editingGuidance
        brief.assumptions = draft.assumptions
        brief.voiceConfidence = draft.voiceConfidence
        brief.updatedAt = Date()
    }

    private func apply(_ variant: PlatformVariantDraft, to output: PlatformOutput) {
        output.caption = variant.caption
        output.openingAdjustment = variant.openingAdjustment
        output.titleOverride = variant.titleOverride
        output.cta = variant.cta
        output.editChanges = variant.editChanges
    }

    private func localProposal(for brief: CreativeBrief, context: ModelContext) -> BriefProposal {
        let storedCanonical = brief.readyBriefPayloadJSON.data(using: .utf8).flatMap { try? JSONDecoder().decode(ReadyBriefWire.self, from: $0) }
        let outputDrafts = outputs(for: brief, context: context).map { output in
            PlatformVariantDraft(
                platform: output.platform,
                caption: output.caption,
                openingAdjustment: output.openingAdjustment,
                titleOverride: output.titleOverride,
                cta: output.cta,
                editChanges: output.editChanges
            )
        }
        let variants = outputDrafts.isEmpty
            ? (storedCanonical?.platformVariants.map {
                PlatformVariantDraft(
                    platform: $0.platform,
                    caption: $0.caption ?? "",
                    openingAdjustment: $0.openingAdjustment ?? "",
                    titleOverride: $0.title ?? "",
                    cta: $0.ctaAdjustment ?? "",
                    editChanges: $0.editChanges.joined(separator: "\n")
                )
            } ?? [])
            : outputDrafts
        let taskDrafts = tasks(for: brief, context: context).map { task in
            ProposedCreatorTask(
                title: task.title,
                kind: task.kind,
                notes: task.notes,
                estimatedMinutes: task.estimatedMinutes,
                isRecordingMilestone: task.isRecordingMilestoneDesignated
            )
        }
        return BriefProposal(
            briefID: brief.id,
            draft: BriefDraft(
                title: brief.title,
                premise: brief.premise,
                audience: brief.audience,
                goal: brief.creativeGoal,
                takeaway: brief.takeaway,
                durationSeconds: brief.durationSeconds,
                spokenHook: brief.spokenHook,
                firstFrameText: brief.firstFrameText,
                scriptBeats: brief.scriptBeats,
                close: brief.close,
                ctaIntent: brief.ctaIntent,
                filmingGuidance: brief.filmingGuidance,
                editingGuidance: brief.editingGuidance,
                assumptions: brief.assumptions,
                voiceConfidence: brief.voiceConfidence
            ),
            variants: variants,
            tasks: taskDrafts,
            canonicalBrief: storedCanonical
        )
    }

    private func canonicalReadyBrief(for brief: CreativeBrief, baseline: BriefProposal) -> ReadyBriefWire {
        if let data = brief.readyBriefPayloadJSON.data(using: .utf8),
           let stored = try? JSONDecoder().decode(ReadyBriefWire.self, from: data),
           stored.briefId == brief.id {
            return stored.overlaying(baseline)
        }
        return fallbackReadyBrief(from: baseline)
    }

    private func fallbackReadyBrief(from proposal: BriefProposal) -> ReadyBriefWire {
        let fallback = ReadyBriefWire(
            briefId: proposal.briefID,
            title: proposal.draft.title,
            premise: proposal.draft.premise,
            audience: proposal.draft.audience,
            creativeGoal: proposal.draft.goal,
            desiredTakeaway: proposal.draft.takeaway,
            durationSeconds: proposal.draft.durationSeconds,
            spokenHook: proposal.draft.spokenHook,
            firstFrameText: proposal.draft.firstFrameText,
            scriptBeats: proposal.draft.scriptBeats.enumerated().map {
                ScriptBeatWire(order: $0.offset, label: "Beat \($0.offset + 1)", purpose: "Advance the idea", script: $0.element)
            },
            close: proposal.draft.close,
            ctaIntent: proposal.draft.ctaIntent,
            filmingGuidance: FilmingGuidanceWire(
                setup: proposal.draft.filmingGuidance.isEmpty ? "Use the creator’s available setup." : proposal.draft.filmingGuidance,
                shots: ["Primary talking-head take"],
                bRoll: [],
                delivery: "Use the approved voice profile.",
                editing: proposal.draft.editingGuidance.isEmpty ? "Keep the edit light." : proposal.draft.editingGuidance,
                audio: "Prioritize a clear voice recording.",
                onScreenText: [proposal.draft.firstFrameText]
            ),
            proposedTasks: [],
            assumptions: proposal.draft.assumptions,
            voiceConfidence: proposal.draft.voiceConfidence,
            platformVariants: []
        )
        return fallback.overlaying(proposal)
    }

    private func reconcileTasks(for brief: CreativeBrief, proposal: BriefRevisionProposal, context: ModelContext) {
        let existing = tasks(for: brief, context: context)
        let sourceSet = Set(proposal.sourceTaskIDs)
        let existingByID = DuplicateSafeIndex.firstValues(existing.map { ($0.id, $0) })
        var usedSourceIDs = Set<UUID>()
        let milestoneAlreadyEmitted = existing.contains(where: \.recordingMilestoneEmitted)

        for (index, proposed) in proposal.edited.tasks.enumerated() {
            let sourceTask = proposal.sourceTaskIDs.indices.contains(index) ? existingByID[proposal.sourceTaskIDs[index]] : nil
            let exactTask = existing.first {
                !usedSourceIDs.contains($0.id) && $0.title == proposed.title && $0.kind == proposed.kind
            }
            if let task = sourceTask ?? exactTask {
                usedSourceIDs.insert(task.id)
                if task.isCompleted || task.recordingMilestoneEmitted {
                    if task.title != proposed.title || task.kind != proposed.kind {
                        insertTask(proposed, for: brief, sortOrder: existing.count + index, milestoneAlreadyEmitted: milestoneAlreadyEmitted, context: context)
                    }
                } else {
                    task.title = proposed.title
                    task.kind = proposed.kind
                    task.notes = proposed.notes
                    task.estimatedMinutes = proposed.estimatedMinutes
                    task.sortOrder = index
                    task.isRecordingMilestoneDesignated = proposed.isRecordingMilestone && !milestoneAlreadyEmitted
                }
            } else {
                insertTask(proposed, for: brief, sortOrder: existing.count + index, milestoneAlreadyEmitted: milestoneAlreadyEmitted, context: context)
            }
        }

        for task in existing where sourceSet.contains(task.id) && !usedSourceIDs.contains(task.id) {
            if !task.isCompleted && !task.recordingMilestoneEmitted { context.delete(task) }
        }
    }

    private func insertTask(_ proposed: ProposedCreatorTask, for brief: CreativeBrief, sortOrder: Int, milestoneAlreadyEmitted: Bool, context: ModelContext) {
        let task = CreatorTask(
            briefID: brief.id,
            title: proposed.title,
            kind: proposed.kind,
            notes: proposed.notes,
            estimatedMinutes: proposed.estimatedMinutes,
            sortOrder: sortOrder,
            isRecordingMilestoneDesignated: proposed.isRecordingMilestone && !milestoneAlreadyEmitted
        )
        task.workspaceID = brief.workspaceID ?? resolvedWorkspaceID(context: context)
        context.insert(task)
    }

    private func persist(proposal: BriefProposal, context: ModelContext) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(proposal)
        guard let payload = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        let briefID = proposal.briefID
        let descriptor = FetchDescriptor<PendingBriefProposal>(
            predicate: #Predicate { $0.briefID == briefID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let records = try context.fetch(descriptor).filter { $0.proposalKindRaw == "composition" }
        if let existing = records.first {
            existing.payloadJSON = payload
            existing.updatedAt = Date()
            for duplicate in records.dropFirst() { context.delete(duplicate) }
        } else {
            let record = PendingBriefProposal(briefID: proposal.briefID, payloadJSON: payload, proposalKindRaw: "composition")
            record.workspaceID = resolvedWorkspaceID(context: context)
            context.insert(record)
        }
    }

    private func persist(revision: BriefRevisionProposal, context: ModelContext) throws {
        let payload = try encodeJSONString(revision)
        let briefID = revision.briefID
        let descriptor = FetchDescriptor<PendingBriefProposal>(predicate: #Predicate { $0.briefID == briefID })
        let records = try context.fetch(descriptor).filter { $0.proposalKindRaw == "revision" }
        guard records.isEmpty else { throw CreativeServiceError.invalidLiveResponse("a revision proposal is already pending") }
        let record = PendingBriefProposal(briefID: briefID, payloadJSON: payload, proposalKindRaw: "revision")
        record.workspaceID = resolvedWorkspaceID(context: context)
        context.insert(record)
    }

    private func persist(voiceProposal: VoiceProfileChangeProposal, context: ModelContext) throws {
        guard try context.fetch(FetchDescriptor<PendingVoiceProfileProposal>()).allSatisfy({ $0.proposalKindRaw != "teach" }) else {
            throw CreativeServiceError.invalidLiveResponse("a voice-profile proposal is already pending")
        }
        context.insert(PendingVoiceProfileProposal(
            profileID: voiceProposal.profileID,
            sourceVersion: voiceProposal.sourceVersion,
            payloadJSON: try encodeJSONString(voiceProposal),
            proposalKindRaw: "teach"
        ))
    }

    private func persist(initialVoiceProposal: InitialVoiceProfileProposal, context: ModelContext) throws {
        guard try context.fetch(FetchDescriptor<PendingVoiceProfileProposal>()).allSatisfy({ $0.proposalKindRaw != "initial" }) else {
            throw CreativeServiceError.invalidLiveResponse("an initial voice-profile proposal is already pending")
        }
        context.insert(PendingVoiceProfileProposal(
            profileID: initialVoiceProposal.profileID,
            sourceVersion: 0,
            payloadJSON: try encodeJSONString(initialVoiceProposal),
            proposalKindRaw: "initial"
        ))
    }

    private func deletePendingProposals(for briefID: UUID, kind: String, context: ModelContext) throws {
        let descriptor = FetchDescriptor<PendingBriefProposal>(predicate: #Predicate { $0.briefID == briefID })
        for record in try context.fetch(descriptor) where record.proposalKindRaw == kind {
            context.delete(record)
        }
    }

    private func deletePendingVoiceProposals(context: ModelContext) throws {
        for record in try context.fetch(FetchDescriptor<PendingVoiceProfileProposal>()) { context.delete(record) }
    }

    private func deletePendingVoiceProposals(kind: String, context: ModelContext) throws {
        for record in try context.fetch(FetchDescriptor<PendingVoiceProfileProposal>()) where record.proposalKindRaw == kind {
            context.delete(record)
        }
    }

    private func encodeJSONString<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func validVoiceDraft(_ draft: VoiceProfileDraft) -> Bool {
        !draft.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.tone.isEmpty &&
        !draft.sentenceStyle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.signatureQualities.isEmpty &&
        !draft.guidance.isEmpty &&
        (0...1).contains(draft.confidence)
    }

    private func normalizedExampleText(_ value: String) -> String {
        value
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }

    private func voiceEvidenceIssue(in context: CreatorContextWire) -> String? {
        guard context.voiceExamples.count >= 3 else {
            return "Add and review at least three real examples before Cy builds your voice profile."
        }
        return VoiceExampleEvidenceLimits.issue(in: context.voiceExamples)
    }

    private func can(_ action: AccessAction, context: ModelContext) -> Bool {
        guard let state = subscriptionState(context) else {
            notice = .error("Access state is unavailable. New creation is paused so the free journey cannot be reset accidentally.")
            return false
        }
        let allowed = AccessPolicy.allows(action, state: state)
        if !allowed {
            notice = .info("Your existing work is still yours to edit and finish. Start the trial to create something new or ask Cy.")
        }
        return allowed
    }

    private func canUseCy(_ action: AccessAction, context: ModelContext) async -> Bool {
        precondition(action.isCyGeneration)
        if LocalCyPreferences.isEnabledAndConnected { return true }
        guard let state = subscriptionState(context) else {
            // Let the hosted service make the authoritative entitlement
            // decision. Restored devices can briefly have no local access row.
            return true
        }
        let allowed = AccessPolicy.allows(action, state: state)
        if !allowed {
            notice = .info("Your existing work is still yours to edit and finish. Open Access to use hosted Agent Cy.")
        }
        return allowed
    }

    private func titleFromSpark(_ text: String) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).prefix(7).joined(separator: " ")
        guard let first = words.first else { return "Untitled spark" }
        return String(first).uppercased() + words.dropFirst()
    }

    private func brief(id: UUID, context: ModelContext) -> CreativeBrief? {
        let descriptor = FetchDescriptor<CreativeBrief>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func fetchOne<T: PersistentModel>(_ type: T.Type, context: ModelContext) -> T? {
        try? context.fetch(FetchDescriptor<T>()).first
    }

    private func creatorContextWire(
        profile: CreatorProfile,
        context: ModelContext,
        includeDormantVoiceData: Bool = false
    ) -> CreatorContextWire? {
        let workspaces = (try? context.fetch(FetchDescriptor<CreatorWorkspace>())) ?? []
        let workspaceID = resolvedWorkspaceID(context: context)
        let identity = ActiveCreatorIdentity.resolve(
            profile: profile,
            workspaces: workspaces,
            preferredWorkspaceID: workspaceID
        )
        let storedName = identity.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedGoal = profile.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedPlatforms = Array(Set(profile.selectedPlatforms)).sorted { $0.rawValue < $1.rawValue }

        // A newly restored device can have usable post data before every
        // optional onboarding field has finished syncing. Spark should still
        // be able to use that post and either provider in that state.
        let name = storedName.isEmpty ? "Creator" : storedName
        let goal = storedGoal.isEmpty ? "Create clear, authentic content." : storedGoal
        let selectedPlatforms = storedPlatforms.isEmpty ? [.instagramReels] : storedPlatforms

        // Voice personalization is intentionally dormant in this release.
        // Only the retained, non-UI voice contract tests and future migration path
        // opt into these records. Normal creation requests send neither value.
        let voiceExamples: [VoiceExampleWire]
        let voiceProfile: VoiceProfileWire?
        if includeDormantVoiceData {
            let storedExamples = ((try? context.fetch(FetchDescriptor<VoiceExample>(
                sortBy: [SortDescriptor(\.sortOrder)]
            ))) ?? [])
                .filter {
                    $0.profileID == profile.id &&
                        $0.creatorConfirmed &&
                        !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            voiceExamples = storedExamples.prefix(5).enumerated().map { index, example in
                VoiceExampleWire(
                    exampleId: example.id,
                    order: index,
                    text: example.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    source: example.source,
                    creatorConfirmed: true
                )
            }

            let approvedProfile = ((try? context.fetch(FetchDescriptor<VoiceProfile>())) ?? [])
                .filter { $0.profileID == profile.id && $0.isApproved }
                .sorted {
                    if $0.version == $1.version { return $0.updatedAt > $1.updatedAt }
                    return $0.version > $1.version
                }
                .first
            voiceProfile = approvedProfile.flatMap(voiceProfileWire)
        } else {
            voiceExamples = []
            voiceProfile = nil
        }

        let activePillarRecords = ((try? context.fetch(FetchDescriptor<Pillar>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [])
            .filter {
                !$0.isArchived &&
                    !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: workspaceID, workspaces: workspaces)
            }
        let pillarRecords = Array(activePillarRecords.prefix(10))
        let pillarByID = DuplicateSafeIndex.firstValues(activePillarRecords.map { ($0.id, $0) })
        let pillars = pillarRecords
            .map { pillar in
                let detail = pillar.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                return PillarSummaryWire(pillarId: pillar.id, name: pillar.name.trimmingCharacters(in: .whitespacesAndNewlines), description: detail.isEmpty ? nil : detail)
            }

        let allOutputs = ((try? context.fetch(FetchDescriptor<PlatformOutput>())) ?? []).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: workspaceID, workspaces: workspaces)
        }
        let activeTasks = ((try? context.fetch(FetchDescriptor<CreatorTask>())) ?? [])
            .filter {
                !$0.isSkipped &&
                    $0.parentTaskID == nil &&
                    WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: workspaceID, workspaces: workspaces)
            }
        let tasksByBrief = Dictionary(grouping: activeTasks.filter { $0.briefID != nil }) {
            $0.briefID!
        }

        func snippet(_ value: String) -> String? {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            return String(cleaned.prefix(500))
        }

        let summaries = ((try? context.fetch(FetchDescriptor<CreativeBrief>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? [])
            .filter {
                $0.status != .archived &&
                    WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: workspaceID, workspaces: workspaces) &&
                    !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .prefix(20)
            .map { brief -> BriefSummaryWire in
                let briefOutputs = allOutputs.filter { $0.briefID == brief.id }
                let outputPlatforms = Array(Set(briefOutputs.map(\.platform)))
                    .sorted { $0.rawValue < $1.rawValue }
                let primaryOutput = briefOutputs.sorted { lhs, rhs in
                    let lhsDate = lhs.targetDate ?? lhs.postedAt ?? .distantFuture
                    let rhsDate = rhs.targetDate ?? rhs.postedAt ?? .distantFuture
                    return lhsDate < rhsDate
                }.first
                let briefTasks = tasksByBrief[brief.id] ?? []
                let pillar = brief.pillarID.flatMap { pillarByID[$0] }
                let formatName = primaryOutput?.formatID.flatMap { formatID in
                    PublishingCatalog.formatSeeds.first(where: { $0.0 == formatID })?.2
                }
                return BriefSummaryWire(
                    briefId: brief.id,
                    title: brief.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    premise: snippet(brief.premise),
                    takeaway: snippet(brief.takeaway),
                    notes: snippet(brief.notes),
                    hook: snippet(brief.spokenHook),
                    caption: primaryOutput.flatMap { snippet($0.caption) },
                    pillarId: pillar?.id,
                    pillarName: pillar?.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    format: formatName,
                    status: brief.status,
                    platforms: outputPlatforms.isEmpty ? selectedPlatforms : outputPlatforms,
                    targetDate: primaryOutput?.targetDate,
                    includesTargetTime: primaryOutput.map(\.includesTargetTime),
                    postedAt: briefOutputs.compactMap(\.postedAt).max(),
                    taskCount: briefTasks.count,
                    completedTaskCount: briefTasks.filter(\.isCompleted).count
                )
            }

        let taskSummaries = activeTasks
            .sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
                let lhsDate = lhs.targetDate ?? .distantFuture
                let rhsDate = rhs.targetDate ?? .distantFuture
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return lhs.createdAt > rhs.createdAt
            }
            .prefix(20)
            .map { task in
                TaskSummaryWire(
                    taskId: task.id,
                    title: String(task.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)),
                    kind: task.kind,
                    priority: task.priority.normalized,
                    isCompleted: task.isCompleted,
                    targetDate: task.targetDate,
                    includesTargetTime: task.includesTargetTime,
                    postId: task.briefID,
                    pillarId: task.pillarID
                )
            }

        return CreatorContextWire(
            name: name,
            primaryGoal: goal,
            selectedPlatforms: selectedPlatforms,
            voiceExamples: voiceExamples,
            voiceProfile: voiceProfile,
            pillars: Array(pillars),
            librarySummaries: Array(summaries),
            taskSummaries: Array(taskSummaries)
        )
    }

    private func voiceProfileWire(_ profile: VoiceProfile) -> VoiceProfileWire? {
        if let data = profile.canonicalPayloadJSON.data(using: .utf8),
           let canonical = try? JSONDecoder().decode(VoiceProfileWire.self, from: data) {
            return canonical
        }
        let summary = profile.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let traits = splitProfileList(profile.traitsText)
        guard !summary.isEmpty, !traits.isEmpty else { return nil }
        return VoiceProfileWire(
            summary: summary,
            tone: Array(traits.prefix(4)),
            sentenceStyle: summary,
            signatureQualities: Array(traits.prefix(8)),
            phrasesToUse: [],
            phrasesToAvoid: Array(splitProfileList(profile.avoidText).prefix(12)),
            guidance: ["Preserve the approved voice summary and recurring traits."],
            confidence: 0.7
        )
    }

    private func splitProfileList(_ value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func conversationWire(_ messages: [ConversationMessage]) -> [ConversationMessageWire] {
        messages.suffix(24).map { message in
            ConversationMessageWire(
                messageId: message.id,
                role: message.role == .creator ? .user : .assistant,
                content: message.text
            )
        }
    }

    private func preferredSocialAccountID(for destinationID: UUID, context: ModelContext) -> UUID? {
        let profileID = (try? context.fetch(FetchDescriptor<CreatorProfile>()))?.first?.id
        let workspaces = (try? context.fetch(FetchDescriptor<CreatorWorkspace>())) ?? []
        let workspaceID = resolvedWorkspaceID(context: context)
        let accounts = ((try? context.fetch(FetchDescriptor<CreatorSocialAccount>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? [])
            .filter { account in
                account.destinationID == destinationID &&
                    !account.isArchived &&
                    WorkspaceScope.includes(
                        account.workspaceID,
                        activeWorkspaceID: workspaceID,
                        workspaces: workspaces
                    ) &&
                    profileID.map { account.profileID == $0 } != false
            }
        return accounts.first(where: \.isPrimary)?.id ?? accounts.first?.id
    }

}
