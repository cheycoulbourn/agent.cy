import SwiftData
import SwiftUI

struct AgendaView: View {
    @Binding var planMode: PlanMode
    @Binding var weekOffset: Int
    @Binding var selectedDay: Date
    let showsHeader: Bool
    let selectDay: (Date) -> Void
    @Environment(AppModel.self) private var appModel
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt) private var allOutputs: [PlatformOutput]
    @Query(sort: \CreatorTask.createdAt) private var allTasks: [CreatorTask]
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    @Query private var destinations: [PublishingDestination]
    @Query private var formats: [PublishingFormat]
    @Query(sort: \CreatorSocialAccount.sortOrder) private var allSocialAccounts: [CreatorSocialAccount]
    @Query private var profiles: [CreatorProfile]
    @Query private var allFocusTemplates: [DailyFocusTemplateEntry]
    @Query private var allFocusOverrides: [DailyFocusOverride]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @AppStorage("didPresentWeeklyFocusSetup") private var didPresentWeeklyFocusSetup = false
    @State private var headerHeight: CGFloat = 0
    @State private var schedulingPost: AgendaDaySelection?
    @State private var reschedulingOutput: PlatformOutput?
    @State private var focusedDay: AgendaDaySelection?
    @State private var showWeeklyFocusSetup = false
    @State private var deepLinkedBrief: CreativeBrief?
    @State private var deepLinkedBriefOpensEditor = false

    private var briefs: [CreativeBrief] { scoped(allBriefs) }
    private var outputs: [PlatformOutput] { scoped(allOutputs) }
    private var tasks: [CreatorTask] { scoped(allTasks) }
    private var pillars: [Pillar] { scoped(allPillars) }
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

    init(
        planMode: Binding<PlanMode>,
        weekOffset: Binding<Int>,
        selectedDay: Binding<Date>,
        showsHeader: Bool = true,
        selectDay: @escaping (Date) -> Void
    ) {
        _planMode = planMode
        _weekOffset = weekOffset
        _selectedDay = selectedDay
        self.showsHeader = showsHeader
        self.selectDay = selectDay
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if showsHeader {
                        header
                            .reportAgentViewHeight()
                    }
                    AgentDashboardSurface(
                        minimumHeight: max(0, proxy.size.height - (showsHeader ? headerHeight : 0))
                    ) {
                        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                            if focusTemplates.isEmpty {
                                weeklyFocusPrompt
                            } else {
                                weeklyFocusSummary
                            }
                            calendarStrip
                            VStack(spacing: 0) {
                                ForEach(weekDays, id: \.self) { day in
                                    weekRow(day)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AgentLayout.dashboardGutter)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $reschedulingOutput) { output in
            PostRescheduleSheet(output: output)
        }
        .sheet(isPresented: $showWeeklyFocusSetup) {
            WeeklyFocusSetupView()
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
                ScrollView {
                    ResumablePostEditorView(brief: brief, output: output, onSpark: {})
                        .padding(.horizontal, AgentLayout.pageMargin)
                        .padding(.top, AgentSpacing.x4)
                        .padding(.bottom, 120)
                }
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
        .task {
            guard focusTemplates.isEmpty, !didPresentWeeklyFocusSetup else { return }
            didPresentWeeklyFocusSetup = true
            await Task.yield()
            showWeeklyFocusSetup = true
        }
        .onPreferenceChange(AgentViewHeightPreferenceKey.self) { headerHeight = $0 }
        .onChange(of: appModel.widgetBriefID, initial: true) { _, id in
            guard let id, let brief = activeBriefs.first(where: { $0.id == id }) else { return }
            deepLinkedBriefOpensEditor = appModel.widgetBriefOpensEditor
            deepLinkedBrief = brief
            appModel.widgetBriefOpensEditor = false
            appModel.widgetBriefID = nil
        }
        .agentDashboardScreen()
    }

    private var header: some View {
        PlanHeader(
            mode: $planMode,
            breadcrumb: weekSummary,
            profile: profiles.first,
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

    private func weekButton(symbol: String, label: String, amount: Int) -> some View {
        Button { moveWeek(amount) } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var calendarStrip: some View {
        HStack(spacing: AgentSpacing.x1) {
            ForEach(weekDays, id: \.self) { day in
                calendarDay(day)
            }
        }
        .padding(.bottom, AgentSpacing.x4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.agentHairline).frame(height: 1)
        }
    }

    private var weeklyFocusPrompt: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel("Weekly focus")
                Spacer()
                Text("Not set")
                    .font(.agentMono)
                    .foregroundStyle(Color.agentSecondary)
            }

            Text("Batch similar work.")
                .font(.agentHeadline)

            Text("Choose up to two focuses for each day. Unassigned days are Rest.")
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showWeeklyFocusSetup = true
            } label: {
                HStack(spacing: AgentSpacing.x3) {
                    Text("Set weekly focus")
                        .font(.agentBody.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.agentText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, AgentSpacing.x2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.agentHairline)
                .frame(height: 1)
        }
    }

    private var weeklyFocusSummary: some View {
        Button { showWeeklyFocusSetup = true } label: {
            HStack(spacing: AgentSpacing.x4) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    MetaLabel("Weekly focus")
                    Text(weeklyFocusSummaryText)
                        .font(.agentBody.weight(.medium))
                }
                Spacer()
                Text("Edit")
                    .font(.agentSubtext.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Color.agentText)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var weeklyFocusSummaryText: String {
        let focusedDays = Set(focusTemplates.filter(\.isActive).map(\.weekdayRaw)).count
        let restDays = max(0, 7 - focusedDays)
        let focusLabel = focusedDays == 1 ? "focus day" : "focus days"
        let restLabel = restDays == 1 ? "rest day" : "rest days"
        return "\(focusedDays) \(focusLabel) · \(restDays) \(restLabel)"
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
            selectDay(day)
        } label: {
            VStack(spacing: 10) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.agentMono)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.agentSecondary)
                Text(day.formatted(.dateTime.day()))
                    .font(.agentBody.weight(isToday ? .semibold : .medium))
                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
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

    @ViewBuilder
    private func weekRow(_ day: Date) -> some View {
        let dayOutputs = outputs(on: day)
        let dayTasks = tasks(on: day)
        let dayFocus = focus(on: day)

        if AgendaDayPresentation.shouldCompact(
            day: day,
            outputs: dayOutputs.map { output in
                AgendaOutputState(
                    outputStatus: output.status,
                    briefStatus: activeBriefs.first(where: { $0.id == output.briefID })?.status
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
                    focus: dayFocus,
                    taskCount: dayTasks.count,
                    hasPosts: !dayOutputs.isEmpty
                )

                ForEach(dayOutputs) { output in
                    if let brief = activeBriefs.first(where: { $0.id == output.briefID }) {
                        agendaPostCard(output: output, brief: brief, day: day, dayTasks: dayTasks)
                    }
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

    private func compactCompletedDay(
        day: Date,
        focus: ResolvedDailyFocus?,
        postCount: Int
    ) -> some View {
        let pillarHexes = compactPillarHexes(on: day)
        let focusTitle = focus?.title ?? "Rest"
        let postCountLabel = AgendaDayPresentation.postCountLabel(postCount)

        return NavigationLink {
            DayAgendaView(day: day)
        } label: {
            HStack(spacing: AgentSpacing.x3) {
                Text(day.formatted(.dateTime.weekday(.abbreviated).day()))
                    .font(.agentMono)
                    .textCase(.uppercase)
                    .frame(width: 56, alignment: .leading)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 14, height: 14)

                if !pillarHexes.isEmpty {
                    HStack(spacing: AgentSpacing.x1) {
                        ForEach(Array(pillarHexes.enumerated()), id: \.offset) { _, hex in
                            Circle()
                                .fill(Color(agentHex: AgendaPillarDotPresentation.displayedHex(storedHex: hex)))
                                .frame(width: 6, height: 6)
                                .overlay {
                                    Circle()
                                        .stroke(Color.agentText.opacity(0.20), lineWidth: 0.5)
                                }
                        }
                    }
                    .fixedSize()
                }

                Text(focusTitle)
                    .font(.agentBody.weight(.medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(postCountLabel)
                    .font(.agentMono)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize()
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
        .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())), complete, focus \(focusTitle), \(postCountLabel)")
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
        focus: ResolvedDailyFocus?,
        taskCount: Int,
        hasPosts: Bool
    ) -> some View {
        HStack(spacing: AgentSpacing.x1) {
            NavigationLink {
                DayAgendaView(day: day)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x2) {
                    Text(dayHeaderDate(day))
                        .font(.agentMono.weight(Calendar.current.isDateInToday(day) ? .semibold : .medium))
                        .textCase(.uppercase)
                        .foregroundStyle(Calendar.current.isDateInToday(day) ? Color.cyAccent : Color.agentText)
                        .fixedSize()
                    Text(focus?.title ?? "Rest")
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.17)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if taskCount > 0 {
                        Text("· \(taskCount) \(taskCount == 1 ? "task" : "tasks")")
                            .font(.agentMono)
                            .textCase(.uppercase)
                            .fixedSize()
                    }
                    Spacer(minLength: AgentSpacing.x1)
                }
                .foregroundStyle(Color.agentText)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if hasPosts {
                NavigationLink {
                    DayAgendaView(day: day)
                } label: {
                    Image(systemName: AgendaDayPresentation.trailingActionSymbol(hasPosts: true))
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(day.formatted(.dateTime.weekday(.wide)))")
            } else {
                Button {
                    schedulingPost = AgendaDaySelection(day: day)
                } label: {
                    Image(systemName: AgendaDayPresentation.trailingActionSymbol(hasPosts: false))
                        .font(.system(size: 18, weight: .regular))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Schedule post")
                .accessibilityHint("Schedules a post for \(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))")
            }
        }
        .foregroundStyle(Color.agentText)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func agendaPostCard(output: PlatformOutput, brief: CreativeBrief, day: Date, dayTasks: [CreatorTask]) -> some View {
        let isDraft = TodayOutputPresentation.section(
            outputStatus: output.status,
            briefStatus: brief.status
        ) == .drafted
        let overdue = !isDraft && AgendaDayPresentation.isOverdue(
            targetDate: output.targetDate,
            status: output.status,
            now: Date()
        )
        let accent = pillarAccent(for: brief)
        let firstTaskDate = firstTaskDate(for: output, dayTasks: dayTasks)
        let displayStatus: PlatformOutputStatus = isDraft ? .draft : output.status
        let displayTime = firstTaskDate ?? (output.includesTargetTime ? output.targetDate : nil)
        let statusText = overdue ? "Missed" : nil

        return AgentPostCard(
            title: outputTitle(output, brief: brief),
            pillar: pillarName(for: brief),
            accent: accent,
            status: displayStatus,
            metadata: platformLabel(for: output),
            timeText: displayTime?.formatted(date: .omitted, time: .shortened),
            statusTextOverride: statusText,
            destination: AnyView(PostOutputDetailView(brief: brief, output: output)),
            footerActionTitle: overdue ? "Reschedule" : nil,
            footerAction: overdue ? { reschedulingOutput = output } : nil
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
    private func outputs(on day: Date) -> [PlatformOutput] {
        outputs.filter { output in output.targetDate.map { Calendar.current.isDate($0, inSameDayAs: day) } == true && activeBriefs.contains { $0.id == output.briefID } }
            .sorted { lhs, rhs in
                AgendaOutputOrdering.precedes(
                    lhs,
                    briefStatus: activeBriefs.first(where: { $0.id == lhs.briefID })?.status,
                    rhs,
                    briefStatus: activeBriefs.first(where: { $0.id == rhs.briefID })?.status
                )
            }
    }
    private func tasks(on day: Date) -> [CreatorTask] {
        tasks.filter {
            $0.parentTaskID == nil &&
                TaskCollectionPolicy.collection(
                    briefID: $0.briefID,
                    platformOutputID: $0.platformOutputID
                ) == .myTasks &&
                $0.targetDate.map { Calendar.current.isDate($0, inSameDayAs: day) } == true
        }
            .sorted { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
    }
    private func focus(on day: Date) -> ResolvedDailyFocus? { DailyFocusResolver.resolve(date: day, templates: focusTemplates, overrides: focusOverrides) }
    private func color(for brief: CreativeBrief) -> Color {
        guard let id = brief.pillarID, let pillar = pillars.first(where: { $0.id == id }) else { return .agentSecondary }
        return Color(agentHex: pillar.resolvedColorHex(in: pillars))
    }
    private func pillarHex(on day: Date) -> String? {
        if let brief = outputs(on: day).compactMap({ output in
            activeBriefs.first(where: { $0.id == output.briefID && $0.pillarID != nil })
        }).first,
           let pillarID = brief.pillarID,
           let pillar = pillars.first(where: { $0.id == pillarID && !$0.isArchived }) {
            return pillar.resolvedColorHex(in: pillars)
        }

        guard let weekday = PillarWeekday(rawValue: Calendar.current.component(.weekday, from: day)),
              let pillar = pillars.first(where: {
                  !$0.isArchived && $0.assignedWeekdays.contains(weekday)
              }) else { return nil }
        return pillar.resolvedColorHex(in: pillars)
    }

    private func compactPillarHexes(on day: Date) -> [String] {
        let outputHexes = outputs(on: day).compactMap { output -> String? in
            guard let brief = activeBriefs.first(where: { $0.id == output.briefID }),
                  let pillarID = brief.pillarID,
                  let pillar = pillars.first(where: { $0.id == pillarID && !$0.isArchived }) else {
                return nil
            }
            return pillar.resolvedColorHex(in: pillars)
        }
        let uniqueOutputHexes = uniqueHexes(outputHexes)
        if !uniqueOutputHexes.isEmpty { return Array(uniqueOutputHexes.prefix(3)) }

        guard let weekday = PillarWeekday(rawValue: Calendar.current.component(.weekday, from: day)) else {
            return []
        }
        let assignedHexes = pillars
            .filter { !$0.isArchived && $0.assignedWeekdays.contains(weekday) }
            .map { $0.resolvedColorHex(in: pillars) }
        return Array(uniqueHexes(assignedHexes).prefix(3))
    }

    private func uniqueHexes(_ hexes: [String]) -> [String] {
        var seen: Set<String> = []
        return hexes.filter { seen.insert($0.uppercased()).inserted }
    }
    private func accountLabel(for output: PlatformOutput) -> String? {
        output.socialAccountID.flatMap { id in socialAccounts.first { $0.id == id } }?.label
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
        TodayOutputPresentation.section(
            outputStatus: outputStatus,
            briefStatus: briefStatus
        ) == .drafted ? 1 : 0
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

private struct AgendaDaySelection: Identifiable, Hashable {
    let day: Date
    var id: Date { Calendar.current.startOfDay(for: day) }
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
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var planner: DayPlannerKind?
    @State private var isChoosingPost = false
    @State private var draftPillarID: UUID?
    @State private var hasLoadedPillarDraft = false
    @State private var showPillarOverwriteConfirmation = false
    @State private var dismissAfterPillarSave = false
    @State private var baselineDaySignature: String?

    private var briefs: [CreativeBrief] { scoped(allBriefs) }
    private var outputs: [PlatformOutput] { scoped(allOutputs) }
    private var tasks: [CreatorTask] { scoped(allTasks) }
    private var pillars: [Pillar] { scoped(allPillars) }
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

    private var activeBriefs: [CreativeBrief] { briefs.filter { $0.status != .archived } }
    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
    private var activeBriefIDs: Set<UUID> { Set(activeBriefs.map(\.id)) }
    private var dayOutputs: [PlatformOutput] {
        outputs.filter {
            AgendaContentVisibility.includesOutput(briefID: $0.briefID, activeBriefIDs: activeBriefIDs) &&
                $0.targetDate.map { Calendar.current.isDate($0, inSameDayAs: day) } == true
        }
        .sorted { lhs, rhs in
            AgendaOutputOrdering.precedes(
                lhs,
                briefStatus: activeBriefs.first(where: { $0.id == lhs.briefID })?.status,
                rhs,
                briefStatus: activeBriefs.first(where: { $0.id == rhs.briefID })?.status
            )
        }
    }
    private var dayTasks: [CreatorTask] {
        tasks.filter {
            $0.parentTaskID == nil &&
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
                        focusSection
                        pillarSection
                        postsSection
                        tasksSection
                    }
                }
                .padding(.horizontal, AgentLayout.dashboardGutter)
                .padding(.top, AgentSpacing.x8)
            }
            .padding(.top, AgentSpacing.x6)
            .padding(.bottom, 110)
        }
        .navigationTitle(day.formatted(.dateTime.weekday(.wide)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if AgendaDayPresentation.showsSaveControl(day: day, now: Date(), hasChanges: hasDayChanges) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: saveAndDismiss) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.black)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .tint(Color.white)
                    .accessibilityLabel("Save day")
                    .accessibilityHint("Saves your changes and returns to the week")
                }
            }
        }
        .sheet(item: $planner) { kind in DayPlannerSheet(day: day, kind: kind) }
        .navigationDestination(isPresented: $isChoosingPost) {
            AgendaPostIdeaPickerView(day: day)
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
        .agentScreen()
    }

    private func saveAndDismiss() {
        if hasPendingPillarChange {
            dismissAfterPillarSave = true
            showPillarOverwriteConfirmation = true
            return
        }
        try? context.save()
        dismiss()
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
                    Image(systemName: "chevron.right")
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

            Menu {
                Button("No pillar") { choosePillar(nil) }
                ForEach(activePillars) { pillar in
                    Button {
                        choosePillar(pillar)
                    } label: {
                        PillarMenuChoiceLabel(
                            title: pillar.name,
                            colorHex: pillar.resolvedColorHex(in: activePillars),
                            isSelected: displayedPillar?.id == pillar.id
                        )
                    }
                }
            } label: {
                HStack(spacing: AgentSpacing.x3) {
                    if let displayedPillar {
                        Circle()
                            .fill(Color(agentHex: displayedPillar.colorHex))
                            .frame(width: 10, height: 10)
                    }
                    Text(displayedPillar?.name ?? "Assign a pillar")
                        .font(.agentBody.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color.agentText)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
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
        guard selected?.id != displayedPillar?.id else { return }
        draftPillarID = selected?.id
        hasLoadedPillarDraft = true

        if !isPastDay {
            dismissAfterPillarSave = false
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
        try? context.save()
        WidgetSnapshotService.refresh(context: context)

        if dismissAfterPillarSave {
            dismissAfterPillarSave = false
            dismiss()
        }
    }

    private var postsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "Posts", trailing: "\(dayOutputs.count)")
            if dayOutputs.isEmpty {
                Text("No posts planned.").font(.agentSubtext).foregroundStyle(Color.agentSecondary).padding(.vertical, AgentSpacing.x4)
            } else {
                ForEach(dayOutputs) { output in
                    if let brief = activeBriefs.first(where: { $0.id == output.briefID }) {
                        NavigationLink { PostOutputDetailView(brief: brief, output: output) } label: {
                            AgentPostCard(
                                title: brief.title,
                                pillar: pillarLabel(for: brief),
                                accent: color(for: brief),
                                status: output.status,
                                metadata: outputLabel(output),
                                timeText: output.includesTargetTime
                                    ? output.targetDate?.formatted(date: .omitted, time: .shortened)
                                    : nil
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, AgentSpacing.x3)
                    }
                }
            }
            AgentAddActionRow(title: "Schedule post") { isChoosingPost = true }
                .padding(.top, AgentSpacing.x6)
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x8) {
            dayTaskCollection(
                title: TaskCollection.postTasks.title,
                tasks: postTasks,
                emptyMessage: "No post tasks."
            )

            dayTaskCollection(
                title: TaskCollection.myTasks.title,
                tasks: myTasks,
                emptyMessage: "No tasks planned."
            )

            AgentAddActionRow(title: "Add task") { planner = .task }
        }
    }

    @ViewBuilder
    private func dayTaskCollection(
        title: String,
        tasks collectionTasks: [CreatorTask],
        emptyMessage: String
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
                        taskRows(group.tasks)
                    }
                } else {
                    taskRows(collectionTasks)
                }
            }
        }
    }

    private func taskRows(_ collectionTasks: [CreatorTask]) -> some View {
        ForEach(collectionTasks) { task in
            TaskRow(
                task: task,
                allTasks: tasks,
                linkedPostTitle: linkedPostTitle(for: task)
            )
            .overlay(alignment: .bottom) {
                if task.id != collectionTasks.last?.id {
                    Rectangle().fill(Color.agentHairline).frame(height: 1)
                }
            }
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

    private func linkedPostTitle(for task: CreatorTask) -> String? {
        let output = task.platformOutputID.flatMap { outputID in
            outputs.first { $0.id == outputID }
        }
        let briefID = task.briefID ?? output?.briefID
        guard let briefID,
              let brief = activeBriefs.first(where: { $0.id == briefID }) else { return nil }
        let override = output?.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return override.isEmpty ? brief.title : override
    }

    private func color(for brief: CreativeBrief) -> Color {
        guard let id = brief.pillarID, let pillar = pillars.first(where: { $0.id == id }) else { return .agentSecondary }
        return Color(agentHex: pillar.colorHex)
    }

    private func pillarLabel(for brief: CreativeBrief) -> String {
        guard let id = brief.pillarID,
              let pillar = pillars.first(where: { $0.id == id }) else { return "Unfiled" }
        return pillar.name
    }
    private func outputLabel(_ output: PlatformOutput) -> String {
        let destination = output.destinationID.flatMap { id in destinations.first { $0.id == id } }?.name
        let format = output.formatID.flatMap { id in formats.first { $0.id == id } }?.name
        let account = output.socialAccountID.flatMap { id in socialAccounts.first { $0.id == id } }?.label
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

enum DayPlannerKind: String, Identifiable { case post, task; var id: String { rawValue } }

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

private struct DayPlannerSheet: View {
    let day: Date
    let kind: DayPlannerKind
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt) private var allOutputs: [PlatformOutput]
    @Query(sort: \CreatorTask.createdAt, order: .reverse) private var allTasks: [CreatorTask]
    @Query private var destinations: [PublishingDestination]
    @Query private var formats: [PublishingFormat]
    @Query(sort: \CreatorSocialAccount.sortOrder) private var allSocialAccounts: [CreatorSocialAccount]
    @Query private var allFocusTemplates: [DailyFocusTemplateEntry]
    @Query private var allFocusOverrides: [DailyFocusOverride]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]

    private var briefs: [CreativeBrief] { scoped(allBriefs) }
    private var outputs: [PlatformOutput] { scoped(allOutputs) }
    private var tasks: [CreatorTask] { scoped(allTasks) }
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

    var body: some View {
        NavigationStack {
            List {
                Section("Create") {
                    Button(kind == .post ? "Create a new post" : "Create a new task", systemImage: "plus") { createNew() }
                }
                if kind == .post {
                    Section("Available posts") {
                        ForEach(availableOutputs) { output in
                            if let brief = briefs.first(where: { $0.id == output.briefID }) {
                                Button {
                                    appModel.schedule(output: output, date: plannedDate, context: context)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(brief.title).foregroundStyle(Color.agentText)
                                        Text(outputLabel(output)).font(.caption).foregroundStyle(Color.agentSecondary)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Section("Available tasks") {
                        ForEach(availableTasks) { task in
                            Button {
                                task.targetDate = plannedDate
                                task.includesTargetTime = false
                                task.lane = .production
                                task.dailyFocusDate = day
                                task.dailyFocusTitle = resolvedFocus?.title
                                task.dailyFocusTemplateEntryID = resolvedFocus?.templateEntryID
                                try? context.save()
                                appModel.queueCalendarSync(context: context)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(task.title).foregroundStyle(Color.agentText)
                                    Text(task.lane.title).font(.caption).foregroundStyle(Color.agentSecondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(kind == .post ? "Schedule post" : "Add task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private var availableOutputs: [PlatformOutput] {
        outputs.filter { output in
            output.targetDate == nil && briefs.contains(where: { $0.id == output.briefID && $0.status != .archived })
        }
    }
    private var availableTasks: [CreatorTask] {
        tasks.filter {
            $0.parentTaskID == nil &&
                $0.targetDate == nil &&
                TaskCollectionPolicy.collection(
                    briefID: $0.briefID,
                    platformOutputID: $0.platformOutputID
                ) == .myTasks
        }
    }
    private var plannedDate: Date { Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day }
    private var resolvedFocus: ResolvedDailyFocus? {
        DailyFocusResolver.resolve(date: day, templates: focusTemplates, overrides: focusOverrides)
    }

    private func createNew() {
        dismiss()
        appModel.quickCaptureTargetDate = plannedDate
        appModel.setQuickCaptureMode(kind == .post ? .post : .task)
        if kind == .task {
            appModel.quickCaptureTaskLane = .production
            appModel.quickCaptureTaskFocus = resolvedFocus.map {
                DailyFocusTaskAssignment(
                    date: day,
                    title: $0.title,
                    taskKind: $0.kinds.first?.taskKind ?? .planning,
                    templateEntryID: $0.templateEntryID
                )
            }
        }
        Task { @MainActor in await Task.yield(); appModel.presentedSheet = .quickCapture }
    }
    private func outputLabel(_ output: PlatformOutput) -> String {
        let destination = output.destinationID.flatMap { id in destinations.first { $0.id == id } }?.name
        let format = output.formatID.flatMap { id in formats.first { $0.id == id } }?.name
        let account = output.socialAccountID.flatMap { id in socialAccounts.first { $0.id == id } }?.label
        return [destination, format, account].compactMap { $0 }.joined(separator: " · ")
    }
}
