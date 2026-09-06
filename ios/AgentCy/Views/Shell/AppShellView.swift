import SwiftData
import SwiftUI
import UIKit

enum AppShellNavigationPolicy {
    static func shouldResetPath(current: AppTab, tapped: AppTab) -> Bool {
        current == tapped
    }
}

enum AppShellMotionPolicy {
    static func shouldRunContinuousPlanningCue(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}

enum AppShellMCPReviewPolicy {
    static func shouldPresent(
        requestIDs: Set<UUID>,
        presentedRequestIDs: Set<UUID>,
        hasGlobalPresentation: Bool
    ) -> Bool {
        !hasGlobalPresentation &&
            !requestIDs.isEmpty &&
            !requestIDs.subtracting(presentedRequestIDs).isEmpty
    }
}

struct AppShellView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(WeeklyPlanningCue.lastOpenedStorageKey) private var cyPlanningWeekOpened = ""
    @AppStorage(AppWalkthrough.completedVersionStorageKey) private var completedWalkthroughVersion = 0
    @State private var isKeyboardVisible = false
    @State private var cueDate = Date()
    @State private var homePath = NavigationPath()
    @State private var planPath = NavigationPath()
    @State private var tasksPath = NavigationPath()
    @State private var pillarsPath = NavigationPath()
    @State private var ideaBankPath = NavigationPath()
    @State private var cyPath = NavigationPath()
    @State private var presentedMCPRequestIDs: Set<UUID> = []
    @State private var hasPendingMCPReview = false
    @State private var walkthroughIsWaitingForQuickAddDismissal = false
    @State private var showsPreviewDailyFocusEditor = PlanRuntimeFixture.requestsDailyFocusEditor(
        arguments: ProcessInfo.processInfo.arguments
    )
    @State private var showsPreviewEpisodeSlotActions = PlanRuntimeFixture.requestsEpisodeSlotActions(
        arguments: ProcessInfo.processInfo.arguments
    )
    @State private var showsPreviewAddLivePost = PlanRuntimeFixture.requestsAddLivePost(
        arguments: ProcessInfo.processInfo.arguments
    )
    private let bottomNavigationClearance: CGFloat = 76

