import SwiftData
import SwiftUI

enum RootDestination: Equatable {
    case launch
    case onboarding
    case installationInvite
    case app

    static func resolve(
        hasProfile: Bool,
        requiresInstallationInvite: Bool,
        isInstallationCredentialStatusResolved: Bool,
        hasInstallationCredential: Bool
    ) -> Self {
        if requiresInstallationInvite && !isInstallationCredentialStatusResolved {
            return .launch
        }
        guard hasProfile else { return .onboarding }
        if requiresInstallationInvite && !hasInstallationCredential {
            return .installationInvite
        }
        return .app
    }
}

struct RootView: View {
    @Query private var profiles: [CreatorProfile]
    @Query private var briefs: [CreativeBrief]
    @Query private var outputs: [PlatformOutput]
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
        .onChange(of: profiles.first?.appearanceRaw, initial: true) { _, rawValue in
            appModel.appearancePreference = rawValue.flatMap { AppearancePreference(rawValue: $0) } ?? .system
        }
        .onChange(of: appModel.appearancePreference, initial: true) { _, preference in
            AgentAppearanceController.apply(preference)
        }
        .task {
            appModel.removeLegacySimplifyPrefixes(context: context)
            try? FocusTaskRecurrenceService.reconcile(context: context)
            let repairedPostTasks = (try? PostTaskScheduleRepairService.reconcileOnce(context: context)) ?? 0
            await appModel.refreshInstallationCredentialStatus(context: context)
            DevelopmentSubscriptionAccess.applyLocalCyPro(context: context)
            appModel.applyPendingWidgetTaskCompletions(context: context)
            WidgetSnapshotService.refresh(context: context)
            appModel.refreshCalendarSync(context: context)
            try? MCPBridgeService.sync(context: context)
            if repairedPostTasks > 0 {
                await appModel.refreshReminderSchedule(context: context)
            }
            handlePendingNotificationRoute()
        }
        .onOpenURL(perform: openWidgetDestination)
        .onReceive(NotificationCenter.default.publisher(for: .agentCyNotificationRouteReady)) { _ in
            handlePendingNotificationRoute()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentCyNotificationContentChanged)) { _ in
            WidgetSnapshotService.refresh(context: context)
            Task { await appModel.refreshReminderSchedule(context: context) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)) { _ in
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
            case .installationInvite:
                InstallationInviteGate()
            case .app:
                AppShellView()
            }
    }

    private var destination: RootDestination {
        .resolve(
            hasProfile: hasProfile,
            requiresInstallationInvite: appModel.requiresInstallationInvite,
            isInstallationCredentialStatusResolved: appModel.isInstallationCredentialStatusResolved,
            hasInstallationCredential: appModel.hasInstallationCredential
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
            prepareQuickCapture(idea: true, post: false, task: false)
        case .quickPost:
            prepareQuickCapture(idea: false, post: true, task: false)
        case .quickTask:
            prepareQuickCapture(idea: false, post: false, task: true)
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

    private func isPlannedForToday(briefID: UUID) -> Bool {
        guard briefs.contains(where: {
            $0.id == briefID && $0.status != .archived && $0.status != .posted
        }) else { return false }
        return outputs.contains { output in
            output.briefID == briefID &&
                output.status != .posted &&
                output.targetDate.map(Calendar.current.isDateInToday) == true
        }
    }

    private func prepareQuickCapture(idea: Bool, post: Bool, task: Bool) {
        if post {
            appModel.setQuickCaptureMode(.post)
        } else if task {
            appModel.setQuickCaptureMode(.task)
        } else {
            appModel.setQuickCaptureMode(.idea)
        }
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
                ContentUnavailableView("No scheduled preview post", systemImage: "calendar")
            }
        }
    }
}
#endif

private struct InstallationInviteGate: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
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
                        Task { await appModel.redeemInstallationInvite(inviteCode, context: context) }
                    } label: {
                        Label("Connect Cy", systemImage: "key")
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
    }
}

#Preview("Onboarding") {
    RootView()
        .environment(AppModel(reminderService: PreviewReminderService()))
        .modelContainer(ModelContainerFactory.make(isStoredInMemoryOnly: true))
}
