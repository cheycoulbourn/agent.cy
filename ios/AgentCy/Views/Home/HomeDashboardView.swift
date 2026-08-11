import SwiftData
import SwiftUI
import OSLog

private let dashboardWidgetLogger = Logger(
    subsystem: "com.agentcy.app",
    category: "DashboardWidgets"
)

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
    @Query(sort: \BrandPartner.updatedAt, order: .reverse) private var allBrandPartners: [BrandPartner]
    @State private var dashboardLayout = DashboardWidgetLayoutState()
    @State private var isArrangingDashboard = false
    @State private var showsWeeklyFocusEditor = false
    @State private var arrangeFeedback = 0
    @AppStorage("agentcy.homeDashboardWidgetPreferences") private var storedDashboardWidgetPreferences = ""
    @AppStorage("agentcy.homeDashboardCardOrderByWorkspace") private var legacyDashboardCardOrders = ""
    @AppStorage("agentcy.homeDashboardHiddenCardsByWorkspace") private var legacyHiddenDashboardCards = ""

    private var briefs: [CreativeBrief] { scoped(allBriefs) }
    private var outputs: [PlatformOutput] { scoped(allOutputs) }
    private var tasks: [CreatorTask] { scoped(allTasks) }
    private var pillars: [Pillar] { scoped(allPillars) }
    private var focusTemplates: [DailyFocusTemplateEntry] { scoped(allFocusTemplates) }
    private var focusOverrides: [DailyFocusOverride] { scoped(allFocusOverrides) }
    private var brandPartners: [BrandPartner] { scoped(allBrandPartners) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                header

                dashboardWidgets
                #if !targetEnvironment(macCatalyst)
                weeklyFocusEditorSection
                #endif
                dashboardCustomizationFooter
            }
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.top, homePageTopPadding)
            .agentBottomNavigationClearance()
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
        .background(Color.agentCanvas.ignoresSafeArea())
        .onAppear {
            restoreDashboardCardOrder()
        }
        .onChange(of: appModel.activeWorkspaceID) { _, _ in
            finishArrangingDashboard()
            restoreDashboardCardOrder()
        }
        .sheet(isPresented: $showsWeeklyFocusEditor) {
            WeeklyFocusSetupView()
        }
        .sensoryFeedback(.selection, trigger: arrangeFeedback)
    }

    private var homePageTopPadding: CGFloat {
        #if targetEnvironment(macCatalyst)
        AgentLayout.pageTopPadding + AgentSpacing.x4
        #else
        AgentLayout.pageTopPadding
        #endif
    }

    private var weeklyFocusEditorSection: some View {
        Button {
            showsWeeklyFocusEditor = true
        } label: {
            HStack(spacing: AgentSpacing.x3) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text("Weekly focus")
                        .font(.agentTitle)
                    Text(weeklyFocusSummary)
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                }

                Spacer(minLength: AgentSpacing.x3)

                Text("Edit")
                    .font(.agentSubtext.weight(.semibold))
                AgentIconView(.forward, size: 12)
            }
            .foregroundStyle(Color.agentText)
            .padding(.horizontal, AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 80)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
        .agentSurfaceChrome(cornerRadius: AgentRadius.dashboard)
        .accessibilityHint("Opens the recurring weekly focus editor")
    }

    private var weeklyFocusSummary: String {
        let focusCount = PillarWeekday.mondayFirst.filter { day in
            focusTemplates.contains { $0.weekday == day && $0.isActive }
        }.count
        let restCount = PillarWeekday.mondayFirst.count - focusCount
        return "\(focusCount) focus \(focusCount == 1 ? "day" : "days") · \(restCount) rest \(restCount == 1 ? "day" : "days")"
    }

    private var dashboardCustomizationFooter: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            if isArrangingDashboard {
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        MetaLabel("Dashboard widgets")
                        Text(dashboardCustomizationInstructions)
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(dashboardCustomizationCards.enumerated()), id: \.element.id) { index, card in
                            dashboardWidgetControl(card)

                            if index < dashboardCustomizationCards.count - 1 {
                                Rectangle()
                                    .fill(Color.agentHairline)
                                    .frame(height: 1)
                            }
                        }

                        if !availableDashboardCards.isEmpty {
                            if !dashboardLayout.orderedCards.isEmpty {
                                Rectangle()
                                    .fill(Color.agentHairline)
                                    .frame(height: 1)
                            }

                            Menu {
                                ForEach(availableDashboardCards) { card in
                                    Button(card.title) {
                                        setDashboardCard(card, isVisible: true)
                                    }
                                }
                            } label: {
                                HStack(spacing: AgentSpacing.x2) {
                                    AgentIconView(.add, size: 14)
                                    Text("Add widget")
                                }
                                .font(.agentSubtext.weight(.semibold))
                                .foregroundStyle(Color.agentText)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows dashboard widgets that are not currently in use")
                        }
                    }
                    .padding(.horizontal, AgentSpacing.x4)
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
                    .agentSurfaceChrome(cornerRadius: AgentRadius.dashboard)
                }
                .transition(.opacity)
            }

            customizeDashboardButton
                .frame(width: 128)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var customizeDashboardButton: some View {
        Button(action: toggleDashboardCustomization) {
            Text(isArrangingDashboard ? "Done" : "Customize")
                .font(.agentSubtext.weight(.semibold))
                .foregroundStyle(Color.agentText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect(cornerRadius: 22))
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

    private func dashboardWidgetControl(_ card: HomeDashboardCard) -> some View {
        return HStack(spacing: AgentSpacing.x3) {
            Text(card.title)
                .font(.agentBody.weight(.medium))
                .foregroundStyle(Color.agentText)

            Spacer()

            dashboardWidgetMoveButton(card, offset: -1)
            dashboardWidgetMoveButton(card, offset: 1)

            Button {
                setDashboardCard(card, isVisible: false)
            } label: {
                Text("Remove")
                    .font(.agentSubtext.weight(.semibold))
                    .foregroundStyle(Color.agentSecondary)
                    .frame(minWidth: 64, minHeight: 44, alignment: .trailing)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(card.title)")
        }
        .frame(minHeight: 54)
    }

    private func dashboardWidgetMoveButton(_ card: HomeDashboardCard, offset: Int) -> some View {
        let cards = renderableDashboardCards
        let currentIndex = cards.firstIndex(of: card)
        let destinationIndex = currentIndex.map { $0 + offset }
        let isEnabled = destinationIndex.map(cards.indices.contains) ?? false

        return Button {
            moveDashboardCard(card, offset: offset)
        } label: {
            AgentIconView(offset < 0 ? .collapse : .expand, size: 11)
                .foregroundStyle(Color.agentSecondary)
                .frame(width: 28, height: 28)
                .background(Color.agentCanvas, in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.28)
        .accessibilityLabel(offset < 0 ? "Move \(card.title) up" : "Move \(card.title) down")
    }

    private var dashboardCustomizationCards: [HomeDashboardCard] {
        dashboardLayout.orderedCards.filter(dashboardCardIsRenderable)
    }

    private var dashboardCustomizationInstructions: String {
        "Move cards up or down, or remove anything you do not need today."
    }

    private var availableDashboardCards: [HomeDashboardCard] {
        HomeDashboardCard.defaultOrder.filter {
            dashboardCardIsRenderable($0) && !dashboardLayout.orderedCards.contains($0)
        }
    }

    private var renderableDashboardCards: [HomeDashboardCard] {
        dashboardLayout.orderedCards.filter(dashboardCardIsRenderable)
    }

    @ViewBuilder
    private var dashboardWidgets: some View {
        LazyVStack(alignment: .leading, spacing: AgentSpacing.x6) {
            ForEach(renderableDashboardCards) { card in
                reorderableDashboardCard(card)
            }
            #if targetEnvironment(macCatalyst)
            weeklyFocusEditorSection
            #endif
        }
    }

    private func dashboardCardIsRenderable(_ card: HomeDashboardCard) -> Bool {
        card != .brandCabinet || (profiles.first?.showsBrandDealsInPostEditor ?? false)
    }

    @ViewBuilder
    private func dashboardCard(_ card: HomeDashboardCard) -> some View {
        switch card {
        case .scheduledToday:
            scheduledTodaySection
        case .continueWorking:
            continueWorkingSection
        case .tasks:
            todayTasksSection
        case .weekAhead:
            weekAhead
        case .nextWeek:
            nextWeekAhead
        case .pastDuePosts:
            pastDuePostsSection
        case .recentIdeas:
            recentIdeasSection
        case .brandCabinet:
            brandCabinetSection
        }
    }

    private var brandCabinetSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack {
                Text("Brand cabinet")
                    .font(.agentTitle)
                Spacer()
                NavigationLink("Open") {
                    BrandCabinetView()
                }
                .font(.agentSubtext.weight(.semibold))
                .foregroundStyle(Color.agentText)
            }

            Rectangle()
                .fill(Color.agentHairline)
                .frame(height: 1)

            let activePartners = brandPartners
                .filter { $0.stage != .archived && $0.stage != .pastPartner }
                .sorted {
                    switch ($0.nextFollowUpAt, $1.nextFollowUpAt) {
                    case let (lhs?, rhs?): lhs < rhs
                    case (.some, .none): true
                    case (.none, .some): false
                    case (.none, .none): $0.updatedAt > $1.updatedAt
                    }
                }

            if activePartners.isEmpty {
                Text("No active partnerships yet.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .padding(.vertical, AgentSpacing.x2)
            } else {
                ForEach(activePartners.prefix(3)) { partner in
                    NavigationLink {
                        BrandPartnerDetailView(partner: partner)
                    } label: {
                        HStack(spacing: AgentSpacing.x3) {
                            BrandPartnerAvatar(partner: partner, size: 34)
                            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                Text(partner.name)
                                    .font(.agentHeadline)
                                    .foregroundStyle(Color.agentText)
                                    .lineLimit(1)
                                Text(
                                    partner.nextFollowUpAt.map {
                                        "Follow up \($0.formatted(.dateTime.month(.abbreviated).day()))"
                                    } ?? partner.stage.title
                                )
                                .font(.agentMetadata)
                                .foregroundStyle(
                                    partner.nextFollowUpAt == nil ? Color.agentSecondary : Color.actionAccent
                                )
                            }
                            Spacer()
                            AgentIconView(.forward, size: 12)
                                .foregroundStyle(Color.agentSecondary)
                        }
                        .frame(minHeight: 48)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
    }

    private func reorderableDashboardCard(_ card: HomeDashboardCard) -> some View {
        dashboardCard(card)
            .agentSurfaceChrome(cornerRadius: AgentRadius.dashboard)
            .disabled(isArrangingDashboard)
            .accessibilityHint(
                isArrangingDashboard
                    ? "Use the dashboard widget controls below to move this card"
                    : "Use Customize at the bottom of the dashboard to arrange cards"
            )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            AgentPageRail(
                breadcrumb: today.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()),
                identity: activeIdentity,
                openSettings: { appModel.presentedSheet = .settings }
            )

            #if !targetEnvironment(macCatalyst)
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
            #endif

            VStack(alignment: .leading, spacing: 2) {
                Text("\(greeting), \(activeIdentity.greetingName).")
                    .font(.agentDisplayLead)
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
                Text("Up next")
                    .font(.agentTitle)
                Spacer()
                Button("View the day") {
                    appModel.widgetAgendaDay = today
                    appModel.selectedTab = .today
                }
                .font(.agentSubtext.weight(.semibold))
                .buttonStyle(.plain)
                .accessibilityHint("Opens today's agenda")
            }

            Rectangle()
                .fill(Color.agentHairline)
                .frame(height: 1)

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
    }

    private var todayTasksSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today’s tasks")
                    .font(.agentTitle)
                Spacer()
                viewAllTasksButton
            }

            Rectangle()
                .fill(Color.agentHairline)
                .frame(height: 1)

            if todayTasks.isEmpty {
                Text("Nothing is planned.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                .padding(.vertical, AgentSpacing.x2)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        homeTaskGroup(
                            title: "Focus tasks",
                            tasks: todayMyTasks,
                            totalCount: todayMyTasks.count,
                            showsHeader: true
                        )
                        homeTaskGroup(
                            title: "Post tasks",
                            tasks: todayPostTasks,
                            totalCount: todayPostTasks.count,
                            showsHeader: true
                        )
                    }
                }
            }
        }
        .padding(.horizontal, AgentSpacing.x4)
        .padding(.top, AgentSpacing.x4)
        .padding(.bottom, AgentSpacing.x4)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
    }

    private var viewAllTasksButton: some View {
        Button("View all") {
            appModel.selectedTab = .tasks
        }
        .font(.agentSubtext.weight(.semibold))
        .buttonStyle(.plain)
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
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)
                    .padding(.bottom, AgentSpacing.x1)
                }

                ForEach(tasks) { task in
                    homeTaskRow(task)
                }
            }
        }
    }

    private func homeTaskRow(_ task: CreatorTask) -> some View {
        HStack(spacing: AgentSpacing.x2) {
            AgentTaskCheckbox(
                isCompleted: task.isCompleted,
                color: taskCheckboxColor(task),
                accessibilityLabel: task.isCompleted
                    ? "Mark \(task.title) open"
                    : "Complete \(task.title)"
            ) {
                appModel.toggleTask(task, context: context)
            }

            NavigationLink(value: TaskNavigationRoute(taskID: task.id)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.agentBody.weight(.semibold))
                        .lineLimit(2)
                    if let metadata = taskMetadata(task) {
                        Text(metadata)
                            .font(.agentMetadata)
                            .foregroundStyle(Color.agentSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Color.agentText)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private var weekAhead: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .font(.agentTitle)
                Spacer()
                Button("Open agenda") {
                    appModel.requestedPlanWeekOffset = 0
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
                    ForEach(Array(weekItems.enumerated()), id: \.element.id) { index, item in
                        weekItemRow(item)
                            .padding(.vertical, AgentSpacing.x4)
                            .overlay(alignment: .bottom) {
                                if index < weekItems.count - 1 {
                                    Rectangle().fill(Color.agentHairline).frame(height: 1)
                                }
                            }
                    }
                }
            }
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
    }

    private var nextWeekAhead: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Next week")
                    .font(.agentTitle)
                Spacer()
                Button("Open agenda") {
                    appModel.requestedPlanWeekOffset = 1
                    appModel.requestedPlanMode = .week
                    appModel.selectedTab = .today
                }
                .font(.agentSubtext.weight(.semibold))
                .buttonStyle(.plain)
            }

            Rectangle()
                .fill(Color.agentHairline)
                .frame(height: 1)

            if nextWeekItems.isEmpty {
                Text("Next week is open.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .padding(.vertical, AgentSpacing.x4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(nextWeekItems.enumerated()), id: \.element.id) { index, item in
                        weekItemRow(item)
                            .padding(.vertical, AgentSpacing.x4)
                            .overlay(alignment: .bottom) {
                                if index < nextWeekItems.count - 1 {
                                    Rectangle().fill(Color.agentHairline).frame(height: 1)
                                }
                            }
                    }
                }
            }
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
    }

    private var pastDuePostsSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Needs a new date")
                    .font(.agentTitle)
                Spacer()
            }

            Rectangle()
                .fill(Color.agentHairline)
                .frame(height: 1)

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
                                            .font(.agentMetadata)
                                            .foregroundStyle(Color.agentDestructive)
                                            .lineLimit(1)
                                            .padding(.leading, AgentSpacing.x3 + 7)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    AgentIconView(.forward, size: 12)
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
    }

    private var recentIdeasSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent ideas")
                    .font(.agentTitle)
                Spacer()
                Button("View all") {
                    appModel.selectedTab = .ideaBank
                }
                .font(.agentSubtext.weight(.semibold))
                .buttonStyle(.plain)
            }

            Rectangle()
                .fill(Color.agentHairline)
                .frame(height: 1)

            if recentIdeas.isEmpty {
                Text("No saved ideas yet.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .padding(.vertical, AgentSpacing.x2)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentIdeas.prefix(3).enumerated()), id: \.element.id) { index, idea in
                        NavigationLink {
                            IdeaPostDraftView(brief: idea, isAlreadyInIdeaBank: true)
                        } label: {
                            HStack(alignment: .center, spacing: AgentSpacing.x3) {
                                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                    HStack(spacing: AgentSpacing.x3) {
                                        PillarColorMark(
                                            color: pillarAccent(for: idea),
                                            diameter: AgentSpacing.x2
                                        )

                                        Text(idea.title)
                                            .font(.agentBody.weight(.semibold))
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .layoutPriority(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Text((pillar(for: idea)?.name ?? "No pillar").uppercased())
                                        .font(.agentMetadata)
                                        .foregroundStyle(Color.agentSecondary)
                                        .lineLimit(1)
                                        .padding(.leading, AgentSpacing.x5)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                AgentIconView(.forward, size: 12)
                                    .foregroundStyle(Color.agentSecondary)
                                    .frame(width: 20, alignment: .trailing)
                            }
                            .foregroundStyle(Color.agentText)
                            .frame(minHeight: AgentSpacing.x12 + AgentSpacing.x2)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(idea.title)
                        .accessibilityValue(pillar(for: idea)?.name ?? "No pillar")
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
    }

    private var continueWorkingSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Continue working on…")
                    .font(.agentTitle)

                Spacer()

                Button("View all") {
                    appModel.routeToOpenPostsList()
                }
                .font(.agentSubtext.weight(.semibold))
                .foregroundStyle(Color.agentText)
                .buttonStyle(.plain)
                .accessibilityHint("Opens the agenda list filtered to open posts")
            }

            Rectangle()
                .fill(Color.agentHairline)
                .frame(height: 1)

            if continueWorkingItems.isEmpty {
                Text("No drafts or posts in progress.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .padding(.vertical, AgentSpacing.x2)
            } else {
                VStack(spacing: AgentSpacing.x3) {
                    ForEach(continueWorkingItems.prefix(3)) { item in
                        AgentPostCard(
                            title: outputTitle(item.output, brief: item.brief),
                            pillar: pillar(for: item.brief)?.name ?? "Unfiled",
                            accent: pillarAccent(for: item.brief),
                            status: item.output.status,
                            metadata: platformLabel(for: item.output),
                            timeText: (item.brief.workDate ?? item.output.targetDate)?
                                .formatted(.dateTime.month(.abbreviated).day()),
                            statusTextOverride: ContinueWorkingPostPolicy.displayLabel(
                                briefStatus: item.brief.status,
                                outputStatus: item.output.status,
                                customStatus: item.brief.resolvedCustomStatusLabel,
                                ideaBankPlacement: item.brief.ideaBankPlacement
                            ),
                            destination: AnyView(
                                ResumablePostEditorView(
                                    brief: item.brief,
                                    output: item.output,
                                    onSpark: {}
                                )
                            )
                        )
                    }
                }
            }
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
    }

    private func pastDueMetadata(_ output: PlatformOutput, brief: CreativeBrief) -> String {
        let date = output.targetDate?.formatted(.dateTime.month(.abbreviated).day()) ?? "Date passed"
        return "MISSED · \(date) · \(pillar(for: brief)?.name ?? "No pillar")"
    }

    @ViewBuilder
    private func weekItemRow(_ item: HomeWeekItem) -> some View {
        NavigationLink {
            PostOutputDetailView(brief: item.brief, output: item.output)
        } label: {
            weekRow(
                date: item.output.targetDate,
                marker: pillarColor(for: item.brief),
                eyebrow: "Post",
                title: outputTitle(item.output, brief: item.brief),
                detail: platformLabel(for: item.output)
            )
        }
        .buttonStyle(.plain)
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
                    .font(.agentMetadata)
                Text(date?.formatted(.dateTime.day()) ?? "")
                    .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
            }
            .frame(width: 42)

            PillarColorMark(
                color: marker,
                diameter: 8,
                lineWidth: 1
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow.uppercased())
                    .font(.agentMetadata)
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

            AgentIconView(.forward, size: 13)
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

    private var scheduledTodayOutputs: [PlatformOutput] {
        outputs.filter { output in
            HomeTodayPostPolicy.includes(
                outputStatus: output.status,
                targetDate: output.targetDate,
                briefStatus: brief(for: output)?.status,
                today: today,
                calendar: .current
            )
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
        let draftBriefIDs = Set(continueWorkingItems.map { $0.brief.id })
        return briefs.filter { brief in
            IdeaBankPlacementPolicy.includes(brief) &&
                !draftBriefIDs.contains(brief.id) &&
                !brief.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var continueWorkingItems: [HomeContinueWorkingItem] {
        let candidates = outputs.compactMap { output -> HomeContinueWorkingItem? in
            guard let brief = brief(for: output),
                  ContinueWorkingPostPolicy.includes(
                    briefStatus: brief.status,
                    outputStatus: output.status,
                    customStatus: brief.resolvedCustomStatusLabel,
                    ideaBankPlacement: brief.ideaBankPlacement
                  ),
                  !brief.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }

            return HomeContinueWorkingItem(brief: brief, output: output)
        }
        .sorted { lhs, rhs in
            if lhs.brief.updatedAt == rhs.brief.updatedAt {
                return lhs.output.createdAt > rhs.output.createdAt
            }
            return lhs.brief.updatedAt > rhs.brief.updatedAt
        }

        var seenBriefIDs = Set<UUID>()
        return candidates.filter { seenBriefIDs.insert($0.brief.id).inserted }
    }

    private var weekItems: [HomeWeekItem] {
        let calendar = Calendar.current
        let postItems: [HomeWeekItem] = outputs.compactMap { output in
            guard let brief = brief(for: output),
                  HomeWeekAgendaPolicy.includes(
                    targetDate: output.targetDate,
                    briefStatus: brief.status,
                    today: today,
                    calendar: calendar
                  )
            else { return nil }
            return HomeWeekItem(output: output, brief: brief)
        }

        return postItems.sorted { $0.date < $1.date }
    }

    private var nextWeekItems: [HomeWeekItem] {
        let calendar = Calendar.current
        let postItems: [HomeWeekItem] = outputs.compactMap { output in
            guard let brief = brief(for: output),
                  HomeNextWeekAgendaPolicy.includes(
                    targetDate: output.targetDate,
                    briefStatus: brief.status,
                    today: today,
                    calendar: calendar
                  )
            else { return nil }
            return HomeWeekItem(output: output, brief: brief)
        }

        return postItems.sorted { $0.date < $1.date }
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

        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
            isArrangingDashboard = true
        }
        arrangeFeedback += 1
    }

    private func toggleDashboardCustomization() {
        if isArrangingDashboard {
            finishArrangingDashboard()
        } else {
            beginArrangingDashboard()
        }
    }

    private func setDashboardCard(_ card: HomeDashboardCard, isVisible: Bool) {
        var updatedLayout = dashboardLayout
        guard updatedLayout.setCard(card, isVisible: isVisible) else { return }

        applyDashboardLayout(updatedLayout)
        let action = isVisible ? "show" : "hide"
        dashboardWidgetLogger.info("Widget action=\(action, privacy: .public) card=\(card.rawValue, privacy: .public)")
        dashboardCardDidMove()
    }

    private func finishArrangingDashboard() {
        guard isArrangingDashboard else { return }

        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
            isArrangingDashboard = false
        }
    }

    private func dashboardCardDidMove() {
        arrangeFeedback += 1
        persistDashboardCardOrder()
    }

    private func moveDashboardCard(_ card: HomeDashboardCard, offset: Int) {
        var updatedLayout = dashboardLayout
        guard updatedLayout.moveCard(card, by: offset, within: renderableDashboardCards) else { return }

        applyDashboardLayout(updatedLayout)
        dashboardWidgetLogger.info("Widget action=move card=\(card.rawValue, privacy: .public) offset=\(offset)")
        dashboardCardDidMove()
    }

    private func restoreDashboardCardOrder() {
        let storedPreferences = DashboardWidgetPreferencesStore.decode(storedDashboardWidgetPreferences)
        let snapshot = storedPreferences?.layoutsByWorkspace[dashboardOrderStorageKey]
        let restoredLayout: DashboardWidgetLayoutState

        if let snapshot {
            restoredLayout = DashboardWidgetLayoutState(snapshot: snapshot)
        } else {
            let legacyOrders = DashboardWidgetPreferencesStore.decodeLegacyMap(legacyDashboardCardOrders)
            let legacyHidden = DashboardWidgetPreferencesStore.decodeLegacyMap(legacyHiddenDashboardCards)
            restoredLayout = DashboardWidgetLayoutState(
                savedOrderRawValues: legacyOrders[dashboardOrderStorageKey] ?? [],
                savedHiddenRawValues: legacyHidden[dashboardOrderStorageKey] ?? []
            )
        }

        applyDashboardLayout(restoredLayout)
        dashboardWidgetLogger.info(
            "Widget action=restore visible=\(restoredLayout.orderedCards.count) hidden=\(restoredLayout.hiddenCards.count)"
        )

        if snapshot == nil {
            persistDashboardCardOrder()
        }
    }

    private func persistDashboardCardOrder() {
        var preferences = DashboardWidgetPreferencesStore.decode(storedDashboardWidgetPreferences) ?? .init()
        preferences.layoutsByWorkspace[dashboardOrderStorageKey] = dashboardLayout.snapshot

        guard let encodedPreferences = preferences.encoded() else {
            dashboardWidgetLogger.error("Widget action=persist result=encoding-failed")
            return
        }
        storedDashboardWidgetPreferences = encodedPreferences
    }

    private func applyDashboardLayout(_ layout: DashboardWidgetLayoutState) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dashboardLayout = layout
        }
    }

}

