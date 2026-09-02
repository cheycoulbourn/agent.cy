import SwiftData
import SwiftUI
import UIKit

enum PlanMode: Sendable {
    case week
}

enum PlanNavigationRoute: Hashable, CaseIterable {
    case socialGrid
    case dailyFocusDetail
}

enum PlanRuntimeFixture {
    static func requestsDailyFocusDetail(arguments: [String]) -> Bool {
        arguments.contains("-agentCyPreviewDailyFocusDetail")
    }

    static func requestsDailyFocusEditor(arguments: [String]) -> Bool {
        #if DEBUG
        arguments.contains("-agentCyPreviewDailyFocusEditor")
        #else
        false
        #endif
    }

    static func requestsEpisodeSlotActions(arguments: [String]) -> Bool {
        #if DEBUG
        arguments.contains("-agentCyPreviewEpisodeSlotActions")
        #else
        false
        #endif
    }

    static func requestsAddLivePost(arguments: [String]) -> Bool {
        #if DEBUG
        arguments.contains("-agentCyPreviewAddLivePost")
        #else
        false
        #endif
    }

    static func requestsPostSearch(arguments: [String]) -> Bool {
        arguments.contains("-agentCyPreviewPostSearch")
    }

    static func postSearchQuery(arguments: [String]) -> String? {
        guard let marker = arguments.firstIndex(of: "-agentCyPreviewPostSearchQuery"),
              arguments.indices.contains(marker + 1) else {
            return nil
        }
        return arguments[marker + 1]
    }
}

extension View {
    func planNavigationDestinations(bottomClearance: CGFloat) -> some View {
        navigationDestination(for: PlanNavigationRoute.self) { route in
            switch route {
            case .socialGrid:
                SocialGridView(presentation: .phone(bottomClearance: bottomClearance))
            case .dailyFocusDetail:
                DailyFocusDetailView(date: Calendar.current.startOfDay(for: Date()))
            }
        }
    }
}

