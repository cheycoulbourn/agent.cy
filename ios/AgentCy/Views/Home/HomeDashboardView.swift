import SwiftData
import SwiftUI
import OSLog
import UIKit

private let dashboardWidgetLogger = Logger(
    subsystem: "com.agentcy.app",
    category: "DashboardWidgets"
)

struct HomeDashboardView: View {
    var body: some View {
        WorkspaceQueryScopeReader { scope in
            HomeDashboardContent(scope: scope)
        }
    }
}

private struct HomeDashboardContent: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
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
    @Query(sort: \AgentActivityRecord.availableAt, order: .reverse) private var allActivityRecords: [AgentActivityRecord]
    @State private var dashboardLayout = DashboardWidgetLayoutState()
    @State private var isArrangingDashboard = false
    @State private var dashboardNow = Date()
    @State private var arrangeFeedback = 0
    @State private var showsConsistencyGoalEditor = false
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

    init(scope: WorkspaceQueryScope) {
        _allBriefs = Query(filter: scope.briefs, sort: \CreativeBrief.updatedAt, order: .reverse)
        _allOutputs = Query(filter: scope.outputs, sort: \PlatformOutput.createdAt)
        _allTasks = Query(filter: scope.tasks, sort: \CreatorTask.createdAt)
        _allPillars = Query(filter: scope.pillars)
        _allFocusTemplates = Query(filter: scope.focusTemplates)
        _allFocusOverrides = Query(filter: scope.focusOverrides)
        _allBrandPartners = Query(filter: scope.brandPartners, sort: \BrandPartner.updatedAt, order: .reverse)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                header

                dashboardWidgets
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
            refreshDashboardClock()
            restoreDashboardCardOrder()
        }
        .onChange(of: appModel.activeWorkspaceID) { _, _ in
            finishArrangingDashboard()
            restoreDashboardCardOrder()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshDashboardClock()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.significantTimeChangeNotification
        )) { _ in
            refreshDashboardClock()
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
            appModel.presentedSheet = HomeDashboardPresentationPolicy.weeklyFocusSheet
        } label: {
            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                HStack(alignment: .firstTextBaseline) {
                    MetaLabel("Weekly focus")
                    Spacer(minLength: AgentSpacing.x3)
                    Text("Edit")
                        .font(.agentSubtext.weight(.semibold))
                }
                Text(weeklyFocusSummary)
                    .font(.agentBody.weight(.semibold))
                HStack {
                    Text("Today: \(todayFocusTitle)")
                        .font(.agentMetadata)
                        .foregroundStyle(Color.agentSecondary)
                    Spacer(minLength: AgentSpacing.x3)
                    AgentIconView(.forward, size: 12)
                }
            }
            .foregroundStyle(Color.agentText)
            .padding(AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
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
                .contentShape(.rect(cornerRadius: AgentRadius.control))
        }
        .buttonStyle(.plain)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.control)
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
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.28)
        .accessibilityLabel(offset < 0 ? "Move \(card.title) up" : "Move \(card.title) down")
    }

    private var dashboardCustomizationCards: [HomeDashboardCard] {
        dashboardLayout.orderedCards.filter { $0 != .cyNoticed && dashboardCardIsRenderable($0) }
    }

    private var dashboardCustomizationInstructions: String {
        "Move cards up or down, or remove anything you do not need today."
    }

    private var availableDashboardCards: [HomeDashboardCard] {
        HomeDashboardCard.allOrder.filter {
            $0 != .cyNoticed && dashboardCardIsRenderable($0) && !dashboardLayout.orderedCards.contains($0)
        }
    }

    private var renderableDashboardCards: [HomeDashboardCard] {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let marker = arguments.firstIndex(of: "-agentCyPreviewDashboardCard"),
           arguments.indices.contains(marker + 1),
           let previewCard = HomeDashboardCard(rawValue: arguments[marker + 1]),
           dashboardCardIsRenderable(previewCard) {
            return [previewCard]
        }
        #endif
        return dashboardLayout.orderedCards.filter { $0 != .cyNoticed && dashboardCardIsRenderable($0) }
    }

    @ViewBuilder
    private var dashboardWidgets: some View {
        LazyVStack(alignment: .leading, spacing: AgentSpacing.x6) {
#if !targetEnvironment(macCatalyst)
            if cyNoticedSummary.needsAttention {
                cyNoticedSection
            }
#endif
            ForEach(renderableDashboardCards) { card in
                reorderableDashboardCard(card)
            }
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
        case .pillarUsage:
            pillarUsageSection
        case .cyNoticed:
            cyNoticedSection
        case .weekAtAGlance:
            weekAtAGlanceSection
        case .consistency:
            consistencySection
        case .recentlyPosted:
            recentlyPostedSection
        case .draftsInProgress:
            draftsInProgressSection
        case .weeklyFocus:
            weeklyFocusEditorSection
        }
    }

    private var pillarUsageSection: some View {
        Button {
            appModel.selectedTab = .pillars
        } label: {
            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                HStack(alignment: .firstTextBaseline) {
                    MetaLabel("Pillar usage")
                    Spacer()
                    Text("This week")
                        .font(.agentSubtext.weight(.medium))
                        .foregroundStyle(Color.agentSecondary)
                }

                if pillarUsageItems.isEmpty {
                    Text("Plan a post this week to see your pillar mix.")
                        .font(.agentBody)
                        .foregroundStyle(Color.agentSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
                } else {
                    GeometryReader { proxy in
                        let trackWidth = max(0, proxy.size.width - AgentSpacing.x3)
                        let widths = WidgetPillarBarLayout.segmentWidths(
                            percentages: pillarUsageItems.map(\.percentage),
                            totalWidth: trackWidth
                        )

                        HStack(spacing: WidgetPillarBarLayout.segmentSpacing) {
                            ForEach(Array(pillarUsageItems.enumerated()), id: \.element.id) { index, item in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(agentHex: item.colorHex))
                                    .frame(width: widths.indices.contains(index) ? widths[index] : 0)
                            }
                        }
                        .frame(width: trackWidth, alignment: .leading)
                        .clipped()
                    }
                    .frame(height: 14)

                    if let anchorPillarUsageItem {
                        HStack(spacing: AgentSpacing.x2) {
                            PillarColorMark(
                                color: Color(agentHex: anchorPillarUsageItem.colorHex),
                                diameter: 7,
                                lineWidth: 1
                            )
                            Text(anchorPillarUsageItem.name)
                                .font(.agentMetadata)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Spacer(minLength: AgentSpacing.x2)
                            Text("\(anchorPillarUsageItem.percentage)%")
                                .font(.agentMetadata.monospacedDigit())
                        }
                    }

                    if !supportingPillarUsageItems.isEmpty {
                        HStack(spacing: AgentSpacing.x3) {
                            ForEach(supportingPillarUsageItems) { item in
                                HStack(spacing: AgentSpacing.x1) {
                                    PillarColorMark(
                                        color: Color(agentHex: item.colorHex),
                                        diameter: 7,
                                        lineWidth: 1
                                    )
                                    Text("\(item.percentage)%")
                                        .font(.agentMetadata.monospacedDigit())
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Text("View all")
                            .font(.agentMetadata)
                            .foregroundStyle(Color.agentSecondary)
                        AgentIconView(.arrowRight, size: 12)
                    }
                }
            }
            .foregroundStyle(Color.agentText)
            .padding(AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .leading)
            .contentShape(.rect(cornerRadius: AgentRadius.dashboard))
        }
        .buttonStyle(.plain)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
    }

    private var anchorPillarUsageItem: HomePillarUsageItem? {
        pillarUsageItems.first
    }

    private var supportingPillarUsageItems: [HomePillarUsageItem] {
        Array(pillarUsageItems.dropFirst())
    }

    private var cyNoticedSection: some View {
        Button {
            appModel.routeToLateWorkList()
        } label: {
            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                HStack(spacing: AgentSpacing.x2) {
                    AgentCyLogoMark()
                    Text("CY NOTICED")
                        .font(.agentMetadata)
                        .tracking(1.4)
                        .foregroundStyle(Color.cyAccent)
                }
                Text(cyNoticedSummary.message)
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
        .buttonStyle(.plain)
        .accessibilityHint("Opens the agenda list filtered to late work")
    }

    private var weekAtAGlanceSection: some View {
        Button {
            appModel.requestedPlanMode = .week
            appModel.selectedTab = .today
        } label: {
            VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                HStack(alignment: .firstTextBaseline) {
                    MetaLabel("Week at a glance")
                    Spacer()
                    Text("\(weekAtAGlanceDays.reduce(0) { $0 + $1.postCount }) posts")
                        .font(.agentSubtext.weight(.medium))
                        .foregroundStyle(Color.agentSecondary)
                }

                HStack(spacing: AgentSpacing.x2) {
                    ForEach(weekAtAGlanceDays) { day in
                        VStack(spacing: AgentSpacing.x2) {
                            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                                .font(.agentMetadata.weight(Calendar.current.isDateInToday(day.date) ? .bold : .medium))
                            PillarColorMark(
                                color: day.color,
                                diameter: 8,
                                lineWidth: day.postCount == 0 ? 1 : 0
                            )
                            .opacity(day.postCount == 0 ? 0.28 : 1)
                            .overlay {
                                if Calendar.current.isDateInToday(day.date) {
                                    Circle()
                                        .stroke(Color.agentText.opacity(0.18), lineWidth: 2)
                                        .padding(-4)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                HStack {
                    Text("Open agenda")
                        .font(.agentSubtext.weight(.semibold))
                    Spacer()
                    AgentIconView(.arrowRight, size: 12)
                }
            }
            .foregroundStyle(Color.agentText)
            .padding(AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 154, alignment: .leading)
            .contentShape(.rect(cornerRadius: AgentRadius.dashboard))
        }
        .buttonStyle(.plain)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
    }

    private var consistencySection: some View {
        let goal = goalConsistency
        return ConsistencyGoalCard(
            snapshot: goal.snapshot,
            weeklyGoalMet: goal.weeklyGoalMet,
            streak: goal.streak,
            onEditGoal: { showsConsistencyGoalEditor = true }
        )
        .padding(AgentSpacing.x4)
        .frame(maxWidth: .infinity, minHeight: 146, alignment: .leading)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
        .contentShape(.rect(cornerRadius: AgentRadius.dashboard))
        .onTapGesture {
            if goal.snapshot.goalState != .unset {
                showsConsistencyGoalEditor = true
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the weekly posting goal")
        .sheet(isPresented: $showsConsistencyGoalEditor) {
            ConsistencyGoalEditorView(
                currentGoal: activeWorkspace?.weeklyPostingGoal,
                onSave: { saveWeeklyPostingGoal($0) },
                onRemove: { saveWeeklyPostingGoal(nil) },
                onClose: { showsConsistencyGoalEditor = false }
            )
            .presentationDetents([.height(320)])
            .presentationBackground(Color.agentCanvas)
            .agentSheetDragIndicator()
        }
    }

    private var activeWorkspace: CreatorWorkspace? {
        workspaces.first { $0.id == activeWorkspaceID }
    }

    private var goalConsistency: (snapshot: WeeklyConsistencySnapshot, weeklyGoalMet: [Bool], streak: Int) {
        let calendar = Calendar.current
        let range = currentWeekRange
        let index = briefByID
        let postedDates = outputs.compactMap { output -> Date? in
            guard index[output.briefID]?.status != .archived,
                  output.status == .posted || index[output.briefID]?.status == .posted else { return nil }
            return output.postedAt ?? output.targetDate
        }
        let goal = activeWorkspace?.weeklyPostingGoal
        let snapshot = WeeklyConsistencyPolicy.snapshot(
            postedDates: postedDates,
            goal: goal,
            weekStart: range.start,
            calendar: calendar,
            today: today
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
        guard let workspace = activeWorkspace else { return }
        workspace.weeklyPostingGoal = goal.map(WeeklyConsistencyPolicy.clampedGoal)
        workspace.updatedAt = Date()
        try? context.save()
        showsConsistencyGoalEditor = false
    }

    private var recentlyPostedSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel("Recently posted")
                Spacer()
                Text("\(recentlyPostedItems.count)")
                    .font(.agentSubtext.weight(.medium))
                    .foregroundStyle(Color.agentSecondary)
            }

            if recentlyPostedItems.isEmpty {
                Text("Posted work will collect here.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .frame(minHeight: 54, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentlyPostedItems.prefix(2).enumerated()), id: \.element.id) { index, item in
                        NavigationLink {
                            PostOutputDetailView(brief: item.brief, output: item.output)
                        } label: {
                            HStack(spacing: AgentSpacing.x3) {
                                RoundedRectangle(cornerRadius: AgentRadius.control)
                                    .fill(pillarAccent(for: item.brief).opacity(0.16))
                                    .frame(width: 44, height: 44)
                                    .overlay(PillarColorMark(color: pillarAccent(for: item.brief), diameter: 8))
                                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                    Text(outputTitle(item.output, brief: item.brief))
                                        .font(.agentSubtext.weight(.semibold))
                                        .lineLimit(1)
                                    Text((item.output.postedAt ?? item.output.targetDate)?.formatted(.dateTime.month(.abbreviated).day()) ?? "Posted")
                                        .font(.agentMetadata)
                                        .foregroundStyle(Color.agentSecondary)
                                }
                                Spacer()
                                AgentIconView(.forward, size: 12)
                            }
                            .foregroundStyle(Color.agentText)
                            .frame(minHeight: 54)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) {
                            if index == 0 && recentlyPostedItems.count > 1 {
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

    private var draftsInProgressSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel("Drafts in progress")
                Spacer()
                Text("\(continueWorkingItems.count)")
                    .font(.agentSubtext.weight(.medium))
                    .foregroundStyle(Color.agentSecondary)
            }

            if continueWorkingItems.isEmpty {
                Text("No drafts are waiting on you.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .frame(minHeight: 54, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(continueWorkingItems.prefix(2).enumerated()), id: \.element.id) { index, item in
                        NavigationLink {
                            ResumablePostEditorView(brief: item.brief, output: item.output, onSpark: {})
                        } label: {
                            HStack(spacing: AgentSpacing.x3) {
                                PillarColorMark(color: pillarAccent(for: item.brief), diameter: 8)
                                Text(outputTitle(item.output, brief: item.brief))
                                    .font(.agentSubtext.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(draftAgeDays(item.output))d")
                                    .font(.agentMetadata)
                                    .foregroundStyle(Color.agentSecondary)
                            }
                            .foregroundStyle(Color.agentText)
                            .frame(minHeight: 48)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) {
                            if index == 0 && continueWorkingItems.count > 1 {
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
            ) {
                HomeActivityBellButton(unreadCount: unreadActivityCount) {
                    appModel.presentedSheet = HomeDashboardPresentationPolicy.activityCenterSheet
                }
            }

            #if !targetEnvironment(macCatalyst)
            Button {
                appModel.selectedTab = .cy
            } label: {
                CyAsterisk(size: 31, strokeWidth: 2.5)
                    .accessibilityHidden(true)
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
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today’s tasks")
                    .font(.agentTitle)
                Spacer()
                viewAllTasksButton
            }

            Rectangle()
                .fill(Color.agentHairline)
                .frame(height: 1)

            // One today-tasks derivation per render: the my/post splits share
            // a single computed list instead of re-deriving it four times.
            let today = todayTasks
            if today.isEmpty {
                Text("Nothing is planned.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                .padding(.vertical, AgentSpacing.x2)
            } else {
                let myTasks = today.filter { $0.briefID == nil }
                let postTasks = today.filter { $0.briefID != nil }
                VStack(alignment: .leading, spacing: AgentSpacing.x5) {
                    homeTaskGroup(
                        title: "Focus tasks",
                        tasks: myTasks,
                        totalCount: myTasks.count,
                        showsHeader: true
                    )
                    homeTaskGroup(
                        title: "Post tasks",
                        tasks: postTasks,
                        totalCount: postTasks.count,
                        showsHeader: true
                    )
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
            isLate: FinalizedPostPresentation.isMissed(
                outputStatus: output.status,
                targetDate: output.targetDate
            ) || PostWorkDateStatusPolicy.isLate(
                workDate: brief.workDate,
                briefStatus: brief.status,
                outputStatus: output.status
            ),
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
                    .padding(.bottom, AgentSpacing.x2)
                }

                ForEach(tasks) { task in
                    TaskRow(
                        task: task,
                        allTasks: self.tasks,
                        linkedPostTitle: linkedPostTitle(for: task),
                        verticalInset: AgentSpacing.x2
                    )
                }
            }
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
                            isLate: FinalizedPostPresentation.isMissed(
                                outputStatus: item.output.status,
                                targetDate: item.output.targetDate
                            ) || PostWorkDateStatusPolicy.isLate(
                                workDate: item.brief.workDate,
                                briefStatus: item.brief.status,
                                outputStatus: item.output.status
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

    private var pillarUsageItems: [HomePillarUsageItem] {
        let activePillars = pillars.filter { !$0.isArchived }
        let pillarByID = DuplicateSafeIndex.firstValues(activePillars.map { ($0.id, $0) })
        let summary = PillarUsageSchedulePolicy.summary(
            pillars: activePillars,
            briefs: briefs,
            outputs: outputs,
            interval: PillarUsageSchedulePolicy.weekInterval(containing: today)
        )
        return summary.compactMap { item in
            guard let pillar = pillarByID[item.pillarID] else { return nil }
            return HomePillarUsageItem(
                id: pillar.id,
                name: pillar.name,
                colorHex: pillar.resolvedColorHex(in: activePillars),
                percentage: item.percentage
            )
        }
    }

    private var weekAtAGlanceDays: [HomeWeekAtAGlanceDay] {
        let range = currentWeekRange
        let index = briefByID
        let weekOutputs = outputs
        return (0..<7).compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: range.start) else { return nil }
            let dayOutputs = weekOutputs.filter { output in
                output.targetDate.map { Calendar.current.isDate($0, inSameDayAs: date) } == true &&
                    index[output.briefID]?.status != .archived
            }
            let color = dayOutputs.first
                .flatMap { index[$0.briefID] }
                .map(pillarAccent(for:)) ?? Color.agentSurface
            return HomeWeekAtAGlanceDay(date: date, postCount: dayOutputs.count, color: color)
        }
    }

    private var recentlyPostedItems: [HomeContinueWorkingItem] {
        let index = briefByID
        return outputs.compactMap { output -> HomeContinueWorkingItem? in
            guard let brief = index[output.briefID],
                  HomeRecentlyPostedPolicy.includes(
                    briefStatus: brief.status,
                    outputStatus: output.status
                  ) else { return nil }
            return HomeContinueWorkingItem(brief: brief, output: output)
        }
        .sorted {
            ($0.output.postedAt ?? $0.output.targetDate ?? $0.output.createdAt) >
                ($1.output.postedAt ?? $1.output.targetDate ?? $1.output.createdAt)
        }
    }

    private var cyNoticedSummary: CyNoticedReconciliationSummary {
        CyNoticedReconciliationPolicy.summary(briefs: briefs, outputs: outputs)
    }

    private var currentWeekRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let offset = (calendar.component(.weekday, from: today) + 5) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
        return (start, calendar.date(byAdding: .day, value: 7, to: start) ?? start)
    }

    private func draftAgeDays(_ output: PlatformOutput) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: output.createdAt, to: Date()).day ?? 0)
    }

    private func refreshDashboardClock() {
        dashboardNow = Date()
    }

    private var today: Date {
        HomeDashboardClockPolicy.day(for: dashboardNow, calendar: .current)
    }

    private var greeting: String {
        HomeDashboardClockPolicy.greeting(for: dashboardNow, calendar: .current)
    }

    private var activeIdentity: ActiveCreatorIdentity {
        ActiveCreatorIdentity.resolve(
            profile: profiles.first,
            workspaces: workspaces,
            preferredWorkspaceID: appModel.activeWorkspaceID
        )
    }

    private var activeWorkspaceID: UUID? {
        WorkspaceScope.activeWorkspaceID(
            preferredID: appModel.activeWorkspaceID,
            workspaces: workspaces
        )
    }

    private var unreadActivityCount: Int {
        let now = Date()
        // The badge counts what the Activity sheet can actually show — every
        // account's records — so a count never points at nothing.
        return allActivityRecords.filter { record in
            NotificationActivityScopePolicy.includes(
                recordWorkspaceID: record.workspaceID,
                activeWorkspaceID: activeWorkspaceID,
                workspaces: workspaces
            ) && AgentActivityPresentationPolicy.isVisible(
                availableAt: record.availableAt,
                archivedAt: record.archivedAt,
                clearedAt: record.clearedAt,
                now: now
            ) && record.readAt == nil
        }.count
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
            HomeTodayTaskPolicy.includes(
                isCompleted: task.isCompleted,
                isSkipped: task.isSkipped,
                isTopLevel: task.parentTaskID == nil,
                targetDate: task.targetDate,
                dailyFocusDate: task.dailyFocusDate,
                isLinkedToArchivedBrief: task.briefID.map(archivedBriefIDs.contains) == true,
                referenceDate: dashboardNow,
                calendar: .current
            )
        }
        .sorted {
            let lhsDate = $0.targetDate ?? $0.dailyFocusDate ?? .distantFuture
            let rhsDate = $1.targetDate ?? $1.dailyFocusDate ?? .distantFuture
            if lhsDate == rhsDate { return $0.createdAt < $1.createdAt }
            return lhsDate < rhsDate
        }
    }

    private var archivedBriefIDs: Set<UUID> {
        Set(briefs.lazy.filter { $0.status == .archived }.map(\.id))
    }

    private var scheduledTodayOutputs: [PlatformOutput] {
        let index = briefByID
        return outputs.filter { output in
            HomeTodayPostPolicy.includes(
                outputStatus: output.status,
                targetDate: output.targetDate,
                briefStatus: index[output.briefID]?.status,
                today: today,
                calendar: .current
            )
        }
        .sorted { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
    }

    private var pastDueOutputs: [PlatformOutput] {
        let index = briefByID
        return outputs.filter { output in
            guard let brief = index[output.briefID], brief.status != .archived else { return false }
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
        let index = briefByID
        let candidates = outputs.compactMap { output -> HomeContinueWorkingItem? in
            guard let brief = index[output.briefID],
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
        let index = briefByID
        let postItems: [HomeWeekItem] = outputs.compactMap { output in
            guard let brief = index[output.briefID],
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
        let index = briefByID
        let postItems: [HomeWeekItem] = outputs.compactMap { output in
            guard let brief = index[output.briefID],
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
        HomeWorkspaceScopePolicy.scoped(
            values,
            preferredWorkspaceID: appModel.activeWorkspaceID,
            workspaces: workspaces
        )
    }

    private var briefByID: [UUID: CreativeBrief] {
        DuplicateSafeIndex.firstValues(briefs.map { ($0.id, $0) })
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

    private func linkedPostTitle(for task: CreatorTask) -> String? {
        task.briefID.flatMap { id in
            briefs.first { $0.id == id }?.title.nilIfBlank
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

private struct HomePillarUsageItem: Identifiable {
    let id: UUID
    let name: String
    let colorHex: String
    let percentage: Int
}

private struct HomeWeekAtAGlanceDay: Identifiable {
    let date: Date
    let postCount: Int
    let color: Color

    var id: Date { date }
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
    case pillarUsage
    case cyNoticed
    case weekAtAGlance
    case consistency
    case recentlyPosted
    case draftsInProgress
    case weeklyFocus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scheduledToday: "Up next"
        case .continueWorking: "Continue working on…"
        case .tasks: "Today’s tasks"
        case .weekAhead: "This week"
        case .nextWeek: "Next week"
        case .pastDuePosts: "Needs a new date"
        case .recentIdeas: "Recent ideas"
        case .brandCabinet: "Brand cabinet"
        case .pillarUsage: "Pillar usage"
        case .cyNoticed: "Cy noticed"
        case .weekAtAGlance: "Week at a glance"
        case .consistency: "Consistency"
        case .recentlyPosted: "Recently posted"
        case .draftsInProgress: "Drafts in progress"
        case .weeklyFocus: "Weekly focus"
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

    static let optionalOrder: [HomeDashboardCard] = [
        .pillarUsage,
        .weekAtAGlance,
        .consistency,
        .recentlyPosted,
        .draftsInProgress,
        .weeklyFocus,
    ]

    static let systemManagedOrder: [HomeDashboardCard] = [.cyNoticed]
    static let allOrder = defaultOrder + optionalOrder + systemManagedOrder
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
        let savedHidden = Set(savedHiddenRawValues.compactMap(HomeDashboardCard.init(rawValue:)))
        let savedCards = savedOrderRawValues.compactMap(HomeDashboardCard.init(rawValue:))
        let systemManaged = Set(HomeDashboardCard.systemManagedOrder)
        let uniqueSavedCards = savedCards.reduce(into: [HomeDashboardCard]()) { result, card in
            guard !systemManaged.contains(card), !savedHidden.contains(card), !result.contains(card) else { return }
            result.append(card)
        }
        let knownCards = Set(uniqueSavedCards).union(savedHidden)
        let newCards = HomeDashboardCard.defaultOrder.filter { !knownCards.contains($0) }
        let newOptionalCards = HomeDashboardCard.optionalOrder.filter { !knownCards.contains($0) }

        orderedCards = uniqueSavedCards + newCards
        hiddenCards = savedHidden.union(newOptionalCards).union(systemManaged)
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
        guard card != .cyNoticed else { return false }
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

enum HomeWorkspaceScopePolicy {
    /// One-pass scope filter for Home's whole-table queries: resolves the
    /// active workspace once, with results identical to per-record
    /// `WorkspaceScope.includes` (which re-resolves — and re-sorts the
    /// workspace list — for every record).
    static func scoped<T: WorkspaceScopedRecord>(
        _ values: [T],
        preferredWorkspaceID: UUID?,
        workspaces: [CreatorWorkspace]
    ) -> [T] {
        guard let activeID = WorkspaceScope.activeWorkspaceID(
            preferredID: preferredWorkspaceID,
            workspaces: workspaces
        ) else {
            return values.filter { $0.workspaceID == nil }
        }
        let defaultMatchesActive = WorkspaceScope.defaultWorkspace(in: workspaces)?.id == activeID
        return values.filter { record in
            if let recordID = record.workspaceID { return recordID == activeID }
            return defaultMatchesActive
        }
    }
}

enum HomeTodayTaskPolicy {
    static func includes(
        isCompleted: Bool,
        isSkipped: Bool,
        isTopLevel: Bool,
        targetDate: Date?,
        dailyFocusDate: Date?,
        isLinkedToArchivedBrief: Bool,
        referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        guard !isCompleted,
              !isSkipped,
              isTopLevel,
              !isLinkedToArchivedBrief else { return false }
        return [targetDate, dailyFocusDate]
            .compactMap { $0 }
            .contains { calendar.isDate($0, inSameDayAs: referenceDate) }
    }
}

enum HomeRecentlyPostedPolicy {
    static func includes(
        briefStatus: BriefStatus,
        outputStatus: PlatformOutputStatus
    ) -> Bool {
        briefStatus != .archived &&
            (briefStatus == .posted || outputStatus == .posted)
    }
}

enum HomeDashboardClockPolicy {
    static func day(for date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    static func greeting(for date: Date, calendar: Calendar) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }
}

enum HomeDashboardPresentationPolicy {
    static let weeklyFocusSheet: AppSheet = .weeklyFocus
    static let activityCenterSheet: AppSheet = .activityCenter
}

private struct HomeWeekItem: Identifiable {
    let output: PlatformOutput
    let brief: CreativeBrief

    var id: UUID { output.id }
    var date: Date { output.targetDate ?? .distantFuture }
}

enum HomeActivityBadgePolicy {
    static let maximumDynamicTypeSize: DynamicTypeSize = .large

    static func displayText(unreadCount: Int) -> String {
        unreadCount > 9 ? "9+" : "\(unreadCount)"
    }
}

private struct HomeActivityBellButton: View {
    let unreadCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                AgentToolbarIconLabel(icon: .bell)

                if unreadCount > 0 {
                    Text(HomeActivityBadgePolicy.displayText(unreadCount: unreadCount))
                        .font(.agentInter(size: 10, weight: .bold, relativeTo: .caption2).monospacedDigit())
                        .dynamicTypeSize(.xSmall ... HomeActivityBadgePolicy.maximumDynamicTypeSize)
                        .foregroundStyle(Color.onCyAccent)
                        .padding(.horizontal, unreadCount > 9 ? 4 : 3)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Color.cyAccent, in: .capsule)  // design-review-allow: accent-mark -- unread count badge
                        .overlay {
                            Capsule().stroke(Color.agentCanvas, lineWidth: 2)
                        }
                        .offset(x: 2, y: -2)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(AgentPressButtonStyle())
        .accessibilityLabel(unreadCount == 0 ? "Activity" : "Activity, \(unreadCount) unread")
        .accessibilityHint("Opens reminders and updates that need your attention")
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