    var body: some View {
        @Bindable var model = appModel
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ZStack {
                    RetainedTab(isSelected: model.selectedTab == .home) {
                        NavigationStack(path: $homePath) { HomeDashboardView().taskNavigationDestinations() }
                    }
                    RetainedTab(isSelected: model.selectedTab == .today) {
                        NavigationStack(path: $planPath) {
                            PlanView(showsFeedShortcut: true)
                                .id(model.requestedPlanNavigationReset)
                                .planNavigationDestinations(bottomClearance: bottomNavigationClearance)
                                .taskNavigationDestinations()
                        }
                    }
                    RetainedTab(isSelected: model.selectedTab == .tasks) {
                        NavigationStack(path: $tasksPath) { TasksView().taskNavigationDestinations() }
                    }
                    RetainedTab(isSelected: model.selectedTab == .pillars) {
                        NavigationStack(path: $pillarsPath) { PillarsView().taskNavigationDestinations() }
                    }
                    RetainedTab(isSelected: model.selectedTab == .ideaBank) {
                        NavigationStack(path: $ideaBankPath) { IdeaBankView().taskNavigationDestinations() }
                    }
                    RetainedTab(isSelected: model.selectedTab == .cy) {
                        NavigationStack(path: $cyPath) {
                            AskCyView(bottomClearance: isKeyboardVisible ? 0 : bottomNavigationClearance)
                                .taskNavigationDestinations()
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)

                if !isKeyboardVisible {
                    PaperBottomNavigation(selection: model.selectedTab, onSelect: selectTab, showCyPlanningCue: WeeklyPlanningCue.shouldPulse(
                        on: cueDate,
                        lastOpenedWeekKey: cyPlanningWeekOpened
                    ), hasPendingCyReview: hasPendingMCPReview, walkthroughStep: model.walkthroughStep, openCreationHub: openCreationHub)
                    .padding(.horizontal, AgentLayout.pageMargin)
                    .padding(.top, AgentSpacing.x2)
                    .padding(.bottom, AgentSpacing.x3)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(model.walkthroughStep == nil ? 10 : 13)
                }

                if !isKeyboardVisible, let undo = appModel.taskCompletionUndo {
                    taskCompletionUndoToast(undo)
                        .padding(.horizontal, AgentLayout.pageMargin + AgentSpacing.x1)
                        .padding(.bottom, 88)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .zIndex(5)
                }

                if !isKeyboardVisible, model.walkthroughStep != nil {
                    WalkthroughBackdrop()
                        .transition(.opacity)
                        .zIndex(11)
                }

                if !isKeyboardVisible, let walkthroughStep = model.walkthroughStep {
                    WalkthroughGuideCard(
                        step: walkthroughStep,
                        primaryAction: { performWalkthroughAction(for: walkthroughStep) },
                        skipAction: finishWalkthrough
                    )
                    .id(walkthroughStep)
                    .padding(.horizontal, AgentLayout.pageMargin)
                    .padding(
                        walkthroughStep.prefersTopPlacement ? .top : .bottom,
                        walkthroughStep.prefersTopPlacement ? 148 : 92
                    )
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: walkthroughStep.prefersTopPlacement ? .top : .bottom
                    )
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: walkthroughStep.prefersTopPlacement ? .top : .bottom)
                                    .combined(with: .opacity),
                                removal: .offset(y: -12).combined(with: .opacity)
                            )
                    )
                    .zIndex(14)
                }

            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.easeOut(duration: 0.24), value: appModel.taskCompletionUndo)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $model.presentedSheet) { sheet in
            Group {
                switch sheet {
                case .creationHub: CreationHubView()
                case .quickCapture: QuickCaptureView()
                case .voiceSpark:
                    #if targetEnvironment(macCatalyst)
                    EmptyView()
                    #else
                    VoiceSparkView()
                    #endif
                case .askCy: AskCyView()
                case .settings: SettingsView()
                case .weeklyFocus: WeeklyFocusSetupView()
                case .activityCenter:
                    NotificationActivityCenterView(
                        preferredWorkspaceID: appModel.activeWorkspaceID
                    )
                    .agentDesktopWorkspaceModal()
                    .presentationDetents([.large])
                    .presentationBackground(Color.agentCanvas)
                }
            }
        }
        .sheet(item: $model.inspirationReviewRoute) { route in
            InspirationReviewView(sourceID: route.id)
        }
        .sheet(isPresented: $showsPreviewDailyFocusEditor) {
            DailyFocusEditorView(date: Calendar.current.startOfDay(for: Date()))
        }
        .sheet(isPresented: $showsPreviewEpisodeSlotActions) {
            EpisodeSlotActionsPreviewHost()
        }
        .sheet(isPresented: $showsPreviewAddLivePost) {
            AddLivePostView()
        }
        .alert("agent.cy", isPresented: Binding(
            get: { appModel.notice != nil },
            set: { if !$0 { appModel.notice = nil } }
        )) {
            Button("Close") { appModel.notice = nil }
        } message: {
            Text(appModel.notice?.message ?? "")
        }
        .agentScreen()
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.16)) { isKeyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.16)) { isKeyboardVisible = false }
        }
        .task {
            await appModel.refreshAccess(context: modelContext)
            await appModel.refreshReminderSchedule(context: modelContext)
            appModel.importPendingInspiration(
                context: modelContext,
                presentsImportedSource: false
            )
            #if DEBUG
            let launchArguments = ProcessInfo.processInfo.arguments
            if PlanRuntimeFixture.requestsDailyFocusDetail(arguments: launchArguments), planPath.isEmpty {
                appModel.selectedTab = .today
                planPath.append(PlanNavigationRoute.dailyFocusDetail)
            }
            #endif
            openRequestedTaskIfNeeded()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            appModel.importPendingInspiration(
                context: modelContext,
                presentsImportedSource: false
            )
            while !Task.isCancelled {
                await presentMCPApprovalsIfNeeded()
                try? await Task.sleep(for: .seconds(4))
            }
        }
        .onChange(of: appModel.requestedTaskID) { _, _ in
            openRequestedTaskIfNeeded()
        }
        .onChange(of: appModel.requestedPlanNavigationReset) { _, _ in
            planPath = NavigationPath()
        }
        .onChange(of: appModel.workspaceRevision) { _, _ in
            homePath = NavigationPath()
            planPath = NavigationPath()
            tasksPath = NavigationPath()
            pillarsPath = NavigationPath()
            ideaBankPath = NavigationPath()
            cyPath = NavigationPath()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            cueDate = Date()
        }
        .onChange(of: appModel.walkthroughStep) { _, step in
            guard let step else { return }
            UIAccessibility.post(
                notification: .screenChanged,
                argument: "\(step.progressLabel). \(step.title). \(step.detail)"
            )
        }
        .onChange(of: appModel.presentedSheet) { _, sheet in
            guard sheet == nil,
                  walkthroughIsWaitingForQuickAddDismissal,
                  appModel.walkthroughStep == .quickAdd else { return }
            walkthroughIsWaitingForQuickAddDismissal = false
            setWalkthroughStep(.agenda, tab: .today)
        }
    }

    private func performWalkthroughAction(for step: AppWalkthroughStep) {
        switch step {
        case .dashboard:
            setWalkthroughStep(.quickAdd, tab: .home)
        case .quickAdd:
            openCreationHub()
        case .agenda:
            setWalkthroughStep(.tasks, tab: .tasks)
        case .tasks:
            setWalkthroughStep(.pillars, tab: .pillars)
        case .pillars:
            setWalkthroughStep(.ideaBank, tab: .ideaBank)
        case .ideaBank:
            setWalkthroughStep(.cy, tab: .cy)
        case .cy:
            startCreatingAfterWalkthrough()
        }
    }

    private func openCreationHub() {
        if appModel.walkthroughStep == .quickAdd {
            walkthroughIsWaitingForQuickAddDismissal = true
        }
        appModel.presentedSheet = .creationHub
    }

    private func setWalkthroughStep(_ step: AppWalkthroughStep, tab: AppTab) {
        let changes = {
            appModel.dismissGlobalPresentation()
            appModel.selectedTab = tab
            appModel.walkthroughStep = step
        }
        if reduceMotion {
            changes()
        } else {
            withAnimation(.snappy(duration: 0.28)) { changes() }
        }
    }

    private func finishWalkthrough() {
        completeWalkthrough(openCreationHub: false)
    }

    private func startCreatingAfterWalkthrough() {
        completeWalkthrough(openCreationHub: true)
    }

    private func completeWalkthrough(openCreationHub: Bool) {
        completedWalkthroughVersion = AppWalkthrough.currentVersion
        walkthroughIsWaitingForQuickAddDismissal = false
        let changes = {
            appModel.dismissGlobalPresentation()
            appModel.walkthroughStep = nil
            appModel.selectedTab = .home
            appModel.presentedSheet = openCreationHub ? .creationHub : nil
        }
        if reduceMotion {
            changes()
        } else {
            withAnimation(.snappy(duration: 0.26)) { changes() }
        }
    }

    private func taskCompletionUndoToast(_ undo: TaskCompletionUndoState) -> some View {
        HStack(spacing: AgentSpacing.x3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Task completed")
                    .font(.agentSubtext.weight(.semibold))
                Text(undo.taskTitle)
                    .font(.paperInter(size: 12, weight: .regular, relativeTo: .caption))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                appModel.undoLastTaskCompletion(context: modelContext)
            } label: {
                Text("Undo")
                    .font(.agentSubtext.weight(.bold))
                    .frame(minWidth: 56, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, AgentSpacing.x4)
        .padding(.trailing, AgentSpacing.x2)
        .frame(minHeight: 58)
        .foregroundStyle(Color.agentCanvas)
        .background(Color.agentText, in: .capsule)
        .shadow(color: Color.agentPureBlack.opacity(0.14), radius: 14, y: 6)
    }

    private func selectTab(_ tab: AppTab) {
        let shouldResetPath = AppShellNavigationPolicy.shouldResetPath(
            current: appModel.selectedTab,
            tapped: tab
        )
        appModel.dismissGlobalPresentation()
        if shouldResetPath {
            switch tab {
            case .home:
                homePath = NavigationPath()
            case .today:
                planPath = NavigationPath()
            case .tasks:
                tasksPath = NavigationPath()
            case .pillars:
                pillarsPath = NavigationPath()
            case .ideaBank:
                ideaBankPath = NavigationPath()
            case .cy:
                cyPath = NavigationPath()
            }
        }
        if tab == .cy {
            cyPlanningWeekOpened = WeeklyPlanningCue.weekKey(for: Date())
        }
        appModel.selectedTab = tab
    }

    private func openRequestedTaskIfNeeded() {
        guard let taskID = appModel.consumeRequestedTaskRoute() else { return }
        appModel.selectedTab = .tasks
        tasksPath = NavigationPath()
        tasksPath.append(TaskNavigationRoute(taskID: taskID))
    }

    private func presentMCPApprovalsIfNeeded() async {
        guard MCPBridgePreferences.isConnected else {
            if hasPendingMCPReview { hasPendingMCPReview = false }
            if !presentedMCPRequestIDs.isEmpty { presentedMCPRequestIDs = [] }
            return
        }
        // Bridge-folder reads can hit iCloud Drive; keep them off the main
        // thread and leave @State untouched when nothing changed, or the
        // 4-second poll hitches whatever the creator is scrolling.
        let fetched = await Task.detached(priority: .utility) {
            try? await MCPBridgeService.refreshPendingRequests()
        }.value
        guard let requests = fetched else {
            return
        }
        let requestIDs = Set(requests.map(\.id))
        if hasPendingMCPReview != !requestIDs.isEmpty {
            hasPendingMCPReview = !requestIDs.isEmpty
        }
        guard !requestIDs.isEmpty else {
            if !presentedMCPRequestIDs.isEmpty { presentedMCPRequestIDs = [] }
            return
        }
        // Never yank the creator out of in-progress work. The badge carries
        // the signal while any global presentation is active, and already
        // presented requests stay suppressed across scene re-entry.
        guard AppShellMCPReviewPolicy.shouldPresent(
            requestIDs: requestIDs,
            presentedRequestIDs: presentedMCPRequestIDs,
            hasGlobalPresentation: appModel.hasGlobalPresentation
        ) else { return }
        presentedMCPRequestIDs = requestIDs

        appModel.presentMCPReview()
    }

}

