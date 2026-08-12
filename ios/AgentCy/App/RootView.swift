import SwiftData
import SwiftUI

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
}

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
            if ProcessInfo.processInfo.arguments.contains("-agentCyPreviewScheduledPost") {
                PreviewScheduledPostRoot()
            } else {
                destinationView
            }
            #else
            destinationView
            #endif
        }
        .onChange(of: appModel.appearancePreference, initial: true) { _, preference in
            AgentAppearanceController.apply(preference)
        }
        .task {
            appModel.removeLegacySimplifyPrefixes(context: context)
            try? FocusTaskRecurrenceService.reconcile(context: context)
            let repairedPostTasks = (try? PostTaskScheduleRepairService.reconcileOnce(context: context)) ?? 0
            let removedAccidentalSeriesPosts =
                (try? AccidentalRecurringPostRepairService.reconcileOnce(context: context)) ?? 0
            await appModel.refreshInstallationCredentialStatus(context: context)
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
        }
        .onOpenURL(perform: openWidgetDestination)
        .onReceive(NotificationCenter.default.publisher(for: .agentCyNotificationRouteReady)) { _ in
            handlePendingNotificationRoute()
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
            AccountRestoreView()
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
        appModel.presentedSheet = nil
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
        }
    }

    private func handlePendingNotificationRoute() {
        guard let route = AgentNotificationRouteStore.take() else { return }
        appModel.presentedSheet = nil
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
#endif

struct InstallationInviteGate: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var inviteCode = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                EditorialHeader(
                    kicker: "Connect Cy",
                    title: "Enter your invite.",
                    subtitle: "Connect this iPhone to Cy. Your saved work stays here."
                )

                VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        MetaLabel("Invitation code")
                        TextField("Enter your pilot code", text: $inviteCode)
                            .agentSingleLineSubmit()
                            .font(.agentBody)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding(AgentSpacing.x4)
                            .background(Color.agentSurface)
                            .clipShape(.rect(cornerRadius: AgentRadius.control))
                            .overlay {
                                RoundedRectangle(cornerRadius: AgentRadius.control)
                                    .stroke(Color.agentBorder, lineWidth: 1)
                            }
                    }

                    Button {
                        Task {
                            if await appModel.redeemInstallationInvite(inviteCode, context: context) {
                                dismiss()
                            }
                        }
                    } label: {
                        AgentIconLabel(title: "Connect Cy", icon: .key)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AgentPrimaryButtonStyle())
                    .disabled(
                        appModel.isRedeemingInvite ||
                            inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).count < 6
                    )

                    if appModel.isRedeemingInvite {
                        ProgressView("Connecting…")
                            .font(.agentBody)
                    }

                    if let notice = appModel.notice {
                        Text(notice.message)
                            .font(.agentBody)
                            .foregroundStyle(Color.agentSecondary)
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }
}

#Preview("Onboarding") {
    RootView()
        .environment(AppModel(reminderService: PreviewReminderService()))
        .modelContainer(ModelContainerFactory.make(isStoredInMemoryOnly: true))
}