struct PlanView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [CreatorProfile]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var weekOffset = 0
    @State private var isSearchingPosts = false
    @State private var planNow = Date()
    let showsFeedShortcut: Bool

    init(showsFeedShortcut: Bool = false) {
        self.showsFeedShortcut = showsFeedShortcut
        #if DEBUG
        _isSearchingPosts = State(initialValue: PlanRuntimeFixture.requestsPostSearch(
            arguments: ProcessInfo.processInfo.arguments
        ))
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            AgendaView(
                weekOffset: $weekOffset,
                selectedDay: $selectedDay,
                referenceDate: planNow
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.agentCanvas.ignoresSafeArea())
        .onAppear(perform: refreshPlanClock)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshPlanClock()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.significantTimeChangeNotification
        )) { _ in
            refreshPlanClock()
        }
        .onChange(of: appModel.requestedPlanMode, initial: true) { _, requestedMode in
            guard let requestedMode else { return }
            if requestedMode == .week, appModel.widgetAgendaDay == nil {
                moveToRequestedWeek(appModel.requestedPlanWeekOffset ?? 0)
            }
            appModel.requestedPlanWeekOffset = nil
            appModel.requestedPlanMode = nil
        }
        .sheet(isPresented: $isSearchingPosts) {
            AgendaPostSearchView()
                .presentationDetents([.large])
                .agentSheetDragIndicator()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            HStack(alignment: .center, spacing: AgentSpacing.x1) {
                MetaLabel("Weekly agenda")
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: AgentSpacing.x1) {
                    Button {
                        isSearchingPosts = true
                    } label: {
                        AgentToolbarIconLabel(icon: .search)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search posts")

                    if showsFeedShortcut {
                        NavigationLink(value: PlanNavigationRoute.socialGrid) {
                            AgentToolbarIconLabel(icon: .instagramCamera)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open social grid")
                        .accessibilityHint("Shows planned and live Instagram posts together")
                    }
                }
                .frame(height: 44)

                ProfileSettingsButton(
                    identity: activeIdentity,
                    action: { appModel.presentedSheet = .settings }
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Button {
                        returnToCurrentWeek()
                    } label: {
                        Text("Today")
                            .font(.agentDisplayLead)
                            .foregroundStyle(Color.cyAccent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Return to this week")
                    .accessibilityHint("Shows the week containing today")

                    Text(" is")
                        .font(.agentDisplayLead)
                        .foregroundStyle(Color.agentText)
                }

                Text(todayTitleDate)
                    .font(.agentDisplay)
                    .foregroundStyle(Color.agentText)
            }
            .tracking(-0.64)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentLayout.pageTopPadding)
        .padding(.bottom, AgentLayout.pageHeaderToContentSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activeIdentity: ActiveCreatorIdentity {
        ActiveCreatorIdentity.resolve(
            profile: profiles.first,
            workspaces: workspaces,
            preferredWorkspaceID: appModel.activeWorkspaceID
        )
    }

    private var todayTitleDate: String {
        planNow.formatted(.dateTime.month(.wide).day().year())
    }

    private func returnToCurrentWeek() {
        moveToRequestedWeek(0)
    }

    private func moveToRequestedWeek(_ offset: Int) {
        let update = {
            let today = Calendar.current.startOfDay(for: planNow)
            selectedDay = Calendar.current.date(
                byAdding: .weekOfYear,
                value: offset,
                to: today
            ) ?? today
            weekOffset = offset
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(.snappy(duration: 0.28), update)
        }
    }

    private func refreshPlanClock() {
        let refreshedNow = Date()
        selectedDay = PlanClockPolicy.rebasedSelection(
            selectedDay,
            oldReferenceDate: planNow,
            newReferenceDate: refreshedNow,
            weekOffset: weekOffset,
            calendar: .current
        )
        planNow = refreshedNow
    }

}

enum PlanClockPolicy {
    static func weekStart(
        referenceDate: Date,
        offset: Int,
        calendar: Calendar
    ) -> Date {
        let day = calendar.startOfDay(for: referenceDate)
        let daysSinceMonday = (calendar.component(.weekday, from: day) + 5) % 7
        let currentWeekStart = calendar.date(
            byAdding: .day,
            value: -daysSinceMonday,
            to: day
        ) ?? day
        return calendar.date(
            byAdding: .weekOfYear,
            value: offset,
            to: currentWeekStart
        ) ?? currentWeekStart
    }

    static func weekOffset(
        containing day: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> Int {
        let currentWeekStart = weekStart(
            referenceDate: referenceDate,
            offset: 0,
            calendar: calendar
        )
        let targetWeekStart = weekStart(
            referenceDate: day,
            offset: 0,
            calendar: calendar
        )
        let dayDistance = calendar.dateComponents(
            [.day],
            from: currentWeekStart,
            to: targetWeekStart
        ).day ?? 0
        return dayDistance / 7
    }

    static func rebasedSelection(
        _ selectedDay: Date,
        oldReferenceDate: Date,
        newReferenceDate: Date,
        weekOffset: Int,
        calendar: Calendar
    ) -> Date {
        let oldWeekStart = weekStart(
            referenceDate: oldReferenceDate,
            offset: weekOffset,
            calendar: calendar
        )
        let newWeekStart = weekStart(
            referenceDate: newReferenceDate,
            offset: weekOffset,
            calendar: calendar
        )
        guard !calendar.isDate(oldWeekStart, inSameDayAs: newWeekStart) else {
            return selectedDay
        }
        let selectedIndex = calendar.dateComponents(
            [.day],
            from: oldWeekStart,
            to: calendar.startOfDay(for: selectedDay)
        ).day ?? 0
        let boundedIndex = min(max(selectedIndex, 0), 6)
        return calendar.date(
            byAdding: .day,
            value: boundedIndex,
            to: newWeekStart
        ) ?? newWeekStart
    }

    static func greeting(referenceDate: Date, calendar: Calendar) -> String {
        switch calendar.component(.hour, from: referenceDate) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}

struct AgendaPostSearchResult: Identifiable {
    let output: PlatformOutput
    let brief: CreativeBrief
    let pillar: Pillar?
    let metadata: String

    var id: UUID { output.id }
}

struct AgendaPostSearchProjection {
    let results: [AgendaPostSearchResult]

    static func make(
        briefs: [CreativeBrief],
        outputs: [PlatformOutput],
        pillars: [Pillar],
        destinations: [PublishingDestination],
        formats: [PublishingFormat],
        preferredWorkspaceID: UUID?,
        workspaces: [CreatorWorkspace],
        query: String
    ) -> AgendaPostSearchProjection {
        let resolvedWorkspaceID = WorkspaceScope.activeWorkspaceID(
            preferredID: preferredWorkspaceID,
            workspaces: workspaces
        )
        let defaultWorkspaceID = WorkspaceScope.defaultWorkspace(in: workspaces)?.id
        let includesWorkspace: (UUID?) -> Bool = { recordWorkspaceID in
            guard let resolvedWorkspaceID else { return recordWorkspaceID == nil }
            if let recordWorkspaceID { return recordWorkspaceID == resolvedWorkspaceID }
            return defaultWorkspaceID == resolvedWorkspaceID
        }

        let activeBriefs = briefs.filter {
            $0.status != .archived && includesWorkspace($0.workspaceID)
        }
        let briefByID = DuplicateSafeIndex.firstValues(activeBriefs.map { ($0.id, $0) })
        let activePillars = pillars.filter {
            !$0.isArchived && includesWorkspace($0.workspaceID)
        }
        let pillarByID = DuplicateSafeIndex.firstValues(activePillars.map { ($0.id, $0) })
        let destinationByID = DuplicateSafeIndex.firstValues(destinations.map { ($0.id, $0) })
        let formatByID = DuplicateSafeIndex.firstValues(formats.map { ($0.id, $0) })
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let results = outputs.compactMap { output -> AgendaPostSearchResult? in
            guard includesWorkspace(output.workspaceID),
                  let brief = briefByID[output.briefID] else {
                return nil
            }
            let pillar = brief.pillarID.flatMap { pillarByID[$0] }
            let destination = output.destinationID.flatMap { destinationByID[$0] }
            let format = output.formatID.flatMap { formatByID[$0] }
            let metadata = destination?.name ?? format?.name ?? output.platform.title
            let searchText = [
                output.titleOverride,
                brief.title,
                brief.notes,
                brief.spokenHook,
                brief.scriptBeatsText,
                brief.ctaIntent,
                output.caption,
                output.cta,
                output.platform.title,
                destination?.name ?? "",
                format?.name ?? "",
                pillar?.name ?? ""
            ].joined(separator: " ")
            guard cleanQuery.isEmpty || searchText.localizedStandardContains(cleanQuery) else {
                return nil
            }
            return AgendaPostSearchResult(
                output: output,
                brief: brief,
                pillar: pillar,
                metadata: metadata
            )
        }
        .sorted { lhs, rhs in
            let leftDate = lhs.output.targetDate ?? lhs.brief.updatedAt
            let rightDate = rhs.output.targetDate ?? rhs.brief.updatedAt
            if leftDate != rightDate { return leftDate > rightDate }
            if lhs.output.createdAt != rhs.output.createdAt {
                return lhs.output.createdAt > rhs.output.createdAt
            }
            return lhs.output.id.uuidString < rhs.output.id.uuidString
        }

        return AgendaPostSearchProjection(results: results)
    }
}

private struct AgendaPostSearchView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt, order: .reverse) private var allOutputs: [PlatformOutput]
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Query(sort: \PublishingFormat.sortOrder) private var formats: [PublishingFormat]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var query = ""

    init() {
        #if DEBUG
        _query = State(initialValue: PlanRuntimeFixture.postSearchQuery(
            arguments: ProcessInfo.processInfo.arguments
        ) ?? "")
        #endif
    }

    var body: some View {
        let results = AgendaPostSearchProjection.make(
            briefs: allBriefs,
            outputs: allOutputs,
            pillars: allPillars,
            destinations: destinations,
            formats: formats,
            preferredWorkspaceID: appModel.activeWorkspaceID,
            workspaces: workspaces,
            query: query
        ).results

        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    searchField

                    SectionRuleHeader(
                        title: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "All posts"
                            : "Results",
                        trailing: "\(results.count)"
                    )

                    if results.isEmpty {
                        AgentEmptyState(
                            title: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "No posts yet"
                                : "No posts found",
                            message: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "Posts you create will appear here."
                                : "Try another title, pillar, platform, or phrase.",
                            icon: .search
                        )
                        .frame(minHeight: 300)
                    } else {
                        ForEach(results) { result in
                            resultCard(result)
                        }
                    }
                }
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x4)
                .padding(.bottom, AgentSpacing.x12)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Search posts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AgentToolbarIconButton(title: "Close", icon: .close) { dismiss() }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .agentScreen()
        }
    }

    private var searchField: some View {
        HStack(spacing: AgentSpacing.x3) {
            AgentIconView(.search, size: 15)
                .foregroundStyle(Color.agentSecondary)
            TextField("Search posts", text: $query)
                .font(.agentBody)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    AgentIconView(.close)
                        .foregroundStyle(Color.agentSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AgentSpacing.x4)
        .frame(minHeight: 48)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.control)
                .stroke(Color.agentBorder, lineWidth: 0.75)
        }
    }

    private func resultCard(_ result: AgendaPostSearchResult) -> some View {
        let output = result.output
        let brief = result.brief
        let missed = FinalizedPostPresentation.isMissed(
            outputStatus: output.status,
            targetDate: output.targetDate
        )
        return AgentPostCard(
            title: postTitle(output: output, brief: brief),
            pillar: result.pillar?.name ?? "Unfiled",
            accent: result.pillar.map { Color(agentHex: $0.colorHex) } ?? .agentSecondary,
            status: output.status,
            metadata: result.metadata,
            timeText: output.targetDate?.formatted(.dateTime.month(.abbreviated).day().hour().minute()),
            isLate: missed || PostWorkDateStatusPolicy.isLate(
                workDate: brief.workDate,
                briefStatus: brief.status,
                outputStatus: output.status
            ),
            destination: AnyView(PostOutputDetailView(brief: brief, output: output))
        )
    }

    private func postTitle(output: PlatformOutput, brief: CreativeBrief) -> String {
        let override = output.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? brief.title : override
    }

}

