import SwiftData
import SwiftUI
import UIKit

enum PlanMode: Sendable {
    case week
}

enum PlanNavigationRoute: Hashable, CaseIterable {
    case socialGrid
}

extension View {
    func planNavigationDestinations(bottomClearance: CGFloat) -> some View {
        navigationDestination(for: PlanNavigationRoute.self) { route in
            switch route {
            case .socialGrid:
                SocialGridView(presentation: .phone(bottomClearance: bottomClearance))
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
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            AgendaView(
                weekOffset: $weekOffset,
                selectedDay: $selectedDay,
                referenceDate: planNow,
                showsHeader: false
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
                        AgentToolbarIconLabel(icon: .search, iconSize: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search posts")

                    if showsFeedShortcut {
                        NavigationLink(value: PlanNavigationRoute.socialGrid) {
                            AgentToolbarIconLabel(icon: .instagramCamera, iconSize: 16)
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

    private var briefs: [CreativeBrief] {
        allBriefs.filter {
            $0.status != .archived && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private var pillars: [Pillar] {
        allPillars.filter {
            !$0.isArchived && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private var outputs: [PlatformOutput] {
        let briefIDs = Set(briefs.map(\.id))
        return allOutputs.filter {
            briefIDs.contains($0.briefID) && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private var results: [(PlatformOutput, CreativeBrief)] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return outputs.compactMap { output in
            guard let brief = brief(for: output) else { return nil }
            if !cleanQuery.isEmpty, !searchText(for: output, brief: brief).localizedStandardContains(cleanQuery) {
                return nil
            }
            return (output, brief)
        }
        .sorted { lhs, rhs in
            let left = lhs.0.targetDate ?? lhs.1.updatedAt
            let right = rhs.0.targetDate ?? rhs.1.updatedAt
            return left > right
        }
    }

    var body: some View {
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
                        ForEach(results, id: \.0.id) { output, brief in
                            resultCard(output: output, brief: brief)
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

    private func resultCard(output: PlatformOutput, brief: CreativeBrief) -> some View {
        let pillar = pillar(for: brief)
        let missed = FinalizedPostPresentation.isMissed(
            outputStatus: output.status,
            targetDate: output.targetDate
        )
        return AgentPostCard(
            title: postTitle(output: output, brief: brief),
            pillar: pillar?.name ?? "Unfiled",
            accent: pillar.map { Color(agentHex: $0.resolvedColorHex(in: pillars)) } ?? .agentSecondary,
            status: output.status,
            metadata: platformLabel(for: output),
            timeText: output.targetDate?.formatted(.dateTime.month(.abbreviated).day().hour().minute()),
            isLate: missed || PostWorkDateStatusPolicy.isLate(
                workDate: brief.workDate,
                briefStatus: brief.status,
                outputStatus: output.status
            ),
            destination: AnyView(PostOutputDetailView(brief: brief, output: output))
        )
    }

    private func brief(for output: PlatformOutput) -> CreativeBrief? {
        briefs.first { $0.id == output.briefID }
    }

    private func pillar(for brief: CreativeBrief) -> Pillar? {
        brief.pillarID.flatMap { id in pillars.first { $0.id == id } }
    }

    private func platformLabel(for output: PlatformOutput) -> String {
        if let id = output.destinationID, let destination = destinations.first(where: { $0.id == id }) {
            return destination.name
        }
        if let id = output.formatID, let format = formats.first(where: { $0.id == id }) {
            return format.name
        }
        return output.platform.title
    }

    private func postTitle(output: PlatformOutput, brief: CreativeBrief) -> String {
        let override = output.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? brief.title : override
    }

    private func searchText(for output: PlatformOutput, brief: CreativeBrief) -> String {
        [
            output.titleOverride,
            brief.title,
            brief.notes,
            brief.spokenHook,
            brief.scriptBeatsText,
            brief.ctaIntent,
            output.caption,
            output.cta,
            platformLabel(for: output),
            pillar(for: brief)?.name ?? ""
        ].joined(separator: " ")
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
