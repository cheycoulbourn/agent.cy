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
        .preferredColorScheme(preferredColorScheme)
        .onChange(of: profiles.first?.appearanceRaw, initial: true) { _, rawValue in
            appModel.appearancePreference = rawValue.flatMap { AppearancePreference(rawValue: $0) } ?? .system
        }
        .task {
            appModel.removeLegacySimplifyPrefixes(context: context)
            await appModel.refreshInstallationCredentialStatus(context: context)
            WidgetSnapshotService.refresh(context: context)
            appModel.refreshCalendarSync(context: context)
        }
        .onOpenURL(perform: openWidgetDestination)
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

    private var preferredColorScheme: ColorScheme? {
        appModel.appearancePreference.colorSchemeOverride
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

        switch destination {
        case .today:
            appModel.selectedTab = .today
        case .agenda(let day):
            appModel.selectedTab = .today
            appModel.widgetAgendaDay = day
            appModel.requestedPlanMode = day == nil ? .week : .day
        case .tasks:
            appModel.selectedTab = .tasks
        case .ideaBank:
            appModel.selectedTab = .ideaBank
        case .brief(let id):
            appModel.selectedTab = .today
            if isPlannedForToday(briefID: id) {
                appModel.requestedPlanMode = .day
                appModel.widgetBriefID = id
            } else {
                appModel.requestedPlanMode = .day
            }
        case .quickIdea:
            prepareQuickCapture(idea: true, post: false, task: false)
        case .quickPost:
            prepareQuickCapture(idea: false, post: true, task: false)
        case .quickTask:
            prepareQuickCapture(idea: false, post: false, task: true)
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
        appModel.quickCaptureStartsWithIdeas = idea
        appModel.quickCaptureStartsWithPost = post
        appModel.quickCaptureStartsWithTask = task
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