private struct EpisodeSlotActionsPreviewHost: View {
    @Query(sort: \SeriesEpisodeSlot.plannedDate) private var slots: [SeriesEpisodeSlot]

    var body: some View {
        if let slot = slots.first(where: { $0.status == .open }) {
            EpisodeSlotActionsView(slot: slot) { _ in }
        } else {
            ContentUnavailableView(
                "Episode slot unavailable",
                systemImage: "calendar.badge.exclamationmark"
            )
        }
    }
}

private extension AppWalkthroughStep {
    var title: String {
        switch self {
        case .dashboard: "Your day starts here."
        case .quickAdd: "Capture it before it disappears."
        case .agenda: "Give the work a day."
        case .tasks: "Know what comes next."
        case .pillars: "Build around what matters."
        case .ideaBank: "Keep ideas without scheduling them."
        case .cy: "Your creative rhythm starts now."
        }
    }

    var detail: String {
        switch self {
        case .dashboard:
            "The dashboard brings today’s focus, posts, and tasks into one place."
        case .quickAdd:
            "The plus button starts an idea, post, or task from anywhere in the app."
        case .agenda:
            "Use the week to see what is scheduled and which focus belongs to each day."
        case .tasks:
            "Focus tasks repeat with your weekly rhythm. Post tasks stay linked to the post they support."
        case .pillars:
            "Your anchor pillar is the through-line. Secondary pillars support it."
        case .ideaBank:
            "The Idea Bank holds thoughts you want to return to later."
        case .cy:
            "One idea can become a post, a plan, and a body of work you’re proud to keep building."
        }
    }