enum HomeDashboardCard: String, CaseIterable, Identifiable, Codable, Sendable {
    case scheduledToday
    case continueWorking
    case tasks
    case weekAhead
    case nextWeek
    case pastDuePosts
    case recentIdeas
    case brandCabinet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scheduledToday: "Up next"
        case .continueWorking: "Continue working on…"
        case .tasks: "Today’s tasks"
        case .weekAhead: "This week"
        case .nextWeek: "Next week"
        case .pastDuePosts: "Past-due posts"
        case .recentIdeas: "Recent ideas"
        case .brandCabinet: "Brand cabinet"
        }
    }

    static let defaultOrder: [HomeDashboardCard] = [
        .scheduledToday,
        .continueWorking,
        .tasks,
        .pastDuePosts,
        .recentIdeas,
        .weekAhead,
        .nextWeek,
        .brandCabinet
    ]
}

struct DashboardWidgetLayoutSnapshot: Codable, Equatable, Sendable {
    let order: [String]
    let hidden: [String]
}

struct DashboardWidgetLayoutState: Equatable, Sendable {
    private(set) var orderedCards: [HomeDashboardCard]
    private(set) var hiddenCards: Set<HomeDashboardCard>

    init(
        savedOrderRawValues: [String] = [],
        savedHiddenRawValues: [String] = []
    ) {
        let hidden = Set(savedHiddenRawValues.compactMap(HomeDashboardCard.init(rawValue:)))
        let savedCards = savedOrderRawValues.compactMap(HomeDashboardCard.init(rawValue:))
        let uniqueSavedCards = savedCards.reduce(into: [HomeDashboardCard]()) { result, card in
            guard !hidden.contains(card), !result.contains(card) else { return }
            result.append(card)
        }
        let knownCards = Set(uniqueSavedCards).union(hidden)
        let newCards = HomeDashboardCard.defaultOrder.filter { !knownCards.contains($0) }

        orderedCards = uniqueSavedCards + newCards
        hiddenCards = hidden
    }

