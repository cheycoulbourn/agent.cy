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
    case standard(AgendaListStandardStatus)
    case custom(String)

    static let defaultFilter: Self = .open
}

private enum AgendaPostOccurrenceKind: String, Hashable {
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

private struct AgendaRenderSnapshot {
    let briefByID: [UUID: CreativeBrief]
    let occurrences: [AgendaPostOccurrence]
    let occurrencesByDay: [Date: [AgendaPostOccurrence]]
    let tasksByDay: [Date: [CreatorTask]]

    func occurrences(on day: Date, calendar: Calendar = .current) -> [AgendaPostOccurrence] {
        occurrencesByDay[calendar.startOfDay(for: day)] ?? []
    }

    func tasks(on day: Date, calendar: Calendar = .current) -> [CreatorTask] {
        tasksByDay[calendar.startOfDay(for: day)] ?? []
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
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt) private var allOutputs: [PlatformOutput]
    @Query(sort: \CreatorTask.createdAt) private var allTasks: [CreatorTask]
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

    private var briefs: [CreativeBrief] { scoped(allBriefs) }
    private var outputs: [PlatformOutput] { scoped(allOutputs) }
    private var tasks: [CreatorTask] { scoped(allTasks) }
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
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let daysSinceMonday = (calendar.component(.weekday, from: today) + 5) % 7
        let current = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        return calendar.date(byAdding: .weekOfYear, value: weekOffset, to: current) ?? current
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
        showsHeader: Bool = true
    ) {
        _weekOffset = weekOffset
        _selectedDay = selectedDay
        self.showsHeader = showsHeader
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
                        agendaListView
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
            DayAgendaView(day: selection.day)
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

    private var agendaModeRail: some View {
        Picker("Agenda view", selection: $displayMode) {
            ForEach(AgendaDisplayMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
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

    private var calendarStrip: some View {
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
        .padding(.horizontal, -AgentSpacing.x2)
        .padding(.bottom, AgentSpacing.x4)
    }

    private func calendarDay(_ day: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        let dotColor = pillarHex(on: day).map {
            Color(agentHex: AgendaPillarDotPresentation.displayedHex(storedHex: $0))
        }
        return Button {
            withAnimation(.snappy(duration: 0.24)) {
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
        let selectedTasks = snapshot.tasks(on: selectedDay)
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
                                            brief: brief,
                                            day: selectedDay,
                                            dayTasks: selectedTasks
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

        return VStack(spacing: AgentSpacing.x2) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: AgentSpacing.x1), count: 7),
                spacing: AgentSpacing.x2
            ) {
                ForEach(Array(calendarWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.agentMetadata)
                        .foregroundStyle(Color.agentSecondary)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .accessibilityHidden(true)
                }

                ForEach(calendarMonthDays, id: \.self) { day in
                    calendarMonthCell(
                        day,
                        postCount: snapshot.occurrences(on: day).count,
                        pillarHex: PillarWeekday(
                            rawValue: Calendar.current.component(.weekday, from: day)
                        ).flatMap { pillarHexByWeekday[$0] }
                    )
                }
            }
        }
    }

    private func calendarMonthCell(
        _ day: Date,
        postCount: Int,
        pillarHex: String?
    ) -> some View {
        let calendar = Calendar.current
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        let isCurrentMonth = calendar.isDate(day, equalTo: calendarMonthStart, toGranularity: .month)
        let dotColor = pillarHex.map {
            Color(agentHex: AgendaPillarDotPresentation.displayedHex(storedHex: $0))
        }

        return Button {
            withAnimation(.snappy(duration: 0.22)) {
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
                    if let dotColor {
                        PillarColorMark(color: dotColor, diameter: 6)
                            .overlay {
                                Circle()
                                    .stroke(Color.agentText.opacity(0.2), lineWidth: 0.5)
                            }
                    }
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

    private var agendaListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x5) {
                agendaListFilters

                if upcomingAgendaGroups.isEmpty &&
                    pastAgendaGroups.isEmpty &&
                    filteredUndatedListPosts.isEmpty {
                    agendaListEmptyState
                } else {
                    agendaListSection(title: "Upcoming", groups: upcomingAgendaGroups)
                    agendaListSection(title: "Past", groups: pastAgendaGroups)
                    agendaUndatedListSection
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

    private var agendaListFilters: some View {
        HStack(spacing: AgentSpacing.x3) {
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

            Button {
                isListStatusFilterPresented = true
            } label: {
                agendaListFilterLabel(
                    category: "Status",
                    value: selectedListStatusTitle
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
        filter: AgendaListStatusFilter
    ) -> some View {
        Button {
            listStatusFilter = filter
            isListStatusFilterPresented = false
        } label: {
            HStack(spacing: AgentSpacing.x3) {
                Text(title)
                    .font(.agentBody)
                    .foregroundStyle(Color.agentText)
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
        color: Color? = nil
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
                    .foregroundStyle(Color.agentText)
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
                                        day: group.day,
                                        dayTasks: tasks(on: group.day),
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
    private var agendaUndatedListSection: some View {
        if !filteredUndatedListPosts.isEmpty {
            AgentInsetSurface {
                VStack(alignment: .leading, spacing: AgentSpacing.x5) {
                    SectionRuleHeader(
                        title: "No date",
                        trailing: AgendaDayPresentation.postCountLabel(
                            filteredUndatedListPosts.count
                        )
                    )

                    ForEach(filteredUndatedListPosts) { item in
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
        let dayTasks = snapshot.tasks(on: day)
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
            now: Date()
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
                            brief: brief,
                            day: day,
                            dayTasks: dayTasks
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
            HStack(spacing: AgentSpacing.x3) {
                Text(day.formatted(.dateTime.weekday(.abbreviated).day()))
                    .font(.agentMetadata)
                    .textCase(.uppercase)
                    .frame(width: 56, alignment: .leading)
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
                        .font(.agentMetadata.weight(Calendar.current.isDateInToday(day) ? .semibold : .medium))
                        .textCase(.uppercase)
                        .foregroundStyle(Calendar.current.isDateInToday(day) ? Color.cyAccent : Color.agentText)
                        .fixedSize()

                    Text(agendaFocusTitle(focus))
                        .font(.agentBody.weight(.medium))
                        .lineLimit(1)
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
        day: Date,
        dayTasks: [CreatorTask],
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
            section == .goingLive &&
            AgendaDayPresentation.isOverdue(
            targetDate: occurrence.date,
            status: output.status,
            now: Date()
        )
        let accent = pillarAccent(for: brief)
        let firstTaskDate = firstTaskDate(for: output, dayTasks: dayTasks)
        let isScheduledDraftOccurrence = occurrence.kind == .post && displaysAsDraft
        let inferredDisplayStatus: PlatformOutputStatus = if isScheduledDraftOccurrence {
            .scheduled
        } else if displaysAsDraft {
            .draft
        } else {
            output.status
        }
        let displayStatus = displayStatusOverride ?? inferredDisplayStatus
        let displayTime: Date? = switch occurrence.kind {
        case .work:
            brief.includesWorkTime ? occurrence.date : nil
        case .post:
            firstTaskDate ?? (output.includesTargetTime ? occurrence.date : nil)
        }
        let statusText: String
        if let statusTextOverride {
            statusText = statusTextOverride
        } else if overdue {
            statusText = "Missed"
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
        day.formatted(.dateTime.weekday(.abbreviated).day())
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

    private func firstTaskDate(for output: PlatformOutput, dayTasks: [CreatorTask]) -> Date? {
        let linkedTasks = dayTasks.filter {
            $0.platformOutputID == output.id || $0.briefID == output.briefID
        }
        let sourceTasks = linkedTasks.isEmpty ? dayTasks : linkedTasks
        let candidates = sourceTasks.map { $0.includesTargetTime ? $0.targetDate : nil }
        return AgendaDayPresentation.firstTaskDate(in: candidates)
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
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
    private func moveWeek(_ amount: Int) {
        withAnimation(.snappy) {
            weekOffset += amount
            selectedDay = Calendar.current.date(byAdding: .weekOfYear, value: amount, to: selectedDay) ?? weekStart
        }
    }
    private func targetWeekOffset(containing day: Date) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let daysSinceMonday = (calendar.component(.weekday, from: today) + 5) % 7
        let currentWeekStart = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        let targetDaysSinceMonday = (calendar.component(.weekday, from: day) + 5) % 7
        let targetWeekStart = calendar.date(byAdding: .day, value: -targetDaysSinceMonday, to: day) ?? day
        return calendar.dateComponents([.weekOfYear], from: currentWeekStart, to: targetWeekStart).weekOfYear ?? 0
    }
    private var calendarMonthStart: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: calendarMonth)
        return calendar.date(from: components) ?? calendar.startOfDay(for: calendarMonth)
    }
    private var calendarWeekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = max(0, min(symbols.count - 1, calendar.firstWeekday - 1))
        return Array(symbols[offset...] + symbols[..<offset])
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
        let briefByID = DuplicateSafeIndex.firstValues(activeBriefs.map { ($0.id, $0) })
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
                let isActiveWork = output.status == .draft &&
                    brief.status != .scheduled &&
                    brief.status != .posted

                let postDateSharesWorkDay = brief.workDate.map { workDate in
                    output.targetDate.map { calendar.isDate($0, inSameDayAs: workDate) } ?? false
                } ?? false

                if isActiveWork, let workDate = brief.workDate, !postDateSharesWorkDay {
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
        let tasksByDay = Dictionary(grouping: tasks.filter {
            $0.parentTaskID == nil &&
                !$0.isSkipped &&
                TaskCollectionPolicy.collection(
                    briefID: $0.briefID,
                    platformOutputID: $0.platformOutputID
                ) == .myTasks &&
                $0.targetDate != nil
        }) {
            calendar.startOfDay(for: $0.targetDate ?? .distantFuture)
        }.mapValues {
            $0.sorted { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
        }

        return AgendaRenderSnapshot(
            briefByID: briefByID,
            occurrences: occurrences,
            occurrencesByDay: occurrencesByDay,
            tasksByDay: tasksByDay
        )
    }

    private var datedAgendaOccurrences: [AgendaPostOccurrence] {
        makeRenderSnapshot().occurrences
    }
    private var upcomingAgendaGroups: [AgendaOutputDayGroup] {
        filteredListAgendaOutputGroups
            .filter { $0.day >= Calendar.current.startOfDay(for: Date()) }
            .sorted { $0.day < $1.day }
    }
    private var pastAgendaGroups: [AgendaOutputDayGroup] {
        filteredListAgendaOutputGroups
            .filter { $0.day < Calendar.current.startOfDay(for: Date()) }
            .sorted { $0.day > $1.day }
    }
    private var filteredListAgendaOccurrences: [AgendaPostOccurrence] {
        let briefByID = DuplicateSafeIndex.firstValues(activeBriefs.map { ($0.id, $0) })
        let occurrencesByOutputID = Dictionary(
            grouping: datedAgendaOccurrences,
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
                case .open, .standard(.draft), .standard(.inProgress), .custom:
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
    private var filteredUndatedListPosts: [AgendaUndatedPost] {
        guard !listStatusRequiresPostDate else { return [] }

        let briefByID = DuplicateSafeIndex.firstValues(activeBriefs.map { ($0.id, $0) })
        let datedOutputIDs = Set(datedAgendaOccurrences.map(\.output.id))
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
            matchesStatus = ContinueWorkingPostPolicy.includes(
                briefStatus: brief.status,
                outputStatus: output.status,
                customStatus: brief.resolvedCustomStatusLabel,
                ideaBankPlacement: brief.ideaBankPlacement
            )
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
    private var filteredListAgendaOutputGroups: [AgendaOutputDayGroup] {
        let calendar = Calendar.current
        let briefByID = Dictionary(
            uniqueKeysWithValues: activeBriefs.map { ($0.id, $0) }
        )
        let grouped = Dictionary(grouping: filteredListAgendaOccurrences) {
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
        withAnimation(.snappy(duration: 0.2)) {
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

        withAnimation(.snappy(duration: 0.24)) {
            calendarMonth = newMonth
            selectedDay = newMonth
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
    private func tasks(on day: Date) -> [CreatorTask] {
        tasks.filter {
            $0.parentTaskID == nil &&
                !$0.isSkipped &&
                TaskCollectionPolicy.collection(
                    briefID: $0.briefID,
                    platformOutputID: $0.platformOutputID
                ) == .myTasks &&
                $0.targetDate.map { Calendar.current.isDate($0, inSameDayAs: day) } == true
        }
            .sorted { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
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
}

enum AgendaDayPresentation {
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
        return outputs.allSatisfy { !$0.needsRescheduling }
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

    static func firstTaskDate(in candidates: [Date?]) -> Date? {
        candidates.compactMap { $0 }.min()
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
                                episodeAction("Create new episode") {
                                    convertNew(series: series)
                                }
                                episodeAction("Use an Idea Bank idea") {
                                    showsIdeas = true
                                }
                                episodeAction("Duplicate previous episode") {
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
            .navigationTitle(showsIdeas ? "Choose an idea" : "Episode")
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
    @State private var confirmsPillarAfterPickerDismissal = false
    @State private var selectedEpisodeSlot: SeriesEpisodeSlot?
    @State private var convertedEpisodeBrief: CreativeBrief?
    @State private var acceptsDayContentInteractions = false

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
        outputs.filter {
            guard AgendaContentVisibility.includesOutput(
                briefID: $0.briefID,
                activeBriefIDs: activeBriefIDs
            ), let brief = activeBriefByID[$0.briefID] else {
                return false
            }
            return AgendaDayOutputVisibility.includes(
                outputTargetDate: $0.targetDate,
                outputStatus: $0.status,
                briefWorkDate: brief.workDate,
                briefStatus: brief.status,
                day: day
            )
        }
        .sorted { lhs, rhs in
            AgendaOutputOrdering.precedes(
                lhs,
                briefStatus: activeBriefByID[lhs.briefID]?.status,
                rhs,
                briefStatus: activeBriefByID[rhs.briefID]?.status
            )
        }
    }
    private var dayTasks: [CreatorTask] {
        tasks.filter {
            $0.parentTaskID == nil &&
                !$0.isSkipped &&
                AgendaContentVisibility.includesTask(briefID: $0.briefID, activeBriefIDs: activeBriefIDs) &&
                taskBelongsToDay($0)
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
                        title: Calendar.current.isDateInToday(day) ? "Today." : day.formatted(.dateTime.weekday(.wide)),
                        subtitle: "Everything planned for this day."
                    )
                    .padding(.horizontal, AgentLayout.pageMargin)

                    AgentInsetSurface {
                        VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                            daySection(title: "Post details") {
                                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                                    focusSection
                                    pillarSection
                                    dayTaskCollection(
                                        title: TaskCollection.myTasks.title,
                                        tasks: snapshot.focusTasks,
                                        snapshot: snapshot,
                                        emptyMessage: "No tasks planned.",
                                        taskTopPadding: AgentSpacing.x1,
                                        addAction: addMyTaskForDay
                                    )
                                }
                            }

                            daySection(title: "Scheduled") {
                                postsSection(snapshot)
                            }

                            postTasksSection(snapshot)
                        }
                    }
                    .padding(.horizontal, AgentLayout.dashboardGutter)
                    .padding(.top, AgentSpacing.x8)
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
            if AgendaDayPresentation.showsSaveControl(day: day, now: Date(), hasChanges: hasDayChanges) {
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
        .sheet(isPresented: $isPillarPickerPresented, onDismiss: finishPillarSelection) {
            pillarPickerSheet
                .presentationDetents([.height(pillarPickerHeight)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.agentCanvas)
        }
        .sheet(item: $selectedEpisodeSlot) { slot in
            EpisodeSlotActionsView(slot: slot) { result in
                convertedEpisodeBrief = result.brief
            }
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
            if AgendaDayPresentation.showsSaveControl(day: day, now: Date(), hasChanges: hasDayChanges) {
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

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            MetaLabel("Focus")
            NavigationLink {
                DailyFocusDetailView(date: day)
            } label: {
                HStack {
                    Text(dayFocus?.title ?? "Rest").font(.agentHeadline)
                    Spacer()
                    AgentIconView(.forward)
                }
                .foregroundStyle(Color.agentText)
                .frame(minHeight: 52)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens focus details")
        }
    }

    private var pillarSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel("Pillar")
                Spacer()
                MetaLabel("Assigned every \(weekday.title)")
            }

            Button {
                isPillarPickerPresented = true
            } label: {
                HStack(spacing: AgentSpacing.x3) {
                    if let displayedPillar {
                        PillarColorMark(
                            color: Color(agentHex: displayedPillar.resolvedColorHex(in: activePillars)),
                            diameter: 10
                        )
                    }
                    Text(displayedPillar?.name ?? "Assign a pillar")
                        .font(.agentBody.weight(.semibold))
                    Spacer()
                    AgentIconView(.expand, size: 11)
                }
                .foregroundStyle(Color.agentText)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private var pillarPickerSheet: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .center) {
                Text("Choose a pillar")
                    .font(.agentTitle)
                    .foregroundStyle(Color.agentText)

                Spacer()

                Button("Close") {
                    confirmsPillarAfterPickerDismissal = false
                    isPillarPickerPresented = false
                }
                .font(.agentSubtext.weight(.semibold))
                .foregroundStyle(Color.agentText)
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                .buttonStyle(.plain)
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
        let outputSignature = dayOutputs.map { output in
            let brief = activeBriefs.first { $0.id == output.briefID }
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
        AgendaDayPresentation.showsPastDaySaveControl(day: day, now: Date())
    }

    private func choosePillar(_ selected: Pillar?) {
        guard selected?.id != displayedPillar?.id else {
            confirmsPillarAfterPickerDismissal = false
            isPillarPickerPresented = false
            return
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            draftPillarID = selected?.id
            hasLoadedPillarDraft = true
        }

        if !isPastDay {
            dismissAfterPillarSave = false
            confirmsPillarAfterPickerDismissal = true
        }
        isPillarPickerPresented = false
    }

    private func finishPillarSelection() {
        guard confirmsPillarAfterPickerDismissal else { return }
        confirmsPillarAfterPickerDismissal = false
        Task { @MainActor in
            await Task.yield()
            showPillarOverwriteConfirmation = true
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

    private func postsSection(_ snapshot: DayAgendaRenderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if snapshot.dayOutputs.isEmpty && snapshot.episodeSlots.isEmpty {
                Text("No posts planned.").font(.agentSubtext).foregroundStyle(Color.agentSecondary).padding(.vertical, AgentSpacing.x4)
            } else {
                VStack(spacing: AgentSpacing.x3) {
                    ForEach(snapshot.dayOutputs) { output in
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
                                        : nil
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    ForEach(snapshot.episodeSlots) { slot in
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
            AgentBlockAddActionButton(title: "Schedule post") { isChoosingPost = true }
                .padding(.top, AgentSpacing.x6)
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

    private func taskBelongsToDay(_ task: CreatorTask) -> Bool {
        if task.dailyFocusDate.map({ Calendar.current.isDate($0, inSameDayAs: day) }) == true ||
            task.targetDate.map({ Calendar.current.isDate($0, inSameDayAs: day) }) == true {
            return true
        }

        if let outputID = task.platformOutputID,
           dayOutputs.contains(where: { $0.id == outputID }) {
            return true
        }

        return task.briefID.map { briefID in
            dayOutputs.contains(where: { $0.briefID == briefID })
        } == true
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
        outputStatus: PlatformOutputStatus,
        briefWorkDate: Date?,
        briefStatus: BriefStatus,
        day: Date,
        calendar: Calendar = .current
    ) -> Bool {
        if let outputTargetDate, calendar.isDate(outputTargetDate, inSameDayAs: day) {
            return true
        }

        guard outputStatus == .draft,
              briefStatus != .scheduled,
              briefStatus != .posted,
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

                    Button("Save new date") {
                        output.includesTargetTime = includesTime
                        let resolvedDate = includesTime
                            ? targetDate
                            : Calendar.current.startOfDay(for: targetDate)
                        appModel.schedule(output: output, date: resolvedDate, context: context)
                        dismiss()
                    }
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
}