    var suggestion: String {
        switch self {
        case .dashboard:
            "Scroll to Customize when you want to add, remove, or reorder cards."
        case .quickAdd:
            "Try saving one thought you do not want to lose."
        case .agenda:
            "Tap a day to open it, or use + to schedule a post."
        case .tasks:
            "Check a box to complete work, or open a task to change its date or priority."
        case .pillars:
            "Choose preferred days so the Agenda can recommend where each post fits."
        case .ideaBank:
            "Open an idea when you are ready to turn it into a post."
        case .cy:
            "Start with the thought already on your mind. You can shape the rest as you go."
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .dashboard: "Next: Quick Add"
        case .quickAdd: "Open Quick Add"
        case .agenda: "Next: Tasks"
        case .tasks: "Next: Pillars"
        case .pillars: "Next: Idea Bank"
        case .ideaBank: "Next: Cy"
        case .cy: "Start creating"
        }
    }

    var suggestionLabel: String {
        self == .cy ? "YOUR FIRST MOVE" : "TRY THIS"
    }

    var progressLabel: String {
        "\(rawValue + 1) of \(Self.allCases.count)"
    }

    var icon: AgentIcon {
        switch self {
        case .dashboard: .home
        case .quickAdd: .add
        case .agenda: .calendar
        case .tasks: .tasks
        case .pillars: .pillars
        case .ideaBank: .ideas
        case .cy: .idea
        }
    }

