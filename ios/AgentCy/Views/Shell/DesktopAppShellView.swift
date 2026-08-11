#if targetEnvironment(macCatalyst)
import SwiftData
import SwiftUI

struct DesktopAppShellView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [CreatorProfile]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @Query(sort: \CreatorTask.createdAt, order: .reverse) private var allTasks: [CreatorTask]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt, order: .reverse) private var allOutputs: [PlatformOutput]
    @State private var selection: DesktopNavigationDestination? = DesktopNavigationPolicy.defaultDestination
    @State private var homePath = NavigationPath()
    @State private var planPath = NavigationPath()
    @State private var feedPath = NavigationPath()
    @State private var tasksPath = NavigationPath()
    @State private var ideaBankPath = NavigationPath()
    @State private var savedPostsPath = NavigationPath()
    @State private var pillarsPath = NavigationPath()
    @State private var cyPath = NavigationPath()
    @State private var presentedMCPRequestIDs: Set<UUID> = []
    @State private var hasPendingMCPReview = false
    @State private var isEditingUtilitySidebar = false
    @AppStorage("agentcy.desktopUtilityHiddenWidgets") private var storedHiddenUtilityWidgets = ""
    @AppStorage("agentcy.desktopUtilityWidgetOrder") private var storedUtilityWidgetOrder = ""

    var body: some View {
        @Bindable var model = appModel

        GeometryReader { proxy in
            let metrics = DesktopLayoutPolicy.metrics(forWindowWidth: proxy.size.width)

            HStack(spacing: 0) {
                sidebar
                    .frame(width: metrics.leadingSidebarWidth)

                workspace(metrics: metrics)

                if metrics.showsUtilitySidebar {
                    utilitySidebar
                        .frame(width: metrics.utilitySidebarWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.agentCanvas)
            .animation(.snappy(duration: 0.24), value: metrics.showsUtilitySidebar)
        }
        .frame(minWidth: 960, minHeight: 640)
        .tint(Color.actionAccent)
        .sheet(item: nonCreationSheetBinding) { sheet in
            let metrics = DesktopLayoutPolicy.sheetMetrics(for: sheet)
            Group {
                switch sheet {
                case .creationHub: EmptyView()
                case .quickCapture: QuickCaptureView()
                case .askCy: AskCyView(showsCloseButton: true)
                case .settings: SettingsView()
                }
            }
            .environment(appModel)
            .modelContext(modelContext)
            .frame(width: metrics.width, height: metrics.height)
            .background(Color.agentCanvas.ignoresSafeArea())
            .presentationBackground(Color.agentCanvas)
        }
        .sheet(item: $model.inspirationReviewRoute) { route in
            InspirationReviewView(sourceID: route.id)
                .environment(appModel)
                .modelContext(modelContext)
                .frame(minWidth: 640, idealWidth: 760, minHeight: 600, idealHeight: 780)
        }
        .alert("agent.cy", isPresented: Binding(
            get: { appModel.notice != nil },
            set: { if !$0 { appModel.notice = nil } }
        )) {
            Button("Close") { appModel.notice = nil }
        } message: {
            Text(appModel.notice?.message ?? "")
        }
        .overlay(alignment: .top) {
            if let undo = appModel.taskCompletionUndo {
                taskCompletionUndoToast(undo)
                    .padding(.top, AgentSpacing.x5)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            cyFloatingButton
            .padding(AgentSpacing.x6)
        }
        .agentScreen()
        .overlay {
            if appModel.presentedSheet == .creationHub {
                creationHubOverlay
            }
        }
        .task {
            await appModel.refreshAccess(context: modelContext)
            await appModel.refreshReminderSchedule(context: modelContext)
            appModel.importPendingInspiration(context: modelContext)
            openRequestedTaskIfNeeded()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            appModel.importPendingInspiration(context: modelContext)
            presentedMCPRequestIDs = []
            while !Task.isCancelled {
                presentMCPApprovalsIfNeeded()
                try? await Task.sleep(for: .seconds(4))
            }
        }
        .onChange(of: selection) { _, destination in
            guard let destination else {
                selection = DesktopNavigationPolicy.defaultDestination
                return
            }
            if let tab = destination.appTab, appModel.selectedTab != tab {
                appModel.selectedTab = tab
            }
        }
        .onChange(of: appModel.selectedTab) { _, tab in
            let destination = DesktopNavigationPolicy.destination(for: tab)
            if selection != destination {
                selection = destination
            }
        }
        .onChange(of: appModel.requestedTaskID) { _, _ in
            openRequestedTaskIfNeeded()
        }
        .onChange(of: appModel.requestedPlanNavigationReset) { _, _ in
            planPath = NavigationPath()
        }
        .onChange(of: appModel.workspaceRevision) { _, _ in
            resetNavigationPaths()
        }
    }

    private var nonCreationSheetBinding: Binding<AppSheet?> {
        Binding(
            get: {
                guard appModel.presentedSheet != .creationHub else { return nil }
                return appModel.presentedSheet
            },
            set: { appModel.presentedSheet = $0 }
        )
    }

    private var creationHubOverlay: some View {
        GeometryReader { proxy in
            let metrics = DesktopLayoutPolicy.sheetMetrics(for: .creationHub)
            let width = min(metrics.width, max(680, proxy.size.width - 160))
            let height = min(metrics.height, max(600, proxy.size.height - 96))

            ZStack {
                Button(action: closeCreationHub) {
                    Color.agentPureBlack.opacity(0.18)
                        .ignoresSafeArea()
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)

                CreationHubView(onDismiss: closeCreationHub)
                    .environment(appModel)
                    .modelContext(modelContext)
                    .frame(width: width, height: height)
                    .background(Color.agentCanvas)
                    .clipShape(.rect(cornerRadius: AgentRadius.floating))
                    .agentSurfaceChrome(cornerRadius: AgentRadius.floating, role: .floating)
                    .accessibilityAddTraits(.isModal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func closeCreationHub() {
        appModel.presentedSheet = nil
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            brandHeader

            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x5) {
                    ForEach(DesktopNavigationPolicy.sidebarSections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                            MetaLabel(section.title)
                                .padding(.horizontal, AgentSpacing.x3)

                            ForEach(section.destinations) { destination in
                                navigationRow(destination)
                            }
                        }
                    }
                }
                .padding(.horizontal, AgentSpacing.x3)
                .padding(.top, AgentSpacing.x3)
            }

            settingsButton
        }
        .background(Color.agentSurface)
    }

    private var brandHeader: some View {
        HStack(spacing: AgentSpacing.x3) {
            CyAsterisk(color: .cyAccent, size: 23, strokeWidth: 2)
                .frame(width: 24, height: 24)

            Text("agent.cy")
                .font(.agentInter(size: 22, weight: .bold, relativeTo: .title3))
                .tracking(-0.5)
                .foregroundStyle(Color.agentText)
                .frame(height: 24)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AgentSpacing.x5)
        .padding(.top, AgentSpacing.x5)
        .padding(.bottom, AgentSpacing.x4)
        .accessibilityElement(children: .combine)
    }

    private func navigationRow(_ destination: DesktopNavigationDestination) -> some View {
        let isSelected = selection == destination

        return Button {
            selection = destination
            if let tab = destination.appTab {
                appModel.selectedTab = tab
            }
        } label: {
            HStack(spacing: AgentSpacing.x3) {
                AgentIconView(destination.icon, size: 17)
                    .foregroundStyle(isSelected ? Color.agentText : Color.agentSecondary)
                    .frame(width: 18, height: 18)

                Text(destination.title)
                    .font(.agentDesktopNavigation.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(Color.agentText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, AgentSpacing.x3)
            .frame(minHeight: 40)
            .background(
                isSelected ? Color.agentSelectionFill : Color.clear,
                in: .rect(cornerRadius: AgentRadius.control)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(Color.agentSelectionIndicator)
                        .frame(width: 2, height: 16)
                        .padding(.leading, 1)
                }
            }
            .contentShape(.rect(cornerRadius: AgentRadius.control))
        }
        .buttonStyle(AgentPressButtonStyle())
        .accessibilityElement(children: .combine)
    }

    private var settingsButton: some View {
        Button {
            appModel.presentedSheet = .settings
        } label: {
            HStack(spacing: AgentSpacing.x3) {
                CreatorAvatar(identity: activeIdentity, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(activeIdentity.greetingName)
                        .font(.agentDesktopUtilityBodyEmphasis)
                        .foregroundStyle(Color.agentText)
                        .lineLimit(1)
                    Text("Settings")
                        .font(.agentDesktopUtilityMetadata)
                        .foregroundStyle(Color.agentSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "gearshape")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Color.agentSecondary)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, AgentSpacing.x4)
            .padding(.vertical, AgentSpacing.x2)
            .contentShape(.rect)
        }
        .buttonStyle(AgentPressButtonStyle())
        .overlay(alignment: .top) {
            Rectangle().fill(Color.agentBorder).frame(height: 1)
        }
        .accessibilityLabel("Profile and settings")
    }

    private func workspace(metrics: DesktopLayoutMetrics) -> some View {
        detail
            .frame(maxWidth: metrics.contentMaximumWidth, maxHeight: .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, metrics.contentHorizontalPadding)
            .background(Color.agentCanvas)
            .clipped()
    }

    private var utilitySidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x5) {
                utilitySidebarHeader
                quickAddButton

                if isEditingUtilitySidebar {
                    utilityWidgetEditor
                }

                ForEach(orderedUtilityWidgets) { widget in
                    if isUtilityWidgetVisible(widget) {
                        utilityWidget(widget)
                    }
                }
            }
            .padding(.horizontal, AgentSpacing.x4)
            .padding(.top, AgentSpacing.x5)
            .padding(.bottom, 104)
        }
        .scrollIndicators(.hidden)
        .background(Color.agentSurface)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.agentHairline)
                .frame(width: 0.5)
                .allowsHitTesting(false)
        }
    }

    private var utilitySidebarHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            MetaLabel("Control Center")
            Spacer(minLength: AgentSpacing.x3)
            Button(isEditingUtilitySidebar ? "Done" : "Edit") {
                isEditingUtilitySidebar.toggle()
            }
            .font(.agentDesktopUtilityAction)
            .foregroundStyle(Color.actionAccent)
            .frame(minWidth: 40, minHeight: 40)
            .contentShape(.rect)
            .buttonStyle(.plain)
            .accessibilityHint(
                isEditingUtilitySidebar
                    ? "Finishes customizing the sidebar"
                    : "Chooses which widgets appear in the sidebar"
            )
        }
    }

    private var utilityWidgetEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Show and arrange")
                .font(.agentDesktopUtilityMetadata)
                .foregroundStyle(Color.agentSecondary)
                .padding(.horizontal, AgentSpacing.x3)
                .padding(.top, AgentSpacing.x3)
                .padding(.bottom, AgentSpacing.x2)

            ForEach(Array(orderedUtilityWidgets.enumerated()), id: \.element.id) { index, widget in
                HStack(spacing: AgentSpacing.x2) {
                    AgentIconView(widget.icon, size: 15)
                        .foregroundStyle(Color.agentSecondary)
                        .frame(width: 20, height: 20)

                    Text(widget.title)
                        .font(.agentDesktopUtilityBodyEmphasis)
                        .foregroundStyle(Color.agentText)
                        .lineLimit(1)

                    Spacer(minLength: AgentSpacing.x1)

                    widgetMoveButton(widget, direction: -1, isEnabled: index > 0)
                    widgetMoveButton(
                        widget,
                        direction: 1,
                        isEnabled: index < orderedUtilityWidgets.count - 1
                    )

                    Toggle("Show \(widget.title)", isOn: utilityWidgetVisibilityBinding(for: widget))
                        .labelsHidden()
                        .tint(Color.actionAccent)
                        .controlSize(.small)
                }
                .padding(.horizontal, AgentSpacing.x3)
                .frame(minHeight: 48)

                if index < orderedUtilityWidgets.count - 1 {
                    Rectangle().fill(Color.agentHairline).frame(height: 1)
                }
            }
        }
        .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.panel))
        .agentSurfaceChrome(cornerRadius: AgentRadius.panel, role: .structural)
    }

    private func widgetMoveButton(
        _ widget: DesktopUtilityWidget,
        direction: Int,
        isEnabled: Bool
    ) -> some View {
        Button {
            moveUtilityWidget(widget, direction: direction)
        } label: {
            AgentIconView(direction < 0 ? .collapse : .expand, size: 11)
                .foregroundStyle(Color.agentSecondary)
                .frame(width: 28, height: 28)
                .background(Color.agentSurface, in: .circle)
                .frame(width: 40, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.28)
        .accessibilityLabel(direction < 0 ? "Move \(widget.title) up" : "Move \(widget.title) down")
    }

    private var quickAddButton: some View {
        Button {
            appModel.presentedSheet = .creationHub
        } label: {
            HStack(spacing: AgentSpacing.x3) {
                AgentIconView(.add, size: 15)
                    .foregroundStyle(Color.agentPureBlack)
                    .frame(width: 32, height: 32)
                    .background(Color.agentPureBlack.opacity(0.045), in: .circle)
                Text("Quick add")
                    .font(.agentDesktopQuickAction)
                    .foregroundStyle(Color.agentPureBlack)
                Spacer(minLength: 0)
                Text("⌘N")
                    .font(.agentDesktopUtilityMetadata)
                    .foregroundStyle(Color.agentPureBlack.opacity(0.58))
            }
            .padding(.horizontal, AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color.agentPureWhite, in: .rect(cornerRadius: AgentRadius.panel))
            .overlay {
                RoundedRectangle(cornerRadius: AgentRadius.panel)
                    .stroke(Color.agentPureBlack.opacity(0.14), lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: AgentRadius.panel))
        }
        .buttonStyle(AgentPressButtonStyle())
        .keyboardShortcut("n", modifiers: .command)
        .accessibilityHint("Creates a new idea, post, or task")
    }

    @ViewBuilder
    private func utilityWidget(_ widget: DesktopUtilityWidget) -> some View {
        switch widget {
        case .tasks:
            taskWidget
        case .upcomingPosts:
            upcomingPostsWidget
        case .ideas:
            ideasWidget
        }
    }

    private var taskWidget: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    MetaLabel("Tasks")
                    Text("What’s next")
                        .font(.agentDesktopUtilityTitle)
                }
                Spacer(minLength: AgentSpacing.x2)
                Text("\(utilityTasks.count)")
                    .font(.agentDesktopUtilityAction)
                    .monospacedDigit()
                    .foregroundStyle(Color.agentSecondary)
            }

            if utilityTasks.isEmpty {
                Text("No tasks due today.")
                    .font(.agentDesktopUtilityBody)
                    .foregroundStyle(Color.agentSecondary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(utilityTasks.prefix(5).enumerated()), id: \.element.id) { index, task in
                        HStack(alignment: .center, spacing: AgentSpacing.x2) {
                            AgentTaskCheckbox(
                                isCompleted: task.isCompleted,
                                color: .agentSecondary,
                                accessibilityLabel: "Complete \(utilityTitle(for: task))"
                            ) {
                                completeUtilityTask(task)
                            }
                            .frame(width: 28, height: 44, alignment: .leading)
                            .accessibilityHint("Marks this task complete")

                            Button { openTask(task.id) } label: {
                                Text(utilityTitle(for: task))
                                    .font(.agentDesktopUtilityBody)
                                    .fontWeight(.regular)
                                    .foregroundStyle(Color.agentText)
                                    .lineLimit(2)
                                    .frame(
                                        maxWidth: .infinity,
                                        minHeight: 44,
                                        alignment: .leading
                                    )
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens task details")
                        }
                        .frame(minHeight: 44)

                        if index < min(utilityTasks.count, 5) - 1 {
                            Rectangle().fill(Color.agentHairline).frame(height: 1)
                        }
                    }
                }
            }

            utilityWidgetViewAllFooter(
                accessibilityLabel: "View all tasks",
                action: openTasks
            )
        }
        .utilityWidgetCard()
    }

    private func completeUtilityTask(_ task: CreatorTask) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            appModel.toggleTask(task, context: modelContext)
        }
    }

    private var upcomingPostsWidget: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel("Upcoming Posts")
                Spacer(minLength: AgentSpacing.x2)
                Text("\(upcomingUtilityOutputs.count)")
                    .font(.agentDesktopUtilityAction)
                    .monospacedDigit()
                    .foregroundStyle(Color.agentSecondary)
            }

            if let output = upcomingUtilityOutputs.first,
               let brief = utilityBrief(for: output) {
                Button { openUpcomingPost(brief.id) } label: {
                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        Text(brief.title)
                            .font(.agentDesktopUtilityTitle)
                            .foregroundStyle(Color.agentText)
                            .lineLimit(2)
                        Text(output.targetDate.map(utilityPostDate) ?? "Scheduled")
                            .font(.agentDesktopUtilityMetadata)
                            .foregroundStyle(Color.agentSecondary)
                            .lineLimit(1)
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 44,
                        alignment: .leading
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(AgentPressButtonStyle())
                .accessibilityHint("Opens this post")
            } else {
                Text("Nothing scheduled yet.")
                    .font(.agentDesktopUtilityBody)
                    .foregroundStyle(Color.agentSecondary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }

            utilityWidgetViewAllFooter(
                accessibilityLabel: "View all upcoming posts",
                action: openPlan
            )
        }
        .utilityWidgetCard()
    }

    private var ideasWidget: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel("Idea Bank")
                Spacer(minLength: AgentSpacing.x2)
                Text("\(utilityIdeas.count)")
                    .font(.agentDesktopUtilityAction)
                    .monospacedDigit()
                    .foregroundStyle(Color.agentSecondary)
            }

            if utilityIdeas.isEmpty {
                Text("Capture an idea to see it here.")
                    .font(.agentDesktopUtilityBody)
                    .foregroundStyle(Color.agentSecondary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(
                        Array(utilityIdeas.prefix(DesktopUtilityWidgetContentPolicy.ideaPreviewLimit).enumerated()),
                        id: \.element.id
                    ) { index, idea in
                        Button { openUtilityIdea(idea) } label: {
                            Text(idea.title)
                                .font(.agentDesktopUtilityBodyEmphasis)
                                .foregroundStyle(Color.agentText)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(AgentPressButtonStyle())
                        .accessibilityHint("Opens this idea")

                        if index < min(
                            utilityIdeas.count,
                            DesktopUtilityWidgetContentPolicy.ideaPreviewLimit
                        ) - 1 {
                            Rectangle().fill(Color.agentHairline).frame(height: 1)
                        }
                    }
                }
            }

            utilityWidgetViewAllFooter(
                accessibilityLabel: "View all ideas",
                action: openIdeaBank
            )
        }
        .utilityWidgetCard()
    }

    private func utilityWidgetViewAllFooter(
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: AgentSpacing.x2) {
            Rectangle()
                .fill(Color.agentHairline)
                .frame(height: 1)

            Button(action: action) {
                HStack(spacing: AgentSpacing.x2) {
                    Text("View all")
                        .font(.agentDesktopUtilityAction)
                        .foregroundStyle(Color.agentSecondary)
                    Spacer(minLength: AgentSpacing.x2)
                    AgentIconView(.arrowRight, size: 12)
                        .foregroundStyle(Color.actionAccent)
                }
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private var cyFloatingButton: some View {
        Button {
            appModel.presentedSheet = .askCy
        } label: {
            ZStack(alignment: .topTrailing) {
                CyAsterisk(color: .agentPureWhite, size: 24, strokeWidth: 2)
                    .frame(width: 56, height: 56)
                    .background(Color.cyAccent, in: .circle)
                    .shadow(color: Color.cyAccent.opacity(0.26), radius: 18, y: 8)

                if hasPendingMCPReview {
                    Circle()
                        .fill(Color.agentPureWhite)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.cyAccent, lineWidth: 2))
                }
            }
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("k", modifiers: .command)
        .accessibilityLabel("Open Cy")
        .accessibilityHint("Opens your creative copilot")
    }

    private var utilityTasks: [CreatorTask] {
        let archivedBriefIDs = Set(allBriefs.lazy.filter { $0.status == .archived }.map(\.id))
        return allTasks
            .filter { task in
                DesktopUtilityTaskPolicy.includes(
                    task,
                    archivedBriefIDs: archivedBriefIDs,
                    activeWorkspaceID: appModel.activeWorkspaceID,
                    workspaces: workspaces
                )
            }
            .sorted {
                let lhs = $0.targetDate ?? $0.dailyFocusDate ?? .distantFuture
                let rhs = $1.targetDate ?? $1.dailyFocusDate ?? .distantFuture
                if lhs != rhs { return lhs < rhs }
                return $0.createdAt < $1.createdAt
            }
    }

    private var utilityIdeas: [CreativeBrief] {
        allBriefs.filter { brief in
            WorkspaceScope.includes(
                brief.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            ) && IdeaBankPlacementPolicy.includes(brief) &&
                !brief.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var upcomingUtilityOutputs: [PlatformOutput] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let activeBriefIDs = Set(allBriefs.lazy.filter { brief in
            brief.status != .archived && WorkspaceScope.includes(
                brief.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }.map(\.id))

        return allOutputs.filter { output in
            guard let targetDate = output.targetDate else { return false }
            return targetDate >= startOfToday && output.status != .posted &&
                activeBriefIDs.contains(output.briefID) && WorkspaceScope.includes(
                    output.workspaceID,
                    activeWorkspaceID: appModel.activeWorkspaceID,
                    workspaces: workspaces
                )
        }
        .sorted { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
    }

    private func utilityBrief(for output: PlatformOutput) -> CreativeBrief? {
        allBriefs.first { $0.id == output.briefID }
    }

    private func utilityPostDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var hiddenUtilityWidgets: Set<DesktopUtilityWidget> {
        DesktopUtilityWidgetVisibilityPolicy.hiddenWidgets(from: storedHiddenUtilityWidgets)
    }

    private var orderedUtilityWidgets: [DesktopUtilityWidget] {
        DesktopUtilityWidgetOrderPolicy.orderedWidgets(from: storedUtilityWidgetOrder)
    }

    private func isUtilityWidgetVisible(_ widget: DesktopUtilityWidget) -> Bool {
        !hiddenUtilityWidgets.contains(widget)
    }

    private func utilityWidgetVisibilityBinding(for widget: DesktopUtilityWidget) -> Binding<Bool> {
        Binding(
            get: { isUtilityWidgetVisible(widget) },
            set: { isVisible in
                var hiddenWidgets = hiddenUtilityWidgets
                if isVisible {
                    hiddenWidgets.remove(widget)
                } else {
                    hiddenWidgets.insert(widget)
                }
                storedHiddenUtilityWidgets = DesktopUtilityWidgetVisibilityPolicy.storageValue(
                    for: hiddenWidgets
                )
            }
        )
    }

    private func moveUtilityWidget(_ widget: DesktopUtilityWidget, direction: Int) {
        var widgets = orderedUtilityWidgets
        guard let currentIndex = widgets.firstIndex(of: widget) else { return }
        let destinationIndex = currentIndex + direction
        guard widgets.indices.contains(destinationIndex) else { return }
        widgets.swapAt(currentIndex, destinationIndex)
        storedUtilityWidgetOrder = DesktopUtilityWidgetOrderPolicy.storageValue(for: widgets)
    }

    private func utilityTitle(for task: CreatorTask) -> String {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled task" : title
    }

    private func openTasks() {
        selection = .tasks
        appModel.selectedTab = .tasks
    }

    private func openPlan() {
        selection = .plan
        appModel.selectedTab = .today
    }

    private func openIdeaBank() {
        selection = .ideaBank
        appModel.selectedTab = .ideaBank
    }

    private func openUpcomingPost(_ briefID: UUID) {
        selection = .plan
        appModel.selectedTab = .today
        planPath = NavigationPath()
        appModel.widgetBriefOpensEditor = true
        appModel.widgetBriefID = briefID
    }

    private func openUtilityIdea(_ idea: CreativeBrief) {
        ideaBankPath = NavigationPath()
        appModel.openIdea(idea, developsPost: false, context: modelContext)
    }

    private func openTask(_ taskID: UUID) {
        openTasks()
        tasksPath = NavigationPath()
        tasksPath.append(TaskNavigationRoute(taskID: taskID))
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? DesktopNavigationPolicy.defaultDestination {
        case .home:
            NavigationStack(path: $homePath) {
                HomeDashboardView().taskNavigationDestinations()
            }
        case .plan:
            NavigationStack(path: $planPath) {
                PlanView()
                    .id(appModel.requestedPlanNavigationReset)
                    .taskNavigationDestinations()
            }
        case .feed:
            NavigationStack(path: $feedPath) {
                SocialGridView().taskNavigationDestinations()
            }
        case .tasks:
            NavigationStack(path: $tasksPath) {
                TasksView().taskNavigationDestinations()
            }
        case .ideaBank:
            NavigationStack(path: $ideaBankPath) {
                IdeaBankView().taskNavigationDestinations()
            }
        case .savedPosts:
            NavigationStack(path: $savedPostsPath) {
                SavedPostsLibraryView().taskNavigationDestinations()
            }
        case .pillars:
            NavigationStack(path: $pillarsPath) {
                PillarsView().taskNavigationDestinations()
            }
        case .cy:
            NavigationStack(path: $cyPath) {
                AskCyView(bottomClearance: 0).taskNavigationDestinations()
            }
        }
    }

    private var activeIdentity: ActiveCreatorIdentity {
        ActiveCreatorIdentity.resolve(
            profile: profiles.first,
            workspaces: workspaces,
            preferredWorkspaceID: appModel.activeWorkspaceID
        )
    }

    private func taskCompletionUndoToast(_ undo: TaskCompletionUndoState) -> some View {
        HStack(spacing: AgentSpacing.x4) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Task completed")
                    .font(.agentDesktopUtilityBodyEmphasis)
                Text(undo.taskTitle)
                    .font(.agentDesktopUtilityAction.weight(.regular))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Undo") {
                appModel.undoLastTaskCompletion(context: modelContext)
            }
            .font(.agentDesktopUtilityBodyEmphasis)
            .frame(minWidth: 56, minHeight: 40)
            .buttonStyle(.plain)
        }
        .padding(.leading, AgentSpacing.x4)
        .padding(.trailing, AgentSpacing.x2)
        .frame(width: 340)
        .frame(minHeight: 58)
        .foregroundStyle(Color.agentCanvas)
        .background(Color.agentText, in: .rect(cornerRadius: AgentRadius.panel))
        .agentSurfaceChrome(cornerRadius: AgentRadius.panel, role: .floating)
    }

    private func openRequestedTaskIfNeeded() {
        guard let taskID = appModel.requestedTaskID else { return }
        selection = .tasks
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
        guard let requests = try? MCPBridgeService.pendingRequests() else { return }
        let requestIDs = Set(requests.map(\.id))
        hasPendingMCPReview = !requestIDs.isEmpty
        guard !requestIDs.isEmpty else {
            presentedMCPRequestIDs = []
            return
        }
        guard !requestIDs.subtracting(presentedMCPRequestIDs).isEmpty else { return }
        presentedMCPRequestIDs = requestIDs

        appModel.requestedSettingsPage = nil
        appModel.presentedSheet = .askCy
    }

    private func resetNavigationPaths() {
        homePath = NavigationPath()
        planPath = NavigationPath()
        feedPath = NavigationPath()
        tasksPath = NavigationPath()
        ideaBankPath = NavigationPath()
        savedPostsPath = NavigationPath()
        pillarsPath = NavigationPath()
        cyPath = NavigationPath()
    }
}

private extension View {
    func utilityWidgetCard() -> some View {
        padding(AgentSpacing.x4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.panel))
            .contentShape(.rect(cornerRadius: AgentRadius.panel))
    }
}
#endif
