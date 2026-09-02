import os
import SwiftData
import SwiftUI
import UIKit

enum RootDestination: Equatable {
    case launch
    case onboarding
    case accountAccess
    case restoringAccount
    case app

    static func resolve(
        hasProfile: Bool,
        requiresInstallationInvite: Bool,
        isInstallationCredentialStatusResolved: Bool,
        hasInstallationCredential: Bool,
        hasLinkedAccount: Bool
    ) -> Self {
        if requiresInstallationInvite && !isInstallationCredentialStatusResolved {
            return .launch
        }
        if requiresInstallationInvite && !hasInstallationCredential {
            return .accountAccess
        }
        guard hasProfile else {
            return hasLinkedAccount ? .restoringAccount : .onboarding
        }
        return .app
    }

    fileprivate var diagnosticName: String {
        switch self {
        case .launch: "launch"
        case .onboarding: "onboarding"
        case .accountAccess: "account_access"
        case .restoringAccount: "restoring_account"
        case .app: "app"
        }
    }
}

@MainActor
enum RootLaunchDiagnostics {
    private static let logger = Logger(subsystem: "com.agentcy.app", category: "RootLaunch")
    private static let signposter = OSSignposter(logger: logger)
    private static var signpostID: OSSignpostID?
    private static var intervalState: OSSignpostIntervalState?
    private static var startedAt: TimeInterval?
    private static var didFinish = false

    static func begin() {
        guard startedAt == nil else { return }
        let id = signposter.makeSignpostID()
        signpostID = id
        startedAt = ProcessInfo.processInfo.systemUptime
        intervalState = signposter.beginInterval("Root Launch", id: id)
        mark("process_initialized")
    }

    static func mark(_ milestone: String) {
        guard let startedAt, let signpostID else { return }
        let elapsedMilliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        signposter.emitEvent(
            "Root Milestone",
            id: signpostID,
            "milestone=\(milestone, privacy: .public) elapsed_ms=\(elapsedMilliseconds, format: .fixed(precision: 1))"
        )
        logger.notice(
            "milestone=\(milestone, privacy: .public) elapsed_ms=\(elapsedMilliseconds, format: .fixed(precision: 1))"
        )
    }

    static func destinationPresented(_ destination: RootDestination) {
        mark("destination_\(destination.diagnosticName)")
        guard destination != .launch,
              !didFinish,
              let intervalState else { return }
        signposter.endInterval(
            "Root Launch",
            intervalState,
            "destination=\(destination.diagnosticName, privacy: .public)"
        )
        self.intervalState = nil
        didFinish = true
    }
}

#if DEBUG
enum RootRuntimeFixture: String, Equatable {
    case restoringAccount
    case restoringThenApp

    static func resolve(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
        guard let marker = arguments.firstIndex(of: "-agentCyRootFixture"),
              arguments.indices.contains(marker + 1) else {
            return nil
        }
        return Self(rawValue: arguments[marker + 1])
    }

    var identity: InstallationIdentity {
        InstallationIdentity(
            installationID: UUID(uuidString: "B5E49C45-5D32-4E89-B50A-59AC6C3C29E9")!,
            credential: String(repeating: "r", count: 48),
            access: .comped,
            credentialExpiresAt: Date().addingTimeInterval(3_600),
            promotionalEntitlementEndsAt: nil,
            accountID: UUID(uuidString: "8B662D34-0707-45F0-84FE-9CD5984AA19A")!
        )
    }

    @MainActor
    func scheduleProfileArrival(context: ModelContext) {
        guard self == .restoringThenApp else { return }
        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(900))
            } catch {
                return
            }
            guard ((try? context.fetch(FetchDescriptor<CreatorProfile>())) ?? []).isEmpty else { return }
            context.insert(
                CreatorProfile(
                    name: "Restored creator",
                    goal: "Keep creating",
                    adultConfirmed: true,
                    onboardingCompleted: true
                )
            )
            if ((try? context.fetch(FetchDescriptor<SubscriptionState>())) ?? []).isEmpty {
                context.insert(SubscriptionState(access: .comped))
            }
            try? context.save()
        }
    }
}
#endif

