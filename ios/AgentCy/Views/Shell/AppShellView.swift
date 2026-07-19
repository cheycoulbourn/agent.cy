import SwiftData
import SwiftUI
import UIKit

enum AppWalkthroughTarget: Hashable {
    case dashboardOverview
    case dashboardMenu
    case quickAdd
    case agendaCalendar
    case agendaMenu
    case pillarsOverview
    case pillarsMenu
    case cyComposer
    case cyMenu
}

struct AppWalkthroughTargetPreferenceKey: PreferenceKey {
    static let defaultValue: [AppWalkthroughTarget: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [AppWalkthroughTarget: Anchor<CGRect>],
        nextValue: () -> [AppWalkthroughTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

extension View {
    func appWalkthroughTarget(_ target: AppWalkthroughTarget) -> some View {
        anchorPreference(key: AppWalkthroughTargetPreferenceKey.self, value: .bounds) {
            [target: $0]
        }
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
    private let bottomNavigationClearance: CGFloat = 76

    var body: some View {
        @Bindable var model = appModel
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ZStack {
                    NavigationStack(path: $homePath) { HomeDashboardView().taskNavigationDestinations() }
                        .appTabLayer(.home, selection: model.selectedTab)
                    NavigationStack(path: $planPath) {
                        PlanView()
                            .id(model.requestedPlanNavigationReset)
                            .taskNavigationDestinations()
                    }
                        .appTabLayer(.today, selection: model.selectedTab)
                    NavigationStack(path: $tasksPath) { TasksView().taskNavigationDestinations() }
                        .appTabLayer(.tasks, selection: model.selectedTab)
                    NavigationStack(path: $pillarsPath) { PillarsView().taskNavigationDestinations() }
                        .appTabLayer(.pillars, selection: model.selectedTab)
                    NavigationStack(path: $ideaBankPath) { IdeaBankView().taskNavigationDestinations() }
                        .appTabLayer(.ideaBank, selection: model.selectedTab)
                    NavigationStack(path: $cyPath) {
                        AskCyView(bottomClearance: isKeyboardVisible ? 0 : bottomNavigationClearance)
                            .taskNavigationDestinations()
                    }
                        .appTabLayer(.cy, selection: model.selectedTab)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)

                if !isKeyboardVisible {
                    PaperBottomNavigation(selection: model.selectedTab, onSelect: selectTab, showCyPlanningCue: WeeklyPlanningCue.shouldPulse(
                        on: cueDate,
                        lastOpenedWeekKey: cyPlanningWeekOpened
                    ), hasPendingCyReview: hasPendingMCPReview, openCreationHub: openCreationHub)
                    .padding(.horizontal, AgentLayout.pageMargin)
                    .padding(.top, AgentSpacing.x2)
                    .padding(.bottom, AgentSpacing.x3)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
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

            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.easeOut(duration: 0.24), value: appModel.taskCompletionUndo)
            .overlayPreferenceValue(AppWalkthroughTargetPreferenceKey.self) { targets in
                GeometryReader { overlayProxy in
                    if !isKeyboardVisible,
                       let walkthroughStep = model.walkthroughStep,
                       let target = walkthroughStep.resolvedTarget(in: targets) {
                        WalkthroughSpotlightOverlay(
                            step: walkthroughStep,
                            targetRect: overlayProxy[target],
                            primaryAction: { performWalkthroughAction(for: walkthroughStep) },
                            skipAction: finishWalkthrough
                        )
                        .id(walkthroughStep)
                        .transition(reduceMotion ? .identity : .opacity)
                        .zIndex(12)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $model.presentedSheet) { sheet in
            Group {
                switch sheet {
                case .creationHub: CreationHubView()
                case .quickCapture: QuickCaptureView()
                case .askCy: AskCyView()
                case .settings: SettingsView()
                }
            }
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
            openRequestedTaskIfNeeded()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            presentedMCPRequestIDs = []
            while !Task.isCancelled {
                presentMCPApprovalsIfNeeded()
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
            setWalkthroughStep(.pillars, tab: .pillars)
        case .pillars:
            setWalkthroughStep(.cy, tab: .cy)
        case .cy:
            finishWalkthrough()
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
            appModel.presentedSheet = nil
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
        completedWalkthroughVersion = AppWalkthrough.currentVersion
        walkthroughIsWaitingForQuickAddDismissal = false
        let changes = {
            appModel.presentedSheet = nil
            appModel.walkthroughStep = nil
            appModel.selectedTab = .home
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

            Button("Undo") {
                appModel.undoLastTaskCompletion(context: modelContext)
            }
            .font(.agentSubtext.weight(.bold))
            .frame(minWidth: 56, minHeight: 44)
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
        appModel.presentedSheet = nil
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
            cyPlanningWeekOpened = WeeklyPlanningCue.weekKey(for: Date())
        }
        appModel.selectedTab = tab
    }

    private func openRequestedTaskIfNeeded() {
        guard let taskID = appModel.requestedTaskID else { return }
        appModel.selectedTab = .tasks
        tasksPath = NavigationPath()
        tasksPath.append(TaskNavigationRoute(taskID: taskID))
        appModel.requestedTaskID = nil
    }

    private func presentMCPApprovalsIfNeeded() {
        guard MCPBridgePreferences.isConnected else {
            hasPendingMCPReview = false
            presentedMCPRequestIDs = []
            return
        }
        guard let requests = try? MCPBridgeService.pendingRequests() else {
            return
        }
        let requestIDs = Set(requests.map(\.id))
        hasPendingMCPReview = !requestIDs.isEmpty
        guard !requestIDs.isEmpty else {
            presentedMCPRequestIDs = []
            return
        }
        guard !requestIDs.subtracting(presentedMCPRequestIDs).isEmpty else { return }
        presentedMCPRequestIDs = requestIDs

        appModel.presentedSheet = nil
        appModel.requestedSettingsPage = nil
        cyPath = NavigationPath()
        appModel.selectedTab = .cy
    }

}

private extension AppWalkthroughStep {
    var title: String {
        switch self {
        case .dashboard: "Your day, at a glance."
        case .quickAdd: "Start with whatever you have."
        case .agenda: "Give the work a place."
        case .pillars: "Keep ideas connected."
        case .cy: "Shape it with Cy."
        }
    }

    var detail: String {
        switch self {
        case .dashboard:
            "See today’s focus, scheduled posts, tasks, and recent ideas."
        case .quickAdd:
            "Save an idea, create a post, or add a task from the plus button."
        case .agenda:
            "Plan posts by day and use focus days to batch similar work."
        case .pillars:
            "Pillars organize what you create. The Idea Bank holds thoughts you are not ready to schedule."
        case .cy:
            "Ask for ideas, post development, or planning help. Review changes before they enter your calendar."
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .dashboard, .agenda, .pillars: "Next"
        case .quickAdd: "Open Quick Add"
        case .cy: "Finish"
        }
    }

    var progressLabel: String {
        "\(rawValue + 1) of \(Self.allCases.count)"
    }

    var preferredTargets: [AppWalkthroughTarget] {
        switch self {
        case .dashboard: [.dashboardOverview, .dashboardMenu]
        case .quickAdd: [.quickAdd]
        case .agenda: [.agendaCalendar, .agendaMenu]
        case .pillars: [.pillarsOverview, .pillarsMenu]
        case .cy: [.cyComposer, .cyMenu]
        }
    }

    func resolvedTarget(
        in targets: [AppWalkthroughTarget: Anchor<CGRect>]
    ) -> Anchor<CGRect>? {
        preferredTargets.lazy.compactMap { targets[$0] }.first
    }

    var spotlightCornerRadius: CGFloat {
        switch self {
        case .quickAdd: 34
        case .agenda, .dashboard, .pillars: 22
        case .cy: 28
        }
    }
}

private struct WalkthroughSpotlightOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let step: AppWalkthroughStep
    let targetRect: CGRect
    let primaryAction: () -> Void
    let skipAction: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let spotlight = spotlightRect(in: proxy.size)

            ZStack {
                WalkthroughSpotlightMask(
                    spotlightRect: spotlight,
                    cornerRadius: step.spotlightCornerRadius
                )
                .fill(
                    Color.agentPureBlack.opacity(colorScheme == .dark ? 0.58 : 0.44),
                    style: FillStyle(eoFill: true)
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                WalkthroughInteractionShield(spotlightRect: spotlight)
                    .accessibilityHidden(true)

                RoundedRectangle(cornerRadius: step.spotlightCornerRadius)
                    .stroke(Color.cyAccent, lineWidth: 1.5)
                    .frame(width: spotlight.width, height: spotlight.height)
                    .position(x: spotlight.midX, y: spotlight.midY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                coachPlacement(around: spotlight, in: proxy.size)
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: targetRect)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func coachPlacement(around spotlight: CGRect, in size: CGSize) -> some View {
        let placeAbove = spotlight.midY > size.height * 0.54

        VStack(spacing: 0) {
            if placeAbove {
                WalkthroughCoachCard(
                    step: step,
                    primaryAction: primaryAction,
                    skipAction: skipAction
                )
                .padding(.top, 64)
                Spacer(minLength: AgentSpacing.x4)
            } else {
                Spacer(minLength: AgentSpacing.x4)
                WalkthroughCoachCard(
                    step: step,
                    primaryAction: primaryAction,
                    skipAction: skipAction
                )
                .padding(.bottom, 92)
            }
        }
        .padding(.horizontal, AgentLayout.pageMargin)
    }

    private func spotlightRect(in size: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
        let expanded = targetRect.insetBy(dx: -10, dy: -10)
        return expanded.intersection(bounds)
    }
}

private struct WalkthroughSpotlightMask: Shape {
    let spotlightRect: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(
            in: spotlightRect,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
        )
        return path
    }
}

private struct WalkthroughInteractionShield: View {
    let spotlightRect: CGRect

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                blocker(
                    x: size.width / 2,
                    y: spotlightRect.minY / 2,
                    width: size.width,
                    height: spotlightRect.minY
                )
                blocker(
                    x: size.width / 2,
                    y: spotlightRect.maxY + (size.height - spotlightRect.maxY) / 2,
                    width: size.width,
                    height: size.height - spotlightRect.maxY
                )
                blocker(
                    x: spotlightRect.minX / 2,
                    y: spotlightRect.midY,
                    width: spotlightRect.minX,
                    height: spotlightRect.height
                )
                blocker(
                    x: spotlightRect.maxX + (size.width - spotlightRect.maxX) / 2,
                    y: spotlightRect.midY,
                    width: size.width - spotlightRect.maxX,
                    height: spotlightRect.height
                )
            }
        }
    }

    private func blocker(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        Color.clear
            .frame(width: max(0, width), height: max(0, height))
            .contentShape(.rect)
            .position(x: x, y: y)
            .onTapGesture { }
    }
}

private struct WalkthroughCoachCard: View {
    let step: AppWalkthroughStep
    let primaryAction: () -> Void
    let skipAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(alignment: .center, spacing: AgentSpacing.x3) {
                Text(step.progressLabel.uppercased())
                    .font(.paperInter(size: 11, weight: .semibold, relativeTo: .caption))
                    .tracking(1)
                    .foregroundStyle(Color.agentSecondary)

                Spacer()

                Button("Skip tour", action: skipAction)
                    .font(.paperInter(size: 13, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(Color.agentSecondary)
                    .frame(minWidth: 72, minHeight: 44)
                    .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                Text(step.title)
                    .font(.paperInter(size: 22, weight: .bold, relativeTo: .title2))
                    .foregroundStyle(Color.agentText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.detail)
                    .font(.paperInter(size: 15, weight: .regular, relativeTo: .body))
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: primaryAction) {
                HStack(spacing: AgentSpacing.x2) {
                    Text(step.primaryActionTitle)
                    Spacer()
                    AgentIconView(step == .cy ? .check : .forward, size: 15)
                }
                .font(.paperInter(size: 15, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(Color.agentCanvas)
                .padding(.horizontal, AgentSpacing.x4)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.agentText, in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Continues to the next walkthrough step")
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentSurface, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.cyAccent.opacity(0.34), lineWidth: 1)
        }
        .accessibilityLabel("Walkthrough. \(step.title) \(step.detail)")
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(100)
    }
}

private extension View {
    func appTabLayer(_ tab: AppTab, selection: AppTab) -> some View {
        opacity(selection == tab ? 1 : 0)
            .allowsHitTesting(selection == tab)
            .accessibilityHidden(selection != tab)
            .zIndex(selection == tab ? 1 : 0)
            .transaction { transaction in
                transaction.animation = nil
            }
    }
}

private struct PaperBottomNavigation: View {
    let selection: AppTab
    let onSelect: (AppTab) -> Void
    let showCyPlanningCue: Bool
    let hasPendingCyReview: Bool
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
                                        if tab == .cy,
                                           showCyPlanningCue,
                                           !hasPendingCyReview,
                                           selection != .cy {
                                            CyWeeklyPlanningPulse()
                                        }
                                        if selection == tab {
                                            Circle()
                                                .fill(Color.clear)
                                                .glassEffect(
                                                    .clear.interactive()
                                                        .tint(
                                                            tab == .cy
                                                                ? Color.cyAccent.opacity(colorScheme == .dark ? 0.34 : 0.78)
                                                                : Color.agentText.opacity(0.09)
                                                        ),
                                                    in: .circle
                                                )
                                                .matchedGeometryEffect(id: "active-tab", in: glassNamespace)
                                        }
                                    }
                                    .contentShape(.circle)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .anchorPreference(
                                key: AppWalkthroughTargetPreferenceKey.self,
                                value: .bounds
                            ) { anchor in
                                guard let target = walkthroughTarget(for: tab) else { return [:] }
                                return [target: anchor]
                            }
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
                        .foregroundStyle(Color.agentText)
                }
                .buttonStyle(.plain)
                .glassEffect(.clear, in: .circle)
                .overlay {
                    Circle()
                        .stroke(innerHighlight, lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
                .contentShape(.circle)
                .appWalkthroughTarget(.quickAdd)
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
        if tab == .cy { return selection == .cy ? .onCyAccent : .cyAccent }
        return .agentText
    }

    private var innerHighlight: Color {
        Color.agentPureWhite.opacity(colorScheme == .dark ? 0.14 : 0.45)
    }

    private func walkthroughTarget(for tab: AppTab) -> AppWalkthroughTarget? {
        switch tab {
        case .home: .dashboardMenu
        case .today: .agendaMenu
        case .pillars: .pillarsMenu
        case .cy: .cyMenu
        case .tasks, .ideaBank: nil
        }
    }

    @ViewBuilder
    private func tabIcon(for tab: AppTab) -> some View {
        if tab == .cy {
            if hasPendingCyReview {
                CyPendingReviewAsterisk(color: foreground(for: tab))
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

private struct CyPendingReviewAsterisk: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRotating = false

    var body: some View {
        CyAsterisk(color: color, size: 20, strokeWidth: 1.8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .rotationEffect(.degrees(reduceMotion ? 0 : (isRotating ? 360 : 0)))
            .animation(
                reduceMotion ? nil : .linear(duration: 1.8).repeatForever(autoreverses: false),
                value: isRotating
            )
            .onAppear { isRotating = true }
            .accessibilityHidden(true)
    }
}

private struct CyWeeklyPlanningPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let progress = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.8) / 1.8
            let wave = CGFloat((sin(progress * .pi * 2) + 1) / 2)

            Circle()
                .fill(Color.cyAccent.opacity(reduceMotion ? 0.18 : 0.12 + (wave * 0.14)))
                .frame(width: 42, height: 42)
                .scaleEffect(reduceMotion ? 1.05 : 0.94 + (wave * 0.18))
                .shadow(
                    color: Color.cyAccent.opacity(reduceMotion ? 0.28 : 0.24 + (wave * 0.34)),
                    radius: reduceMotion ? 8 : 7 + (wave * 7)
                )
        }
        .frame(width: 46, height: 46)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Loaded creator") {
    let container = PreviewData.makeContainer()
    AppShellView()
        .environment(AppModel(reminderService: PreviewReminderService(), credentialStore: PreviewCredentialStore()))
        .modelContainer(container)
}
