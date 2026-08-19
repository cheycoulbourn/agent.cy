import SwiftData
import SwiftUI

private enum AgendaDisplayMode: String, CaseIterable, Identifiable {
    case week
    case calendar
    case list

    var id: Self { self }

    var title: String {
        switch self {
        case .week: "Week"
        case .calendar: "Calendar"
        case .list: "List"
        }
    }
}

private enum AgendaListPillarFilter: Hashable {
    case all
    case unfiled
    case pillar(UUID)
}

enum AgendaListStandardStatus: String, CaseIterable, Hashable {
    case draft
    case inProgress
    case scheduled
    case posted

    var title: String {
        switch self {
        case .draft: "Draft"
        case .inProgress: "In progress"
        case .scheduled: "Scheduled"
        case .posted: "Posted"
        }
    }
}

enum AgendaListStatusFilter: Hashable {
    case all
    case open
    case lateWork
    case standard(AgendaListStandardStatus)
    case custom(String)

    static let defaultFilter: Self = .open
}

enum AgendaPostOccurrenceKind: String, Hashable {
    case work
    case post

    var label: String {
        switch self {
        case .work: "Work date"
        case .post: "Post date"
        }
    }

    var sortOrder: Int {
        switch self {
        case .work: 0
        case .post: 1
        }
    }
}

private struct AgendaPostOccurrence: Identifiable {
    let output: PlatformOutput
    let date: Date
    let kind: AgendaPostOccurrenceKind

    var id: String {
        "\(output.id.uuidString)-\(kind.rawValue)-\(date.timeIntervalSinceReferenceDate)"
    }
}

private struct AgendaOutputDayGroup: Identifiable {
    let day: Date
    let occurrences: [AgendaPostOccurrence]

    var id: Date { day }
}

private struct AgendaUndatedPost: Identifiable {
    let output: PlatformOutput
    let brief: CreativeBrief

    var id: UUID { output.id }
}

private struct AgendaListProjection {
    let upcomingGroups: [AgendaOutputDayGroup]
    let pastGroups: [AgendaOutputDayGroup]
    let undatedPosts: [AgendaUndatedPost]
}

private struct AgendaRenderSnapshot {
    let briefByID: [UUID: CreativeBrief]
    let occurrences: [AgendaPostOccurrence]
    let occurrencesByDay: [Date: [AgendaPostOccurrence]]

    func occurrences(on day: Date, calendar: Calendar = .current) -> [AgendaPostOccurrence] {
        occurrencesByDay[calendar.startOfDay(for: day)] ?? []
    }

}

private enum AgendaLayout {
    static let modeRailReservedHeight: CGFloat = 47
}