struct RootView: View {
    @Query private var profiles: [CreatorProfile]
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context

    private var hasProfile: Bool {
        !profiles.isEmpty
    }

    var body: some View {
        Group {
            #if DEBUG
            if IdeaDraftRuntimeFixture.requestsIdeaDraft() {
                PreviewIdeaDraftRoot()
            } else if PostEditorRuntimeFixture.requestsSparkDevelopment() {
                PreviewSparkDevelopmentRoot()
            } else if PostEditorRuntimeFixture.requestsPostEditor() {
                PreviewPostEditorRoot()
            } else if ProcessInfo.processInfo.arguments.contains("-agentCyPreviewScheduledPost") {
                PreviewScheduledPostRoot()
            } else if ProcessInfo.processInfo.arguments.contains("-agentCyPreviewInspirationReview") {
                PreviewInspirationReviewRoot()
            } else {
                destinationView
            }
            #else
            destinationView
            #endif
        }
        .onAppear {
            RootLaunchDiagnostics.destinationPresented(destination)
        }
        .onChange(of: appModel.appearancePreference, initial: true) { _, preference in
            AgentAppearanceController.apply(preference)
        }
        .task {
            RootLaunchDiagnostics.mark("root_task_started")
            #if DEBUG
            RootRuntimeFixture.resolve()?.scheduleProfileArrival(context: context)
            #endif
            if !CreatorSessionFeatureAvailability.isEnabled {
                if appModel.presentedSheet == .creatorSession {
                    appModel.presentedSheet = nil
                }
                await CreatorSessionActivityController.retireUnavailableFeature()
            }
            appModel.removeLegacySimplifyPrefixes(context: context)
            try? FocusTaskRecurrenceService.reconcile(context: context)
            let repairedPostTasks = (try? PostTaskScheduleRepairService.reconcileOnce(context: context)) ?? 0
            let removedAccidentalSeriesPosts =
                (try? AccidentalRecurringPostRepairService.reconcileOnce(context: context)) ?? 0
            RootLaunchDiagnostics.mark("precredential_work_complete")
            await appModel.refreshInstallationCredentialStatus(context: context)
            RootLaunchDiagnostics.mark("credential_status_resolved")
            appModel.refreshInspirationShareCreatorSnapshot(context: context)
            DevelopmentSubscriptionAccess.applyLocalCyPro(context: context)
            appModel.applyPendingWidgetTaskCompletions(context: context)
            WidgetSnapshotService.refresh(context: context)
            appModel.refreshCalendarSync(context: context)
            try? MCPBridgeService.sync(context: context)
            if repairedPostTasks > 0 || removedAccidentalSeriesPosts > 0 {
                await appModel.refreshReminderSchedule(context: context)
            }
            if removedAccidentalSeriesPosts > 0 {
                appModel.notice = .info("Removed \(removedAccidentalSeriesPosts) accidental repeat posts.")
            }
            handlePendingNotificationRoute()
            handlePendingPhoneFeatureLaunch()
        }
        .onOpenURL(perform: openWidgetDestination)
        .onReceive(NotificationCenter.default.publisher(for: .agentCyNotificationRouteReady)) { _ in
            handlePendingNotificationRoute()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            handlePendingPhoneFeatureLaunch()
        }
        .onChange(of: destination) { _, newDestination in
            RootLaunchDiagnostics.destinationPresented(newDestination)
            guard newDestination == .app else { return }
            handlePendingPhoneFeatureLaunch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentCyNotificationContentChanged).receive(on: DispatchQueue.main)) { _ in
            WidgetSnapshotService.refresh(context: context)
            Task { await appModel.refreshReminderSchedule(context: context) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange).receive(on: DispatchQueue.main)) { _ in
            Task { await appModel.refreshReminderSchedule(context: context) }
        }
        .agentScreen()
    }

    @ViewBuilder
    private var destinationView: some View {
        switch destination {
        case .launch:
            Color.agentCanvas.ignoresSafeArea()
        case .onboarding:
            OnboardingView()
        case .accountAccess:
            AccountAccessGate()
        case .restoringAccount:
            AccountRestoreView(
                localOnlyFallback: ModelContainerFactory.didFallBackToLocalOnlyStore
            )
        case .app:
            #if targetEnvironment(macCatalyst)
            DesktopAppShellView()
            #else
            AppShellView()
            #endif
        }
    }

    private var destination: RootDestination {
        .resolve(
            hasProfile: hasProfile,
            requiresInstallationInvite: appModel.requiresInstallationInvite,
            isInstallationCredentialStatusResolved: appModel.isInstallationCredentialStatusResolved,
            hasInstallationCredential: appModel.hasInstallationCredential,
            hasLinkedAccount: appModel.hasLinkedAccount
        )
    }

    private func openWidgetDestination(_ url: URL) {
        guard let destination = AgentCyDeepLink(url: url) else { return }
        appModel.dismissGlobalPresentation()
        appModel.widgetAgendaDay = nil
        appModel.widgetBriefID = nil
        appModel.widgetBriefOpensEditor = false

        switch destination {
        case .today:
            appModel.selectedTab = .home
        case .agenda(let day):
            appModel.selectedTab = .today
            appModel.widgetAgendaDay = day
            appModel.requestedPlanMode = .week
        case .tasks:
            appModel.selectedTab = .tasks
        case .pillars:
            appModel.selectedTab = .pillars
        case .ideaBank:
            appModel.selectedTab = .ideaBank
        case .brief(let id):
            appModel.selectedTab = .today
            appModel.requestedPlanMode = .week
            appModel.widgetBriefID = id
            appModel.widgetBriefOpensEditor = false
        case .quickIdea:
            prepareQuickCapture(.idea)
        case .quickPost:
            prepareQuickCapture(.post)
        case .quickTask:
            prepareQuickCapture(.task)
        case .voiceSpark:
            #if !targetEnvironment(macCatalyst)
            appModel.presentedSheet = .voiceSpark
            #endif
        case .creatorSession:
            break
        }
    }

    private func handlePendingPhoneFeatureLaunch() {
        guard destination == .app else { return }
        #if !targetEnvironment(macCatalyst)
        guard let route = PhoneFeatureLaunchRequestStore.take() else { return }
        guard route == .voiceSpark else { return }
        appModel.presentedSheet = .voiceSpark
        #endif
    }

    private func handlePendingNotificationRoute() {
        guard let route = AgentNotificationRouteStore.take() else { return }
        appModel.dismissGlobalPresentation()
        switch route.kind {
        case .day:
            appModel.selectedTab = .today
            appModel.widgetAgendaDay = route.date
            appModel.requestedPlanMode = .week
        case .week:
            appModel.selectedTab = .today
            appModel.widgetAgendaDay = route.date
            appModel.requestedPlanMode = .week
        case .cyWeek:
            appModel.pendingCyPrompt = "Help me plan this week around my saved ideas, scheduled posts, tasks, and daily focuses."
            appModel.selectedTab = .cy
        case .brief, .draft:
            guard let id = route.objectID else { return }
            appModel.selectedTab = .today
            appModel.requestedPlanMode = .week
            appModel.widgetBriefOpensEditor = route.kind == .draft
            appModel.widgetBriefID = id
        case .task:
            appModel.selectedTab = .tasks
            appModel.requestedTaskID = route.objectID
        case .access:
            appModel.requestedSettingsPage = .access
            appModel.presentedSheet = .settings
        case .mcpReview:
            appModel.presentMCPReview()
        }
    }

    private func prepareQuickCapture(_ mode: QuickCaptureLaunchMode) {
        appModel.setQuickCaptureMode(mode)
        appModel.quickCaptureTargetDate = nil
        appModel.quickCapturePillarID = nil
        appModel.quickCaptureTaskLane = nil
        appModel.quickCaptureTaskFocus = nil
        appModel.presentedSheet = .quickCapture
    }
}