struct PlanHeader<Actions: View>: View {
    let breadcrumb: String
    let identity: ActiveCreatorIdentity
    let firstLine: String
    let secondLine: String
    let openSettings: () -> Void
    let showsBreadcrumb: Bool
    @ViewBuilder let actions: Actions

    init(
        breadcrumb: String,
        identity: ActiveCreatorIdentity,
        firstLine: String,
        secondLine: String,
        openSettings: @escaping () -> Void,
        showsBreadcrumb: Bool = false,
        @ViewBuilder actions: () -> Actions
    ) {
        self.breadcrumb = breadcrumb
        self.identity = identity
        self.firstLine = firstLine
        self.secondLine = secondLine
        self.openSettings = openSettings
        self.showsBreadcrumb = showsBreadcrumb
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .center, spacing: AgentSpacing.x1) {
                if showsBreadcrumb {
                    MetaLabel(breadcrumb)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                actions
                ProfileSettingsButton(identity: identity, action: openSettings)
            }
            .frame(height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(firstLine)
                    .font(.agentDisplayLead)
                Text(secondLine)
                    .font(.agentDisplay)
            }
            .tracking(-0.64)
            .foregroundStyle(Color.agentText)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)

        }
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentLayout.pageTopPadding)
        .padding(.bottom, AgentLayout.pageHeaderToContentSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PlanHeader where Actions == EmptyView {
    init(
        breadcrumb: String,
        identity: ActiveCreatorIdentity,
        firstLine: String,
        secondLine: String,
        openSettings: @escaping () -> Void
    ) {
        self.init(
            breadcrumb: breadcrumb,
            identity: identity,
            firstLine: firstLine,
            secondLine: secondLine,
            openSettings: openSettings,
            showsBreadcrumb: true,
            actions: { EmptyView() }
        )
    }
}