    init(snapshot: DashboardWidgetLayoutSnapshot) {
        self.init(
            savedOrderRawValues: snapshot.order,
            savedHiddenRawValues: snapshot.hidden
        )
    }

    var snapshot: DashboardWidgetLayoutSnapshot {
        DashboardWidgetLayoutSnapshot(
            order: orderedCards.map(\.rawValue),
            hidden: hiddenCards.map(\.rawValue).sorted()
        )
    }

    @discardableResult
    mutating func setCard(_ card: HomeDashboardCard, isVisible: Bool) -> Bool {
        if isVisible {
            guard hiddenCards.remove(card) != nil || !orderedCards.contains(card) else { return false }
            if !orderedCards.contains(card) {
                orderedCards.append(card)
            }
            return true
        }

        guard orderedCards.contains(card) || !hiddenCards.contains(card) else { return false }
        hiddenCards.insert(card)
        orderedCards.removeAll { $0 == card }
        return true
    }

    @discardableResult
    mutating func moveCard(
        _ card: HomeDashboardCard,
        by offset: Int,
        within eligibleCards: [HomeDashboardCard]
    ) -> Bool {
        let eligibleSet = Set(eligibleCards)
        var eligibleOrder = orderedCards.filter { eligibleSet.contains($0) }
        guard let sourceIndex = eligibleOrder.firstIndex(of: card), !eligibleOrder.isEmpty else { return false }

        let destinationIndex = min(max(sourceIndex + offset, 0), eligibleOrder.count - 1)
        guard sourceIndex != destinationIndex else { return false }

        let movedCard = eligibleOrder.remove(at: sourceIndex)
        eligibleOrder.insert(movedCard, at: destinationIndex)
        var iterator = eligibleOrder.makeIterator()
        orderedCards = orderedCards.map { existingCard in
            eligibleSet.contains(existingCard) ? (iterator.next() ?? existingCard) : existingCard
        }
        return true
    }
}