#if DEBUG
private struct PreviewIdeaDraftRoot: View {
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]

    var body: some View {
        NavigationStack {
            if let brief = briefs.first(where: {
                IdeaDraftRoutePolicy.destination(for: $0.status) == .editor
                    && $0.ideaBankPlacement == .idea
            }) {
                IdeaPostDraftView(brief: brief, isAlreadyInIdeaBank: true)
            } else {
                AgentEmptyState(
                    title: "No idea draft",
                    message: "Seed preview data to open the Idea Draft fixture.",
                    icon: .ideas
                )
            }
        }
    }
}

private struct PreviewScheduledPostRoot: View {
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt, order: .reverse) private var outputs: [PlatformOutput]

    var body: some View {
        NavigationStack {
            if let output = outputs.first(where: {
                PostOutputDetailPolicy.usesFinalizedView(
                    outputStatus: $0.status,
                    targetDate: $0.targetDate
                )
            }),
               let brief = briefs.first(where: { $0.id == output.briefID }) {
                ScheduledPostDetailView(brief: brief, output: output)
            } else {
                AgentEmptyState(
                    title: "No scheduled preview post",
                    message: "Schedule a post to preview the finalized page.",
                    icon: .calendar
                )
            }
        }
    }
}

private struct PreviewPostEditorRoot: View {
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt, order: .reverse) private var outputs: [PlatformOutput]

    var body: some View {
        NavigationStack {
            if let output = outputs.first,
               let brief = briefs.first(where: { $0.id == output.briefID }) {
                ResumablePostEditorView(brief: brief, output: output, onSpark: {})
            } else {
                AgentEmptyState(
                    title: "No post editor fixture",
                    message: "Seed preview data to open the resumable post editor.",
                    icon: .calendar
                )
            }
        }
    }
}