struct AgendaView: View {
    @Binding var weekOffset: Int
    @Binding var selectedDay: Date
    let showsHeader: Bool
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt) private var allOutputs: [PlatformOutput]
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    @Query(sort: \ContentSeries.createdAt) private var allSeries: [ContentSeries]
    @Query(sort: \SeriesEpisodeSlot.plannedDate) private var allEpisodeSlots: [SeriesEpisodeSlot]
    @Query private var destinations: [PublishingDestination]
    @Query private var formats: [PublishingFormat]
    @Query(sort: \CreatorSocialAccount.sortOrder) private var allSocialAccounts: [CreatorSocialAccount]
    @Query private var profiles: [CreatorProfile]
    @Query private var allFocusTemplates: [DailyFocusTemplateEntry]
    @Query private var allFocusOverrides: [DailyFocusOverride]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var headerHeight: CGFloat = 0
    @State private var schedulingPost: AgendaDaySelection?
    @State private var reschedulingOutput: PlatformOutput?
    @State private var focusedDay: AgendaDaySelection?
    @State private var deepLinkedBrief: CreativeBrief?
    @State private var deepLinkedBriefOpensEditor = false
    @State private var selectedEpisodeSlot: SeriesEpisodeSlot?
    @State private var displayMode: AgendaDisplayMode = .week
    @State private var calendarMonth = Date()
    @State private var listPillarFilter: AgendaListPillarFilter = .all
    @State private var listStatusFilter: AgendaListStatusFilter = .defaultFilter
    @State private var isListPillarFilterPresented = false
    @State private var isListStatusFilterPresented = false
    let referenceDate: Date

    private var briefs: [CreativeBrief] { scoped(allBriefs) }
    private var outputs: [PlatformOutput] { scoped(allOutputs) }
    private var pillars: [Pillar] { scoped(allPillars) }
    private var seriesRecords: [ContentSeries] {
        scoped(allSeries).filter { $0.state != .archived }
    }
    private var episodeSlots: [SeriesEpisodeSlot] {
        scoped(allEpisodeSlots).filter { $0.status == .open }
    }
    private var socialAccounts: [CreatorSocialAccount] { scoped(allSocialAccounts) }
    private var focusTemplates: [DailyFocusTemplateEntry] { scoped(allFocusTemplates) }
    private var focusOverrides: [DailyFocusOverride] { scoped(allFocusOverrides) }

    private func scoped<T>(_ values: [T]) -> [T] where T: WorkspaceScopedRecord {
        values.filter {
            WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private var weekStart: Date {
        PlanClockPolicy.weekStart(
            referenceDate: referenceDate,
            offset: weekOffset,
            calendar: .current
        )
    }
    private var weekDays: [Date] { (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) } }
    private var activeBriefs: [CreativeBrief] { briefs.filter { $0.status != .archived } }
    private var activeBriefIDs: Set<UUID> { Set(activeBriefs.map(\.id)) }
    private var activeWorkspace: CreatorWorkspace? {
        guard let activeWorkspaceID = WorkspaceScope.activeWorkspaceID(
            preferredID: appModel.activeWorkspaceID,
            workspaces: workspaces
        ) else {
            return nil
        }
        return workspaces.first(where: { $0.id == activeWorkspaceID && !$0.isArchived })
    }

    init(
        weekOffset: Binding<Int>,
        selectedDay: Binding<Date>,
        referenceDate: Date,
        showsHeader: Bool = true
    ) {
        _weekOffset = weekOffset
        _selectedDay = selectedDay
        _calendarMonth = State(initialValue: referenceDate)
        self.referenceDate = referenceDate
        self.showsHeader = showsHeader
#if DEBUG
        if let previewMode = PreviewAgendaRuntimeFixture.initialDisplayMode() {
            _displayMode = State(initialValue: previewMode)
        }
#endif
    }

    var body: some View {
        let snapshot = makeRenderSnapshot()

        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                if showsHeader {
                    header
                        .reportAgentViewHeight()
                }

                agendaModeRail
                    .padding(.horizontal, AgentLayout.dashboardGutter)
                    .padding(.bottom, AgentSpacing.x3)

                Group {
                    switch displayMode {
                    case .week:
                        AgendaFixedCalendarSurface(
                            minimumHeight: max(
                                0,
                                proxy.size.height -
                                    (showsHeader ? headerHeight : 0) -
                                    AgendaLayout.modeRailReservedHeight
                            )
                        ) {
                            calendarStrip
                        } content: {
                            VStack(spacing: 0) {
                                ForEach(weekDays, id: \.self) { day in
                                    weekRow(day, snapshot: snapshot)
                                }
                            }
                        }
                    case .calendar:
                        calendarAgendaView(snapshot: snapshot)
                    case .list:
                        agendaListView(snapshot: snapshot)
                    }
                }
                .padding(.horizontal, AgentLayout.dashboardGutter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $reschedulingOutput) { output in
            PostRescheduleSheet(output: output)
        }
        .sheet(item: $selectedEpisodeSlot) { slot in
            EpisodeSlotActionsView(slot: slot) { result in
                deepLinkedBriefOpensEditor = true
                deepLinkedBrief = result.brief
            }
        }
        .navigationDestination(item: $focusedDay) { selection in
            DayAgendaView(day: selection.day, referenceDate: referenceDate)
        }
        .navigationDestination(item: $schedulingPost) { selection in
            AgendaPostIdeaPickerView(day: selection.day)
        }
        .navigationDestination(item: $deepLinkedBrief) { brief in
            if deepLinkedBriefOpensEditor,
               let output = outputs.first(where: { $0.briefID == brief.id && $0.status != .posted }) {
                ResumablePostEditorView(brief: brief, output: output, onSpark: {})
                .navigationTitle("Edit post")
                .navigationBarTitleDisplayMode(.inline)
                .agentScreen()
                .agentKeyboardDismissal()
            } else if let output = outputs.first(where: {
                $0.briefID == brief.id && PostOutputDetailPolicy.usesFinalizedView(
                    outputStatus: $0.status,
                    targetDate: $0.targetDate
                )
            }) {
                PostOutputDetailView(brief: brief, output: output)
            } else {
                IdeaPostDraftView(brief: brief)
            }
        }
        .onPreferenceChange(AgentViewHeightPreferenceKey.self) { headerHeight = $0 }
        .onChange(of: displayMode) { _, mode in
            guard mode == .calendar else { return }
            calendarMonth = selectedDay
        }
        .onChange(of: appModel.requestedPlanNavigationReset) { _, _ in
            schedulingPost = nil
            reschedulingOutput = nil
            focusedDay = nil
            deepLinkedBrief = nil
            deepLinkedBriefOpensEditor = false
            selectedEpisodeSlot = nil
        }
        .onChange(of: appModel.requestedOpenPostsList, initial: true) { _, request in
            guard request > 0 else { return }
            displayMode = .list
            listStatusFilter = .open
            appModel.requestedOpenPostsList = 0
        }
        .onChange(of: appModel.requestedLateWorkList, initial: true) { _, request in
            guard request > 0 else { return }
            displayMode = .list
            listStatusFilter = .lateWork
            appModel.requestedLateWorkList = 0
        }
        .onChange(of: appModel.widgetBriefID, initial: true) { _, id in
            guard let id, let brief = activeBriefs.first(where: { $0.id == id }) else { return }
            deepLinkedBriefOpensEditor = appModel.widgetBriefOpensEditor
            deepLinkedBrief = brief
            appModel.widgetBriefOpensEditor = false
            appModel.widgetBriefID = nil
        }
        .onChange(of: appModel.widgetAgendaDay, initial: true) { _, day in
            guard let day else { return }
            let normalizedDay = Calendar.current.startOfDay(for: day)
            selectedDay = normalizedDay
            weekOffset = targetWeekOffset(containing: normalizedDay)
            focusedDay = AgendaDaySelection(day: normalizedDay)
            appModel.widgetAgendaDay = nil
        }
        .agentDashboardScreen()
    }

    @ViewBuilder
    private var agendaModeRail: some View {
#if targetEnvironment(macCatalyst)
        agendaModePicker
#else
        agendaModePicker.padding(3)
#endif
    }

    private var agendaModePicker: some View {
        Picker("Agenda view", selection: $displayMode) {
            ForEach(AgendaDisplayMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .dynamicTypeSize(...AgendaCompactCalendarPolicy.maximumDynamicTypeSize)
        .frame(maxWidth: .infinity)
        .accessibilityHint("Switch between week, calendar, and post list views")
    }

    private var header: some View {
        PlanHeader(
            breadcrumb: weekSummary,
            identity: activeIdentity,
            firstLine: "\(greeting),",
            secondLine: "here's your week.",
            openSettings: { appModel.presentedSheet = .settings }
        ) {
                HStack(spacing: AgentSpacing.x1) {
                    weekButton(symbol: "chevron.left", label: "Previous week", amount: -1)
                    weekButton(symbol: "chevron.right", label: "Next week", amount: 1)
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

    private func weekButton(symbol: String, label: String, amount: Int) -> some View {
        Button { moveWeek(amount) } label: {
            ZStack {
                Circle()
                    .fill(Color.agentCanvas)
                    .overlay {
                        Circle()
                            .stroke(Color.agentBorder, lineWidth: 0.75)
                    }
                    .frame(width: 36, height: 36)

                AgentIconView(AgentIcon(legacySystemName: symbol), size: 14)
                    .foregroundStyle(Color.agentText)
            }
            .frame(width: 44, height: 44)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var calendarStrip: some View {
        if AgendaCompactCalendarPolicy.showsWeekdayChips(
            dynamicTypeSize: dynamicTypeSize
        ) {
            weekdayChipStrip
        } else {
            accessibilityWeekNavigator
        }
    }

    private var weekdayChipStrip: some View {
        HStack(spacing: AgentSpacing.x1) {
            weekButton(symbol: "chevron.left", label: "Previous week", amount: -1)

            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { day in
                    calendarDay(day)
                }
            }
            .frame(maxWidth: .infinity)
            .layoutPriority(1)

            weekButton(symbol: "chevron.right", label: "Next week", amount: 1)
        }
        .dynamicTypeSize(...AgendaCompactCalendarPolicy.maximumDynamicTypeSize)
        .padding(.horizontal, -AgentSpacing.x2)
        .padding(.bottom, AgentSpacing.x4)
    }

    private var accessibilityWeekNavigator: some View {
        HStack(spacing: AgentSpacing.x3) {
            weekButton(symbol: "chevron.left", label: "Previous week", amount: -1)

            Text(weekRange)
                .font(.agentBody.weight(.semibold))
                .foregroundStyle(Color.agentText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            weekButton(symbol: "chevron.right", label: "Next week", amount: 1)
        }
        .padding(.horizontal, -AgentSpacing.x2)
        .padding(.bottom, AgentSpacing.x4)
        .accessibilityElement(children: .contain)
    }

    private func calendarDay(_ day: Date) -> some View {
        let isToday = Calendar.current.isDate(day, inSameDayAs: referenceDate)
        let dotColor = pillarHex(on: day).map {
            Color(agentHex: AgendaPillarDotPresentation.displayedHex(storedHex: $0))
        }
        return Button {
            performAgendaUpdate(animation: .snappy(duration: 0.24)) {
                selectedDay = Calendar.current.startOfDay(for: day)
            }
            openDay(day)
        } label: {
            VStack(spacing: 10) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.agentMetadata)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.agentSecondary)
                Text(day.formatted(.dateTime.day()))
                    .font(.agentBody.weight(isToday ? .semibold : .medium))
                if let dotColor {
                    PillarColorMark(color: dotColor, diameter: 8)
                        .overlay {
                            Circle()
                                .stroke(Color.agentText.opacity(0.24), lineWidth: 0.75)
                        }
                        .accessibilityHidden(true)
                } else {
                    Color.clear
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, AgentSpacing.x2)
            .foregroundStyle(Color.agentText)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(Color.clear, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isToday ? Color.agentFocusControl : Color.clear,
                        lineWidth: 1
                    )
            }
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityAddTraits(isToday ? .isSelected : [])
    }

    private func calendarAgendaView(snapshot: AgendaRenderSnapshot) -> some View {
        let selectedOccurrences = snapshot.occurrences(on: selectedDay)
        let selectedSlots = episodeSlots(on: selectedDay)

        return ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x5) {
                AgentInsetSurface {
                    VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                        calendarMonthHeader
                        calendarMonthGrid(snapshot: snapshot)
                    }
                }

                AgentInsetSurface {
                    VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                        SectionRuleHeader(
                            title: selectedDay.formatted(
                                .dateTime.weekday(.wide).month(.abbreviated).day()
                            ),
                            trailing: AgendaDayPresentation.postCountLabel(
                                selectedOccurrences.count
                            )
                        )

                        if selectedOccurrences.isEmpty && selectedSlots.isEmpty {
                            Text("No posts planned.")
                                .font(.agentBody)
                                .foregroundStyle(Color.agentSecondary)
                                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                        } else {
                            VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                                ForEach(selectedOccurrences) { occurrence in
                                    if let brief = snapshot.briefByID[occurrence.output.briefID] {
                                        agendaPostCard(
                                            occurrence: occurrence,
                                            brief: brief
                                        )
                                    }
                                }

                                ForEach(selectedSlots) { slot in
                                    episodeSlotCard(slot)
                                }
                            }
                        }

                        Button {
                            focusedDay = AgendaDaySelection(day: selectedDay)
                        } label: {
                            HStack {
                                Text("View the day")
                                    .font(.agentBody.weight(.semibold))
                                Spacer()
                                AgentIconView(.forward, size: 11)
                            }
                            .foregroundStyle(Color.agentText)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .agentBottomNavigationClearance()
        }
        .scrollIndicators(.hidden)
    }

    private var calendarMonthHeader: some View {
        HStack(spacing: AgentSpacing.x2) {
            Text(calendarMonthStart.formatted(.dateTime.month(.wide).year()))
                .font(.agentTitle)
                .foregroundStyle(Color.agentText)
                .frame(maxWidth: .infinity, alignment: .leading)

            calendarMonthButton(amount: -1)
            calendarMonthButton(amount: 1)
        }
    }

    private func calendarMonthButton(amount: Int) -> some View {
        Button {
            shiftCalendarMonth(amount)
        } label: {
            AgentIconView(amount < 0 ? .back : .forward, size: 13)
                .foregroundStyle(Color.agentText)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(amount < 0 ? "Previous month" : "Next month")
    }

    private func calendarMonthGrid(snapshot: AgendaRenderSnapshot) -> some View {
        let pillarHexByWeekday = calendarPillarHexByWeekday()
        let weekdayHeaders = AgendaMonthCalendarColorPolicy.weekdayHeaders(
            symbols: Calendar.current.veryShortStandaloneWeekdaySymbols,
            firstWeekday: Calendar.current.firstWeekday,
            pillarHexByWeekday: pillarHexByWeekday
        )

        return VStack(spacing: AgentSpacing.x2) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: AgentSpacing.x1), count: 7),
                spacing: AgentSpacing.x2
            ) {
                ForEach(weekdayHeaders) { header in
                    calendarWeekdayHeader(header)
                }

                ForEach(calendarMonthDays, id: \.self) { day in
                    calendarMonthCell(
                        day,
                        postCount: snapshot.occurrences(on: day).count
                    )
                }
            }
        }
        .dynamicTypeSize(...AgendaCompactCalendarPolicy.maximumDynamicTypeSize)
    }

    private func calendarWeekdayHeader(
        _ header: AgendaMonthCalendarWeekdayHeader
    ) -> some View {
        let displayedHex = header.pillarHex.map {
            AgendaPillarDotPresentation.displayedHex(storedHex: $0)
        }
        let markerColor = displayedHex.map { Color(agentHex: $0) }
        let foreground = displayedHex.map {
            Color(agentHex: AgentChipContrast.foregroundHex(on: $0))
        } ?? Color.agentSecondary

        return ZStack {
            if let markerColor {
                Circle()
                    .fill(markerColor)
                    .overlay {
                        Circle()
                            .stroke(Color.agentText.opacity(0.2), lineWidth: 0.5)
                    }
            }

            Text(header.symbol)
                .font(.agentMetadata.weight(.semibold))
                .foregroundStyle(foreground)
        }
        .frame(width: 28, height: 28)
        .frame(maxWidth: .infinity, minHeight: 32)
        .accessibilityHidden(true)
    }

    private func calendarMonthCell(
        _ day: Date,
        postCount: Int
    ) -> some View {
        let calendar = Calendar.current
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDate(day, inSameDayAs: referenceDate)
        let isCurrentMonth = calendar.isDate(day, equalTo: calendarMonthStart, toGranularity: .month)

        return Button {
            performAgendaUpdate(animation: .snappy(duration: 0.22)) {
                selectedDay = calendar.startOfDay(for: day)
                if !isCurrentMonth {
                    calendarMonth = day
                }
            }
        } label: {
            VStack(spacing: 5) {
                Text(day.formatted(.dateTime.day()))
                    .font(.agentBody.weight(isSelected || isToday ? .semibold : .regular))
                    .foregroundStyle(
                        isSelected ? Color.agentCanvas :
                            (isCurrentMonth ? Color.agentText : Color.agentSecondary)
                    )

                HStack(spacing: 4) {
                    if postCount > 0 {
                        Text("\(postCount)")
                            .font(.agentMetadata.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.agentCanvas : Color.agentSecondary)
                    }
                }
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                isSelected ? Color.agentText : Color.clear,
                in: .rect(cornerRadius: 13)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(
                        !isSelected && isToday ? Color.agentFocusControl : Color.clear,
                        lineWidth: 1
                    )
            }
            .contentShape(.rect(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            [
                day.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                AgendaDayPresentation.postCountLabel(postCount)
            ].joined(separator: ", ")
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func agendaListView(snapshot: AgendaRenderSnapshot) -> some View {
        let projection = makeAgendaListProjection(snapshot: snapshot)

        return ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x5) {
                agendaListFilters

                if projection.upcomingGroups.isEmpty &&
                    projection.pastGroups.isEmpty &&
                    projection.undatedPosts.isEmpty {
                    agendaListEmptyState
                } else {
                    agendaListSection(title: "Upcoming", groups: projection.upcomingGroups)
                    agendaListSection(title: "Past", groups: projection.pastGroups)
                    agendaUndatedListSection(posts: projection.undatedPosts)
                }
            }
            .agentBottomNavigationClearance()
        }
        .scrollIndicators(.hidden)
    }

    private var agendaListEmptyState: some View {
        AgentInsetSurface {
            VStack(alignment: .leading, spacing: AgentSpacing.x5) {
                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    Text(hasActiveListFilter ? "Nothing fits this view yet." : "Your next post can start here.")
                        .font(.agentTitle)
                        .foregroundStyle(Color.agentText)

                    Text(
                        hasActiveListFilter
                            ? "Start a post for this view, or save an idea to shape later."
                            : "Create a post for your calendar, or save an idea to shape later."
                    )
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: AgentSpacing.x3) {
                    AgentBlockAddActionButton(
                        title: "Start a post",
                        background: .actionAccent,
                        foreground: .onAccent,
                        border: .clear,
                        action: { presentListEmptyStateCapture(.post) }
                    )

                    AgentBlockAddActionButton(
                        title: "Save an idea",
                        action: { presentListEmptyStateCapture(.idea) }
                    )
                }

                if hasActiveListFilter {
                    Button("Clear filters", action: clearAgendaListFilters)
                        .font(.agentSubtext.weight(.semibold))
                        .foregroundStyle(Color.agentSecondary)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                        .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var agendaListFilters: some View {
        if AgendaCompactCalendarPolicy.usesStackedListFilters(
            dynamicTypeSize: dynamicTypeSize
        ) {
            VStack(spacing: AgentSpacing.x3) {
                agendaListPillarFilterButton
                agendaListStatusFilterButton
            }
        } else {
            HStack(spacing: AgentSpacing.x3) {
                agendaListPillarFilterButton
                agendaListStatusFilterButton
            }
        }
    }

    private var agendaListPillarFilterButton: some View {
        Button {
            isListPillarFilterPresented = true
        } label: {
            agendaListFilterLabel(
                category: "Pillar",
                value: selectedListPillarTitle,
                color: selectedListPillarColor
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter by pillar")
        .accessibilityValue(selectedListPillarTitle)
        .popover(isPresented: $isListPillarFilterPresented) {
            agendaListPillarFilterPopover
                .presentationCompactAdaptation(.popover)
                .presentationBackground(.ultraThinMaterial)
                .presentationCornerRadius(24)
        }
    }

    private var agendaListStatusFilterButton: some View {
        Button {
            isListStatusFilterPresented = true
        } label: {
            agendaListFilterLabel(
                category: "Status",
                value: selectedListStatusTitle,
                valueColor: listStatusFilter == .lateWork ? .agentDestructive : nil
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter by status")
        .accessibilityValue(selectedListStatusTitle)
        .popover(isPresented: $isListStatusFilterPresented) {
            agendaListStatusFilterPopover
                .presentationCompactAdaptation(.popover)
                .presentationBackground(.ultraThinMaterial)
                .presentationCornerRadius(24)
        }
    }

    private var agendaListPillarFilterPopover: some View {
        VStack(spacing: 0) {
            agendaListPillarFilterRow(
                title: "All pillars",
                filter: .all,
                color: nil
            )
            agendaListPillarFilterRow(
                title: "No pillar",
                filter: .unfiled,
                color: nil
            )

            ForEach(availableListPillars) { pillar in
                agendaListPillarFilterRow(
                    title: pillar.name,
                    filter: .pillar(pillar.id),
                    color: Color(agentHex: pillar.resolvedColorHex(in: pillars))
                )
            }
        }
        .padding(.vertical, AgentSpacing.x2)
        .frame(width: 248)
    }

    private func agendaListPillarFilterRow(
        title: String,
        filter: AgendaListPillarFilter,
        color: Color?
    ) -> some View {
        Button {
            listPillarFilter = filter
            isListPillarFilterPresented = false
        } label: {
            HStack(spacing: AgentSpacing.x3) {
                if let color {
                    PillarColorMark(color: color, diameter: 12)
                } else {
                    Circle()
                        .stroke(Color.agentSecondary.opacity(0.7), lineWidth: 1)
                        .frame(width: 12, height: 12)
                }

                Text(title)
                    .font(.agentBody)
                    .foregroundStyle(Color.agentText)
                    .lineLimit(1)

                Spacer(minLength: AgentSpacing.x3)

                if listPillarFilter == filter {
                    AgentIconView(.check, size: 13)
                        .foregroundStyle(Color.agentText)
                }
            }
            .padding(.horizontal, AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var agendaListStatusFilterPopover: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                agendaListStatusFilterRow(
                    title: "All statuses",
                    filter: .all
                )
                agendaListStatusFilterRow(
                    title: "Open posts",
                    filter: .open
                )
                ForEach(AgendaListStandardStatus.allCases, id: \.self) { status in
                    agendaListStatusFilterRow(
                        title: status.title,
                        filter: .standard(status)
                    )
                }

                agendaListStatusFilterRow(
                    title: "Late work",
                    filter: .lateWork,
                    textColor: .agentDestructive
                )

                if !availableListCustomStatuses.isEmpty {
                    Rectangle()
                        .fill(Color.agentHairline)
                        .frame(height: 1)
                        .padding(.horizontal, AgentSpacing.x4)

                    ForEach(availableListCustomStatuses, id: \.self) { status in
                        agendaListStatusFilterRow(
                            title: status,
                            filter: .custom(
                                CustomPostStatusPolicy.comparisonKey(status) ?? status.lowercased()
                            )
                        )
                    }
                }
            }
            .padding(.vertical, AgentSpacing.x2)
        }
        .scrollIndicators(.hidden)
        .frame(width: 248)
        .frame(maxHeight: 440)
    }

    private func agendaListStatusFilterRow(
        title: String,
        filter: AgendaListStatusFilter,
        textColor: Color? = nil
    ) -> some View {
        Button {
            listStatusFilter = filter
            isListStatusFilterPresented = false
        } label: {
            HStack(spacing: AgentSpacing.x3) {
                Text(title)
                    .font(.agentBody)
                    .foregroundStyle(textColor ?? Color.agentText)
                    .lineLimit(1)

                Spacer(minLength: AgentSpacing.x3)

                if listStatusFilter == filter {
                    AgentIconView(.check, size: 13)
                        .foregroundStyle(Color.agentText)
                }
            }
            .padding(.horizontal, AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(listStatusFilter == filter ? .isSelected : [])
    }

    private func agendaListFilterLabel(
        category: String,
        value: String,
        color: Color? = nil,
        valueColor: Color? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x1) {
            Text(category.uppercased())
                .font(.agentMetadata)
                .foregroundStyle(Color.agentSecondary)

            HStack(spacing: AgentSpacing.x2) {
                if let color {
                    PillarColorMark(color: color, diameter: 9)
                }

                Text(value)
                    .font(.agentSubtext.weight(.semibold))
                    .foregroundStyle(valueColor ?? Color.agentText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                AgentIconView(.expand, size: 10)
                    .foregroundStyle(Color.agentSecondary)
            }
        }
        .padding(.horizontal, AgentSpacing.x4)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.control)
                .stroke(Color.agentHairline, lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: AgentRadius.control))
    }

    @ViewBuilder
    private func agendaListSection(
        title: String,
        groups: [AgendaOutputDayGroup]
    ) -> some View {
        if !groups.isEmpty {
            AgentInsetSurface {
                VStack(alignment: .leading, spacing: AgentSpacing.x5) {
                    SectionRuleHeader(
                        title: title,
                        trailing: AgendaDayPresentation.postCountLabel(
                            groups.reduce(0) { $0 + $1.occurrences.count }
                        )
                    )

                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                            Button {
                                selectedDay = group.day
                                focusedDay = AgendaDaySelection(day: group.day)
                            } label: {
                                HStack {
                                    Text(
                                        group.day.formatted(
                                            .dateTime.weekday(.wide).month(.abbreviated).day()
                                        )
                                    )
                                    .font(.agentHeadline)
                                    Spacer()
                                    AgentIconView(.forward, size: 11)
                                        .foregroundStyle(Color.agentSecondary)
                                }
                                .foregroundStyle(Color.agentText)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)

                            ForEach(group.occurrences) { occurrence in
                                if let brief = activeBriefs.first(where: {
                                    $0.id == occurrence.output.briefID
                                }) {
                                    let statusOverride = listStatusOverride(for: brief)
                                    agendaPostCard(
                                        occurrence: occurrence,
                                        brief: brief,
                                        statusTextOverride: statusOverride?.text,
                                        displayStatusOverride: statusOverride?.status
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func agendaUndatedListSection(posts: [AgendaUndatedPost]) -> some View {
        if !posts.isEmpty {
            AgentInsetSurface {
                VStack(alignment: .leading, spacing: AgentSpacing.x5) {
                    SectionRuleHeader(
                        title: "No date",
                        trailing: AgendaDayPresentation.postCountLabel(posts.count)
                    )

                    ForEach(posts) { item in
                        let statusOverride = listStatusOverride(for: item.brief)
                        AgentPostCard(
                            title: outputTitle(item.output, brief: item.brief),
                            pillar: pillarName(for: item.brief),
                            accent: pillarAccent(for: item.brief),
                            status: statusOverride?.status ?? item.output.status,
                            metadata: platformLabel(for: item.output),
                            timeText: nil,
                            statusTextOverride: statusOverride?.text ??
                                CustomPostStatusPolicy.displayLabel(
                                    briefStatus: item.brief.status,
                                    outputStatus: item.output.status,
                                    customStatus: item.brief.resolvedCustomStatusLabel,
                                    ideaBankPlacement: item.brief.ideaBankPlacement
                                ),
                            destination: postDestination(
                                brief: item.brief,
                                output: item.output
                            )
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func weekRow(_ day: Date, snapshot: AgendaRenderSnapshot) -> some View {
        let dayOccurrences = snapshot.occurrences(on: day)
        let dayOutputs = dayOccurrences.map(\.output)
        let dayFocus = focus(on: day)
        let dayEpisodeSlots = episodeSlots(on: day)

        if dayEpisodeSlots.isEmpty && AgendaDayPresentation.shouldCompact(
            day: day,
            outputs: dayOutputs.map { output in
                AgendaOutputState(
                    outputStatus: output.status,
                    briefStatus: snapshot.briefByID[output.briefID]?.status
                )
            },
            now: referenceDate
        ) {
            compactCompletedDay(
                day: day,
                focus: dayFocus,
                postCount: nonDraftPostCount(in: dayOutputs)
            )
        } else {
            VStack(alignment: .leading, spacing: 14) {
                dayHeader(
                    day: day,
                    focus: dayFocus
                )

                ForEach(dayOccurrences) { occurrence in
                    if let brief = snapshot.briefByID[occurrence.output.briefID] {
                        agendaPostCard(
                            occurrence: occurrence,
                            brief: brief
                        )
                    }
                }

                ForEach(dayEpisodeSlots) { slot in
                    episodeSlotCard(slot)
                }
            }
            .foregroundStyle(Color.agentText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 20)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.agentHairline).frame(height: 1)
            }
        }
    }

    private func episodeSlots(on day: Date) -> [SeriesEpisodeSlot] {
        episodeSlots.filter { Calendar.current.isDate($0.plannedDate, inSameDayAs: day) }
    }

    @ViewBuilder
    private func episodeSlotCard(_ slot: SeriesEpisodeSlot) -> some View {
        if let series = seriesRecords.first(where: { $0.id == slot.seriesID }) {
            Button {
                selectedEpisodeSlot = slot
            } label: {
                EpisodeNeededCard(slot: slot, series: series)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens options for this planned series episode")
        }
    }

    private func compactCompletedDay(
        day: Date,
        focus: ResolvedDailyFocus?,
        postCount: Int
    ) -> some View {
        let focusTitle = agendaFocusTitle(focus)
        let postCountLabel = AgendaDayPresentation.compactPostCountLabel(postCount)

        return Button {
            openDay(day)
        } label: {
            compactCompletedDayContent(
                day: day,
                focusTitle: focusTitle,
                postCountLabel: postCountLabel
            )
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.agentHairline).frame(height: 1)
        }
        .accessibilityLabel(
            [
                day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                "complete",
                "focus \(focusTitle)",
                postCountLabel
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        )
        .accessibilityHint("Opens this day's schedule")
    }

    @ViewBuilder
    private func compactCompletedDayContent(
        day: Date,
        focusTitle: String,
        postCountLabel: String?
    ) -> some View {
        if AgendaCompactCalendarPolicy.usesStackedCompletedDayLayout(
            dynamicTypeSize: dynamicTypeSize
        ) {
            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                HStack(spacing: AgentSpacing.x3) {
                    Text(AgendaDayPresentation.weekdayMonthDayLabel(day))
                        .font(.agentMetadata)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    AgentIconView(.check, size: 13)
                    AgentIconView(.forward, size: 11)
                        .foregroundStyle(Color.agentSecondary)
                }

                Text(focusTitle)
                    .font(.agentBody.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let postCountLabel {
                    Text(postCountLabel)
                        .font(.agentMetadata)
                        .foregroundStyle(Color.agentSecondary)
                }
            }
            .foregroundStyle(Color.agentText)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, AgentSpacing.x4)
            .contentShape(.rect)
        } else {
            HStack(spacing: AgentSpacing.x3) {
                Text(AgendaDayPresentation.weekdayMonthDayLabel(day))
                    .font(.agentMetadata)
                    .textCase(.uppercase)
                    .frame(width: 92, alignment: .leading)
                AgentIconView(.check, size: 13)
                    .frame(width: 14, height: 14)

                Text(focusTitle)
                    .font(.agentBody.weight(.medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let postCountLabel {
                    Text(postCountLabel)
                        .font(.agentMetadata)
                        .foregroundStyle(Color.agentSecondary)
                        .fixedSize()
                }

                AgentIconView(.forward, size: 11)
                    .foregroundStyle(Color.agentSecondary)
                    .frame(width: 14, height: 14)
            }
            .foregroundStyle(Color.agentText)
            .frame(maxWidth: .infinity, minHeight: 39)
            .padding(.vertical, AgentSpacing.x3)
            .contentShape(.rect)
        }
    }

    private func nonDraftPostCount(in outputs: [PlatformOutput]) -> Int {
        outputs.filter { output in
            TodayOutputPresentation.section(
                outputStatus: output.status,
                briefStatus: activeBriefs.first(where: { $0.id == output.briefID })?.status
            ) != .drafted
        }.count
    }

    private func dayHeader(
        day: Date,
        focus: ResolvedDailyFocus?
    ) -> some View {
        HStack(alignment: .center, spacing: AgentSpacing.x2) {
            Button {
                openDay(day)
            } label: {
                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    Text(dayHeaderDate(day))
                        .font(.agentMetadata.weight(
                            Calendar.current.isDate(day, inSameDayAs: referenceDate) ? .semibold : .medium
                        ))
                        .textCase(.uppercase)
                        .foregroundStyle(
                            Calendar.current.isDate(day, inSameDayAs: referenceDate)
                                ? Color.cyAccent
                                : Color.agentText
                        )
                        .fixedSize()

                    Text(agendaFocusTitle(focus))
                        .font(.agentBody.weight(.medium))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
                .foregroundStyle(Color.agentText)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button {
                schedulingPost = AgendaDaySelection(day: day)
            } label: {
                AgentIconView(.add, size: 18)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Schedule post")
            .accessibilityHint("Schedules a post for \(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))")
        }
        .foregroundStyle(Color.agentText)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }

    private func openDay(_ day: Date) {
        let normalizedDay = AgendaDaySelection.normalizedDay(day)
        selectedDay = normalizedDay

        // Only one route may own a week-row tap. Clearing competing routes
        // prevents nested controls from reusing a stale destination.
        schedulingPost = nil
        reschedulingOutput = nil
        selectedEpisodeSlot = nil
        deepLinkedBrief = nil
        deepLinkedBriefOpensEditor = false
        focusedDay = AgendaDaySelection(day: normalizedDay)
    }

    private func agendaPostCard(
        occurrence: AgendaPostOccurrence,
        brief: CreativeBrief,
        statusTextOverride: String? = nil,
        displayStatusOverride: PlatformOutputStatus? = nil
    ) -> some View {
        let output = occurrence.output
        let section = TodayOutputPresentation.section(
            outputStatus: output.status,
            briefStatus: brief.status
        )
        let displaysAsDraft = section != .goingLive
        let overdue = occurrence.kind == .post &&
            AgendaDayPresentation.isOverdue(
            targetDate: occurrence.date,
            status: output.status,
            now: referenceDate
        )
        let lateWork = occurrence.kind == .work && PostWorkDateStatusPolicy.isLate(
            workDate: occurrence.date,
            briefStatus: brief.status,
            outputStatus: output.status
        )
        let accent = pillarAccent(for: brief)
        let isScheduledDraftOccurrence = occurrence.kind == .post && displaysAsDraft
        let inferredDisplayStatus: PlatformOutputStatus = if isScheduledDraftOccurrence {
            .scheduled
        } else if displaysAsDraft {
            .draft
        } else {
            output.status
        }
        let displayStatus = displayStatusOverride ?? inferredDisplayStatus
        let displayTime = AgendaCardTimePolicy.displayTime(
            kind: occurrence.kind,
            occurrenceDate: occurrence.date,
            includesWorkTime: brief.includesWorkTime,
            includesTargetTime: output.includesTargetTime
        )
        let statusText: String
        if let statusTextOverride {
            statusText = statusTextOverride
        } else if isScheduledDraftOccurrence {
            statusText = "Scheduled draft"
        } else {
            statusText = CustomPostStatusPolicy.displayLabel(
                briefStatus: brief.status,
                outputStatus: output.status,
                customStatus: brief.customStatusLabel,
                ideaBankPlacement: brief.ideaBankPlacement
            )
        }
        let metadata = "\(occurrence.kind.label) · \(platformLabel(for: output))"

        return AgentPostCard(
            title: outputTitle(output, brief: brief),
            pillar: pillarName(for: brief),
            accent: accent,
            status: displayStatus,
            metadata: metadata,
            timeText: displayTime?.formatted(date: .omitted, time: .shortened),
            statusTextOverride: statusText,
            isLate: overdue || lateWork,
            destination: postDestination(brief: brief, output: output),
            footerActionTitle: overdue ? "Reschedule" : nil,
            footerAction: overdue ? { reschedulingOutput = output } : nil
        )
    }

    private func postDestination(
        brief: CreativeBrief,
        output: PlatformOutput
    ) -> AnyView {
        if PostOutputDetailPolicy.usesFinalizedView(
            outputStatus: output.status,
            targetDate: output.targetDate
        ) {
            return AnyView(PostOutputDetailView(brief: brief, output: output))
        }

        return AnyView(
            ResumablePostEditorView(
                brief: brief,
                output: output,
                onSpark: {}
            )
        )
    }

    private func dayHeaderDate(_ day: Date) -> String {
        AgendaDayPresentation.weekdayMonthDayLabel(day)
    }

    private func pillar(for brief: CreativeBrief) -> Pillar? {
        guard let pillarID = brief.pillarID else { return nil }
        return pillars.first(where: { $0.id == pillarID && !$0.isArchived })
    }

    private func pillarName(for brief: CreativeBrief) -> String {
        pillar(for: brief)?.name ?? "Unfiled"
    }

    private func pillarAccent(for brief: CreativeBrief) -> Color {
        guard let pillar = pillar(for: brief) else { return .agentSecondary }
        return Color(agentHex: pillar.resolvedColorHex(in: pillars))
    }

    private func outputTitle(_ output: PlatformOutput, brief: CreativeBrief) -> String {
        let override = output.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? brief.title : override
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

    private var weekRange: String {
        guard let last = weekDays.last else { return "" }
        if Calendar.current.isDate(weekStart, equalTo: last, toGranularity: .month) {
            return "\(weekStart.formatted(.dateTime.month(.abbreviated))) \(weekStart.formatted(.dateTime.day())) – \(last.formatted(.dateTime.day()))"
        }
        return "\(weekStart.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }
    private var weekSummary: String {
        "\(weekRange) · Week \(Calendar.current.component(.weekOfYear, from: weekStart))"
    }
    private var greeting: String {
        PlanClockPolicy.greeting(referenceDate: referenceDate, calendar: .current)
    }
    private func moveWeek(_ amount: Int) {
        performAgendaUpdate(animation: .snappy) {
            weekOffset += amount
            selectedDay = Calendar.current.date(byAdding: .weekOfYear, value: amount, to: selectedDay) ?? weekStart
        }
    }
    private func targetWeekOffset(containing day: Date) -> Int {
        PlanClockPolicy.weekOffset(
            containing: day,
            referenceDate: referenceDate,
            calendar: .current
        )
    }
    private var calendarMonthStart: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: calendarMonth)
        return calendar.date(from: components) ?? calendar.startOfDay(for: calendarMonth)
    }
    private var calendarMonthDays: [Date] {
        let calendar = Calendar.current
        let monthStart = calendarMonthStart
        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingCount = (weekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingCount, to: monthStart) ?? monthStart
        return (0..<42).compactMap {
            calendar.date(byAdding: .day, value: $0, to: gridStart)
        }
    }
    private func makeRenderSnapshot() -> AgendaRenderSnapshot {
        let calendar = Calendar.current
        let activeBriefs = briefs.filter { $0.status != .archived }
        let briefByID = AgendaBriefIndexPolicy.index(activeBriefs)
        let activeBriefIDs = Set(briefByID.keys)
        let occurrences = outputs
            .filter {
                AgendaContentVisibility.includesOutput(
                    briefID: $0.briefID,
                    activeBriefIDs: activeBriefIDs
                )
            }
            .flatMap { output -> [AgendaPostOccurrence] in
                guard let brief = briefByID[output.briefID] else {
                    return []
                }

                var occurrences: [AgendaPostOccurrence] = []
                let showsWorkOccurrence = output.status != .posted &&
                    brief.status != .posted &&
                    brief.status != .archived

                let postDateSharesWorkDay = brief.workDate.map { workDate in
                    output.targetDate.map { calendar.isDate($0, inSameDayAs: workDate) } ?? false
                } ?? false

                if showsWorkOccurrence, let workDate = brief.workDate, !postDateSharesWorkDay {
                    occurrences.append(
                        AgendaPostOccurrence(
                            output: output,
                            date: workDate,
                            kind: .work
                        )
                    )
                }

                if let postDate = output.targetDate {
                    occurrences.append(
                        AgendaPostOccurrence(
                            output: output,
                            date: postDate,
                            kind: .post
                        )
                    )
                }

                return occurrences
            }
            .sorted {
                agendaOccurrencePrecedes(
                    $0,
                    $1,
                    briefByID: briefByID
                )
            }

        let occurrencesByDay = Dictionary(grouping: occurrences) {
            calendar.startOfDay(for: $0.date)
        }
        return AgendaRenderSnapshot(
            briefByID: briefByID,
            occurrences: occurrences,
            occurrencesByDay: occurrencesByDay
        )
    }

    private func makeAgendaListProjection(
        snapshot: AgendaRenderSnapshot
    ) -> AgendaListProjection {
        let filteredOccurrences = filteredListAgendaOccurrences(snapshot: snapshot)
        let groups = filteredListAgendaOutputGroups(
            occurrences: filteredOccurrences,
            briefByID: snapshot.briefByID
        )
        let today = Calendar.current.startOfDay(for: referenceDate)
        return AgendaListProjection(
            upcomingGroups: groups
                .filter { $0.day >= today }
                .sorted { $0.day < $1.day },
            pastGroups: groups
                .filter { $0.day < today }
                .sorted { $0.day > $1.day },
            undatedPosts: filteredUndatedListPosts(snapshot: snapshot)
        )
    }

    private func filteredListAgendaOccurrences(
        snapshot: AgendaRenderSnapshot
    ) -> [AgendaPostOccurrence] {
        let briefByID = AgendaBriefIndexPolicy.index(activeBriefs)
        let occurrencesByOutputID = Dictionary(
            grouping: snapshot.occurrences,
            by: { $0.output.id }
        )

        return outputs
            .compactMap { output -> [AgendaPostOccurrence]? in
                guard let brief = briefByID[output.briefID],
                      matchesListFilters(brief: brief, output: output) else {
                    return nil
                }

                let candidates = occurrencesByOutputID[output.id] ?? []
                switch listStatusFilter {
                case .all:
                    return candidates
                case .standard(.scheduled), .standard(.posted):
                    return candidates.first(where: { $0.kind == .post }).map { [$0] } ?? []
                case .open, .lateWork, .standard(.draft), .standard(.inProgress), .custom:
                    if let workOccurrence = candidates.first(where: { $0.kind == .work }) {
                        return [workOccurrence]
                    }
                    if let postOccurrence = candidates.first(where: { $0.kind == .post }) {
                        return [postOccurrence]
                    }
                    return []
                }
            }
            .flatMap { $0 }
            .sorted {
                agendaOccurrencePrecedes(
                    $0,
                    $1,
                    briefByID: briefByID
                )
            }
    }
    private func filteredUndatedListPosts(
        snapshot: AgendaRenderSnapshot
    ) -> [AgendaUndatedPost] {
        guard !listStatusRequiresPostDate else { return [] }

        let briefByID = AgendaBriefIndexPolicy.index(activeBriefs)
        let datedOutputIDs = Set(snapshot.occurrences.map(\.output.id))
        return outputs
            .compactMap { output in
                guard !datedOutputIDs.contains(output.id),
                      let brief = briefByID[output.briefID],
                      matchesListFilters(brief: brief, output: output) else {
                    return nil
                }
                return AgendaUndatedPost(output: output, brief: brief)
            }
            .sorted {
                if $0.brief.updatedAt != $1.brief.updatedAt {
                    return $0.brief.updatedAt > $1.brief.updatedAt
                }
                return $0.brief.title.localizedCaseInsensitiveCompare($1.brief.title) == .orderedAscending
            }
    }
    private var listStatusRequiresPostDate: Bool {
        switch listStatusFilter {
        case .standard(.scheduled), .standard(.posted):
            true
        default:
            false
        }
    }
    private func matchesListFilters(
        brief: CreativeBrief,
        output: PlatformOutput
    ) -> Bool {
        guard !IdeaBankPlacementPolicy.includes(brief) else { return false }

        let matchesPillar: Bool
        switch listPillarFilter {
        case .all:
            matchesPillar = true
        case .unfiled:
            matchesPillar = brief.pillarID == nil
        case .pillar(let pillarID):
            matchesPillar = brief.pillarID == pillarID
        }

        let matchesStatus: Bool
        switch listStatusFilter {
        case .all:
            matchesStatus = true
        case .open:
            matchesStatus = AgendaOpenPostPolicy.includes(
                briefStatus: brief.status,
                outputStatus: output.status,
                ideaBankPlacement: brief.ideaBankPlacement
            )
        case .lateWork:
            matchesStatus = CyNoticedReconciliationPolicy.includes(brief: brief, output: output)
        case .standard(let status):
            switch status {
            case .draft:
                matchesStatus = output.status == .draft &&
                    brief.status != .developing &&
                    brief.resolvedCustomStatusLabel == nil
            case .inProgress:
                matchesStatus = output.status == .draft &&
                    brief.status == .developing &&
                    brief.resolvedCustomStatusLabel == nil
            case .scheduled:
                matchesStatus = output.status == .scheduled ||
                    brief.status == .scheduled
            case .posted:
                matchesStatus = output.status == .posted ||
                    brief.status == .posted
            }
        case .custom(let statusKey):
            matchesStatus = CustomPostStatusPolicy.comparisonKey(
                brief.resolvedCustomStatusLabel
            ) == statusKey
        }

        return matchesPillar && matchesStatus
    }
    private func listStatusOverride(
        for brief: CreativeBrief
    ) -> (text: String, status: PlatformOutputStatus)? {
        switch listStatusFilter {
        case .custom, .open:
            guard let customStatus = brief.resolvedCustomStatusLabel else { return nil }
            return (customStatus, .draft)
        default:
            return nil
        }
    }
    private func filteredListAgendaOutputGroups(
        occurrences: [AgendaPostOccurrence],
        briefByID: [UUID: CreativeBrief]
    ) -> [AgendaOutputDayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: occurrences) {
            calendar.startOfDay(for: $0.date)
        }
        return grouped.map { day, dayOccurrences in
            AgendaOutputDayGroup(
                day: day,
                occurrences: dayOccurrences.sorted {
                    agendaOccurrencePrecedes(
                        $0,
                        $1,
                        briefByID: briefByID
                    )
                }
            )
        }
    }
    private var availableListPillars: [Pillar] {
        pillars
            .filter { !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private var availableListCustomStatuses: [String] {
        var seen = Set<String>()
        var values = activeWorkspace?.customPostStatuses ?? []
        values.append(contentsOf: activeBriefs.compactMap(\.resolvedCustomStatusLabel))
        return values
            .compactMap(CustomPostStatusPolicy.normalized)
            .filter { status in
                guard let key = CustomPostStatusPolicy.comparisonKey(status) else {
                    return false
                }
                return seen.insert(key).inserted
            }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    private var selectedListPillarTitle: String {
        switch listPillarFilter {
        case .all:
            "All"
        case .unfiled:
            "No pillar"
        case .pillar(let pillarID):
            availableListPillars.first(where: { $0.id == pillarID })?.name ?? "All"
        }
    }
    private var selectedListPillarColor: Color? {
        guard case .pillar(let pillarID) = listPillarFilter,
              let pillar = availableListPillars.first(where: { $0.id == pillarID })
        else {
            return nil
        }
        return Color(agentHex: pillar.resolvedColorHex(in: pillars))
    }
    private var selectedListStatusTitle: String {
        switch listStatusFilter {
        case .all:
            "All"
        case .open:
            "Open posts"
        case .lateWork:
            "Late work"
        case .standard(let status):
            status.title
        case .custom(let statusKey):
            availableListCustomStatuses.first {
                CustomPostStatusPolicy.comparisonKey($0) == statusKey
            } ?? "Custom"
        }
    }
    private var hasActiveListFilter: Bool {
        listPillarFilter != .all || listStatusFilter != .defaultFilter
    }
    private func presentListEmptyStateCapture(_ mode: QuickCaptureLaunchMode) {
        appModel.quickCaptureTargetDate = nil
        if case .pillar(let pillarID) = listPillarFilter {
            appModel.quickCapturePillarID = pillarID
        } else {
            appModel.quickCapturePillarID = nil
        }
        appModel.setQuickCaptureMode(mode)
        appModel.presentedSheet = .quickCapture
    }
    private func clearAgendaListFilters() {
        performAgendaUpdate(animation: .snappy(duration: 0.2)) {
            listPillarFilter = .all
            listStatusFilter = .defaultFilter
        }
    }
    private func shiftCalendarMonth(_ amount: Int) {
        guard let newMonth = Calendar.current.date(
            byAdding: .month,
            value: amount,
            to: calendarMonthStart
        ) else { return }

        performAgendaUpdate(animation: .snappy(duration: 0.24)) {
            calendarMonth = newMonth
            selectedDay = newMonth
        }
    }

    private func performAgendaUpdate(
        animation: Animation,
        _ update: () -> Void
    ) {
        if AgendaMotionPolicy.usesAnimation(reduceMotion: reduceMotion) {
            withAnimation(animation, update)
        } else {
            update()
        }
    }
    private func agendaOccurrencePrecedes(
        _ lhs: AgendaPostOccurrence,
        _ rhs: AgendaPostOccurrence,
        briefByID: [UUID: CreativeBrief]
    ) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date < rhs.date
        }
        if lhs.kind.sortOrder != rhs.kind.sortOrder {
            return lhs.kind.sortOrder < rhs.kind.sortOrder
        }
        return AgendaOutputOrdering.precedes(
            lhs.output,
            briefStatus: briefByID[lhs.output.briefID]?.status,
            rhs.output,
            briefStatus: briefByID[rhs.output.briefID]?.status
        )
    }
    private func focus(on day: Date) -> ResolvedDailyFocus? { DailyFocusResolver.resolve(date: day, templates: focusTemplates, overrides: focusOverrides) }
    private func agendaFocusTitle(_ focus: ResolvedDailyFocus?) -> String {
        "\(focus?.title ?? "Rest") Day"
    }
    private func color(for brief: CreativeBrief) -> Color {
        guard let id = brief.pillarID, let pillar = pillars.first(where: { $0.id == id }) else { return .agentSecondary }
        return Color(agentHex: pillar.resolvedColorHex(in: pillars))
    }
    private func pillarHex(on day: Date) -> String? {
        guard let weekday = PillarWeekday(rawValue: Calendar.current.component(.weekday, from: day)),
              let pillar = pillars.first(where: {
                  !$0.isArchived && $0.resolvedWeekdays(in: pillars).contains(weekday)
              }) else { return nil }
        return pillar.resolvedColorHex(in: pillars)
    }

    private func calendarPillarHexByWeekday() -> [PillarWeekday: String] {
        var result: [PillarWeekday: String] = [:]
        for pillar in pillars where !pillar.isArchived {
            for weekday in pillar.resolvedWeekdays(in: pillars) where result[weekday] == nil {
                result[weekday] = pillar.resolvedColorHex(in: pillars)
            }
        }
        return result
    }

    private func accountLabel(for output: PlatformOutput) -> String? {
        output.socialAccountID.flatMap { id in socialAccounts.first { $0.id == id } }?.label
    }
}

#if DEBUG
private enum PreviewAgendaRuntimeFixture {
    static func initialDisplayMode(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AgendaDisplayMode? {
        guard let marker = arguments.firstIndex(of: "-agentCyPreviewAgendaMode"),
              arguments.indices.contains(marker + 1) else {
            return nil
        }
        return AgendaDisplayMode(rawValue: arguments[marker + 1])
    }
}
#endif

private struct AgendaFixedCalendarSurface<Header: View, Content: View>: View {
    let minimumHeight: CGFloat?
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    init(
        minimumHeight: CGFloat? = nil,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.minimumHeight = minimumHeight
        self.header = header()
        self.content = content()
    }

    private var contentMinimumHeight: CGFloat? {
        minimumHeight.map { max(0, $0 - 124) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AgentSpacing.x6)
                .padding(.top, AgentSpacing.x4)
                .padding(.bottom, AgentSpacing.x2)
                .background(
                    Color.agentSurface,
                    in: .rect(cornerRadius: AgentRadius.dashboard)
                )
                .agentSurfaceChrome(cornerRadius: AgentRadius.dashboard)
                // Leave room for the fixed card's shadow-border.
                .padding(.top, 2)
                .padding(.bottom, AgentSpacing.x3)

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AgentSpacing.x6)
                    .padding(.top, AgentSpacing.x6)
                    .agentBottomNavigationClearance()
                    .frame(
                        maxWidth: .infinity,
                        minHeight: contentMinimumHeight,
                        alignment: .topLeading
                    )
            }
            // The surface card remains fixed. Only its agenda rows scroll,
            // matching the Tasks page container behavior.
            .scrollIndicators(.hidden)
            .scrollClipDisabled(false)
            .background(Color.agentSurface)
            .clipShape(.rect(cornerRadius: AgentRadius.dashboard))
            .agentSurfaceChrome(cornerRadius: AgentRadius.dashboard)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

enum AgendaPillarDotPresentation {
    static func displayedHex(storedHex: String) -> String {
        storedHex
    }
}

struct AgendaMonthCalendarWeekdayHeader: Identifiable, Equatable {
    let weekday: PillarWeekday
    let symbol: String
    let pillarHex: String?

    var id: PillarWeekday { weekday }
}

enum AgendaMonthCalendarColorPolicy {
    static let showsPillarColorOnMonthDates = false

    static func weekdayHeaders(
        symbols: [String],
        firstWeekday: Int,
        pillarHexByWeekday: [PillarWeekday: String]
    ) -> [AgendaMonthCalendarWeekdayHeader] {
        guard symbols.count == PillarWeekday.allCases.count else { return [] }
        let normalizedFirstWeekday = min(max(firstWeekday, 1), symbols.count)

        return (0..<symbols.count).compactMap { offset in
            let symbolIndex = (normalizedFirstWeekday - 1 + offset) % symbols.count
            guard let weekday = PillarWeekday(rawValue: symbolIndex + 1) else { return nil }
            return AgendaMonthCalendarWeekdayHeader(
                weekday: weekday,
                symbol: symbols[symbolIndex],
                pillarHex: pillarHexByWeekday[weekday]
            )
        }
    }
}

enum AgendaCompactCalendarPolicy {
    static let maximumDynamicTypeSize: DynamicTypeSize = .large

    static func usesStackedCompletedDayLayout(
        dynamicTypeSize: DynamicTypeSize
    ) -> Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    static func showsWeekdayChips(dynamicTypeSize: DynamicTypeSize) -> Bool {
        !dynamicTypeSize.isAccessibilitySize
    }

    static func usesStackedListFilters(dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize.isAccessibilitySize
    }
}

enum AgendaCardTimePolicy {
    static func displayTime(
        kind: AgendaPostOccurrenceKind,
        occurrenceDate: Date,
        includesWorkTime: Bool,
        includesTargetTime: Bool
    ) -> Date? {
        switch kind {
        case .work:
            includesWorkTime ? occurrenceDate : nil
        case .post:
            includesTargetTime ? occurrenceDate : nil
        }
    }
}

enum AgendaBriefIndexPolicy {
    static func index(_ briefs: [CreativeBrief]) -> [UUID: CreativeBrief] {
        DuplicateSafeIndex.firstValues(briefs.map { ($0.id, $0) })
    }
}

enum AgendaMotionPolicy {
    static func usesAnimation(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}

enum AgendaOutputOrdering {
    static func rank(
        outputStatus: PlatformOutputStatus,
        briefStatus: BriefStatus?
    ) -> Int {
        switch TodayOutputPresentation.section(
            outputStatus: outputStatus,
            briefStatus: briefStatus
        ) {
        case .goingLive: 0
        case .inProgress: 1
        case .drafted: 2
        }
    }

    static func precedes(
        _ lhs: PlatformOutput,
        briefStatus lhsBriefStatus: BriefStatus?,
        _ rhs: PlatformOutput,
        briefStatus rhsBriefStatus: BriefStatus?
    ) -> Bool {
        let lhsRank = rank(outputStatus: lhs.status, briefStatus: lhsBriefStatus)
        let rhsRank = rank(outputStatus: rhs.status, briefStatus: rhsBriefStatus)
        if lhsRank != rhsRank { return lhsRank < rhsRank }

        let lhsDate = lhs.targetDate ?? .distantFuture
        let rhsDate = rhs.targetDate ?? .distantFuture
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

struct AgendaOutputState {
    let outputStatus: PlatformOutputStatus
    let briefStatus: BriefStatus?

    var needsRescheduling: Bool {
        TodayOutputPresentation.section(
            outputStatus: outputStatus,
            briefStatus: briefStatus
        ) == .goingLive && outputStatus != .posted
    }

    var isUnposted: Bool {
        outputStatus != .posted
    }
}

enum AgendaDayPresentation {
    static func weekdayMonthDayLabel(
        _ day: Date,
        locale: Locale = .current,
        calendar: Calendar = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE MMM d"
        return formatter.string(from: day)
    }

    static func trailingActionSymbol(hasPosts: Bool) -> String {
        hasPosts ? "chevron.right" : "plus"
    }

    static func postCountLabel(_ count: Int) -> String {
        "\(count) \(count == 1 ? "post" : "posts")"
    }

    static func compactPostCountLabel(_ count: Int) -> String? {
        count > 0 ? postCountLabel(count) : nil
    }

    static func showsPastDaySaveControl(
        day: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        calendar.startOfDay(for: day) < calendar.startOfDay(for: now)
    }

    static func showsSaveControl(
        day: Date,
        now: Date,
        hasChanges: Bool,
        calendar: Calendar = .current
    ) -> Bool {
        hasChanges && showsPastDaySaveControl(day: day, now: now, calendar: calendar)
    }

    static func allowsTaskCreation(
        day: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        calendar.startOfDay(for: day) >= calendar.startOfDay(for: now)
    }

    static func shouldCompact(
        day: Date,
        outputs: [AgendaOutputState],
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard calendar.startOfDay(for: day) < calendar.startOfDay(for: now) else { return false }
        return outputs.allSatisfy { !$0.isUnposted }
    }

    static func isOverdue(
        targetDate: Date?,
        status: PlatformOutputStatus,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard status != .posted, let targetDate else { return false }
        return calendar.startOfDay(for: targetDate) < calendar.startOfDay(for: now)
    }

}

enum DayAgendaPostGroup: Equatable {
    case production
    case scheduled
}

enum DayAgendaPostGrouping {
    static func group(
        outputStatus: PlatformOutputStatus,
        briefStatus: BriefStatus?
    ) -> DayAgendaPostGroup {
        TodayOutputPresentation.section(
            outputStatus: outputStatus,
            briefStatus: briefStatus
        ) == .goingLive ? .scheduled : .production
    }
}

enum AgendaPillarAssignment {
    static func apply(
        selectedPillarID: UUID?,
        weekday: PillarWeekday,
        pillars: [Pillar],
        briefs: [CreativeBrief],
        affectedBriefIDs: Set<UUID>
    ) {
        for pillar in pillars {
            var days = pillar.assignedWeekdays
            if pillar.id == selectedPillarID {
                days.insert(weekday)
            } else {
                days.remove(weekday)
            }
            pillar.assignedWeekdays = days
        }

        for brief in briefs where affectedBriefIDs.contains(brief.id) {
            brief.pillarID = selectedPillarID
            brief.updatedAt = Date()
        }
    }
}

struct AgendaDaySelection: Identifiable, Hashable {
    let day: Date

    var id: Date { Self.normalizedDay(day) }

    static func normalizedDay(_ day: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: day)
    }
}

private struct EpisodeNeededCard: View {
    let slot: SeriesEpisodeSlot
    let series: ContentSeries

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x3) {
                Text(series.name)
                    .font(.agentMetadata)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.agentSecondary)
                    .lineLimit(1)

                Spacer(minLength: AgentSpacing.x2)

                Text("Episode needed")
                    .font(.agentMetadata)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.actionAccent)
            }

            HStack(spacing: AgentSpacing.x3) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text("Plan this episode")
                        .font(.agentBody.weight(.semibold))
                        .foregroundStyle(Color.agentText)

                    Text(plannedDateText)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                }

                Spacer(minLength: AgentSpacing.x3)
                AgentIconView(.forward, size: 14)
                    .foregroundStyle(Color.agentSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AgentSpacing.x5)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.dashboard, style: .continuous)
                .stroke(
                    Color.actionAccent.opacity(0.42),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        }
    }

    private var plannedDateText: String {
        if slot.includesTime {
            return slot.plannedDate.formatted(
                .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
            )
        }
        return slot.plannedDate.formatted(
            .dateTime.weekday(.abbreviated).month(.abbreviated).day()
        )
    }
}

struct EpisodeSlotActionsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let slot: SeriesEpisodeSlot
    let onConverted: (SeriesEpisodePlanner.ConversionResult) -> Void
    @Query(sort: \ContentSeries.createdAt) private var allSeries: [ContentSeries]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt) private var allOutputs: [PlatformOutput]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var showsIdeas = false
    @State private var errorMessage: String?

    private var series: ContentSeries? {
        allSeries.first {
            $0.id == slot.seriesID &&
                WorkspaceScope.includes(
                    $0.workspaceID,
                    activeWorkspaceID: appModel.activeWorkspaceID,
                    workspaces: workspaces
                )
        }
    }

    private var savedIdeas: [CreativeBrief] {
        allBriefs.filter {
            WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            ) &&
                IdeaBankPlacementPolicy.includes($0)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    if let series {
                        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                            MetaLabel(series.name)
                            Text("Plan this episode")
                                .font(.agentTitle)
                            Text(plannedDateText)
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                        }

                        if showsIdeas {
                            SectionRuleHeader(title: "Idea Bank", trailing: "\(savedIdeas.count)")
                            if savedIdeas.isEmpty {
                                Text("No saved ideas yet.")
                                    .font(.agentSubtext)
                                    .foregroundStyle(Color.agentSecondary)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(savedIdeas) { idea in
                                        Button {
                                            convert(idea: idea, series: series)
                                        } label: {
                                            HStack(spacing: AgentSpacing.x3) {
                                                Text(idea.title)
                                                    .font(.agentBody.weight(.medium))
                                                    .foregroundStyle(Color.agentText)
                                                    .multilineTextAlignment(.leading)
                                                Spacer()
                                                AgentIconView(.forward, size: 13)
                                                    .foregroundStyle(Color.agentSecondary)
                                            }
                                            .frame(minHeight: 52)
                                            .contentShape(.rect)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        } else {
                            VStack(spacing: AgentSpacing.x3) {
                                episodeAction("Create New Episode") {
                                    convertNew(series: series)
                                }
                                episodeAction("Use an Idea Bank Idea") {
                                    showsIdeas = true
                                }
                                episodeAction("Duplicate Previous Episode") {
                                    duplicatePrevious(series: series)
                                }
                            }

                            Button("Skip this slot", role: .destructive) {
                                skip()
                            }
                            .font(.agentSubtext.weight(.semibold))
                            .frame(minHeight: 44)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.agentSubtext)
                                .foregroundStyle(Color.agentDestructive)
                        }
                    } else {
                        Text("This series is no longer available.")
                            .font(.agentBody)
                            .foregroundStyle(Color.agentSecondary)
                    }
                }
                .padding(AgentLayout.pageMargin)
            }
            .background(Color.agentCanvas)
            .navigationTitle(showsIdeas ? "Choose an Idea" : "Plan Episode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(showsIdeas ? "Back" : "Close") {
                        if showsIdeas {
                            showsIdeas = false
                        } else {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func episodeAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.agentBody.weight(.semibold))
                Spacer()
                AgentIconView(.forward, size: 13)
            }
            .foregroundStyle(Color.agentText)
            .frame(minHeight: 52)
            .padding(.horizontal, AgentSpacing.x4)
            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
            .agentSurfaceChrome(cornerRadius: AgentRadius.control, role: .card)
        }
        .buttonStyle(.plain)
    }

    private var plannedDateText: String {
        if slot.includesTime {
            return slot.plannedDate.formatted(
                .dateTime.weekday(.wide).month(.wide).day().hour().minute()
            )
        }
        return slot.plannedDate.formatted(
            .dateTime.weekday(.wide).month(.wide).day()
        )
    }

    private func convertNew(series: ContentSeries) {
        perform {
            try SeriesEpisodePlanner.convert(slot: slot, series: series, context: context)
        }
    }

    private func convert(idea: CreativeBrief, series: ContentSeries) {
        let output = allOutputs.first(where: { $0.briefID == idea.id })
        perform {
            try SeriesEpisodePlanner.convert(
                slot: slot,
                series: series,
                using: idea,
                output: output,
                context: context
            )
        }
    }

    private func duplicatePrevious(series: ContentSeries) {
        perform {
            try SeriesEpisodePlanner.duplicatePreviousEpisode(
                into: slot,
                series: series,
                context: context
            )
        }
    }

    private func perform(
        _ operation: () throws -> SeriesEpisodePlanner.ConversionResult
    ) {
        do {
            let result = try operation()
            onConverted(result)
            dismiss()
        } catch SeriesEpisodePlannerError.noPreviousEpisode {
            errorMessage = "Create the first episode before duplicating a previous one."
        } catch {
            errorMessage = "This episode could not be created. Your plan is unchanged."
        }
    }

    private func skip() {
        do {
            try SeriesEpisodePlanner.skip(slot, context: context)
            dismiss()
        } catch {
            errorMessage = "This episode could not be skipped. Your plan is unchanged."
        }
    }
}

struct DayAgendaView: View {
    let day: Date
    let referenceDate: Date
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt) private var allOutputs: [PlatformOutput]
    @Query(sort: \CreatorTask.createdAt) private var allTasks: [CreatorTask]
    @Query private var allPillars: [Pillar]
    @Query private var destinations: [PublishingDestination]
    @Query private var formats: [PublishingFormat]
    @Query(sort: \CreatorSocialAccount.sortOrder) private var allSocialAccounts: [CreatorSocialAccount]
    @Query private var allFocusTemplates: [DailyFocusTemplateEntry]
    @Query private var allFocusOverrides: [DailyFocusOverride]
    @Query(sort: \ContentSeries.createdAt) private var allSeries: [ContentSeries]
    @Query(sort: \SeriesEpisodeSlot.plannedDate) private var allEpisodeSlots: [SeriesEpisodeSlot]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var isChoosingPost = false
    @State private var draftPillarID: UUID?
    @State private var hasLoadedPillarDraft = false
    @State private var showPillarOverwriteConfirmation = false
    @State private var dismissAfterPillarSave = false
    @State private var baselineDaySignature: String?
    @State private var selectedPostTaskOutput: PlatformOutput?
    @State private var showPostTaskPicker = false
    @State private var isPillarPickerPresented = false
    // The picker confirms inside its own sheet. The old flow dismissed the
    // sheet and scheduled the alert one yield later, which Catalyst dropped
    // when the dismissal was still animating — leaving a stuck pending alert,
    // a stale draft pillar, and a Close button that could no longer dismiss.
    @State private var confirmsPillarSelectionInPicker = false
    @State private var selectedEpisodeSlot: SeriesEpisodeSlot?
    @State private var convertedEpisodeBrief: CreativeBrief?
    @State private var acceptsDayContentInteractions = false
    @State private var showAddLivePost = false

    private var briefs: [CreativeBrief] { scoped(allBriefs) }
    private var outputs: [PlatformOutput] { scoped(allOutputs) }
    private var tasks: [CreatorTask] { scoped(allTasks) }
    private var pillars: [Pillar] { scoped(allPillars) }
    private var socialAccounts: [CreatorSocialAccount] { scoped(allSocialAccounts) }
    private var focusTemplates: [DailyFocusTemplateEntry] { scoped(allFocusTemplates) }
    private var focusOverrides: [DailyFocusOverride] { scoped(allFocusOverrides) }
    private var seriesRecords: [ContentSeries] {
        scoped(allSeries).filter { $0.state != .archived }
    }
    private var episodeSlots: [SeriesEpisodeSlot] {
        scoped(allEpisodeSlots).filter {
            $0.status == .open && Calendar.current.isDate($0.plannedDate, inSameDayAs: day)
        }
    }

    private func scoped<T>(_ values: [T]) -> [T] where T: WorkspaceScopedRecord {
        values.filter {
            WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private var activeBriefs: [CreativeBrief] { briefs.filter { $0.status != .archived } }
    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
    private var activeBriefIDs: Set<UUID> { Set(activeBriefs.map(\.id)) }
    private var activeBriefByID: [UUID: CreativeBrief] {
        DuplicateSafeIndex.firstValues(activeBriefs.map { ($0.id, $0) })
    }
    private var dayOutputs: [PlatformOutput] {
        // Hoisted once per call. These lookups were computed properties that
        // re-filtered the whole brief store for every output — the sampler
        // caught this cascade saturating the main thread with the day open.
        let briefIndex = activeBriefByID
        let briefIDs = Set(briefIndex.keys)
        return outputs.filter {
            guard AgendaContentVisibility.includesOutput(
                briefID: $0.briefID,
                activeBriefIDs: briefIDs
            ), let brief = briefIndex[$0.briefID] else {
                return false
            }
            return AgendaDayOutputVisibility.includes(
                outputTargetDate: $0.targetDate,
                outputPostedAt: $0.postedAt,
                outputStatus: $0.status,
                briefWorkDate: brief.workDate,
                briefStatus: brief.status,
                day: day
            )
        }
        .sorted { lhs, rhs in
            AgendaOutputOrdering.precedes(
                lhs,
                briefStatus: briefIndex[lhs.briefID]?.status,
                rhs,
                briefStatus: briefIndex[rhs.briefID]?.status
            )
        }
    }
    private var dayTasks: [CreatorTask] {
        // One pass over the day's outputs; membership checks per task are set
        // lookups instead of recomputing dayOutputs (a full-store filter) for
        // every task.
        let outputsForDay = dayOutputs
        let dayOutputIDs = Set(outputsForDay.map(\.id))
        let dayOutputBriefIDs = Set(outputsForDay.map(\.briefID))
        let briefIDs = activeBriefIDs
        return tasks.filter {
            $0.parentTaskID == nil &&
                !$0.isSkipped &&
                AgendaContentVisibility.includesTask(briefID: $0.briefID, activeBriefIDs: briefIDs) &&
                taskBelongsToDay($0, dayOutputIDs: dayOutputIDs, dayOutputBriefIDs: dayOutputBriefIDs)
        }
        .sorted(by: sortTasks)
    }
    private var postTasks: [CreatorTask] {
        dayTasks.filter {
            TaskCollectionPolicy.collection(
                briefID: $0.briefID,
                platformOutputID: $0.platformOutputID
            ) == .postTasks
        }
    }
    private var myTasks: [CreatorTask] {
        dayTasks.filter {
            TaskCollectionPolicy.collection(
                briefID: $0.briefID,
                platformOutputID: $0.platformOutputID
            ) == .myTasks
        }
    }
    private var dayFocus: ResolvedDailyFocus? { DailyFocusResolver.resolve(date: day, templates: focusTemplates, overrides: focusOverrides) }

    var body: some View {
        let snapshot = makeDayRenderSnapshot()

        VStack(spacing: 0) {
#if targetEnvironment(macCatalyst)
            desktopDayNavigationHeader
#endif

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    EditorialHeader(
                        kicker: day.formatted(.dateTime.month(.abbreviated).day().year()),
                        title: Calendar.current.isDate(day, inSameDayAs: referenceDate)
                            ? "Today."
                            : day.formatted(.dateTime.weekday(.wide)),
                        subtitle: "Everything planned for this day."
                    )
                    .padding(.horizontal, AgentLayout.pageMargin)

                    dayPlanningShowcase
                        .padding(.horizontal, AgentLayout.dashboardGutter)
                        .padding(.top, AgentSpacing.x8)

                    AgentInsetSurface {
                        VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                            productionPostsSection(snapshot)
                            scheduledPostsSection(snapshot)
                            dayTaskCollection(
                                title: TaskCollection.myTasks.title,
                                tasks: snapshot.focusTasks,
                                snapshot: snapshot,
                                emptyMessage: "No focus tasks.",
                                taskTopPadding: AgentSpacing.x1,
                                addAction: addMyTaskForDay
                            )
                            postTasksSection(snapshot)
                        }
                    }
                    .padding(.horizontal, AgentLayout.dashboardGutter)
                    .padding(.top, AgentSpacing.x4)
                }
                .padding(.top, AgentSpacing.x6)
                .agentBottomNavigationClearance()
            }
            // A week-row tap can otherwise remain active long enough to trigger
            // whichever control appears beneath the same finger in this pushed
            // destination (for example Pillar on Monday or a task on Editing day).
            // Keep the navigation controls live, but arm the day content only
            // after the originating touch has fully ended.
            .allowsHitTesting(acceptsDayContentInteractions)
        }
#if targetEnvironment(macCatalyst)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
#else
        .navigationTitle(day.formatted(.dateTime.weekday(.wide)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if AgendaDayPresentation.showsSaveControl(
                day: day,
                now: referenceDate,
                hasChanges: hasDayChanges
            ) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: saveAndDismiss) {
                        AgentIconView(.check, size: 15)
                            .foregroundStyle(Color.agentPureBlack)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .tint(Color.agentPureWhite)
                    .accessibilityLabel("Save day")
                    .accessibilityHint("Saves your changes and returns to the week")
                }
            }
        }
#endif
        .confirmationDialog(
            "Add task to which post?",
            isPresented: $showPostTaskPicker,
            titleVisibility: .visible
        ) {
            ForEach(snapshot.dayOutputs) { output in
                if let brief = snapshot.briefByID[output.briefID] {
                    Button(displayTitle(for: output, brief: brief)) {
                        selectedPostTaskOutput = output
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $selectedPostTaskOutput) { output in
            if let brief = snapshot.briefByID[output.briefID] {
                PostDraftTaskComposer(
                    brief: brief,
                    output: output,
                    defaultDate: output.targetDate ?? day
                )
            }
        }
        .sheet(isPresented: $isPillarPickerPresented) {
            // Catalyst gets a fitted compact sheet like the posted-date picker;
            // iPhone-style height detents on the desktop made presentation
            // negotiate sizes against the window and open sluggishly.
            #if targetEnvironment(macCatalyst)
            pillarPickerSheetWithConfirmation
                .frame(width: 460, height: pillarPickerHeight)
                .presentationSizing(.fitted)
                .presentationCornerRadius(AgentRadius.floating)
                .presentationBackground(Color.agentCanvas)
            #else
            pillarPickerSheetWithConfirmation
                .presentationDetents([.height(pillarPickerHeight)])
                .agentSheetDragIndicator()
                .presentationBackground(Color.agentCanvas)
            #endif
        }
        .sheet(item: $selectedEpisodeSlot) { slot in
            EpisodeSlotActionsView(slot: slot) { result in
                convertedEpisodeBrief = result.brief
            }
        }
        .sheet(isPresented: $showAddLivePost, onDismiss: {
            baselineDaySignature = currentDaySignature
        }) {
            AddLivePostView(suggestedPostedAt: day)
                .environment(appModel)
                .presentationDetents([.large])
                .agentSheetDragIndicator()
        }
        .navigationDestination(isPresented: $isChoosingPost) {
            AgendaPostIdeaPickerView(day: day)
        }
        .navigationDestination(item: $convertedEpisodeBrief) { brief in
            if let output = snapshot.outputByBriefID[brief.id] {
                ResumablePostEditorView(brief: brief, output: output, onSpark: {})
                    .navigationTitle("Edit post")
                    .navigationBarTitleDisplayMode(.inline)
                    .agentScreen()
                    .agentKeyboardDismissal()
            } else {
                IdeaPostDraftView(brief: brief)
            }
        }
        .alert(pillarConfirmationTitle, isPresented: $showPillarOverwriteConfirmation) {
            Button("Cancel", role: .cancel) {
                cancelPillarOverwrite()
            }
            Button(pillarConfirmationActionTitle, role: .destructive) {
                applyPillarOverwrite()
            }
        } message: {
            Text(pillarConfirmationMessage)
        }
        .onAppear {
            if baselineDaySignature == nil {
                baselineDaySignature = currentDaySignature
            }
            guard !hasLoadedPillarDraft else { return }
            draftPillarID = assignedPillar?.id
            hasLoadedPillarDraft = true
        }
        .task(id: AgendaDaySelection.normalizedDay(day)) {
            acceptsDayContentInteractions = false
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            acceptsDayContentInteractions = true
        }
        .agentScreen()
    }

#if targetEnvironment(macCatalyst)
    private var desktopDayNavigationHeader: some View {
        AgentDesktopDetailRail(
            title: day.formatted(.dateTime.weekday(.wide)),
            backAction: dismiss.callAsFunction
        ) {
            if AgendaDayPresentation.showsSaveControl(
                day: day,
                now: referenceDate,
                hasChanges: hasDayChanges
            ) {
                AgentDesktopDetailIconButton(
                    title: "Save day",
                    icon: .check,
                    action: saveAndDismiss
                )
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
    }
#endif

    private func makeDayRenderSnapshot() -> DayAgendaRenderSnapshot {
        let calendar = Calendar.current
        let briefs = scoped(allBriefs).filter { $0.status != .archived }
        let briefByID = Dictionary(briefs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let activeBriefIDs = Set(briefByID.keys)
        let outputs = scoped(allOutputs)
        let outputByID = Dictionary(outputs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let outputByBriefID = Dictionary(outputs.map { ($0.briefID, $0) }, uniquingKeysWith: { first, _ in first })

        let dayOutputs = outputs.filter { output in
            guard AgendaContentVisibility.includesOutput(
                briefID: output.briefID,
                activeBriefIDs: activeBriefIDs
            ), let brief = briefByID[output.briefID] else {
                return false
            }
            return AgendaDayOutputVisibility.includes(
                outputTargetDate: output.targetDate,
                outputPostedAt: output.postedAt,
                outputStatus: output.status,
                briefWorkDate: brief.workDate,
                briefStatus: brief.status,
                day: day,
                calendar: calendar
            )
        }
        .sorted { lhs, rhs in
            AgendaOutputOrdering.precedes(
                lhs,
                briefStatus: briefByID[lhs.briefID]?.status,
                rhs,
                briefStatus: briefByID[rhs.briefID]?.status
            )
        }

        let dayOutputIDs = Set(dayOutputs.map(\.id))
        let dayBriefIDs = Set(dayOutputs.map(\.briefID))
        let tasks = scoped(allTasks)
        let dayTasks = tasks.filter { task in
            guard task.parentTaskID == nil,
                  !task.isSkipped,
                  AgendaContentVisibility.includesTask(
                    briefID: task.briefID,
                    activeBriefIDs: activeBriefIDs
                  ) else {
                return false
            }

            if task.dailyFocusDate.map({ calendar.isDate($0, inSameDayAs: day) }) == true ||
                task.targetDate.map({ calendar.isDate($0, inSameDayAs: day) }) == true {
                return true
            }
            if let outputID = task.platformOutputID, dayOutputIDs.contains(outputID) {
                return true
            }
            return task.briefID.map { dayBriefIDs.contains($0) } == true
        }
        .sorted(by: sortTasks)

        let postTasks = dayTasks.filter {
            TaskCollectionPolicy.collection(
                briefID: $0.briefID,
                platformOutputID: $0.platformOutputID
            ) == .postTasks
        }
        let focusTasks = dayTasks.filter {
            TaskCollectionPolicy.collection(
                briefID: $0.briefID,
                platformOutputID: $0.platformOutputID
            ) == .myTasks
        }

        let pillars = scoped(allPillars)
        let socialAccounts = scoped(allSocialAccounts)
        let series = scoped(allSeries).filter { $0.state != .archived }
        let episodeSlots = scoped(allEpisodeSlots).filter {
            $0.status == .open && calendar.isDate($0.plannedDate, inSameDayAs: day)
        }

        return DayAgendaRenderSnapshot(
            briefs: briefs,
            briefByID: briefByID,
            tasks: tasks,
            outputByID: outputByID,
            outputByBriefID: outputByBriefID,
            pillarByID: Dictionary(pillars.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            destinationByID: Dictionary(destinations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            formatByID: Dictionary(formats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            socialAccountByID: Dictionary(socialAccounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            seriesByID: Dictionary(series.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            episodeSlots: episodeSlots,
            dayOutputs: dayOutputs,
            dayTasks: dayTasks,
            postTasks: postTasks,
            focusTasks: focusTasks
        )
    }

    private func saveAndDismiss() {
        if hasPendingPillarChange {
            dismissAfterPillarSave = true
            showPillarOverwriteConfirmation = true
            return
        }
        do {
            try context.save()
            dismiss()
        } catch {
            appModel.notice = .error("Couldn’t save this day. Try again.")
        }
    }

    private func daySection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            Text(title)
                .font(.agentTitle)
                .foregroundStyle(Color.agentText)

            Rectangle()
                .fill(Color.agentHairline)
                .frame(height: 1)

            content()
        }
    }

    private var dayPlanningShowcase: some View {
        AgentInsetSurface {
#if targetEnvironment(macCatalyst)
            HStack(alignment: .top, spacing: AgentSpacing.x6) {
                focusShowcaseControl
                    .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color.agentHairline)
                    .frame(width: 1)
                    .padding(.vertical, AgentSpacing.x1)

                pillarShowcaseControl
                    .frame(maxWidth: .infinity)
            }
#else
            VStack(alignment: .leading, spacing: 0) {
                focusShowcaseControl

                Rectangle()
                    .fill(Color.agentHairline)
                    .frame(height: 1)
                    .padding(.vertical, AgentSpacing.x4)

                pillarShowcaseControl
            }
#endif
        }
    }

    private var focusShowcaseControl: some View {
        NavigationLink {
            DailyFocusDetailView(date: day)
        } label: {
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                HStack {
                    MetaLabel("Focus")
                    Spacer()
                    AgentIconView(.forward, size: 12)
                        .foregroundStyle(Color.agentSecondary)
                        .frame(width: 24, height: 24)
                }

                Text(dayFocusShowcaseTitle)
                    .font(.agentTitle)
                    .foregroundStyle(Color.agentText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Edit this day’s focus")
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(AgentPressButtonStyle())
        .accessibilityHint("Opens focus details")
    }

    private var pillarShowcaseControl: some View {
        Button {
            isPillarPickerPresented = true
        } label: {
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                HStack {
                    MetaLabel("Pillar")
                    Spacer()
                    AgentIconView(.expand, size: 12)
                        .foregroundStyle(Color.agentSecondary)
                        .frame(width: 24, height: 24)
                }

                HStack(spacing: AgentSpacing.x3) {
                    if let displayedPillar {
                        PillarColorMark(
                            color: Color(agentHex: displayedPillar.resolvedColorHex(in: activePillars)),
                            diameter: 12
                        )
                    }
                    Text(displayedPillar?.name ?? "Assign a pillar")
                        .font(.agentTitle)
                        .foregroundStyle(Color.agentText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(displayedPillar == nil
                    ? "Choose the pillar for \(weekday.title)"
                    : "Assigned every \(weekday.title)")
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(AgentPressButtonStyle())
        .accessibilityHint("Opens the pillar picker")
    }

    private var dayFocusShowcaseTitle: String {
        let title = dayFocus?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Rest"
        guard !title.lowercased().hasSuffix(" day") else { return title }
        return "\(title) Day"
    }

    private var pillarPickerSheetWithConfirmation: some View {
        pillarPickerSheet
            .alert(pillarConfirmationTitle, isPresented: $confirmsPillarSelectionInPicker) {
                Button("Cancel", role: .cancel) {
                    cancelPillarOverwrite()
                }
                Button(pillarConfirmationActionTitle, role: .destructive) {
                    applyPillarOverwrite()
                    isPillarPickerPresented = false
                }
            } message: {
                Text(pillarConfirmationMessage)
            }
    }

    private var pillarPickerSheet: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .center) {
                Text("Choose a pillar")
                    .font(.agentTitle)
                    .foregroundStyle(Color.agentText)

                Spacer()

                AgentToolbarIconButton(title: "Close", icon: .close) {
                    isPillarPickerPresented = false
                }
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            }

            VStack(spacing: 0) {
                pillarPickerChoice(
                    title: "No pillar",
                    isSelected: displayedPillar == nil
                ) {
                    choosePillar(nil)
                }

                ForEach(activePillars) { pillar in
                    Rectangle()
                        .fill(Color.agentHairline)
                        .frame(height: 1)

                    pillarPickerChoice(
                        title: pillar.name,
                        color: Color(agentHex: pillar.resolvedColorHex(in: activePillars)),
                        isSelected: displayedPillar?.id == pillar.id
                    ) {
                        choosePillar(pillar)
                    }
                }
            }
            .padding(.horizontal, AgentSpacing.x4)
            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
        }
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x4)
        .padding(.bottom, AgentSpacing.x6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func pillarPickerChoice(
        title: String,
        color: Color? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AgentSpacing.x3) {
                if let color {
                    PillarColorMark(color: color, diameter: 10)
                }

                Text(title)
                    .font(.agentBody)
                    .foregroundStyle(Color.agentText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    AgentIconView(.check, size: 13)
                        .foregroundStyle(Color.agentText)
                }
            }
            .frame(minHeight: 54)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var pillarPickerHeight: CGFloat {
        min(560, max(220, CGFloat((activePillars.count + 1) * 55) + 112))
    }

    private var weekday: PillarWeekday {
        PillarWeekday(rawValue: Calendar.current.component(.weekday, from: day)) ?? .monday
    }

    private var assignedPillar: Pillar? {
        activePillars.first { $0.assignedWeekdays.contains(weekday) }
    }

    private var displayedPillar: Pillar? {
        guard hasLoadedPillarDraft else { return assignedPillar }
        return activePillars.first { $0.id == draftPillarID }
    }

    private var hasPendingPillarChange: Bool {
        hasLoadedPillarDraft && draftPillarID != assignedPillar?.id
    }

    private var hasDayChanges: Bool {
        hasPendingPillarChange || baselineDaySignature.map { $0 != currentDaySignature } == true
    }

    private var currentDaySignature: String {
        // Computed on every body evaluation via hasDayChanges: reuse the one
        // shared index instead of building a second dictionary.
        let briefByID = activeBriefByID
        let outputSignature = dayOutputs.map { output in
            let brief = briefByID[output.briefID]
            return [
                output.id.uuidString,
                output.status.rawValue,
                String(output.targetDate?.timeIntervalSinceReferenceDate ?? -1),
                brief?.title ?? "",
                brief?.pillarID?.uuidString ?? ""
            ].joined(separator: "|")
        }
        .sorted()
        .joined(separator: ";")

        let taskSignature = dayTasks.map { task in
            [
                task.id.uuidString,
                task.title,
                String(task.isCompleted),
                String(task.targetDate?.timeIntervalSinceReferenceDate ?? -1)
            ].joined(separator: "|")
        }
        .sorted()
        .joined(separator: ";")

        return [
            assignedPillar?.id.uuidString ?? "",
            dayFocus?.title ?? "Rest",
            outputSignature,
            taskSignature
        ].joined(separator: "::")
    }

    private var isPastDay: Bool {
        AgendaDayPresentation.showsPastDaySaveControl(day: day, now: referenceDate)
    }

    private func choosePillar(_ selected: Pillar?) {
        guard selected?.id != displayedPillar?.id else {
            isPillarPickerPresented = false
            return
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            draftPillarID = selected?.id
            hasLoadedPillarDraft = true
        }

        if isPastDay {
            // Past days confirm through the day's save control instead.
            isPillarPickerPresented = false
        } else {
            dismissAfterPillarSave = false
            confirmsPillarSelectionInPicker = true
        }
    }

    private var pillarConfirmationTitle: String {
        draftPillarID == nil
            ? "Remove \(weekday.title)'s pillar?"
            : "Replace \(weekday.title)'s pillar?"
    }

    private var pillarConfirmationActionTitle: String {
        draftPillarID == nil ? "Remove & save" : "Replace & save"
    }

    private var pillarConfirmationMessage: String {
        let count = dayOutputs.count
        let postLabel = "\(count) \(count == 1 ? "post" : "posts")"
        let dateLabel = day.formatted(.dateTime.month(.abbreviated).day())

        if let displayedPillar {
            return "\(displayedPillar.name) will replace the pillar assigned to \(weekday.title). The \(postLabel) on \(dateLabel) will also move to \(displayedPillar.name)."
        }
        return "\(weekday.title) will have no assigned pillar. The \(postLabel) on \(dateLabel) will become unfiled."
    }

    private func cancelPillarOverwrite() {
        draftPillarID = assignedPillar?.id
        dismissAfterPillarSave = false
    }

    private func applyPillarOverwrite() {
        let selectedPillarID = draftPillarID
        let affectedBriefIDs = Set(dayOutputs.map(\.briefID))
        AgendaPillarAssignment.apply(
            selectedPillarID: selectedPillarID,
            weekday: weekday,
            pillars: activePillars,
            briefs: activeBriefs,
            affectedBriefIDs: affectedBriefIDs
        )
        do {
            try context.save()
        } catch {
            context.rollback()
            appModel.notice = .error("Couldn’t replace the pillar for this day. Try again.")
            dismissAfterPillarSave = false
            return
        }
        WidgetSnapshotService.refresh(context: context)

        if dismissAfterPillarSave {
            dismissAfterPillarSave = false
            dismiss()
        }
    }

    private func productionPostsSection(_ snapshot: DayAgendaRenderSnapshot) -> some View {
        daySection(title: "In production") {
            dayPostsList(
                outputs: snapshot.dayOutputs.filter {
                    DayAgendaPostGrouping.group(
                        outputStatus: $0.status,
                        briefStatus: snapshot.briefByID[$0.briefID]?.status
                    ) == .production
                },
                episodeSlots: snapshot.episodeSlots,
                snapshot: snapshot,
                emptyMessage: "No posts in production.",
                showsScheduleActions: false
            )
        }
    }

    private func scheduledPostsSection(_ snapshot: DayAgendaRenderSnapshot) -> some View {
        daySection(title: "Scheduled posts") {
            dayPostsList(
                outputs: snapshot.dayOutputs.filter {
                    DayAgendaPostGrouping.group(
                        outputStatus: $0.status,
                        briefStatus: snapshot.briefByID[$0.briefID]?.status
                    ) == .scheduled
                },
                episodeSlots: [],
                snapshot: snapshot,
                emptyMessage: "No scheduled posts.",
                showsScheduleActions: true
            )
        }
    }

    private func dayPostsList(
        outputs: [PlatformOutput],
        episodeSlots: [SeriesEpisodeSlot],
        snapshot: DayAgendaRenderSnapshot,
        emptyMessage: String,
        showsScheduleActions: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if outputs.isEmpty && episodeSlots.isEmpty {
                Text(emptyMessage)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .padding(.vertical, AgentSpacing.x4)
            } else {
                VStack(spacing: AgentSpacing.x3) {
                    ForEach(outputs) { output in
                        if let brief = snapshot.briefByID[output.briefID] {
                            NavigationLink { PostOutputDetailView(brief: brief, output: output) } label: {
                                AgentPostCard(
                                    title: brief.title,
                                    pillar: pillarLabel(for: brief, snapshot: snapshot),
                                    accent: color(for: brief, snapshot: snapshot),
                                    status: output.status,
                                    metadata: outputLabel(output, snapshot: snapshot),
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
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    ForEach(episodeSlots) { slot in
                        if let series = snapshot.seriesByID[slot.seriesID] {
                            Button {
                                selectedEpisodeSlot = slot
                            } label: {
                                EpisodeNeededCard(slot: slot, series: series)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if showsScheduleActions {
                HStack(spacing: AgentSpacing.x3) {
                    AgentBlockAddActionButton(title: "Schedule post") { isChoosingPost = true }
                    AgentBlockAddActionButton(title: "Add live post") { showAddLivePost = true }
                }
                .padding(.top, AgentSpacing.x6)
            }
        }
    }

    private func postTasksSection(_ snapshot: DayAgendaRenderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            dayTaskCollection(
                title: TaskCollection.postTasks.title,
                tasks: snapshot.postTasks,
                snapshot: snapshot,
                emptyMessage: "No post tasks.",
                addAction: addPostTaskForDay
            )

            Button {
                appModel.selectedTab = .tasks
            } label: {
                HStack {
                    Text("See all tasks").font(.agentSubtext.weight(.medium))
                    Spacer()
                    AgentIconView(.arrowRight)
                }
                .foregroundStyle(Color.agentText)
                .padding(.top, AgentSpacing.x3)
                .frame(minHeight: 44)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.agentHairline).frame(height: 1)
                }
                .contentShape(.rect)
            }
            .buttonStyle(AgentPressButtonStyle())
        }
    }

    @ViewBuilder
    private func dayTaskCollection(
        title: String,
        tasks collectionTasks: [CreatorTask],
        snapshot: DayAgendaRenderSnapshot,
        emptyMessage: String,
        taskTopPadding: CGFloat = 0,
        addAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: title, trailing: "\(collectionTasks.count)")

            if collectionTasks.isEmpty {
                Text(emptyMessage)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .padding(.vertical, AgentSpacing.x4)
            } else {
                let groups = dueDateGroups(for: collectionTasks)
                if groups.count > 1 {
                    ForEach(groups) { group in
                        taskGroupHeader(group)
                        taskRows(group.tasks, snapshot: snapshot)
                    }
                } else {
                    taskRows(collectionTasks, snapshot: snapshot)
                        .padding(.top, taskTopPadding)
                }
            }

            AgentBlockAddActionButton(title: "Add task", action: addAction)
                .padding(.top, AgentSpacing.x3)
        }
    }

    private func addPostTaskForDay() {
        guard !dayOutputs.isEmpty else {
            appModel.notice = .info("Schedule a post before adding a post task.")
            return
        }
        if dayOutputs.count == 1 {
            selectedPostTaskOutput = dayOutputs[0]
        } else {
            showPostTaskPicker = true
        }
    }

    private func addMyTaskForDay() {
        appModel.quickCaptureTargetDate = day
        appModel.quickCapturePillarID = nil
        appModel.quickCaptureTaskLane = .production
        appModel.quickCaptureTaskFocus = dayFocus.map {
            DailyFocusTaskAssignment(
                date: day,
                title: $0.title,
                taskKind: $0.kinds.first?.taskKind ?? .planning,
                templateEntryID: $0.templateEntryID
            )
        }
        appModel.setQuickCaptureMode(.task)
        appModel.presentedSheet = .quickCapture
    }

    private func displayTitle(for output: PlatformOutput, brief: CreativeBrief) -> String {
        let override = output.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? brief.title : override
    }

    private func taskRows(
        _ collectionTasks: [CreatorTask],
        snapshot: DayAgendaRenderSnapshot
    ) -> some View {
        ForEach(collectionTasks) { task in
            TaskRow(
                task: task,
                allTasks: snapshot.tasks,
                linkedPostTitle: linkedPostTitle(for: task, snapshot: snapshot)
            )
        }
    }

    private func taskGroupHeader(_ group: TaskDueDateGroup) -> some View {
        HStack {
            MetaLabel(group.title)
            Spacer()
            MetaLabel("\(group.tasks.count)")
        }
        .padding(.top, AgentSpacing.x4)
        .padding(.bottom, AgentSpacing.x2)
    }

    private func dueDateGroups(for collectionTasks: [CreatorTask]) -> [TaskDueDateGroup] {
        Dictionary(grouping: collectionTasks) { task in
            task.targetDate.map(Calendar.current.startOfDay(for:))
        }
        .map { TaskDueDateGroup(day: $0.key, tasks: $0.value.sorted(by: sortTasks)) }
        .sorted { lhs, rhs in
            switch (lhs.day, rhs.day) {
            case let (left?, right?): left < right
            case (nil, _?): false
            case (_?, nil): true
            case (nil, nil): false
            }
        }
    }

    private func sortTasks(_ lhs: CreatorTask, _ rhs: CreatorTask) -> Bool {
        let rank: (CreatorTask) -> Int = { task in
            task.priority.normalized == .urgent ? 0 : (task.priority.normalized == .high ? 1 : 2)
        }
        if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
        if (lhs.targetDate ?? .distantFuture) != (rhs.targetDate ?? .distantFuture) {
            return (lhs.targetDate ?? .distantFuture) < (rhs.targetDate ?? .distantFuture)
        }
        return lhs.createdAt < rhs.createdAt
    }

    private func taskBelongsToDay(
        _ task: CreatorTask,
        dayOutputIDs: Set<UUID>,
        dayOutputBriefIDs: Set<UUID>
    ) -> Bool {
        if task.dailyFocusDate.map({ Calendar.current.isDate($0, inSameDayAs: day) }) == true ||
            task.targetDate.map({ Calendar.current.isDate($0, inSameDayAs: day) }) == true {
            return true
        }

        if let outputID = task.platformOutputID, dayOutputIDs.contains(outputID) {
            return true
        }

        return task.briefID.map { dayOutputBriefIDs.contains($0) } == true
    }

    private func linkedPostTitle(
        for task: CreatorTask,
        snapshot: DayAgendaRenderSnapshot
    ) -> String? {
        let output = task.platformOutputID.flatMap { snapshot.outputByID[$0] }
        let briefID = task.briefID ?? output?.briefID
        guard let briefID,
              let brief = snapshot.briefByID[briefID] else { return nil }
        let override = output?.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return override.isEmpty ? brief.title : override
    }

    private func color(
        for brief: CreativeBrief,
        snapshot: DayAgendaRenderSnapshot
    ) -> Color {
        guard let id = brief.pillarID,
              let pillar = snapshot.pillarByID[id] else { return .agentSecondary }
        return Color(agentHex: pillar.colorHex)
    }

    private func pillarLabel(
        for brief: CreativeBrief,
        snapshot: DayAgendaRenderSnapshot
    ) -> String {
        guard let id = brief.pillarID,
              let pillar = snapshot.pillarByID[id] else { return "Unfiled" }
        return pillar.name
    }

    private func outputLabel(
        _ output: PlatformOutput,
        snapshot: DayAgendaRenderSnapshot
    ) -> String {
        let destination = output.destinationID.flatMap { snapshot.destinationByID[$0] }?.name
        let format = output.formatID.flatMap { snapshot.formatByID[$0] }?.name
        let account = output.socialAccountID.flatMap { snapshot.socialAccountByID[$0] }?.label
        return [destination, format, account].compactMap { $0 }.joined(separator: " · ")
    }
}

enum AgendaContentVisibility {
    static func includesOutput(briefID: UUID, activeBriefIDs: Set<UUID>) -> Bool {
        activeBriefIDs.contains(briefID)
    }

    static func includesTask(briefID: UUID?, activeBriefIDs: Set<UUID>) -> Bool {
        guard let briefID else { return true }
        return activeBriefIDs.contains(briefID)
    }
}

enum AgendaDayOutputVisibility {
    static func includes(
        outputTargetDate: Date?,
        outputPostedAt: Date? = nil,
        outputStatus: PlatformOutputStatus,
        briefWorkDate: Date?,
        briefStatus: BriefStatus,
        day: Date,
        calendar: Calendar = .current
    ) -> Bool {
        if outputStatus == .posted, let outputPostedAt {
            return calendar.isDate(outputPostedAt, inSameDayAs: day)
        }
        if let outputTargetDate, calendar.isDate(outputTargetDate, inSameDayAs: day) {
            return true
        }

        guard outputStatus != .posted,
              briefStatus != .posted,
              briefStatus != .archived,
              let briefWorkDate else {
            return false
        }
        return calendar.isDate(briefWorkDate, inSameDayAs: day)
    }
}

private struct DayAgendaRenderSnapshot {
    let briefs: [CreativeBrief]
    let briefByID: [UUID: CreativeBrief]
    let tasks: [CreatorTask]
    let outputByID: [UUID: PlatformOutput]
    let outputByBriefID: [UUID: PlatformOutput]
    let pillarByID: [UUID: Pillar]
    let destinationByID: [UUID: PublishingDestination]
    let formatByID: [UUID: PublishingFormat]
    let socialAccountByID: [UUID: CreatorSocialAccount]
    let seriesByID: [UUID: ContentSeries]
    let episodeSlots: [SeriesEpisodeSlot]
    let dayOutputs: [PlatformOutput]
    let dayTasks: [CreatorTask]
    let postTasks: [CreatorTask]
    let focusTasks: [CreatorTask]
}

struct PostRescheduleSheet: View {
    let output: PlatformOutput
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    private let minimumDate: Date
    @State private var targetDate: Date
    @State private var includesTime: Bool

    init(output: PlatformOutput) {
        let now = Date()
        self.output = output
        minimumDate = now
        _targetDate = State(initialValue: max(output.targetDate ?? now, now))
        _includesTime = State(initialValue: output.includesTargetTime)
    }

    var body: some View {
#if targetEnvironment(macCatalyst)
        desktopBody
#else
        standardBody
#endif
    }

    private var standardBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                    EditorialHeader(
                        kicker: "Due date",
                        title: "Choose a new date.",
                        subtitle: "Move this post without changing the rest of your week."
                    )

                    VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                        MetaLabel("New date")
                        DatePicker(
                            "Date",
                            selection: $targetDate,
                            in: minimumDate...,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .tint(Color.cyAccent)

                        Toggle("Include a time", isOn: $includesTime)
                            .font(.agentBody.weight(.semibold))
                            .tint(Color.actionAccent)

                        if includesTime {
                            DatePicker("Time", selection: $targetDate, displayedComponents: .hourAndMinute)
                        }
                    }
                    .padding(AgentSpacing.x4)
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))

                    Button("Save new date", action: saveAndDismiss)
                    .buttonStyle(AgentPrimaryButtonStyle())
                }
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x6)
                .padding(.bottom, AgentSpacing.x12)
            }
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .agentScreen()
        }
    }

#if targetEnvironment(macCatalyst)
    private var desktopBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: AgentSpacing.x3) {
                Text("Reschedule post")
                    .font(.agentHeadline)
                    .foregroundStyle(Color.agentText)
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    AgentIconView(.close, size: 14)
                        .frame(width: 40, height: 40)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel")
            }
            .padding(.leading, AgentSpacing.x5)
            .padding(.trailing, AgentSpacing.x3)
            .padding(.top, AgentSpacing.x3)

            VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                Text("Choose a new scheduled date.")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)

                PillarCalendarDatePicker(
                    date: $targetDate,
                    pillarMarkers: [],
                    minimumDate: minimumDate,
                    cellHeight: 38,
                    dayDiameter: 28
                )
                .padding(AgentSpacing.x4)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.card)
                        .stroke(Color.agentBorder, lineWidth: 1)
                }

                VStack(spacing: 0) {
                    Toggle("Include a time", isOn: $includesTime)
                        .font(.agentBody.weight(.medium))
                        .tint(Color.actionAccent)
                        .padding(.horizontal, AgentSpacing.x4)
                        .frame(minHeight: 52)

                    if includesTime {
                        Divider().overlay(Color.agentHairline)
                        HStack {
                            Text("Time").font(.agentBody)
                            Spacer()
                            DatePicker(
                                "Time",
                                selection: $targetDate,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                        }
                        .padding(.horizontal, AgentSpacing.x4)
                        .frame(minHeight: 52)
                    }
                }
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .stroke(Color.agentBorder, lineWidth: 1)
                }
            }
            .padding(.horizontal, AgentSpacing.x5)
            .padding(.top, AgentSpacing.x2)
            .padding(.bottom, AgentSpacing.x5)

            Divider().overlay(Color.agentHairline)

            HStack(spacing: AgentSpacing.x3) {
                Button("Cancel") { dismiss() }
                    .font(.agentSubtext.weight(.medium))
                    .foregroundStyle(Color.agentSecondary)
                    .frame(width: 92)
                    .frame(minHeight: 44)
                    .contentShape(.rect(cornerRadius: AgentRadius.card))
                    .buttonStyle(.plain)

                Button(action: saveAndDismiss) {
                    Text("Save new date")
                        .font(.agentSubtext.weight(.medium))
                        .foregroundStyle(Color.agentText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.card))
                        .overlay {
                            RoundedRectangle(cornerRadius: AgentRadius.card)
                                .stroke(Color.agentBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(AgentSpacing.x4)
        }
        .frame(width: 500)
        .background(Color.agentCanvas)
        .agentScreen()
        .presentationSizing(.fitted)
        .presentationCornerRadius(AgentRadius.floating)
        .presentationBackground(Color.agentCanvas)
    }
#endif

    private func saveAndDismiss() {
        output.includesTargetTime = includesTime
        let resolvedDate = includesTime
            ? targetDate
            : Calendar.current.startOfDay(for: targetDate)
        appModel.schedule(output: output, date: resolvedDate, context: context)
        dismiss()
    }
}