struct DashboardWidgetPreferencesStore: Codable, Equatable, Sendable {
    var layoutsByWorkspace: [String: DashboardWidgetLayoutSnapshot] = [:]

    static func decode(_ value: String) -> DashboardWidgetPreferencesStore? {
        guard !value.isEmpty,
              let data = value.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(DashboardWidgetPreferencesStore.self, from: data)
    }

    static func decodeLegacyMap(_ value: String) -> [String: [String]] {
        guard let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return decoded
    }

    func encoded() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private struct HomeContinueWorkingItem: Identifiable {
    let brief: CreativeBrief
    let output: PlatformOutput

    var id: UUID { output.id }
}


enum HomeWeekAgendaPolicy {
    static func includes(
        targetDate: Date?,
        briefStatus: BriefStatus?,
        today: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard briefStatus != .archived, let targetDate else { return false }
        let startOfToday = calendar.startOfDay(for: today)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return false }
        let daysSinceMonday = (calendar.component(.weekday, from: startOfToday) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: startOfToday) ?? startOfToday
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: monday) ?? startOfToday
        let targetDay = calendar.startOfDay(for: targetDate)
        return targetDay >= tomorrow && targetDay < endOfWeek
    }
}

enum HomeNextWeekAgendaPolicy {
    static func includes(
        targetDate: Date?,
        briefStatus: BriefStatus?,
        today: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard briefStatus != .archived, let targetDate else { return false }
        let startOfToday = calendar.startOfDay(for: today)
        let daysSinceMonday = (calendar.component(.weekday, from: startOfToday) + 5) % 7
        let currentMonday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: startOfToday) ?? startOfToday
        guard let nextMonday = calendar.date(byAdding: .day, value: 7, to: currentMonday),
              let followingMonday = calendar.date(byAdding: .day, value: 14, to: currentMonday)
        else { return false }
        let targetDay = calendar.startOfDay(for: targetDate)
        return targetDay >= nextMonday && targetDay < followingMonday
    }
}

enum HomeTodayPostPolicy {
    static func includes(
        outputStatus: PlatformOutputStatus,
        targetDate: Date?,
        briefStatus: BriefStatus?,
        today: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard briefStatus != .archived,
              let targetDate,
              calendar.isDate(targetDate, inSameDayAs: today)
        else { return false }

        return outputStatus == .scheduled || outputStatus == .posted
    }
}

private struct HomeWeekItem: Identifiable {
    let output: PlatformOutput
    let brief: CreativeBrief

    var id: UUID { output.id }
    var date: Date { output.targetDate ?? .distantFuture }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