private struct PreviewSparkDevelopmentRoot: View {
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt, order: .reverse) private var outputs: [PlatformOutput]

    var body: some View {
        if let output = outputs.first,
           let brief = briefs.first(where: { $0.id == output.briefID }) {
            DevelopBriefView(brief: brief, output: output)
        } else if let brief = briefs.first {
            DevelopBriefView(brief: brief)
        } else {
            AgentEmptyState(
                title: "No spark fixture",
                message: "Seed preview data to open Build with Cy.",
                icon: .calendar
            )
        }
    }
}

/// `inspiration-review` has no other headless entry point — it is normally
/// reached only via `$model.inspirationReviewRoute`, which needs a share
/// extension or a live source tap to populate. This mirrors
/// `PreviewSparkDevelopmentRoot`: a DEBUG-only route straight to the view
/// with the first seeded `InspirationSource`, for capture and measurement.
private struct PreviewInspirationReviewRoot: View {
    @Query(sort: \InspirationSource.updatedAt, order: .reverse) private var sources: [InspirationSource]

    var body: some View {
        if let source = sources.first {
            InspirationReviewView(sourceID: source.id)
        } else {
            AgentEmptyState(
                title: "No saved post fixture",
                message: "Seed preview data to open the saved post review.",
                icon: .link
            )
        }
    }
}
#endif

