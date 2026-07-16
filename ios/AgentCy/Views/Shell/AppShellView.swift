import SwiftData
import SwiftUI
import UIKit

struct AppShellView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(WeeklyPlanningCue.lastOpenedStorageKey) private var cyPlanningWeekOpened = ""
    @State private var isKeyboardVisible = false
    @State private var cueDate = Date()
    @State private var planPath = NavigationPath()
    @State private var tasksPath = NavigationPath()
    @State private var pillarsPath = NavigationPath()
    @State private var ideaBankPath = NavigationPath()
    @State private var cyPath = NavigationPath()
    @State private var planRootID = UUID()
    @State private var tasksRootID = UUID()
    @State private var pillarsRootID = UUID()
    @State private var ideaBankRootID = UUID()
    @State private var cyRootID = UUID()
    @State private var presentedMCPRequestIDs: Set<UUID> = []
    @State private var hasPendingMCPReview = false
    private let bottomNavigationClearance: CGFloat = 76

    var body: some View {
        @Bindable var model = appModel
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ZStack {
                    NavigationStack(path: $planPath) { PlanView().taskNavigationDestinations() }
                        .id(planRootID)
                        .appTabLayer(.today, selection: model.selectedTab)
                    NavigationStack(path: $tasksPath) { TasksView().taskNavigationDestinations() }
                        .id(tasksRootID)
                        .appTabLayer(.tasks, selection: model.selectedTab)
                    NavigationStack(path: $pillarsPath) { PillarsView().taskNavigationDestinations() }
                        .id(pillarsRootID)
                        .appTabLayer(.pillars, selection: model.selectedTab)
                    NavigationStack(path: $ideaBankPath) { IdeaBankView().taskNavigationDestinations() }
                        .id(ideaBankRootID)
                        .appTabLayer(.ideaBank, selection: model.selectedTab)
                    NavigationStack(path: $cyPath) {
                        AskCyView(bottomClearance: isKeyboardVisible ? 0 : bottomNavigationClearance)
                            .taskNavigationDestinations()
                    }
                        .id(cyRootID)
                        .appTabLayer(.cy, selection: model.selectedTab)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)

                if !isKeyboardVisible {
                    PaperBottomNavigation(selection: model.selectedTab, onSelect: selectTab, showCyPlanningCue: WeeklyPlanningCue.shouldPulse(
                        on: cueDate,
                        lastOpenedWeekKey: cyPlanningWeekOpened
                    ), hasPendingCyReview: hasPendingMCPReview) {
                        appModel.presentedSheet = .creationHub
                    }
                    .padding(.horizontal, AgentLayout.pageMargin)
                    .padding(.top, AgentSpacing.x2)
                    .padding(.bottom, AgentSpacing.x3)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
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
        .onChange(of: appModel.workspaceRevision) { _, _ in
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
    }

    private func selectTab(_ tab: AppTab) {
        appModel.presentedSheet = nil
        switch tab {
        case .today:
            planPath = NavigationPath()
            planRootID = UUID()
        case .tasks:
            tasksPath = NavigationPath()
            tasksRootID = UUID()
        case .pillars:
            pillarsPath = NavigationPath()
            pillarsRootID = UUID()
        case .ideaBank:
            ideaBankPath = NavigationPath()
            ideaBankRootID = UUID()
        case .cy:
            cyPath = NavigationPath()
            cyRootID = UUID()
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
                                if reduceMotion {
                                    onSelect(tab)
                                } else {
                                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                        onSelect(tab)
                                    }
                                }
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
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .medium))
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
        Color.white.opacity(colorScheme == .dark ? 0.14 : 0.45)
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
            Image(systemName: tab.symbol)
                .font(.system(size: 18, weight: .regular))
                .symbolRenderingMode(.monochrome)
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
