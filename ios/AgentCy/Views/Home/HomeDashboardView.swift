import SwiftData
import SwiftUI

struct HomeDashboardView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var profiles: [CreatorProfile]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt) private var allOutputs: [PlatformOutput]
    @Query(sort: \CreatorTask.createdAt) private var allTasks: [CreatorTask]
    @Query private var allPillars: [Pillar]
    @Query private var destinations: [PublishingDestination]
    @Query private var formats: [PublishingFormat]
    @Query private var allFocusTemplates: [DailyFocusTemplateEntry]
    @Query private var allFocusOverrides: [DailyFocusOverride]
    @State private var showsAllTodayTasks = false
    @State private var showsWeeklyFocusEditor = false
    @State private var dashboardCards = HomeDashboardCard.defaultOrder
    @State private var hiddenDashboardCards = Set<HomeDashboardCard>()
    @State private var draggedDashboardCard: HomeDashboardCard?
    @State private var dashboardCardFrames: [HomeDashboardCard: CGRect] = [:]
    @State private var dashboardDragOriginFrame: CGRect?
    @State private var dashboardDragCompensationY: CGFloat = 0
    @State private var isArrangingDashboard = false
    @State private var arrangeFeedback = 0
    @State private var quickCyPrompt = ""
    @AppStorage("agentcy.homeDashboardCardOrderByWorkspace") private var storedDashboardCardOrders = ""
    @AppStorage("agentcy.homeDashboardHiddenCardsByWorkspace") private var storedHiddenDashboardCards = ""

    private var briefs: [CreativeBrief] { scoped(allBriefs) }
    private var outputs: [PlatformOutput] { scoped(allOutputs) }
    private var tasks: [CreatorTask] { scoped(allTasks) }
    private var pillars: [Pillar] { scoped(allPillars) }
    private var focusTemplates: [DailyFocusTemplateEntry] { scoped(allFocusTemplates) }
    private var focusOverrides: [DailyFocusOverride] { scoped(allFocusOverrides) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                header

                ForEach(dashboardCards) { card in
                    reorderableDashboardCard(card)
                }

                dashboardCustomizationFooter
            }
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.top, AgentSpacing.x6)
            .padding(.bottom, 120)
        }
        .coordinateSpace(name: HomeDashboardCoordinateSpace.name)
        .onPreferenceChange(HomeDashboardCardFramePreferenceKey.self) { frames in
            dashboardCardFrames = frames
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
        .background(Color.agentCanvas.ignoresSafeArea())
        .sheet(isPresented: $showsWeeklyFocusEditor) {
            WeeklyFocusSetupView()
        }
        .onAppear(perform: restoreDashboardCardOrder)
        .onChange(of: appModel.activeWorkspaceID) { _, _ in
            finishArrangingDashboard()
            restoreDashboardCardOrder()
        }
        .sensoryFeedback(.selection, trigger: arrangeFeedback)
    }

    private var dashboardCustomizationFooter: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            if isArrangingDashboard {
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        MetaLabel("Dashboard widgets")
                        Text("Drag the cards to reorder them. Add or remove anything you do not need today.")
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(HomeDashboardCard.allCases.enumerated()), id: \.element.id) { index, card in
                            dashboardWidgetControl(card)

                            if index < HomeDashboardCard.allCases.count - 1 {
                                Rectangle()
                                    .fill(Color.agentHairline)
                                    .frame(height: 1)
                            }
                        }
                    }
                    .padding(.horizontal, AgentSpacing.x4)
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Button(action: toggleDashboardCustomization) {
                Text(isArrangingDashboard ? "Done" : "Customize")
                    .font(.agentSubtext.weight(.semibold))
                    .foregroundStyle(Color.agentText)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(.rect(cornerRadius: 24))
            }
            .buttonStyle(.plain)
            .background(Color.agentSurface, in: .capsule)
            .overlay {
                Capsule()
                    .stroke(Color.agentBorder, lineWidth: 1)
            }
            .accessibilityHint(
                isArrangingDashboard
                    ? "Finishes customizing your dashboard"
                    : "Reorders, adds, or removes dashboard widgets"
            )
        }
    }

    private func dashboardWidgetControl(_ card: HomeDashboardCard) -> some View {
        let isVisible = dashboardCards.contains(card)

        return HStack(spacing: AgentSpacing.x3) {
            Text(card.title)
                .font(.agentBody.weight(.medium))
                .foregroundStyle(Color.agentText)

            Spacer()

            Button {
                setDashboardCard(card, isVisible: !isVisible)
            } label: {
                Text(isVisible ? "Remove" : "Add")
                    .font(.agentSubtext.weight(.semibold))
                    .foregroundStyle(isVisible ? Color.agentSecondary : Color.agentText)
                    .frame(minWidth: 64, minHeight: 44, alignment: .trailing)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(isVisible ? "Remove" : "Add") \(card.title)")
        }
        .frame(minHeight: 54)
    }

    @ViewBuilder
    private func dashboardCard(_ card: HomeDashboardCard) -> some View {
        switch card {
        case .scheduledToday:
            scheduledTodaySection
        case .tasks:
            todayTasksSection
        case .weekAhead:
            weekAhead
        case .weeklyFocus:
            weeklyFocusSection
        case .quickCy:
            quickCySection
        case .pastDuePosts:
            pastDuePostsSection
        case .recentIdeas:
            recentIdeasSection
        }
    }

    private func reorderableDashboardCard(_ card: HomeDashboardCard) -> some View {
        DashboardReorderableCard(
            card: card,
            isArranging: isArrangingDashboard,
            reduceMotion: reduceMotion,
            dragCompensationY: draggedDashboardCard == card ? dashboardDragCompensationY : 0,
            onDragBegan: {
                guard draggedDashboardCard == nil else { return }
                draggedDashboardCard = card
                dashboardDragOriginFrame = dashboardCardFrames[card]
                arrangeFeedback += 1
            },
            onDragChanged: { translation in
                updateDashboardOrder(card, translation: translation)
            },
            onDragEnded: { translation in
                guard draggedDashboardCard == card else { return }
                finishDashboardDrag(card, translation: translation)
            }
        ) {
            dashboardCard(card)
                .disabled(isArrangingDashboard)
        }
        .accessibilityHint(
            isArrangingDashboard
                ? "Drag the handle above this card to move it"
                : "Use Customize at the bottom of the dashboard to rearrange cards"
        )
        .accessibilityAction(named: "Move earlier") {
            moveDashboardCard(card, offset: -1)
        }
        .accessibilityAction(named: "Move later") {
            moveDashboardCard(card, offset: 1)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            AgentPageRail(
                breadcrumb: today.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()),
                identity: activeIdentity,
                openSettings: { appModel.presentedSheet = .settings }
            )

            Button {
                appModel.selectedTab = .cy
            } label: {
                CyAnimatedLogo()
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Cy")
            .accessibilityHint("Opens your creative copilot")

            VStack(alignment: .leading, spacing: 2) {
                Text("\(greeting), \(activeIdentity.greetingName).")
                    .font(.system(size: 32, weight: .regular, design: .default))
                    .foregroundStyle(Color.agentText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Today is for \(todayFocusTitle.lowercased()).")
                    .font(.agentDisplay)
                    .foregroundStyle(Color.agentText)
                    .fixedSize(horizontal: false, vertical: true)

                if let note = todayFocus?.note.nilIfBlank {
                    Text(note)
                        .font(.agentBody)
                        .foregroundStyle(Color.agentSecondary)
                        .tracking(0)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, AgentSpacing.x3)
                }
            }
            .tracking(-0.64)

        }
    }

    private var scheduledTodaySection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel("Scheduled today")
                Spacer()
                Text("\(scheduledTodayOutputs.count)")
                    .font(.agentMono)
                    .foregroundStyle(Color.agentSecondary)
            }

            if scheduledTodayOutputs.isEmpty {
                Text("Nothing is scheduled today.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .padding(.vertical, AgentSpacing.x2)
            } else {
                VStack(spacing: AgentSpacing.x3) {
                    ForEach(scheduledTodayOutputs) { output in
                        if let brief = brief(for: output) {
                            homePostCard(output: output, brief: brief)
                        }
                    }
                }
            }
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
        .shadow(color: Color.black.opacity(0.045), radius: 18, y: 8)
    }

    private var todayTasksSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            if todayTasks.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text("Nothing is planned.")
                        .font(.agentBody)
                        .foregroundStyle(Color.agentSecondary)
                    Spacer()
                    viewAllTasksButton
                }
                .padding(.vertical, AgentSpacing.x2)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x2) {
                    Text(firstTodayTaskGroupTitle.uppercased())
                    Text("\(firstTodayTaskGroupCount)")
                        .foregroundStyle(Color.agentSecondary)
                    Spacer()
                    viewAllTasksButton
                }
                .font(.agentMono)

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                        homeTaskGroup(
                            title: "My tasks",
                            tasks: displayedTodayMyTasks,
                            totalCount: todayMyTasks.count,
                            showsHeader: false
                        )
                        homeTaskGroup(
                            title: "Post tasks",
                            tasks: displayedTodayPostTasks,
                            totalCount: todayPostTasks.count,
                            showsHeader: !displayedTodayMyTasks.isEmpty
                        )
                    }

                    if hiddenTodayTaskCount > 0 {
                        Button {
                            showsAllTodayTasks = true
                        } label: {
                            Text("+\(hiddenTodayTaskCount) more")
                                .font(.agentSubtext.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, AgentSpacing.x2)
                        .padding(.top, AgentSpacing.x1)
                        .accessibilityHint("Shows every task planned for today")
                    }
                }
            }
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
        .shadow(color: Color.black.opacity(0.045), radius: 18, y: 8)
    }

    private var viewAllTasksButton: some View {
        Button("View all") {
            appModel.selectedTab = .tasks
        }
        .font(.agentSubtext.weight(.semibold))
        .buttonStyle(.plain)
    }

    private var firstTodayTaskGroupTitle: String {
        displayedTodayMyTasks.isEmpty ? "Post tasks" : "My tasks"
    }

    private var firstTodayTaskGroupCount: Int {
        displayedTodayMyTasks.isEmpty ? todayPostTasks.count : todayMyTasks.count
    }

    private func homePostCard(output: PlatformOutput, brief: CreativeBrief) -> some View {
        AgentPostCard(
            title: outputTitle(output, brief: brief),
            pillar: pillar(for: brief)?.name ?? "Unfiled",
            accent: pillarAccent(for: brief),
            status: output.status,
            metadata: platformLabel(for: output),
            timeText: output.includesTargetTime
                ? output.targetDate?.formatted(date: .omitted, time: .shortened)
                : nil,
            destination: AnyView(PostOutputDetailView(brief: brief, output: output))
        )
    }

    @ViewBuilder
    private func homeTaskGroup(
        title: String,
        tasks: [CreatorTask],
        totalCount: Int,
        showsHeader: Bool
    ) -> some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if showsHeader {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title.uppercased())
                        Spacer()
                        Text("\(totalCount)")
                    }
                    .font(.agentMono)
                    .foregroundStyle(Color.agentSecondary)
                    .padding(.bottom, AgentSpacing.x1)
                }

                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    homeTaskRow(task)
                        .overlay(alignment: .bottom) {
                            if index < tasks.count - 1 {
                                Rectangle()
                                    .fill(Color.agentHairline)
                                    .frame(height: 1)
                            }
                        }
                }
            }
        }
    }

    private func homeTaskRow(_ task: CreatorTask) -> some View {
        HStack(spacing: AgentSpacing.x2) {
            Button {
                appModel.toggleTask(task, context: context)
            } label: {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(taskCheckboxColor(task), lineWidth: 1.25)
                    .frame(width: 19, height: 19)
                    .frame(width: 36, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(task.title)")

            NavigationLink(value: TaskNavigationRoute(taskID: task.id)) {
                HStack(spacing: AgentSpacing.x2) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.agentBody.weight(.semibold))
                            .lineLimit(2)
                        if let metadata = taskMetadata(task) {
                            Text(metadata)
                                .font(.agentMono)
                                .foregroundStyle(Color.agentSecondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.agentText)
                .frame(minHeight: 52)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private var weekAhead: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text("This week")
                        .font(.agentTitle)
                    Text("A few things to look forward to.")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                }
                Spacer()
                Button("Open Plan") {
                    appModel.requestedPlanMode = .week
                    appModel.selectedTab = .today
                }
                .font(.agentSubtext.weight(.semibold))
                .buttonStyle(.plain)
            }

            Rectangle()
                .fill(Color.agentHairline)
                .frame(height: 1)

            if weekItems.isEmpty {
                Text("The rest of the week is open.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .padding(.vertical, AgentSpacing.x4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(weekItems.prefix(5).enumerated()), id: \.element.id) { index, item in
                        weekItemRow(item)
                            .padding(.vertical, AgentSpacing.x4)
                            .overlay(alignment: .bottom) {
                                if index < min(weekItems.count, 5) - 1 {
                                    Rectangle().fill(Color.agentHairline).frame(height: 1)
                                }
                            }
                    }
                }
            }
        }
        .padding(AgentSpacing.x6)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
    }

    private var weeklyFocusSection: some View {
        Button {
            showsWeeklyFocusEditor = true
        } label: {
            HStack(spacing: AgentSpacing.x3) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    MetaLabel("Weekly focus")
                    Text(weeklyFocusSummaryText)
                        .font(.agentBody.weight(.medium))
                        .foregroundStyle(Color.agentText)
                }

                Spacer(minLength: AgentSpacing.x3)

                Text(focusTemplates.isEmpty ? "Set" : "Edit")
                    .font(.agentSubtext.weight(.semibold))
                    .foregroundStyle(Color.agentText)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.agentSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(AgentSpacing.x4)
            .contentShape(.rect(cornerRadius: AgentRadius.dashboard))
        }
        .buttonStyle(.plain)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
        .accessibilityLabel("Weekly focus, \(weeklyFocusSummaryText)")
        .accessibilityHint(focusTemplates.isEmpty ? "Sets your weekly focus" : "Edits your weekly focus")
    }

    private var weeklyFocusSummaryText: String {
        guard !focusTemplates.isEmpty else { return "Not set" }
        let focusedDays = Set(focusTemplates.filter(\.isActive).map(\.weekdayRaw)).count
        let restDays = max(0, 7 - focusedDays)
        let focusLabel = focusedDays == 1 ? "focus day" : "focus days"
        let restLabel = restDays == 1 ? "rest day" : "rest days"
        return "\(focusedDays) \(focusLabel) · \(restDays) \(restLabel)"
    }

    private var quickCySection: some View {
        let canSend = !quickCyPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                MetaLabel("Quick Cy")
                Text("Start with what is on your mind.")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
            }

            ZStack(alignment: .bottomTrailing) {
                TextField("Ask Cy", text: $quickCyPrompt, axis: .vertical)
                    .font(.agentBody)
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.send)
                    .onSubmit(sendQuickCyPrompt)
                    .padding(.leading, AgentSpacing.x4)
                    .padding(.trailing, AgentSpacing.x12 + AgentSpacing.x3)
                    .padding(.vertical, AgentSpacing.x4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: sendQuickCyPrompt) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(canSend ? Color.onCyAccent : Color.agentSecondary)
                        .frame(width: 44, height: 44)
                        .background(canSend ? Color.cyAccent : Color.agentSurface, in: .circle)
                        .overlay {
                            Circle()
                                .stroke(canSend ? Color.cyAccent : Color.agentBorder, lineWidth: 1)
                        }
                        .shadow(
                            color: canSend ? Color.cyAccent.opacity(0.24) : Color.clear,
                            radius: 10,
                            y: 4
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .padding(6)
                .accessibilityLabel("Send to Cy")
            }
            .frame(minHeight: 56)
            .background(Color.agentCanvas, in: .rect(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.agentBorder, lineWidth: 1)
            }
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
        .shadow(color: Color.black.opacity(0.045), radius: 18, y: 8)
    }

    private var pastDuePostsSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel("Needs a new date")
                Spacer()
                Text("\(pastDueOutputs.count)")
                    .font(.agentMono)
                    .foregroundStyle(Color.agentSecondary)
            }

            if pastDueOutputs.isEmpty {
                Text("No missed posts.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .padding(.vertical, AgentSpacing.x2)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(pastDueOutputs.prefix(3).enumerated()), id: \.element.id) { index, output in
                        if let brief = brief(for: output) {
                            NavigationLink {
                                PostOutputDetailView(brief: brief, output: output)
                            } label: {
                                HStack(spacing: AgentSpacing.x3) {
                                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                                        HStack(spacing: AgentSpacing.x3) {
                                            Circle()
                                                .fill(Color.agentDestructive)
                                                .frame(width: 7, height: 7)

                                            Text(outputTitle(output, brief: brief))
                                                .font(.agentBody.weight(.semibold))
                                                .lineLimit(2)
                                        }

                                        Text(pastDueMetadata(output, brief: brief))
                                            .font(.agentMono)
                                            .foregroundStyle(Color.agentDestructive)
                                            .lineLimit(1)
                                            .padding(.leading, AgentSpacing.x3 + 7)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(Color.agentText)
                                .frame(minHeight: 58)
                                .padding(.vertical, AgentSpacing.x2)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .bottom) {
                                if index < min(pastDueOutputs.count, 3) - 1 {
                                    Rectangle()
                                        .fill(Color.agentHairline)
                                        .frame(height: 1)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
        .shadow(color: Color.black.opacity(0.045), radius: 18, y: 8)
    }

    private var recentIdeasSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel("Recent ideas")
                Spacer()
                Button("Open Idea Bank") {
                    appModel.selectedTab = .ideaBank
                }
                .font(.agentSubtext.weight(.semibold))
                .buttonStyle(.plain)
            }

            if recentIdeas.isEmpty {
                Text("No saved ideas yet.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .padding(.vertical, AgentSpacing.x2)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentIdeas.prefix(3).enumerated()), id: \.element.id) { index, idea in
                        NavigationLink {
                            IdeaPostDraftView(brief: idea)
                        } label: {
                            HStack(spacing: AgentSpacing.x3) {
                                Circle()
                                    .fill(pillarAccent(for: idea))
                                    .frame(width: 7, height: 7)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(idea.title)
                                        .font(.agentBody.weight(.semibold))
                                        .lineLimit(2)
                                    Text((pillar(for: idea)?.name ?? "No pillar").uppercased())
                                        .font(.agentMono)
                                        .foregroundStyle(Color.agentSecondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(Color.agentText)
                            .frame(minHeight: 58)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) {
                            if index < min(recentIdeas.count, 3) - 1 {
                                Rectangle()
                                    .fill(Color.agentHairline)
                                    .frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
        .shadow(color: Color.black.opacity(0.045), radius: 18, y: 8)
    }

    private func sendQuickCyPrompt() {
        let trimmedPrompt = quickCyPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }
        appModel.pendingCyPrompt = trimmedPrompt
        quickCyPrompt = ""
        appModel.selectedTab = .cy
    }

    private func pastDueMetadata(_ output: PlatformOutput, brief: CreativeBrief) -> String {
        let date = output.targetDate?.formatted(.dateTime.month(.abbreviated).day()) ?? "Date passed"
        return "MISSED · \(date) · \(pillar(for: brief)?.name ?? "No pillar")"
    }

    @ViewBuilder
    private func weekItemRow(_ item: HomeWeekItem) -> some View {
        switch item {
        case .post(let output, let brief):
            NavigationLink {
                PostOutputDetailView(brief: brief, output: output)
            } label: {
                weekRow(
                    date: output.targetDate,
                    marker: pillarColor(for: brief),
                    eyebrow: "Post",
                    title: outputTitle(output, brief: brief),
                    detail: platformLabel(for: output)
                )
            }
            .buttonStyle(.plain)
        case .task(let task):
            NavigationLink(value: TaskNavigationRoute(taskID: task.id)) {
                weekRow(
                    date: task.targetDate ?? task.dailyFocusDate,
                    marker: .agentSecondary,
                    eyebrow: "Task",
                    title: task.title,
                    detail: task.targetDate?.formatted(date: .omitted, time: task.includesTargetTime ? .shortened : .omitted) ?? "Planned"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func weekRow(
        date: Date?,
        marker: Color,
        eyebrow: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(spacing: AgentSpacing.x3) {
            VStack(spacing: 1) {
                Text(date?.formatted(.dateTime.weekday(.abbreviated)) ?? "—")
                    .font(.agentMono)
                Text(date?.formatted(.dateTime.day()) ?? "")
                    .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
            }
            .frame(width: 42)

            Circle()
                .fill(marker)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow.uppercased())
                    .font(.agentMono)
                    .foregroundStyle(Color.agentSecondary)
                Text(title)
                    .font(.agentBody.weight(.semibold))
                    .lineLimit(2)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(Color.agentText)
        .contentShape(.rect)
    }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var activeIdentity: ActiveCreatorIdentity {
        ActiveCreatorIdentity.resolve(
            profile: profiles.first,
            workspaces: workspaces,
            preferredWorkspaceID: appModel.activeWorkspaceID
        )
    }

    private var todayFocus: ResolvedDailyFocus? {
        DailyFocusResolver.resolve(
            date: today,
            templates: focusTemplates,
            overrides: focusOverrides
        )
    }

    private var todayFocusTitle: String {
        todayFocus?.title.nilIfBlank ?? "Rest"
    }

    private var todayTasks: [CreatorTask] {
        tasks.filter { task in
            !task.isCompleted &&
                !task.isSkipped &&
                task.parentTaskID == nil &&
                [task.targetDate, task.dailyFocusDate]
                    .compactMap { $0 }
                    .contains(where: Calendar.current.isDateInToday)
        }
        .sorted {
            let lhsDate = $0.targetDate ?? $0.dailyFocusDate ?? .distantFuture
            let rhsDate = $1.targetDate ?? $1.dailyFocusDate ?? .distantFuture
            if lhsDate == rhsDate { return $0.createdAt < $1.createdAt }
            return lhsDate < rhsDate
        }
    }

    private var todayMyTasks: [CreatorTask] {
        todayTasks.filter { $0.briefID == nil }
    }

    private var todayPostTasks: [CreatorTask] {
        todayTasks.filter { $0.briefID != nil }
    }

    private var displayedTodayMyTasks: [CreatorTask] {
        showsAllTodayTasks ? todayMyTasks : Array(todayMyTasks.prefix(2))
    }

    private var displayedTodayPostTasks: [CreatorTask] {
        showsAllTodayTasks ? todayPostTasks : Array(todayPostTasks.prefix(2))
    }

    private var hiddenTodayTaskCount: Int {
        guard !showsAllTodayTasks else { return 0 }
        return todayTasks.count - displayedTodayMyTasks.count - displayedTodayPostTasks.count
    }

    private var scheduledTodayOutputs: [PlatformOutput] {
        outputs.filter { output in
            output.status == .scheduled &&
                output.targetDate.map(Calendar.current.isDateInToday) == true &&
                brief(for: output)?.status != .archived
        }
        .sorted { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
    }

    private var pastDueOutputs: [PlatformOutput] {
        outputs.filter { output in
            guard let brief = brief(for: output), brief.status != .archived else { return false }
            return FinalizedPostPresentation.isMissed(
                outputStatus: output.status,
                targetDate: output.targetDate
            )
        }
        .sorted { ($0.targetDate ?? .distantPast) > ($1.targetDate ?? .distantPast) }
    }

    private var recentIdeas: [CreativeBrief] {
        briefs.filter { brief in
            (brief.status == .spark || brief.status == .developing) &&
                !brief.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var weekItems: [HomeWeekItem] {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let daysSinceMonday = (calendar.component(.weekday, from: today) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: monday) ?? today

        let postItems: [HomeWeekItem] = outputs.compactMap { output in
            guard output.status != .posted,
                  let date = output.targetDate,
                  date >= tomorrow,
                  date < endOfWeek,
                  let brief = brief(for: output),
                  brief.status != .archived
            else { return nil }
            return .post(output, brief)
        }

        let taskItems: [HomeWeekItem] = tasks.compactMap { task in
            guard !task.isCompleted,
                  !task.isSkipped,
                  task.parentTaskID == nil,
                  let date = task.targetDate ?? task.dailyFocusDate,
                  date >= tomorrow,
                  date < endOfWeek
            else { return nil }
            return .task(task)
        }

        return (postItems + taskItems).sorted { $0.date < $1.date }
    }

    private func scoped<T: WorkspaceScopedRecord>(_ values: [T]) -> [T] {
        values.filter {
            WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private func brief(for output: PlatformOutput) -> CreativeBrief? {
        briefs.first { $0.id == output.briefID }
    }

    private func pillar(for brief: CreativeBrief) -> Pillar? {
        brief.pillarID.flatMap { id in pillars.first { $0.id == id } }
    }

    private func pillarColor(for brief: CreativeBrief) -> Color {
        pillarAccent(for: brief)
    }

    private func pillarAccent(for brief: CreativeBrief) -> Color {
        guard let pillar = pillar(for: brief) else { return .agentSecondary }
        return Color(agentHex: pillar.resolvedColorHex(in: pillars))
    }

    private func outputTitle(_ output: PlatformOutput, brief: CreativeBrief) -> String {
        let titleOverride = output.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return titleOverride.isEmpty ? brief.title : titleOverride
    }

    private func platformLabel(for output: PlatformOutput) -> String {
        if let destinationID = output.destinationID,
           let destination = destinations.first(where: { $0.id == destinationID }) {
            return destination.name
        }
        if let formatID = output.formatID,
           let format = formats.first(where: { $0.id == formatID }) {
            return format.name
        }
        return output.platform.title
    }

    private func taskMetadata(_ task: CreatorTask) -> String? {
        let postTitle = task.briefID.flatMap { id in
            briefs.first { $0.id == id }?.title.nilIfBlank
        }
        let time = task.includesTargetTime
            ? task.targetDate?.formatted(date: .omitted, time: .shortened)
            : nil
        let priority = task.priority.normalized == .none ? nil : task.priority.normalized.title
        let values = [postTitle, time, priority].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private func taskCheckboxColor(_ task: CreatorTask) -> Color {
        switch task.priority.normalized {
        case .urgent: .agentDestructive
        case .high: .orange
        default: .agentBorder
        }
    }

    private var dashboardOrderStorageKey: String {
        appModel.activeWorkspaceID?.uuidString ?? "default"
    }

    private func beginArrangingDashboard() {
        guard !isArrangingDashboard else { return }

        withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
            isArrangingDashboard = true
        }
        arrangeFeedback += 1
    }

    private func finishDashboardDrag(_ card: HomeDashboardCard, translation: CGSize) {
        updateDashboardOrder(card, translation: translation)

        withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) {
            dashboardDragCompensationY = 0
            draggedDashboardCard = nil
        }
        dashboardDragOriginFrame = nil
        dashboardCardDidMove()
    }

    private func updateDashboardOrder(_ card: HomeDashboardCard, translation: CGSize) {
        guard isArrangingDashboard,
              draggedDashboardCard == card,
              let originFrame = dashboardDragOriginFrame
        else { return }

        let finalMidY = originFrame.midY + translation.height
        let remainingCards = dashboardCards.filter { $0 != card }
        let insertionIndex = remainingCards.firstIndex { candidate in
            guard let frame = dashboardCardFrames[candidate] else { return false }
            return finalMidY < frame.midY
        } ?? remainingCards.endIndex

        var reorderedCards = remainingCards
        reorderedCards.insert(card, at: insertionIndex)
        guard reorderedCards != dashboardCards else { return }

        let destinationMinY = dashboardCardMinY(for: card, in: reorderedCards)
        let compensation = destinationMinY.map { originFrame.minY - $0 } ?? dashboardDragCompensationY

        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2, extraBounce: 0.04)) {
            dashboardCards = reorderedCards
            dashboardDragCompensationY = compensation
        }
        arrangeFeedback += 1
    }

    private func dashboardCardMinY(
        for target: HomeDashboardCard,
        in orderedCards: [HomeDashboardCard]
    ) -> CGFloat? {
        guard let firstMinY = dashboardCardFrames.values.map(\.minY).min() else { return nil }

        var currentMinY = firstMinY
        for card in orderedCards {
            if card == target { return currentMinY }
            guard let frame = dashboardCardFrames[card] else { return nil }
            currentMinY += frame.height + AgentSpacing.x6
        }
        return nil
    }

    private func toggleDashboardCustomization() {
        if isArrangingDashboard {
            finishArrangingDashboard()
        } else {
            beginArrangingDashboard()
        }
    }

    private func setDashboardCard(_ card: HomeDashboardCard, isVisible: Bool) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
            if isVisible {
                hiddenDashboardCards.remove(card)
                guard !dashboardCards.contains(card) else { return }
                dashboardCards.append(card)
            } else {
                hiddenDashboardCards.insert(card)
                dashboardCards.removeAll { $0 == card }
                if draggedDashboardCard == card {
                    draggedDashboardCard = nil
                    dashboardDragOriginFrame = nil
                    dashboardDragCompensationY = 0
                }
            }
        }
        dashboardCardDidMove()
    }

    private func finishArrangingDashboard() {
        guard isArrangingDashboard || draggedDashboardCard != nil else { return }

        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
            isArrangingDashboard = false
            draggedDashboardCard = nil
            dashboardDragOriginFrame = nil
            dashboardDragCompensationY = 0
        }
        persistDashboardCardOrder()
    }

    private func dashboardCardDidMove() {
        arrangeFeedback += 1
        persistDashboardCardOrder()
    }

    private func moveDashboardCard(_ card: HomeDashboardCard, offset: Int) {
        guard let sourceIndex = dashboardCards.firstIndex(of: card) else { return }
        let destinationIndex = min(max(sourceIndex + offset, 0), dashboardCards.count - 1)
        guard sourceIndex != destinationIndex else { return }

        beginArrangingDashboard()
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
            dashboardCards.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
            )
        }
        dashboardCardDidMove()
    }

    private func restoreDashboardCardOrder() {
        let savedValues = decodedDashboardCardOrders[dashboardOrderStorageKey] ?? []
        let savedCards = savedValues.compactMap(HomeDashboardCard.init(rawValue:))
        let savedHiddenValues = decodedHiddenDashboardCards[dashboardOrderStorageKey] ?? []
        let savedHiddenCards = Set(savedHiddenValues.compactMap(HomeDashboardCard.init(rawValue:)))
        let uniqueSavedCards = savedCards.reduce(into: [HomeDashboardCard]()) { result, card in
            guard !result.contains(card), !savedHiddenCards.contains(card) else { return }
            result.append(card)
        }
        let knownCards = Set(uniqueSavedCards).union(savedHiddenCards)
        let missingCards = HomeDashboardCard.defaultOrder.filter { !knownCards.contains($0) }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dashboardCards = uniqueSavedCards + missingCards
            hiddenDashboardCards = savedHiddenCards
        }
    }

    private func persistDashboardCardOrder() {
        var orders = decodedDashboardCardOrders
        orders[dashboardOrderStorageKey] = dashboardCards.map(\.rawValue)

        guard let data = try? JSONEncoder().encode(orders),
              let value = String(data: data, encoding: .utf8)
        else { return }
        storedDashboardCardOrders = value

        var hiddenOrders = decodedHiddenDashboardCards
        hiddenOrders[dashboardOrderStorageKey] = hiddenDashboardCards.map(\.rawValue).sorted()

        guard let hiddenData = try? JSONEncoder().encode(hiddenOrders),
              let hiddenValue = String(data: hiddenData, encoding: .utf8)
        else { return }
        storedHiddenDashboardCards = hiddenValue
    }

    private var decodedDashboardCardOrders: [String: [String]] {
        guard let data = storedDashboardCardOrders.data(using: .utf8),
              let orders = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return orders
    }

    private var decodedHiddenDashboardCards: [String: [String]] {
        guard let data = storedHiddenDashboardCards.data(using: .utf8),
              let orders = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return orders
    }

}

private enum HomeDashboardCard: String, CaseIterable, Identifiable {
    case scheduledToday
    case tasks
    case weekAhead
    case weeklyFocus
    case quickCy
    case pastDuePosts
    case recentIdeas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scheduledToday: "Scheduled today"
        case .tasks: "Tasks"
        case .weekAhead: "This week"
        case .weeklyFocus: "Weekly focus"
        case .quickCy: "Quick Cy"
        case .pastDuePosts: "Past-due posts"
        case .recentIdeas: "Recent ideas"
        }
    }

    static let defaultOrder: [HomeDashboardCard] = [
        .quickCy,
        .scheduledToday,
        .tasks,
        .pastDuePosts,
        .recentIdeas,
        .weekAhead,
        .weeklyFocus
    ]
}

private struct DashboardReorderableCard<Content: View>: View {
    let card: HomeDashboardCard
    let isArranging: Bool
    let reduceMotion: Bool
    let dragCompensationY: CGFloat
    let onDragBegan: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void
    let content: Content

    @GestureState private var dragTranslation: CGSize = .zero
    @State private var isDragging = false

    init(
        card: HomeDashboardCard,
        isArranging: Bool,
        reduceMotion: Bool,
        dragCompensationY: CGFloat,
        onDragBegan: @escaping () -> Void,
        onDragChanged: @escaping (CGSize) -> Void,
        onDragEnded: @escaping (CGSize) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.card = card
        self.isArranging = isArranging
        self.reduceMotion = reduceMotion
        self.dragCompensationY = dragCompensationY
        self.onDragBegan = onDragBegan
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .top) {
            content
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: HomeDashboardCardFramePreferenceKey.self,
                            value: [card: proxy.frame(in: .named(HomeDashboardCoordinateSpace.name))]
                        )
                    }
                }

            if isArranging {
                dragHandle
                    .offset(y: -15)
                    .zIndex(1)
            }
        }
        .offset(y: isDragging ? dragTranslation.height + dragCompensationY : 0)
        .scaleEffect(isDragging ? 1.01 : 1)
        .shadow(
            color: isDragging ? Color.black.opacity(0.14) : .clear,
            radius: isDragging ? 18 : 0,
            y: isDragging ? 9 : 0
        )
        .zIndex(isDragging ? 10 : 0)
    }

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.agentSecondary)
            .frame(width: 52, height: 30)
            .contentShape(.capsule)
            .glassEffect(.clear.interactive(), in: .capsule)
            .overlay {
                Capsule()
                    .stroke(Color.agentBorder, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: Color.black.opacity(0.08),
                radius: 8,
                y: 3
            )
            .gesture(reorderGesture)
            .accessibilityLabel("Move \(card.title)")
            .accessibilityHint("Drag up or down to reorder this dashboard card")
    }

    private var reorderGesture: some Gesture {
        DragGesture(
            minimumDistance: 2,
            coordinateSpace: .named(HomeDashboardCoordinateSpace.name)
        )
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onChanged { value in
                guard isArranging else { return }

                if !isDragging {
                    isDragging = true
                    onDragBegan()
                }
                onDragChanged(value.translation)
            }
            .onEnded { value in
                guard isArranging, isDragging else { return }
                onDragEnded(value.translation)
                isDragging = false
            }
    }
}

private enum HomeDashboardCoordinateSpace {
    static let name = "home-dashboard-reorder"
}

private struct HomeDashboardCardFramePreferenceKey: PreferenceKey {
    static let defaultValue: [HomeDashboardCard: CGRect] = [:]

    static func reduce(
        value: inout [HomeDashboardCard: CGRect],
        nextValue: () -> [HomeDashboardCard: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

private enum HomeWeekItem: Identifiable {
    case post(PlatformOutput, CreativeBrief)
    case task(CreatorTask)

    var id: String {
        switch self {
        case .post(let output, _): "post-\(output.id.uuidString)"
        case .task(let task): "task-\(task.id.uuidString)"
        }
    }

    var date: Date {
        switch self {
        case .post(let output, _): output.targetDate ?? .distantFuture
        case .task(let task): task.targetDate ?? task.dailyFocusDate ?? .distantFuture
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