struct InstallationInviteGate: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var inviteCode = ""
    @FocusState private var inviteCodeIsFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                EditorialHeader(
                    kicker: "Connect Cy",
                    title: "Enter your invite.",
                    subtitle: "Connect this iPhone to Cy with the invitation code you received."
                )

                VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        MetaLabel("Invitation code")
                            .accessibilityHidden(true)
                        TextField("Enter your pilot code", text: $inviteCode, axis: .vertical)
                            .font(.agentBody)
                            .lineLimit(1...3)
                            .submitLabel(.go)
                            .onSubmit { submit() }
                            .onChange(of: inviteCode) { _, updatedCode in
                                let keyboardSubmit = InstallationInviteInput.consumeSubmitMarker(
                                    in: updatedCode
                                )
                                guard keyboardSubmit.shouldSubmit else { return }
                                inviteCode = keyboardSubmit.code
                                submit()
                            }
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .textContentType(.oneTimeCode)
                            .focused($inviteCodeIsFocused)
                            .padding(AgentSpacing.x4)
                            .background(Color.agentSurface)
                            .clipShape(.rect(cornerRadius: AgentRadius.control))
                            .overlay {
                                RoundedRectangle(cornerRadius: AgentRadius.control)
                                    .stroke(Color.agentBorder, lineWidth: 1)
                            }
                            .accessibilityLabel("Invitation code")
                            .accessibilityHint(invitationCodeHint)
                            .accessibilityIdentifier("installation-invite-code")
                    }

                    Button(action: submit) {
                        AgentIconLabel(title: "Connect Cy", icon: .key)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AgentPrimaryButtonStyle())
                    .disabled(appModel.isRedeemingInvite)

                    if appModel.installationInviteStatus.message != nil {
                        InstallationInviteStatusView(
                            status: appModel.installationInviteStatus
                        )
                    }
                }

                CyCallout(heading: .keepsItPrivate) {
                    Text("Your invite is checked before any content is sent.")
                        .font(.agentBody)
                }
            }
            .padding(.horizontal, AgentSpacing.x6)
            .padding(.top, AgentSpacing.x12)
            .padding(.bottom, AgentSpacing.x16)
        }
        .scrollDismissesKeyboard(.interactively)
        .agentKeyboardDismissal()
        .interactiveDismissDisabled(appModel.isRedeemingInvite)
        .onAppear { appModel.prepareInstallationInviteEntry() }
        .onDisappear { appModel.resetInstallationInviteState() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    appModel.resetInstallationInviteState()
                    dismiss()
                }
                .disabled(appModel.isRedeemingInvite)
            }
        }
    }

    private var invitationCodeHint: String {
        if case .error(let message) = appModel.installationInviteStatus {
            return message
        }
        return "Enter the code you received with your invitation."
    }

    private func submit() {
        guard !appModel.isRedeemingInvite else { return }
        Task {
            let outcome = await appModel.redeemInstallationInvite(
                inviteCode,
                context: context
            )
            switch outcome {
            case .redeemed:
                AgentKeyboard.dismiss()
                dismiss()
            case .validationFailed:
                inviteCodeIsFocused = true
            case .failed, .duplicateIgnored:
                break
            }
        }
    }
}

private struct InstallationInviteStatusView: View {
    let status: InstallationInviteStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x3) {
            if status.showsProgress {
                ProgressView()
            }
            if let message = status.message {
                Text(message)
                    .font(.agentSubtext)
                    .foregroundStyle(status.isUrgent ? Color.agentDestructive : Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(status.message ?? "")
        .accessibilityIdentifier("installation-invite-status")
        .onAppear { announce(status) }
        .onChange(of: status) { _, status in
            announce(status)
        }
    }

    private func announce(_ status: InstallationInviteStatus) {
        guard let messageText = status.message else { return }
        let message = NSMutableAttributedString(string: messageText)
        message.addAttribute(
            .accessibilitySpeechAnnouncementPriority,
            value: status.isUrgent ? UIAccessibilityPriority.high : UIAccessibilityPriority.low,
            range: NSRange(location: 0, length: message.length)
        )
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

#Preview("Onboarding") {
    RootView()
        .environment(AppModel(reminderService: PreviewReminderService()))
        .modelContainer(ModelContainerFactory.make(isStoredInMemoryOnly: true))
}