    var prefersTopPlacement: Bool { self == .cy }
}

private struct WalkthroughBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.agentPureBlack
            .opacity(colorScheme == .dark ? 0.42 : 0.16)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct WalkthroughGuideCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let step: AppWalkthroughStep
    let primaryAction: () -> Void
    let skipAction: () -> Void
    @State private var contentIsVisible = false

    private var walkthroughPrimaryLabel: some View {
        HStack(spacing: AgentSpacing.x2) {
            Text(step.primaryActionTitle)
            Spacer()
            AgentIconView(step == .cy ? .check : .forward, size: 15)
        }
        .frame(maxWidth: .infinity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(alignment: .center, spacing: AgentSpacing.x3) {
                WalkthroughAnimatedGlyph(step: step, isVisible: contentIsVisible)

                Text("GUIDED TOUR · \(step.progressLabel.uppercased())")
                    .font(.paperInter(size: 11, weight: .semibold, relativeTo: .caption))
                    .tracking(0.8)
                    .foregroundStyle(Color.agentSecondary)
                    .monospacedDigit()

                Spacer(minLength: AgentSpacing.x2)

                Button("Skip tour", action: skipAction)
                    .font(.paperInter(size: 13, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(Color.agentSecondary)
                    .frame(minWidth: 72, minHeight: 44)
                    .contentShape(.rect)
                    .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                Text(step.title)
                    .font(.paperInter(size: 20, weight: .bold, relativeTo: .title2))
                    .foregroundStyle(Color.agentText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(step.detail)
                    .font(.paperInter(size: 14, weight: .regular, relativeTo: .body))
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(step.suggestionLabel)
                    .font(.paperInter(size: 10, weight: .semibold, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(Color.cyAccentText)

                Text(step.suggestion)
                    .font(.paperInter(size: 13, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(Color.agentText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AgentSpacing.x3)
            .padding(.vertical, AgentSpacing.x1)
            .frame(maxWidth: .infinity, alignment: .leading)

            // The tour's last step is the one accent-worthy action on this
            // surface (it hands the user to Cy); every earlier step is a plain
            // ink primary, so the accent still lands only once.
            if step == .cy {
                Button(action: primaryAction) {
                    walkthroughPrimaryLabel
                }
                .buttonStyle(AgentQuietAccentButtonStyle(size: .page))
                .accessibilityHint("Continues to the next walkthrough step")
            } else {
                Button(action: primaryAction) {
                    walkthroughPrimaryLabel
                }
                .buttonStyle(AgentPrimaryButtonStyle())
                .accessibilityHint("Continues to the next walkthrough step")
            }
        }
        .padding(AgentSpacing.x4)
        .frame(maxWidth: 440)
        .background(Color.agentSurface, in: .rect(cornerRadius: 28))
        .agentSurfaceChrome(
            cornerRadius: 28,
            borderColor: colorScheme == .dark
                ? Color.agentPureWhite.opacity(0.16)
                : Color.agentPureBlack.opacity(0.10),
            role: .walkthrough
        )
        .onAppear {
            if reduceMotion {
                contentIsVisible = true
            } else {
                contentIsVisible = false
                withAnimation(.spring(duration: 0.3, bounce: 0)) {
                    contentIsVisible = true
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(100)
    }
}

private struct WalkthroughAnimatedGlyph: View {
    let step: AppWalkthroughStep
    let isVisible: Bool

    var body: some View {
        Group {
            if step == .cy {
                CyAsterisk(color: .cyAccent, size: 18, strokeWidth: 1.6)
            } else {
                AgentIconView(step.icon, size: 17)
                    .foregroundStyle(Color.cyAccentText)
            }
        }
        .frame(width: 36, height: 36)
        .background(Color.cyAccent.opacity(0.10), in: .circle)
        .scaleEffect(isVisible ? 1 : 0.25)
        .opacity(isVisible ? 1 : 0)
        .blur(radius: isVisible ? 0 : 4)
        .accessibilityHidden(true)
    }
}

private struct PaperBottomNavigation: View {
    let selection: AppTab
    let onSelect: (AppTab) -> Void
    let showCyPlanningCue: Bool
    let hasPendingCyReview: Bool
    let walkthroughStep: AppWalkthroughStep?
    let openCreationHub: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var glassNamespace

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(.rect)
                .onTapGesture { }
                .accessibilityHidden(true)

            HStack(spacing: AgentSpacing.x3) {
                GlassEffectContainer(spacing: AgentSpacing.x1) {
                    HStack(spacing: 0) {
                        ForEach(AppTab.allCases) { tab in
                            Button {
                                onSelect(tab)
                            } label: {
                                tabIcon(for: tab)
                                    .frame(width: 46, height: 46)
                                    .foregroundStyle(foreground(for: tab))
                                    .background {
                                        if isWalkthroughTarget(tab) {
                                            AgentWalkthroughControlCue()
                                        }
                                        if tab == .cy,
                                           showCyPlanningCue,
                                           !hasPendingCyReview,
                                           selection != .cy {
                                            CyWeeklyPlanningPulse()
                                        }
                                        if selection == tab, !isWalkthroughTarget(tab) {
                                            Circle()
                                                .fill(Color.clear)
                                                .agentGlassCircle(
                                                    tint: tab == .cy
                                                        ? Color.cyAccent.opacity(colorScheme == .dark ? 0.34 : 0.78)
                                                        : Color.agentText.opacity(0.09)
                                                )
                                                .matchedGeometryEffect(id: "active-tab", in: glassNamespace)
                                        }
                                    }
                                    .contentShape(.circle)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tab.title)
                            .accessibilityHint(
                                cyAccessibilityHint(for: tab)
                            )
                            .accessibilityAddTraits(selection == tab ? .isSelected : [])
                        }
                    }
                    .padding(6)
                    .frame(height: 58)
                    .frame(maxWidth: .infinity)
                    .glassEffect(
                        .clear,
                        in: .capsule
                    )
                    .overlay {
                        Capsule()
                            .stroke(innerHighlight, lineWidth: 0.5)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity)

                Button(action: openCreationHub) {
                    AgentIconView(.add, size: 24)
                        .frame(width: 56, height: 56)
                        .foregroundStyle(walkthroughStep == .quickAdd ? Color.onCyAccent : Color.agentText)
                }
                .buttonStyle(.plain)
                .agentGlassCircle(interactive: false)
                .background {
                    if walkthroughStep == .quickAdd {
                        AgentWalkthroughControlCue()
                    }
                }
                .overlay {
                    Circle()
                        .stroke(innerHighlight, lineWidth: 0.5)
                    .allowsHitTesting(false)
                }
                .contentShape(.circle)
                .zIndex(2)
                .accessibilityLabel("Create")
                .accessibilityHint("Opens ideas, posts, tasks, and Idea Bank")
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 68)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .snappy(duration: 0.32), value: selection)
    }

    private func foreground(for tab: AppTab) -> Color {
        if isWalkthroughTarget(tab) { return .onCyAccent }
        if tab == .cy { return selection == .cy ? .onCyAccent : .cyAccent }
        return .agentText
    }

    private var innerHighlight: Color {
        Color.agentPureWhite.opacity(colorScheme == .dark ? 0.14 : 0.45)
    }

    private func isWalkthroughTarget(_ tab: AppTab) -> Bool {
        switch walkthroughStep {
        case .dashboard: tab == .home
        case .agenda: tab == .today
        case .tasks: tab == .tasks
        case .pillars: tab == .pillars
        case .ideaBank: tab == .ideaBank
        case .cy: tab == .cy
        case .quickAdd, .none: false
        }
    }

    @ViewBuilder
    private func tabIcon(for tab: AppTab) -> some View {
        if tab == .cy {
            if hasPendingCyReview {
                CyPendingReviewLogo(color: foreground(for: tab))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                CyAsterisk(color: foreground(for: tab), size: 20, strokeWidth: 1.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        } else {
            AgentIconView(tab.icon, size: 20)
        }
    }

    private func cyAccessibilityHint(for tab: AppTab) -> String {
        guard tab == .cy else { return "" }
        if hasPendingCyReview { return "Cy has new changes waiting for review" }
        if showCyPlanningCue { return "Cy is ready to help plan the new week" }
        return ""
    }
}

private struct CyWeeklyPlanningPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if AppShellMotionPolicy.shouldRunContinuousPlanningCue(reduceMotion: reduceMotion) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let progress = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 1.8) / 1.8
                    let wave = CGFloat((sin(progress * .pi * 2) + 1) / 2)
                    planningCueCircle(wave: wave)
                }
            } else {
                planningCueCircle(wave: 0.5)
            }
        }
        .frame(width: 46, height: 46)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func planningCueCircle(wave: CGFloat) -> some View {
        Circle()
            .fill(Color.cyAccent.opacity(reduceMotion ? 0.18 : 0.12 + (wave * 0.14)))
            .frame(width: 42, height: 42)
            .scaleEffect(reduceMotion ? 1.05 : 0.94 + (wave * 0.18))
    }
}

#if DEBUG
#Preview("Loaded creator") {
    let container = PreviewData.makeContainer()
    AppShellView()
        .environment(AppModel(reminderService: PreviewReminderService(), credentialStore: PreviewCredentialStore()))
        .modelContainer(container)
}
#endif
