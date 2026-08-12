import SwiftData
import SwiftUI

struct TodayView: View {
    let day: Date
    let showsHeader: Bool
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Query private var profiles: [CreatorProfile]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \CreatorTask.createdAt) private var allTasks: [CreatorTask]
    @Query(sort: \PlatformOutput.createdAt) private var allOutputs: [PlatformOutput]
    @Query private var allPillars: [Pillar]
    @Query private var destinations: [PublishingDestination]
    @Query private var formats: [PublishingFormat]
    @Query private var allFocusTemplates: [DailyFocusTemplateEntry]
    @Query private var allFocusOverrides: [DailyFocusOverride]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var headerHeight: CGFloat = 0
    @State private var selectedPostTaskOutput: PlatformOutput?
    @State private var showPostTaskPicker = false

    private var briefs: [CreativeBrief] { scoped(allBriefs) }
    private var tasks: [CreatorTask] { scoped(allTasks) }
    private var outputs: [PlatformOutput] { scoped(allOutputs) }
    private var pillars: [Pillar] { scoped(allPillars) }
    private var focusTemplates: [DailyFocusTemplateEntry] { scoped(allFocusTemplates) }
    private var focusOverrides: [DailyFocusOverride] { scoped(allFocusOverrides) }
    private func scoped<T: WorkspaceScopedRecord>(_ values: [T]) -> [T] {
        values.filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: appModel.activeWorkspaceID, workspaces: workspaces)
        }
    }

    private var activeBriefs: [CreativeBrief] { briefs.filter { $0.status != .archived } }

    init(day: Date, showsHeader: Bool = true) {
        self.day = Calendar.current.startOfDay(for: day)
        self.showsHeader = showsHeader
    }

    private var todayPostTasks: [CreatorTask] {
        tasks
            .filter {
                !$0.isCompleted &&
                    !$0.isSkipped &&
                    $0.parentTaskID == nil &&
                    TaskCollectionPolicy.collection(
                        briefID: $0.briefID,
                        platformOutputID: $0.platformOutputID
                    ) == .postTasks &&
                    taskBelongsToSelectedDay($0)
            }
            .sorted(by: taskSort)
    }

    private var todayMyTasks: [CreatorTask] {
        tasks
            .filter {
                !$0.isCompleted &&
                    !$0.isSkipped &&
                    $0.parentTaskID == nil &&
                    TaskCollectionPolicy.collection(
                        briefID: $0.briefID,
                        platformOutputID: $0.platformOutputID
                    ) == .myTasks &&
                    taskBelongsToSelectedDay($0)
            }
            .sorted(by: taskSort)
    }

    private var todayOutputs: [PlatformOutput] {
        outputs.filter { output in
            output.targetDate.map { Calendar.current.isDate($0, inSameDayAs: day) } == true &&
                activeBriefs.contains(where: { $0.id == output.briefID })
        }
        .sorted { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
    }

    private var draftedOutputs: [PlatformOutput] {
        todayOutputs.filter { output in
            TodayOutputPresentation.section(
                outputStatus: output.status,
                briefStatus: brief(for: output)?.status
            ) == .drafted
        }
    }

    private var inProgressOutputs: [PlatformOutput] {
        todayOutputs.filter { output in
            TodayOutputPresentation.section(
                outputStatus: output.status,
                briefStatus: brief(for: output)?.status
            ) == .inProgress
        }
    }

    private var goingLiveOutputs: [PlatformOutput] {
        todayOutputs.filter { output in
            TodayOutputPresentation.section(
                outputStatus: output.status,
                briefStatus: brief(for: output)?.status
            ) == .goingLive
        }
    }

    private var resolvedFocus: ResolvedDailyFocus? {
        DailyFocusResolver.resolve(date: day, templates: focusTemplates, overrides: focusOverrides)
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
                        VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                            focusSection
                            postSections
                            taskSection
                        }
                    }
                    .padding(.horizontal, AgentLayout.dashboardGutter)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
        .onPreferenceChange(AgentViewHeightPreferenceKey.self) { headerHeight = $0 }
        .confirmationDialog(
            "Add task to which post?",
            isPresented: $showPostTaskPicker,
            titleVisibility: .visible
        ) {
            ForEach(todayOutputs) { output in
                if let brief = brief(for: output) {
                    Button(outputTitle(output, brief: brief)) {
                        selectedPostTaskOutput = output
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $selectedPostTaskOutput) { output in
            if let brief = brief(for: output) {
                PostDraftTaskComposer(
                    brief: brief,
                    output: output,
                    defaultDate: output.targetDate ?? day
                )
            }
        }
        .agentDashboardScreen()
    }

    private var header: some View {
        PlanHeader(
            breadcrumb: day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()),
            identity: activeIdentity,
            firstLine: "Hi \(activeIdentity.greetingName),",
            secondLine: dayTitle,
            openSettings: { appModel.presentedSheet = .settings }
        )
    }

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            MetaLabel("\(day.formatted(.dateTime.weekday(.wide)))’s focus")
            NavigationLink {
                DailyFocusDetailView(date: day)
            } label: {
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    if let focus = resolvedFocus {
                        HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x3) {
                            Text(focus.title).font(.agentTitle)
                            Text("DAY \(weekdayPosition) OF 7").font(.agentMetadata)
                            Spacer()
                            AgentIconView(.forward, size: 13)
                        }
                        if !focus.note.isEmpty {
                            Text(focus.note).font(.agentBody)
                        }
                        HStack(spacing: AgentSpacing.x4) {
                            if let duration = focus.durationMinutes {
                                MetaLabel("\(duration) min")
                            }
                            if let time = focus.time {
                                MetaLabel(time.formatted(date: .omitted, time: .shortened))
                            }
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Rest").font(.agentTitle)
                            Spacer()
                            AgentIconView(.forward, size: 13)
                        }
                        Text("Nothing is planned.")
                            .font(.agentBody)
                            .foregroundStyle(Color.agentSecondary)
                    }
                }
                .foregroundStyle(Color.agentText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, AgentSpacing.x4)
                .overlay(alignment: .top) { Rectangle().fill(Color.agentHairline).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Color.agentHairline).frame(height: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens today's focus details")
        }
    }

    private var postSections: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            if !goingLiveOutputs.isEmpty {
                postOutputSection(title: "Scheduled", outputs: goingLiveOutputs, displayAsDraft: false)
            }

            if !inProgressOutputs.isEmpty {
                postOutputSection(
                    title: "In progress",
                    outputs: inProgressOutputs,
                    displayAsDraft: true,
                    statusTextOverride: "In progress"
                )
            }

            if !draftedOutputs.isEmpty {
                postOutputSection(title: "Drafted", outputs: draftedOutputs, displayAsDraft: true)
            }

            if goingLiveOutputs.isEmpty, inProgressOutputs.isEmpty, draftedOutputs.isEmpty {
                VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                    sectionHeading("Posts", count: 0, unit: "post")
                    Text("No posts planned.")
                        .font(.agentBody)
                        .foregroundStyle(Color.agentSecondary)
                }
            }

            AgentAddActionRow(title: "Schedule post", action: addPostForToday)
                .accessibilityHint("Creates a post scheduled for this day")
        }
    }

    private func postOutputSection(
        title: String,
        outputs: [PlatformOutput],
        displayAsDraft: Bool,
        statusTextOverride: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            sectionHeading(title, count: outputs.count, unit: "post")
            ForEach(outputs) { output in
                if let brief = brief(for: output) {
                    NavigationLink { PostOutputDetailView(brief: brief, output: output) } label: {
                        AgentPostCard(
                            title: outputTitle(output, brief: brief),
                            pillar: pillar(for: brief)?.name ?? "Unfiled",
                            accent: pillar(for: brief).map { Color(agentHex: $0.colorHex) } ?? .agentSecondary,
                            status: displayAsDraft ? .draft : output.status,
                            metadata: outputLabel(output),
                            timeText: output.includesTargetTime
                                ? output.targetDate?.formatted(date: .omitted, time: .shortened)
                                : nil,
                            statusTextOverride: statusTextOverride
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x8) {
            dayTaskCollection(
                title: TaskCollection.postTasks.title,
                tasks: todayPostTasks,
                emptyMessage: "No post tasks.",
                addAction: addPostTaskForToday,
                accessibilityHint: "Adds a task to a post scheduled for this day"
            )

            dayTaskCollection(
                title: TaskCollection.myTasks.title,
                tasks: todayMyTasks,
                emptyMessage: "No tasks planned.",
                addAction: addMyTaskForToday,
                accessibilityHint: "Creates a task scheduled for this day"
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
                .overlay(alignment: .top) { Rectangle().fill(Color.agentHairline).frame(height: 1) }
                .contentShape(.rect)
                .agentHoverRow()
            }
            .buttonStyle(AgentPressButtonStyle())
        }
    }

    private func dayTaskCollection(
        title: String,
        tasks collectionTasks: [CreatorTask],
        emptyMessage: String,
        addAction: @escaping () -> Void,
        accessibilityHint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            sectionHeading(title, count: collectionTasks.count, unit: "task")

            if collectionTasks.isEmpty {
                Text(emptyMessage)
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
            } else {
                ForEach(Array(collectionTasks.prefix(4))) { task in
                    TaskRow(task: task, allTasks: tasks)
                }
            }

            AgentAddActionRow(title: "Add task", action: addAction)
                .accessibilityHint(accessibilityHint)
        }
    }

    private func sectionHeading(_ title: String, count: Int, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            MetaLabel(title)
            Spacer()
            Text("\(count) \(count == 1 ? unit : unit + "s")".uppercased()).font(.agentMetadata)
        }
    }

    private var activeIdentity: ActiveCreatorIdentity {
        ActiveCreatorIdentity.resolve(
            profile: profiles.first,
            workspaces: workspaces,
            preferredWorkspaceID: appModel.activeWorkspaceID
        )
    }

    private var weekdayPosition: Int {
        let raw = Calendar.current.component(.weekday, from: day)
        return raw == 1 ? 7 : raw - 1
    }

    private var dayTitle: String {
        if Calendar.current.isDateInToday(day) {
            return "what are we creating today?"
        }
        return "here's your \(day.formatted(.dateTime.weekday(.wide)))."
    }

    private func taskSort(_ lhs: CreatorTask, _ rhs: CreatorTask) -> Bool {
        if lhs.priority == .urgent, rhs.priority != .urgent { return true }
        if rhs.priority == .urgent, lhs.priority != .urgent { return false }
        return (lhs.targetDate ?? .distantFuture) < (rhs.targetDate ?? .distantFuture)
    }

    private func taskBelongsToSelectedDay(_ task: CreatorTask) -> Bool {
        if task.dailyFocusDate.map({ Calendar.current.isDate($0, inSameDayAs: day) }) == true ||
            task.targetDate.map({ Calendar.current.isDate($0, inSameDayAs: day) }) == true {
            return true
        }

        if let outputID = task.platformOutputID,
           todayOutputs.contains(where: { $0.id == outputID }) {
            return true
        }

        return task.briefID.map { briefID in
            todayOutputs.contains(where: { $0.briefID == briefID })
        } == true
    }

    private func addPostTaskForToday() {
        guard !todayOutputs.isEmpty else {
            appModel.notice = .info("Schedule a post before adding a post task.")
            return
        }
        if todayOutputs.count == 1 {
            selectedPostTaskOutput = todayOutputs[0]
        } else {
            showPostTaskPicker = true
        }
    }

    private func addMyTaskForToday() {
        appModel.quickCaptureTargetDate = day
        appModel.quickCapturePillarID = nil
        appModel.quickCaptureTaskLane = .production
        appModel.quickCaptureTaskFocus = resolvedFocus.map {
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

    private func addPostForToday() {
        appModel.quickCaptureTargetDate = day
        appModel.quickCapturePillarID = nil
        appModel.setQuickCaptureMode(.post)
        appModel.presentedSheet = .quickCapture
    }

    private func brief(for output: PlatformOutput) -> CreativeBrief? { activeBriefs.first { $0.id == output.briefID } }
    private func pillar(for brief: CreativeBrief) -> Pillar? { brief.pillarID.flatMap { id in pillars.first { $0.id == id } } }
    private func outputTitle(_ output: PlatformOutput, brief: CreativeBrief) -> String {
        let override = output.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? brief.title : override
    }
    private func outputLabel(_ output: PlatformOutput) -> String {
        guard let destinationID = output.destinationID,
              let destination = destinations.first(where: { $0.id == destinationID }) else { return output.platform.title }
        let format = output.formatID.flatMap { id in formats.first { $0.id == id } }
        return [destination.name, format?.name].compactMap { $0 }.joined(separator: " · ")
    }
}

enum TodayOutputSection: Equatable {
    case drafted
    case inProgress
    case goingLive
}

enum TodayOutputPresentation {
    static func section(
        outputStatus: PlatformOutputStatus,
        briefStatus: BriefStatus?
    ) -> TodayOutputSection {
        if briefStatus == .developing {
            return .inProgress
        }
        if outputStatus == .draft || briefStatus == .spark {
            return .drafted
        }
        return .goingLive
    }
}
