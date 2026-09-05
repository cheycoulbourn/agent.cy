#if targetEnvironment(macCatalyst)
import SwiftData
import SwiftUI

struct DesktopAppShellView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var profiles: [CreatorProfile]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @Query(sort: \CreatorTask.createdAt, order: .reverse) private var allTasks: [CreatorTask]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt, order: .reverse) private var allOutputs: [PlatformOutput]
    @Query private var allPillars: [Pillar]
    @Query private var allFocusTemplates: [DailyFocusTemplateEntry]
    @Query private var allFocusOverrides: [DailyFocusOverride]
    @Query(sort: \BrandPartner.updatedAt, order: .reverse) private var allBrandPartners: [BrandPartner]
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
    @State private var showsWeeklyFocusEditor = false
    @State private var creationHubStage: DesktopCreationHubStage = .menu
    @State private var showsConsistencyGoalEditor = false
    @AppStorage("agentcy.desktopUtilityHiddenWidgets") private var storedHiddenUtilityWidgets = ""
    @AppStorage("agentcy.desktopUtilityWidgetOrder") private var storedUtilityWidgetOrder = ""

    var body: some View {
        @Bindable var model = appModel

        GeometryReader { proxy in
            let metrics = DesktopLayoutPolicy.metrics(forWindowWidth: proxy.size.width)

            HStack(spacing: 0) {
                sidebar(metrics: metrics)
                    .frame(width: metrics.leadingSidebarWidth)

                workspace(metrics: metrics)

                if metrics.showsUtilitySidebar {
                    utilitySidebar
                        .frame(width: metrics.utilitySidebarWidth)
                        .transition(
                            DesktopShellMotionPolicy.animatesUtilityRail(reduceMotion: reduceMotion)
                                ? .move(edge: .trailing).combined(with: .opacity)
                                : .identity
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.agentCanvas)
            .animation(
                DesktopShellMotionPolicy.animatesUtilityRail(reduceMotion: reduceMotion)
                    ? .snappy(duration: 0.24)
                    : nil,
                value: metrics.showsUtilitySidebar
            )
        }
        .frame(minWidth: 960, minHeight: 640)
        .tint(Color.actionAccent)
        .sheet(item: nonCreationSheetBinding) { sheet in
            Group {
                switch sheet {
                case .creationHub, .voiceSpark: EmptyView()
                case .quickCapture: QuickCaptureView()
                case .askCy: AskCyView(showsCloseButton: true)
                case .settings: SettingsView()
                case .weeklyFocus: WeeklyFocusSetupView()
                case .activityCenter:
                    NotificationActivityCenterView(
                        preferredWorkspaceID: appModel.activeWorkspaceID
                    )
                }
            }
            .environment(appModel)
            .modelContext(modelContext)
            .agentDesktopWorkspaceModal(sheet: sheet)
        }
        .sheet(item: $model.inspirationReviewRoute) { route in
            InspirationReviewView(sourceID: route.id)
                .environment(appModel)
                .modelContext(modelContext)
                .frame(minWidth: 640, idealWidth: 760, minHeight: 600, idealHeight: 780)
        }
        .sheet(isPresented: $showsWeeklyFocusEditor) {
            WeeklyFocusSetupView()
                .environment(appModel)
                .modelContext(modelContext)
                .agentDesktopWorkspaceModal()
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
            while !Task.isCancelled {
                await presentMCPApprovalsIfNeeded()
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
        .onChange(of: appModel.selectedTabRevision) { _, _ in
            let destination = DesktopNavigationPolicy.destination(for: appModel.selectedTab)
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
            presentedMCPRequestIDs = []
            hasPendingMCPReview = false
            showsWeeklyFocusEditor = false
        }
        .onChange(of: appModel.presentedSheet) { _, sheet in
            if sheet == .voiceSpark {
                appModel.presentedSheet = nil
                return
            }
            if sheet != nil { showsWeeklyFocusEditor = false }
        }
        .onChange(of: appModel.inspirationReviewRoute) { _, route in
            if route != nil { showsWeeklyFocusEditor = false }
        }
    }

    private var nonCreationSheetBinding: Binding<AppSheet?> {
        Binding(
            get: {
                switch appModel.presentedSheet {
                case .creationHub, .voiceSpark:
                    return nil
                default:
                    return appModel.presentedSheet
                }
            },
            set: { appModel.presentedSheet = $0 }
        )
    }

    private var creationHubOverlay: some View {
        GeometryReader { proxy in
            let metrics = DesktopLayoutPolicy.creationHubMetrics(stage: creationHubStage)
            let width = min(metrics.width, max(360, proxy.size.width - 160))
            let height = min(metrics.height, max(360, proxy.size.height - 96))

            ZStack {
                Button(action: closeCreationHub) {
                    Color.agentPureBlack.opacity(0.18)
                        .ignoresSafeArea()
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityHidden(true)

                // The content lays out once at its target size and the cheap
                // outer window animates over it. Animating the content frame
                // itself relayouts the whole editor every frame and stutters.
                CreationHubView(onDismiss: closeCreationHub)
                    .environment(appModel)
                    .modelContext(modelContext)
                    .frame(width: width, height: height)
                    .transaction { $0.animation = nil }
                    .frame(width: width, height: height)
                    .background(Color.agentCanvas)
                    .clipShape(.rect(cornerRadius: AgentRadius.floating))
                    .agentSurfaceChrome(cornerRadius: AgentRadius.floating, role: .floating)
                    .accessibilityAddTraits(.isModal)
                    .animation(reduceMotion ? nil : AgentModalResize.animation, value: creationHubStage)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityAction(.escape, closeCreationHub)
        }
        .onPreferenceChange(DesktopCreationHubStagePreferenceKey.self) { stage in
            Task { @MainActor in creationHubStage = stage }
        }
    }

    private func closeCreationHub() {
        appModel.presentedSheet = nil
        creationHubStage = .menu
    }

    private func openCreationHub() {
        showsWeeklyFocusEditor = false
        appModel.dismissGlobalPresentation()
        creationHubStage = .menu
        appModel.presentedSheet = .creationHub
    }

    private func sidebar(metrics: DesktopLayoutMetrics) -> some View {
        VStack(spacing: 0) {
            brandHeader

            if !metrics.showsUtilitySidebar {
                quickAddButton
                    .padding(.horizontal, AgentSpacing.x3)
                    .padding(.bottom, AgentSpacing.x3)
            }

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

            HStack(spacing: 0) {
                settingsButton
                appearanceCycleButton
                    .padding(.trailing, AgentSpacing.x3)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(Color.agentBorder).frame(height: 1)
            }
        }
        .background(Color.agentSurface)
    }

    private var appearanceCycleButton: some View {
        Button {
            let order = AppearancePreference.allCases
            let current = order.firstIndex(of: appModel.appearancePreference) ?? 0
            let next = order[(current + 1) % order.count]
            DeviceAppearancePreferences.save(next)
            appModel.appearancePreference = next
        } label: {
            Image(systemName: appearanceCycleSymbol)
                .font(.agentInter(size: 15, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(Color.agentSecondary)
                .frame(width: 36, height: 36)
                .background(Color.agentText.opacity(0.04), in: .circle)
                .overlay { Circle().stroke(Color.agentBorder, lineWidth: 1) }
                .contentShape(.circle)
        }
        .buttonStyle(AgentPressButtonStyle())
        .accessibilityLabel("Appearance")
        .accessibilityValue(appModel.appearancePreference.title)
        .accessibilityHint("Cycles between system, light, and dark appearance")
        .help("Appearance: \(appModel.appearancePreference.title)")
    }

    private var appearanceCycleSymbol: String {
        switch appModel.appearancePreference {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    private var brandHeader: some View {
        HStack(spacing: AgentSpacing.x3) {
            AgentCyLogoMark(size: 23)
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
            .agentHoverRow()
        }
        .buttonStyle(AgentPressButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                AgentIconView(.sliders, size: 16)
                    .foregroundStyle(Color.agentSecondary)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, AgentSpacing.x4)
            .padding(.vertical, AgentSpacing.x2)
            .contentShape(.rect)
        }
        .buttonStyle(AgentPressButtonStyle())
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

                if utilityCyNoticedSummary.needsAttention {
                    cyNoticedWidget
                }

                ForEach(configurableUtilityWidgets) { widget in
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

            ForEach(Array(configurableUtilityWidgets.enumerated()), id: \.element.id) { index, widget in
                HStack(spacing: AgentSpacing.x2) {
                    Group {
                        if widget == .cyNoticed {
                            AgentCyLogoMark(size: 15)
                        } else if let icon = widget.icon {
                            AgentIconView(icon, size: 15)
                                .foregroundStyle(Color.agentSecondary)
                        }
                    }
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
                        isEnabled: index < configurableUtilityWidgets.count - 1
                    )

                    Toggle("Show \(widget.title)", isOn: utilityWidgetVisibilityBinding(for: widget))
                        .labelsHidden()
                        .tint(Color.actionAccent)
                        .controlSize(.small)
                }
                .padding(.horizontal, AgentSpacing.x3)
                .frame(minHeight: 48)

                if index < configurableUtilityWidgets.count - 1 {
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
        // Quiet, theme-aware chrome: the old pure-white card glared in dark
        // mode. Tokens keep it a calm control in both appearances, and the
        // plus circle carries its own border so it stays visible.
        Button(action: openCreationHub) {
            HStack(spacing: AgentSpacing.x3) {
                AgentIconView(.add, size: 15)
                    .foregroundStyle(Color.agentText)
                    .frame(width: 32, height: 32)
                    .background(Color.agentText.opacity(0.05), in: .circle)
                    .overlay {
                        Circle().stroke(Color.agentBorder, lineWidth: 1)
                    }
                Text("Quick add")
                    .font(.agentDesktopQuickAction)
                    .foregroundStyle(Color.agentText)
                Spacer(minLength: 0)
                Text("⌘N")
                    .font(.agentDesktopUtilityMetadata)
                    .foregroundStyle(Color.agentSecondary)
            }
            .padding(.horizontal, AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.panel))
            .overlay {
                RoundedRectangle(cornerRadius: AgentRadius.panel)
                    .stroke(Color.agentBorder, lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: AgentRadius.panel))
            .agentHoverRow(cornerRadius: AgentRadius.panel)
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
        case .pillarUsage:
            pillarUsageWidget
        case .needsNewDate:
            needsNewDateWidget
        case .cyNoticed:
            cyNoticedWidget
        case .weekAtAGlance:
            weekAtAGlanceWidget
        case .consistency:
            consistencyWidget
        case .recentlyPosted:
            recentlyPostedWidget
        case .draftsInProgress:
            draftsInProgressWidget
        case .brandCabinet:
            brandCabinetWidget
        case .weeklyFocus:
            weeklyFocusWidget
        }
    }

    private var taskWidget: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel("Tasks")
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
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(utilityTasks.prefix(DesktopUtilityWidgetContentPolicy.taskPreviewLimit)) { task in
                        utilityTaskRow(task)
                    }
                }
            }

            utilityWidgetViewAllFooter(
                accessibilityLabel: "View all tasks",
                foregroundColor: .agentText,
                arrowColor: .agentText,
                action: openTasks
            )
        }
        .utilityWidgetCard()
    }

    private func utilityTaskRow(_ task: CreatorTask) -> some View {
        HStack(alignment: AgentTaskCheckboxMetrics.rowAlignment, spacing: 10) {
            AgentTaskCheckbox(
                isCompleted: task.isCompleted,
                color: utilityTaskCheckboxColor(task),
                accessibilityLabel: "Complete \(utilityTitle(for: task))"
            ) {
                completeUtilityTask(task)
            }
            .accessibilityHint("Marks this task complete")

            Button { openTask(task.id) } label: {
                Text(utilityTitle(for: task))
                    .font(.agentDesktopUtilityBody)
                    .foregroundStyle(Color.agentText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(AgentPressButtonStyle())
            .accessibilityHint("Opens task details")
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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

    private var pillarUsageWidget: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel("Pillar usage")
                Spacer()
                Text("This week")
                    .font(.agentDesktopUtilityMetadata)
                    .foregroundStyle(Color.agentSecondary)
            }
            if utilityPillarUsage.isEmpty {
                Text("Plan a post to see the mix.")
                    .font(.agentDesktopUtilityBody)
                    .foregroundStyle(Color.agentSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .center)
            } else {
                GeometryReader { proxy in
                    let widths = WidgetPillarBarLayout.segmentWidths(
                        percentages: utilityPillarUsage.map(\.percentage),
                        totalWidth: proxy.size.width,
                        minimumWidth: 6
                    )

                    HStack(spacing: WidgetPillarBarLayout.segmentSpacing) {
                        ForEach(Array(utilityPillarUsage.enumerated()), id: \.element.id) { index, item in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(agentHex: item.colorHex))
                                .frame(width: widths.indices.contains(index) ? widths[index] : 0)
                        }
                    }
                    .frame(width: proxy.size.width, alignment: .leading)
                    .clipped()
                }
                .frame(height: 12)
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: AgentSpacing.x2
                ) {
                    ForEach(utilityPillarUsage) { item in
                        HStack(spacing: AgentSpacing.x2) {
                            PillarColorMark(
                                color: Color(agentHex: item.colorHex),
                                diameter: 7,
                                lineWidth: 1
                            )
                            Text(item.name)
                                .font(.agentDesktopUtilityMetadata)
                                .lineLimit(1)
                            Spacer(minLength: AgentSpacing.x1)
                            Text("\(item.percentage)%")
                                .font(.agentDesktopUtilityMetadata.monospacedDigit())
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("View all", action: openPillars)
                        .font(.agentDesktopUtilityAction)
                        .buttonStyle(.plain)
                }
            }
        }
        .utilityWidgetCard()
    }

    private var needsNewDateWidget: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel("Needs a new date")
                Spacer()
                Text("\(utilityPastDueOutputs.count)")
                    .font(.agentDesktopUtilityAction)
                    .foregroundStyle(Color.agentSecondary)
            }
            if let output = utilityPastDueOutputs.first,
               let brief = utilityBrief(for: output) {
                Button { openUpcomingPost(brief.id) } label: {
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        Text(brief.title)
                            .font(.agentDesktopUtilityBodyEmphasis)
                            .lineLimit(2)
                        Text("MISSED · \(output.targetDate?.formatted(.dateTime.month(.abbreviated).day()) ?? "DATE PASSED")")
                            .font(.agentDesktopUtilityMetadata)
                            .foregroundStyle(Color.agentDestructive)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(AgentPressButtonStyle())
                utilityWidgetViewAllFooter(accessibilityLabel: "Open agenda", action: openPlan)
            } else {
                Text("No missed posts.")
                    .font(.agentDesktopUtilityBody)
                    .foregroundStyle(Color.agentSecondary)
                    .frame(minHeight: 42, alignment: .leading)
            }
        }
        .utilityWidgetCard()
    }

    private var cyNoticedWidget: some View {
        Button(action: openLateWork) {
            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                HStack(spacing: AgentSpacing.x2) {
                    AgentCyLogoMark()
                    Text("CY NOTICED")
                        .font(.agentMetadata)
                        .tracking(1.4)
                        .foregroundStyle(Color.cyAccent)
                }
                Text(utilityCyNoticedSummary.message)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text("Show me")
                        .font(.agentSubtext.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.cyAccent)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(
                    Color.cyAccent.opacity(0.12),
                    in: .rect(cornerRadius: AgentRadius.button)
                )
            }
            .padding(AgentSpacing.x4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cyAccent.opacity(0.06), in: .rect(cornerRadius: AgentRadius.panel))
            .overlay {
                RoundedRectangle(cornerRadius: AgentRadius.panel)
                    .stroke(Color.cyAccent.opacity(0.4), lineWidth: 0.75)
            }
            .contentShape(.rect(cornerRadius: AgentRadius.panel))
        }
        .buttonStyle(AgentPressButtonStyle())
        .accessibilityHint("Opens the agenda list filtered to late work")
    }

    private var weekAtAGlanceWidget: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel("Week at a glance")
                Spacer()
                Text("\(utilityWeekDays.reduce(0) { $0 + $1.postCount }) posts")
                    .font(.agentDesktopUtilityMetadata)
                    .foregroundStyle(Color.agentSecondary)
            }
            HStack(spacing: AgentSpacing.x1) {
                ForEach(utilityWeekDays) { day in
                    VStack(spacing: AgentSpacing.x2) {
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.agentDesktopUtilityMetadata)
                        PillarColorMark(color: day.color, diameter: 7, lineWidth: day.postCount == 0 ? 1 : 0)
                            .opacity(day.postCount == 0 ? 0.28 : 1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            utilityWidgetViewAllFooter(accessibilityLabel: "Open week", action: openPlan)
        }
        .utilityWidgetCard()
    }

    private var consistencyWidget: some View {
        let goal = utilityGoalConsistency
        return ConsistencyGoalCard(
            snapshot: goal.snapshot,
            weeklyGoalMet: goal.weeklyGoalMet,
            streak: goal.streak,
            onEditGoal: { showsConsistencyGoalEditor = true }
        )
        .utilityWidgetCard()
        .onTapGesture {
            if goal.snapshot.goalState != .unset {
                showsConsistencyGoalEditor = true
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the weekly posting goal")
        .sheet(isPresented: $showsConsistencyGoalEditor) {
            ConsistencyGoalEditorView(
                currentGoal: utilityActiveWorkspace?.weeklyPostingGoal,
                onSave: { saveWeeklyPostingGoal($0) },
                onRemove: { saveWeeklyPostingGoal(nil) },
                onClose: { showsConsistencyGoalEditor = false }
            )
            .frame(minWidth: 460, idealWidth: 480)
            .presentationSizing(.fitted)
            .presentationCornerRadius(AgentRadius.floating)
            .presentationBackground(Color.agentCanvas)
        }
    }

    private var utilityActiveWorkspace: CreatorWorkspace? {
        let activeID = WorkspaceScope.activeWorkspaceID(
            preferredID: appModel.activeWorkspaceID,
            workspaces: workspaces
        )
        return workspaces.first { $0.id == activeID }
    }

    private var utilityGoalConsistency: (snapshot: WeeklyConsistencySnapshot, weeklyGoalMet: [Bool], streak: Int) {
        let calendar = Calendar.current
        let range = utilityCurrentWeekRange
        let postedDates = allOutputs.compactMap { output -> Date? in
            guard let brief = utilityBrief(for: output),
                  brief.status != .archived,
                  output.status == .posted || brief.status == .posted else { return nil }
            return output.postedAt ?? output.targetDate
        }
        let goal = utilityActiveWorkspace?.weeklyPostingGoal
        let snapshot = WeeklyConsistencyPolicy.snapshot(
            postedDates: postedDates,
            goal: goal,
            weekStart: range.start,
            calendar: calendar,
            today: Date()
        )
        guard let goal else { return (snapshot, Array(repeating: false, count: 8), 0) }
        let counts = WeeklyConsistencyPolicy.weeklyPostedDayCounts(
            postedDates: postedDates,
            weekCount: 8,
            currentWeekStart: range.start,
            calendar: calendar
        )
        let met = counts.map { $0 >= goal }
        return (snapshot, met, WeeklyConsistencyPolicy.goalStreak(weeklyPostedDayCounts: counts, goal: goal))
    }

    private func saveWeeklyPostingGoal(_ goal: Int?) {
        guard let workspace = utilityActiveWorkspace else { return }
        workspace.weeklyPostingGoal = goal.map(WeeklyConsistencyPolicy.clampedGoal)
        workspace.updatedAt = Date()
        try? modelContext.save()
        showsConsistencyGoalEditor = false
    }

    private var recentlyPostedWidget: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel("Recently posted")
                Spacer()
                Text("\(utilityRecentlyPosted.count)")
                    .font(.agentDesktopUtilityAction)
                    .foregroundStyle(Color.agentSecondary)
            }
            if utilityRecentlyPosted.isEmpty {
                Text("Posted work will collect here.")
                    .font(.agentDesktopUtilityBody)
                    .foregroundStyle(Color.agentSecondary)
            } else {
                ForEach(utilityRecentlyPosted.prefix(2), id: \.output.id) { item in
                    Button { openUpcomingPost(item.brief.id) } label: {
                        HStack(spacing: AgentSpacing.x3) {
                            PillarColorMark(color: utilityPillarColor(item.brief), diameter: 8)
                            Text(item.brief.title)
                                .font(.agentDesktopUtilityBodyEmphasis)
                                .lineLimit(1)
                            Spacer()
                            Text((item.output.postedAt ?? item.output.targetDate)?.formatted(.dateTime.month(.abbreviated).day()) ?? "Posted")
                                .font(.agentDesktopUtilityMetadata)
                                .foregroundStyle(Color.agentSecondary)
                        }
                        .frame(minHeight: 40)
                        .contentShape(.rect)
                    }
                    .buttonStyle(AgentPressButtonStyle())
                }
            }
        }
        .utilityWidgetCard()
    }

    private var draftsInProgressWidget: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel("Drafts in progress")
                Spacer()
                Text("\(utilityDrafts.count)")
                    .font(.agentDesktopUtilityAction)
                    .foregroundStyle(Color.agentSecondary)
            }
            if utilityDrafts.isEmpty {
                Text("No drafts are waiting on you.")
                    .font(.agentDesktopUtilityBody)
                    .foregroundStyle(Color.agentSecondary)
            } else {
                ForEach(utilityDrafts.prefix(2), id: \.output.id) { item in
                    Button { openUpcomingPost(item.brief.id) } label: {
                        HStack(spacing: AgentSpacing.x3) {
                            PillarColorMark(color: utilityPillarColor(item.brief), diameter: 8)
                            Text(item.brief.title)
                                .font(.agentDesktopUtilityBodyEmphasis)
                                .lineLimit(1)
                            Spacer()
                            Text("\(utilityDraftAge(item.output))d")
                                .font(.agentDesktopUtilityMetadata)
                                .foregroundStyle(Color.agentSecondary)
                        }
                        .frame(minHeight: 40)
                        .contentShape(.rect)
                    }
                    .buttonStyle(AgentPressButtonStyle())
                }
            }
        }
        .utilityWidgetCard()
    }

    private var brandCabinetWidget: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel("Brand cabinet")
                Spacer()
                Text("\(utilityBrandPartners.count)")
                    .font(.agentDesktopUtilityAction)
                    .foregroundStyle(Color.agentSecondary)
            }
            if let partner = utilityBrandPartners.first {
                HStack(spacing: AgentSpacing.x3) {
                    BrandPartnerAvatar(partner: partner, size: 34)
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        Text(partner.name)
                            .font(.agentDesktopUtilityBodyEmphasis)
                        Text(partner.nextFollowUpAt.map { "Follow up \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? partner.stage.title)
                            .font(.agentDesktopUtilityMetadata)
                            .foregroundStyle(Color.agentSecondary)
                    }
                }
                .frame(minHeight: 44)
            } else {
                Text("No active partnerships yet.")
                    .font(.agentDesktopUtilityBody)
                    .foregroundStyle(Color.agentSecondary)
            }
        }
        .utilityWidgetCard()
    }

    private var weeklyFocusWidget: some View {
        Button(action: openWeeklyFocusEditor) {
            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                HStack(alignment: .firstTextBaseline) {
                    MetaLabel("Weekly focus")
                    Spacer()
                    Text("Edit")
                        .font(.agentDesktopUtilityAction)
                        .foregroundStyle(Color.actionAccent)
                }
                Text(utilityWeeklyFocusSummary)
                    .font(.agentDesktopUtilityBodyEmphasis)
                Text("Today: \(utilityTodayFocusTitle)")
                    .font(.agentDesktopUtilityMetadata)
                    .foregroundStyle(Color.agentSecondary)
            }
            .foregroundStyle(Color.agentText)
            .padding(AgentSpacing.x4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.panel))
            .contentShape(.rect(cornerRadius: AgentRadius.panel))
        }
        .buttonStyle(AgentPressButtonStyle())
    }

    private func openWeeklyFocusEditor() {
        appModel.dismissGlobalPresentation()
        showsWeeklyFocusEditor = true
    }

    private func utilityWidgetViewAllFooter(
        accessibilityLabel: String,
        foregroundColor: Color = .agentSecondary,
        arrowColor: Color = .actionAccent,
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
                        .foregroundStyle(foregroundColor)
                    Spacer(minLength: AgentSpacing.x2)
                    AgentIconView(.arrowRight, size: 12)
                        .foregroundStyle(arrowColor)
                }
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(.rect)
            }
            .buttonStyle(AgentPressButtonStyle())
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private var cyFloatingButton: some View {
        Button {
            appModel.presentedSheet = .askCy
        } label: {
            ZStack {
                Circle()
                    .fill(Color.agentSurface)
                Circle()
                    .stroke(Color.agentBorder, lineWidth: 1)
                if hasPendingMCPReview {
                    CyPendingReviewLogo(color: .cyAccent, size: 24, strokeWidth: 2)
                } else {
                    CyAsterisk(color: .cyAccent, size: 24, strokeWidth: 2)
                }
            }
            .frame(width: 56, height: 56)
            .agentSurfaceChrome(cornerRadius: AgentRadius.floating, role: .floating)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("k", modifiers: .command)
        .accessibilityLabel(hasPendingMCPReview ? "Review Cy changes" : "Open Cy")
        .accessibilityHint(
            hasPendingMCPReview
                ? "Cy has new MCP proposals waiting for review"
                : "Opens your creative copilot"
        )
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

    private var utilityPillars: [Pillar] {
        allPillars.filter {
            !$0.isArchived && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private var utilityCurrentWeekRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let offset = (calendar.component(.weekday, from: today) + 5) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
        return (start, calendar.date(byAdding: .day, value: 7, to: start) ?? start)
    }

    private var utilityPillarUsage: [DesktopUtilityPillarUsageItem] {
        let scopedBriefs = allBriefs.filter { brief in
            brief.status != .archived && WorkspaceScope.includes(
                brief.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
        let scopedOutputs = allOutputs.filter { output in
            WorkspaceScope.includes(
                output.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
        let summary = PillarUsageSchedulePolicy.summary(
            pillars: utilityPillars,
            briefs: scopedBriefs,
            outputs: scopedOutputs,
            interval: PillarUsageSchedulePolicy.weekInterval(containing: Date())
        )
        let pillarByID = DuplicateSafeIndex.firstValues(utilityPillars.map { ($0.id, $0) })
        return summary.compactMap { item in
            guard let pillar = pillarByID[item.pillarID] else { return nil }
            return DesktopUtilityPillarUsageItem(
                id: pillar.id,
                name: pillar.name,
                colorHex: pillar.resolvedColorHex(in: utilityPillars),
                percentage: item.percentage
            )
        }
    }

    private var utilityPastDueOutputs: [PlatformOutput] {
        allOutputs.filter { output in
            guard let brief = utilityBrief(for: output), brief.status != .archived else { return false }
            return FinalizedPostPresentation.isMissed(outputStatus: output.status, targetDate: output.targetDate)
        }
        .sorted { ($0.targetDate ?? .distantPast) > ($1.targetDate ?? .distantPast) }
    }

    private var utilityWeekDays: [DesktopUtilityWeekDay] {
        let range = utilityCurrentWeekRange
        return (0..<7).compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: range.start) else { return nil }
            let outputs = allOutputs.filter {
                $0.targetDate.map { Calendar.current.isDate($0, inSameDayAs: date) } == true && utilityBrief(for: $0) != nil
            }
            let color = outputs.first
                .flatMap { utilityBrief(for: $0) }
                .map(utilityPillarColor) ?? Color.agentCanvas
            return DesktopUtilityWeekDay(date: date, postCount: outputs.count, color: color)
        }
    }

    private var utilityRecentlyPosted: [DesktopUtilityPostItem] {
        allOutputs.compactMap { output -> DesktopUtilityPostItem? in
            guard let brief = utilityBrief(for: output),
                  output.status == .posted || brief.status == .posted else { return nil }
            return DesktopUtilityPostItem(output: output, brief: brief)
        }
        .sorted {
            ($0.output.postedAt ?? $0.output.targetDate ?? $0.output.createdAt) >
                ($1.output.postedAt ?? $1.output.targetDate ?? $1.output.createdAt)
        }
    }

    private var utilityDrafts: [DesktopUtilityPostItem] {
        allOutputs.compactMap { output -> DesktopUtilityPostItem? in
            guard let brief = utilityBrief(for: output),
                  ContinueWorkingPostPolicy.includes(
                    briefStatus: brief.status,
                    outputStatus: output.status,
                    customStatus: brief.resolvedCustomStatusLabel,
                    ideaBankPlacement: brief.ideaBankPlacement
                  ) else { return nil }
            return DesktopUtilityPostItem(output: output, brief: brief)
        }
        .sorted { $0.brief.updatedAt > $1.brief.updatedAt }
    }

    private var utilityBrandPartners: [BrandPartner] {
        allBrandPartners.filter {
            $0.stage != .archived && $0.stage != .pastPartner && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private var utilityTodayFocusTitle: String {
        let title = DailyFocusResolver.resolve(
            date: Calendar.current.startOfDay(for: Date()),
            templates: allFocusTemplates.filter {
                WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: appModel.activeWorkspaceID, workspaces: workspaces)
            },
            overrides: allFocusOverrides.filter {
                WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: appModel.activeWorkspaceID, workspaces: workspaces)
            }
        )?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Rest" : title
    }

    private var utilityWeeklyFocusSummary: String {
        let activeTemplates = allFocusTemplates.filter {
            $0.isActive && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
        let focusCount = PillarWeekday.mondayFirst.filter { day in
            activeTemplates.contains { $0.weekday == day }
        }.count
        return "\(focusCount) focus days · \(7 - focusCount) rest days"
    }

    private var utilityCyNoticedSummary: CyNoticedReconciliationSummary {
        let scopedBriefs = allBriefs.filter {
            WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
        let scopedOutputs = allOutputs.filter {
            WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
        return CyNoticedReconciliationPolicy.summary(
            briefs: scopedBriefs,
            outputs: scopedOutputs
        )
    }

    private func utilityPillarColor(_ brief: CreativeBrief) -> Color {
        guard let id = brief.pillarID,
              let pillar = utilityPillars.first(where: { $0.id == id }) else { return .agentSecondary }
        return Color(agentHex: pillar.resolvedColorHex(in: utilityPillars))
    }

    private func utilityDraftAge(_ output: PlatformOutput) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: output.createdAt, to: Date()).day ?? 0)
    }

    private func utilityBrief(for output: PlatformOutput) -> CreativeBrief? {
        allBriefs.first { brief in
            guard brief.id == output.briefID else { return false }
            return DesktopUtilityOutputPolicy.includes(
                briefStatus: brief.status,
                outputIsInActiveWorkspace: WorkspaceScope.includes(
                    output.workspaceID,
                    activeWorkspaceID: appModel.activeWorkspaceID,
                    workspaces: workspaces
                ),
                briefIsInActiveWorkspace: WorkspaceScope.includes(
                    brief.workspaceID,
                    activeWorkspaceID: appModel.activeWorkspaceID,
                    workspaces: workspaces
                )
            )
        }
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

    private var configurableUtilityWidgets: [DesktopUtilityWidget] {
        orderedUtilityWidgets.filter { $0 != .cyNoticed }
    }

    private func isUtilityWidgetVisible(_ widget: DesktopUtilityWidget) -> Bool {
        guard widget != .cyNoticed else { return false }
        return !hiddenUtilityWidgets.contains(widget)
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
        guard widget != .cyNoticed else { return }
        var widgets = configurableUtilityWidgets
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

    private func utilityTaskCheckboxColor(_ task: CreatorTask) -> Color {
        switch task.priority.normalized {
        case .urgent: .agentDestructive
        case .high: .agentPriorityHigh
        default: .agentBorder
        }
    }

    private func openTasks() {
        selection = .tasks
        appModel.selectedTab = .tasks
    }

    private func openPillars() {
        selection = .pillars
        appModel.selectedTab = .pillars
    }

    private func openPlan() {
        selection = .plan
        appModel.selectedTab = .today
    }

    private func openLateWork() {
        selection = .plan
        planPath = NavigationPath()
        appModel.routeToLateWorkList()
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

            Button {
                appModel.undoLastTaskCompletion(context: modelContext)
            } label: {
                Text("Undo")
                    .font(.agentDesktopUtilityBodyEmphasis)
                    .frame(minWidth: 56, minHeight: 40)
                    .contentShape(.rect)
            }
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
        guard appModel.requestedTaskID != nil else { return }
        showsWeeklyFocusEditor = false
        guard let taskID = appModel.consumeRequestedTaskRoute() else { return }
        selection = .tasks
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
        let requestedWorkspaceID = appModel.activeWorkspaceID
        let fetched = await Task.detached(priority: .utility) {
            try? await MCPBridgeService.refreshPendingRequests(
                workspaceID: requestedWorkspaceID
            )
        }.value
        guard DesktopShellWorkspacePolicy.acceptsMCPResult(
            requestedWorkspaceID: requestedWorkspaceID,
            activeWorkspaceID: appModel.activeWorkspaceID
        ) else { return }
        guard let requests = fetched else { return }
        let requestIDs = Set(requests.map(\.id))
        if hasPendingMCPReview != !requestIDs.isEmpty {
            hasPendingMCPReview = !requestIDs.isEmpty
        }
        guard !requestIDs.isEmpty else {
            if !presentedMCPRequestIDs.isEmpty { presentedMCPRequestIDs = [] }
            return
        }
        guard DesktopShellMCPReviewPolicy.shouldPresent(
            requestIDs: requestIDs,
            presentedRequestIDs: presentedMCPRequestIDs,
            hasGlobalPresentation: appModel.hasGlobalPresentation,
            hasLocalPresentation: showsWeeklyFocusEditor
        ) else { return }

        // Never replace work in progress. The floating-button badge carries
        // the signal and the poll retries after the active presentation closes.
        presentedMCPRequestIDs = requestIDs

        appModel.presentMCPReview()
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

private struct DesktopUtilityPillarUsageItem: Identifiable {
    let id: UUID
    let name: String
    let colorHex: String
    let percentage: Int
}

private struct DesktopUtilityWeekDay: Identifiable {
    let date: Date
    let postCount: Int
    let color: Color

    var id: Date { date }
}

private struct DesktopUtilityPostItem {
    let output: PlatformOutput
    let brief: CreativeBrief
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
