import SwiftData
import SwiftUI
import UIKit
import Observation

struct TaskNavigationRoute: Hashable {
    let taskID: UUID
}

private struct TaskNavigationDestinationView: View {
    let route: TaskNavigationRoute
    @Environment(AppModel.self) private var appModel
    @Query private var tasks: [CreatorTask]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]

    init(route: TaskNavigationRoute) {
        self.route = route
        let taskID = route.taskID
        _tasks = Query(filter: #Predicate<CreatorTask> { $0.id == taskID })
    }

    var body: some View {
        if let task = tasks.first(where: {
            $0.id == route.taskID && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }) {
            TaskDetailView(task: task)
        } else {
            AgentEmptyState(
                title: "Task not found",
                message: "It may have been completed or deleted.",
                icon: .tasks
            )
            .agentScreen()
        }
    }
}

enum TaskDetailExitState {
    case editing
    case persisted
    case deleted
}

enum TaskDetailExitPolicy {
    static func shouldPersistOnDisappear(state: TaskDetailExitState) -> Bool {
        state == .editing
    }
}

enum TaskDetailDuplicationPolicy {
    static func copy(of task: CreatorTask) -> CreatorTask {
        let copy = CreatorTask(
            briefID: task.briefID,
            pillarID: task.pillarID,
            platformOutputID: task.platformOutputID,
            title: "\(task.title) copy",
            kind: task.kind,
            lane: task.lane,
            priority: task.priority.normalized,
            notes: task.notes,
            estimatedMinutes: task.estimatedMinutes,
            targetDate: task.targetDate,
            includesTargetTime: task.includesTargetTime,
            dailyFocusDate: task.dailyFocusDate,
            dailyFocusTitle: task.dailyFocusTitle,
            dailyFocusTemplateEntryID: task.dailyFocusTemplateEntryID
        )
        copy.workspaceID = task.workspaceID
        copy.brandPartnerID = task.brandPartnerID
        return copy
    }
}

enum TaskDetailPillarPolicy {
    static func activePillars(
        from pillars: [Pillar],
        taskWorkspaceID: UUID?,
        workspaces: [CreatorWorkspace]
    ) -> [Pillar] {
        pillars.filter {
            !$0.isArchived && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: taskWorkspaceID,
                workspaces: workspaces
            )
        }
    }
}

private struct TaskLinkedPostSection: View {
    let task: CreatorTask
    @Query private var outputs: [PlatformOutput]

    init(task: CreatorTask) {
        self.task = task
        if let outputID = task.platformOutputID {
            _outputs = Query(
                filter: #Predicate<PlatformOutput> { $0.id == outputID }
            )
        } else if let briefID = task.briefID {
            _outputs = Query(
                filter: #Predicate<PlatformOutput> { $0.briefID == briefID },
                sort: \PlatformOutput.createdAt
            )
        } else {
            _outputs = Query(
                filter: #Predicate<PlatformOutput> { _ in false }
            )
        }
    }

    var body: some View {
        let linkedOutput = TaskLinkedPostPolicy.output(for: task, in: outputs)
        if let briefID = task.briefID ?? linkedOutput?.briefID {
            TaskLinkedBriefSection(briefID: briefID, output: linkedOutput)
        }
    }
}

private struct TaskLinkedBriefSection: View {
    let output: PlatformOutput?
    @Query private var briefs: [CreativeBrief]

    init(briefID: UUID, output: PlatformOutput?) {
        self.output = output
        _briefs = Query(
            filter: #Predicate<CreativeBrief> { $0.id == briefID }
        )
    }

    var body: some View {
        if let brief = briefs.first {
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                MetaLabel("Linked post")
                NavigationLink {
                    if let output {
                        PostOutputDetailView(brief: brief, output: output)
                    } else {
                        IdeaPostDraftView(brief: brief)
                    }
                } label: {
                    Text(brief.title)
                }
                .font(.agentBody.weight(.semibold))
                .foregroundStyle(Color.agentText)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
    }
}

extension View {
    func taskNavigationDestinations() -> some View {
        navigationDestination(for: TaskNavigationRoute.self) { route in
            TaskNavigationDestinationView(route: route)
        }
    }
}

enum TaskDateFilter: String, CaseIterable, Identifiable {
    case all = "Any date"
    case today = "Today"
    case thisWeek = "This week"
    case pastDue = "Past due"
    case noDate = "No due date"
    case specificDate = "Choose date"

    var id: String { rawValue }
}

enum TaskPillarFilter: Equatable {
    case all
    case unfiled
    case pillar(UUID)
}

enum TaskFocusFilter: Equatable {
    case all
    case noFocus
    case focus(DailyFocusKind)
}

enum TaskListFilterPolicy {
    static func matchesDate(
        _ date: Date?,
        filter: TaskDateFilter,
        selectedDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        switch filter {
        case .all:
            return true
        case .today:
            return date.map { calendar.isDate($0, inSameDayAs: now) } == true
        case .thisWeek:
            guard let date,
                  let week = TaskCalendarPolicy.mondayWeekInterval(
                    containing: now,
                    calendar: calendar
                  )
            else { return false }
            return TaskCalendarPolicy.contains(date, in: week, calendar: calendar)
        case .pastDue:
            guard let date else { return false }
            return calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
        case .noDate:
            return date == nil
        case .specificDate:
            return date.map { calendar.isDate($0, inSameDayAs: selectedDate) } == true
        }
    }

    static func matchesPillar(_ pillarID: UUID?, filter: TaskPillarFilter) -> Bool {
        switch filter {
        case .all: return true
        case .unfiled: return pillarID == nil
        case .pillar(let selectedID): return pillarID == selectedID
        }
    }

    static func matchesPriority(_ priority: TaskPriority, selected: TaskPriority?) -> Bool {
        guard let selected else { return true }
        return priority.normalized == selected.normalized
    }

    static func matchesFocus(
        title: String?,
        kind: CreatorTaskKind,
        hasFocusAssignment: Bool,
        filter: TaskFocusFilter
    ) -> Bool {
        switch filter {
        case .all:
            return true
        case .noFocus:
            return !hasFocusAssignment
        case .focus(let focus):
            guard hasFocusAssignment else { return false }
            let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !cleanTitle.isEmpty,
               cleanTitle.localizedCaseInsensitiveContains(focus.title) {
                return true
            }
            return focus.taskKind == kind
        }
    }
}

enum TaskRootDatePolicy {
    static func taskOwnedDate(targetDate: Date?, dailyFocusDate: Date?) -> Date? {
        targetDate ?? dailyFocusDate
    }
}

enum TaskRootVisibilityPolicy {
    static func includes(
        collection: TaskCollection,
        isCompleted: Bool,
        isArchived: Bool,
        focusTaskTemplateID: UUID?,
        recurrence: TaskRecurrenceFrequency,
        recurrenceRootTaskID: UUID?,
        taskOwnedDate: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        if isCompleted || isArchived {
            return true
        }
        return TaskListVisibilityPolicy.includes(
            collection: collection,
            focusTaskTemplateID: focusTaskTemplateID,
            recurrence: recurrence,
            recurrenceRootTaskID: recurrenceRootTaskID,
            targetDate: taskOwnedDate,
            now: now,
            calendar: calendar
        )
    }
}

enum TaskRootLinkPolicy {
    static func linkedBriefID(
        taskBriefID: UUID?,
        platformOutputID: UUID?,
        outputBriefIDs: [UUID: UUID]
    ) -> UUID? {
        taskBriefID ?? platformOutputID.flatMap { outputBriefIDs[$0] }
    }

    static func isArchived(
        taskBriefID: UUID?,
        platformOutputID: UUID?,
        outputBriefIDs: [UUID: UUID],
        archivedBriefIDs: Set<UUID>
    ) -> Bool {
        linkedBriefID(
            taskBriefID: taskBriefID,
            platformOutputID: platformOutputID,
            outputBriefIDs: outputBriefIDs
        ).map(archivedBriefIDs.contains) == true
    }
}

enum TaskDueDatePresentation {
    static func isPastDue(
        _ date: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let date else { return false }
        return calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
    }

    static func title(
        for date: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let date else { return "No due date" }
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        if isPastDue(date, now: now, calendar: calendar) {
            return "Past due · \(formattedDay(date, calendar: calendar))"
        }
        return formattedDay(date, calendar: calendar)
    }

    static func rowDateText(
        for date: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let date else { return "None" }
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        return formattedShortDay(date, calendar: calendar)
    }

    private static func formattedDay(_ date: Date, calendar: Calendar) -> String {
        formatter(calendar: calendar, dateFormat: "EEEE, MMM d").string(from: date)
    }

    private static func formattedShortDay(_ date: Date, calendar: Calendar) -> String {
        formatter(calendar: calendar, dateFormat: "MMM d").string(from: date)
    }

    private static func formatter(calendar: Calendar, dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = dateFormat
        return formatter
    }
}

enum TaskRootMotionPolicy {
    static func usesCollectionAnimation(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}

enum TaskRootAccessibilityPolicy {
    static let maximumFixedControlDynamicTypeSize: DynamicTypeSize = .large

    static func usesStackedMetadata(dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    static func taskTitleLineLimit(dynamicTypeSize: DynamicTypeSize) -> Int {
        dynamicTypeSize.isAccessibilitySize ? 3 : 2
    }

    static func groupLabel(title: String, taskCount: Int) -> String {
        "\(title), \(taskCount) \(taskCount == 1 ? "task" : "tasks")"
    }
}

enum TaskRootNavigationPolicy {
    static func route(for taskID: UUID) -> TaskNavigationRoute {
        TaskNavigationRoute(taskID: taskID)
    }
}

#if DEBUG
private enum TaskRootRuntimeFixture {
    static func value(after marker: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: marker),
              arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }
}
#endif

enum TaskRuntimeFixture {
    static func requestsCaptureDueDateEditor(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
#if DEBUG
        arguments.contains("-agentCyPreviewCaptureTaskDueDate")
#else
        false
#endif
    }

    static func requestsDueDateEditor(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
#if DEBUG
        arguments.contains("-agentCyPreviewTaskDueDate")
#else
        false
#endif
    }

    static func requestsPostTaskChooser(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
#if DEBUG
        arguments.contains("-agentCyPreviewPostTaskChooser")
#else
        false
#endif
    }

    static func requestsPostTaskComposer(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
#if DEBUG
        arguments.contains("-agentCyPreviewPostTaskComposer")
#else
        false
#endif
    }
}

struct TasksView: View {
    enum StatusFilter: String, CaseIterable, Identifiable {
        case open = "Open"
        case completed = "Completed"
        case archive = "Archived"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \CreatorTask.createdAt, order: .reverse) private var tasks: [CreatorTask]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt) private var outputs: [PlatformOutput]
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @Query private var profiles: [CreatorProfile]
    @State private var collection: TaskCollection = .myTasks
    @State private var status: StatusFilter = .open
    @State private var isFilterPresented = false
    @State private var dateFilter: TaskDateFilter = .all
    @State private var selectedFilterDate = Date()
    @State private var pillarFilter: TaskPillarFilter = .all
    @State private var priorityFilter: TaskPriority?
    @State private var focusFilter: TaskFocusFilter = .all
    @State private var collapsedMyTaskDays: Set<String> = []
    @State private var isAddingPostTask = false
    @State private var tasksNow = Date()

    init() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let rawCollection = TaskRootRuntimeFixture.value(
            after: "-agentCyPreviewTaskCollection",
            arguments: arguments
        ), let collection = TaskCollection(rawValue: rawCollection) {
            _collection = State(initialValue: collection)
        }
        if let rawStatus = TaskRootRuntimeFixture.value(
            after: "-agentCyPreviewTaskStatus",
            arguments: arguments
        ), let status = StatusFilter.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(rawStatus) == .orderedSame
        }) {
            _status = State(initialValue: status)
        }
        if arguments.contains("-agentCyPreviewTaskFilterSheet") {
            _isFilterPresented = State(initialValue: true)
        }
        if TaskRuntimeFixture.requestsPostTaskChooser(arguments: arguments) ||
            TaskRuntimeFixture.requestsPostTaskComposer(arguments: arguments) {
            _collection = State(initialValue: .postTasks)
            _isAddingPostTask = State(initialValue: true)
        }
#endif
    }

    private func filtered(for collection: TaskCollection) -> [CreatorTask] {
        let archivedBriefIDs = archivedBriefIDs
        let outputBriefIDs = DuplicateSafeIndex.firstValues(outputs.map { ($0.id, $0.briefID) })
        return tasks
            .filter { task in
                guard task.parentTaskID == nil,
                      !task.isSkipped,
                      WorkspaceScope.includes(
                        task.workspaceID,
                        activeWorkspaceID: appModel.activeWorkspaceID,
                        workspaces: workspaces
                      ),
                      TaskCollectionPolicy.collection(
                        briefID: task.briefID,
                        platformOutputID: task.platformOutputID
                      ) == collection
                else { return false }
                let isArchived = TaskRootLinkPolicy.isArchived(
                    taskBriefID: task.briefID,
                    platformOutputID: task.platformOutputID,
                    outputBriefIDs: outputBriefIDs,
                    archivedBriefIDs: archivedBriefIDs
                )
                switch status {
                case .open:
                    guard !task.isCompleted && !isArchived else { return false }
                case .completed:
                    guard task.isCompleted && !isArchived else { return false }
                case .archive:
                    guard isArchived else { return false }
                }
                let taskOwnedDate = taskOwnedDate(for: task)
                guard TaskRootVisibilityPolicy.includes(
                    collection: collection,
                    isCompleted: task.isCompleted,
                    isArchived: isArchived,
                    focusTaskTemplateID: task.focusTaskTemplateID,
                    recurrence: task.recurrence,
                    recurrenceRootTaskID: task.recurrenceRootTaskID,
                    taskOwnedDate: taskOwnedDate,
                    now: tasksNow
                ) else { return false }

                return TaskListFilterPolicy.matchesDate(
                    taskOwnedDate,
                    filter: dateFilter,
                    selectedDate: selectedFilterDate,
                    now: tasksNow
                ) && TaskListFilterPolicy.matchesPillar(
                    effectivePillarID(for: task),
                    filter: pillarFilter
                ) && TaskListFilterPolicy.matchesPriority(
                    task.priority,
                    selected: priorityFilter
                ) && TaskListFilterPolicy.matchesFocus(
                    title: task.dailyFocusTitle,
                    kind: task.kind,
                    hasFocusAssignment: hasFocusAssignment(task),
                    filter: focusFilter
                )
            }
            .sorted(by: sortTasks)
    }

    private var archivedBriefIDs: Set<UUID> {
        Set(briefs.lazy.filter {
            $0.status == .archived && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }.map(\.id))
    }

    private func taskOwnedDate(for task: CreatorTask) -> Date? {
        TaskRootDatePolicy.taskOwnedDate(
            targetDate: task.targetDate,
            dailyFocusDate: task.dailyFocusDate
        )
    }

    private func effectivePillarID(for task: CreatorTask) -> UUID? {
        if let pillarID = task.pillarID { return pillarID }
        let linkedOutput = task.platformOutputID.flatMap { outputID in
            outputs.first { $0.id == outputID }
        }
        let briefID = task.briefID ?? linkedOutput?.briefID
        return briefID.flatMap { id in briefs.first(where: { $0.id == id })?.pillarID }
    }

    private func hasFocusAssignment(_ task: CreatorTask) -> Bool {
        task.dailyFocusDate != nil
            || task.dailyFocusTemplateEntryID != nil
            || task.focusTaskTemplateID != nil
            || !(task.dailyFocusTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            taskCollectionRail
            .padding(.horizontal, AgentLayout.dashboardGutter)
            .padding(.bottom, AgentSpacing.x3)

            taskCollectionContent
            .animation(
                TaskRootMotionPolicy.usesCollectionAnimation(reduceMotion: reduceMotion)
                    ? .snappy(duration: 0.24)
                    : nil,
                value: collection
            )
            .background(Color.agentSurface)
            .clipShape(.rect(cornerRadius: AgentRadius.dashboard))
            .agentSurfaceChrome(cornerRadius: AgentRadius.dashboard)
            .padding(.horizontal, AgentLayout.dashboardGutter)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isAddingPostTask) {
            PostTaskCreationFlow()
                .presentationDetents([.large])
                .agentSheetDragIndicator()
        }
        .sheet(isPresented: $isFilterPresented) {
            taskFilterSheet
                .presentationDetents([.medium, .large])
                .agentSheetDragIndicator()
        }
        .onChange(of: appModel.activeWorkspaceID) {
            pillarFilter = .all
        }
        .onAppear(perform: refreshTaskClock)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshTaskClock()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.significantTimeChangeNotification
        )) { _ in
            refreshTaskClock()
        }
        .agentScreen()
    }

    @ViewBuilder
    private var taskCollectionRail: some View {
#if targetEnvironment(macCatalyst)
        taskCollectionPicker
#else
        taskCollectionPicker.padding(3)
#endif
    }

    private var taskCollectionPicker: some View {
        Picker("Task list", selection: $collection) {
            ForEach(TaskCollection.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .dynamicTypeSize(...TaskRootAccessibilityPolicy.maximumFixedControlDynamicTypeSize)
    }

    @ViewBuilder
    private var taskCollectionContent: some View {
#if targetEnvironment(macCatalyst)
        taskPage(for: collection)
            .id(collection)
            .transition(.opacity)
#else
        TabView(selection: $collection) {
            ForEach(TaskCollection.allCases) { page in
                taskPage(for: page)
                    .tag(page)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
#endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            AgentPageRail(
                breadcrumb: "Tasks",
                identity: activeIdentity,
                openSettings: { appModel.presentedSheet = .settings }
            ) {
                taskFilterButton
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Let’s get")
                    .font(.agentDisplayLead)
                Text("things done.")
                    .font(.agentDisplay)
            }
            .tracking(-0.64)
            .accessibilityElement(children: .combine)
        }
        .foregroundStyle(Color.agentText)
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentLayout.pageTopPadding)
        .padding(.bottom, AgentLayout.pageHeaderToContentSpacing)
    }

    private var activeIdentity: ActiveCreatorIdentity {
        ActiveCreatorIdentity.resolve(
            profile: profiles.first,
            workspaces: workspaces,
            preferredWorkspaceID: appModel.activeWorkspaceID
        )
    }

    private var taskFilterButton: some View {
        Button {
            isFilterPresented = true
        } label: {
            ZStack(alignment: .topTrailing) {
                AgentToolbarIconLabel(icon: .filter)

                if activeFilterCount > 0 {
                    Text("\(activeFilterCount)")
                        .font(.agentInter(size: 10, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(Color.agentSurface)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Color.agentText, in: .circle)
                        .offset(x: 2, y: 2)
                        .dynamicTypeSize(...TaskRootAccessibilityPolicy.maximumFixedControlDynamicTypeSize)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter tasks")
        .accessibilityValue(activeFilterCount == 0 ? "No filters" : "\(activeFilterCount) active")
    }

    private var taskFilterSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    Text("Narrow either task list by the details that matter right now.")
                        .font(.agentBody)
                        .foregroundStyle(Color.agentSecondary)

                    VStack(spacing: 0) {
                        filterMenuRow(label: "Status", value: status.rawValue) {
                            ForEach(StatusFilter.allCases) { option in
                                filterMenuButton(
                                    option.rawValue,
                                    isSelected: status == option
                                ) { status = option }
                            }
                        }

                        filterMenuRow(label: "Date", value: dateFilterLabel) {
                            ForEach(TaskDateFilter.allCases) { option in
                                filterMenuButton(
                                    option.rawValue,
                                    isSelected: dateFilter == option
                                ) { dateFilter = option }
                            }
                        }

                        if dateFilter == .specificDate {
                            HStack(spacing: AgentSpacing.x3) {
                                MetaLabel("On date")
                                Spacer()
                                DatePicker(
                                    "Date",
                                    selection: $selectedFilterDate,
                                    displayedComponents: .date
                                )
                                .labelsHidden()
                                .datePickerStyle(.compact)
                            }
                            .frame(minHeight: 52)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Color.agentHairline).frame(height: 1)
                            }
                        }

                        filterMenuRow(label: "Pillar", value: pillarFilterLabel) {
                            filterMenuButton("All pillars", isSelected: pillarFilter == .all) {
                                pillarFilter = .all
                            }
                            filterMenuButton("No pillar", isSelected: pillarFilter == .unfiled) {
                                pillarFilter = .unfiled
                            }
                            ForEach(activePillars) { pillar in
                                Button {
                                    pillarFilter = .pillar(pillar.id)
                                } label: {
                                    Label {
                                        Text(pillar.name)
                                    } icon: {
                                        Circle()
                                            .fill(Color(agentHex: pillar.resolvedColorHex(in: activePillars)))
                                    }
                                }
                            }
                        }

                        filterMenuRow(label: "Priority", value: priorityFilterLabel) {
                            filterMenuButton("All priorities", isSelected: priorityFilter == nil) {
                                priorityFilter = nil
                            }
                            ForEach(TaskPriority.selectableCases) { option in
                                filterMenuButton(
                                    option.title,
                                    isSelected: priorityFilter == option
                                ) { priorityFilter = option }
                            }
                        }

                        filterMenuRow(label: "Focus", value: focusFilterLabel) {
                            filterMenuButton("All focuses", isSelected: focusFilter == .all) {
                                focusFilter = .all
                            }
                            filterMenuButton("No focus", isSelected: focusFilter == .noFocus) {
                                focusFilter = .noFocus
                            }
                            ForEach(DailyFocusKind.selectableCases) { option in
                                filterMenuButton(
                                    option.title,
                                    isSelected: focusFilter == .focus(option)
                                ) { focusFilter = .focus(option) }
                            }
                        }
                    }
                    .padding(.horizontal, AgentSpacing.x4)
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))

                    if activeFilterCount > 0 {
                        Button("Clear filters") {
                            resetTaskFilters()
                        }
                        .buttonStyle(AgentSecondaryButtonStyle())
                    }
                }
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x4)
                .padding(.bottom, AgentSpacing.x8)
            }
            .navigationTitle("Filter tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isFilterPresented = false }
                }
            }
            .agentScreen()
        }
    }

    private func filterMenuRow<Content: View>(
        label: String,
        value: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu(content: content) {
            HStack(spacing: AgentSpacing.x3) {
                MetaLabel(label)
                Spacer()
                Text(value)
                    .font(.agentBody)
                    .foregroundStyle(Color.agentText)
                    .lineLimit(1)
                AgentIconView(.expand, size: 11)
                    .foregroundStyle(Color.agentSecondary)
            }
            .frame(minHeight: 52)
            .contentShape(.rect)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.agentHairline).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func filterMenuButton(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if isSelected {
                AgentIconLabel(title: title, icon: .check)
            } else {
                Text(title)
            }
        }
    }

    private var activeFilterCount: Int {
        (status == .open ? 0 : 1)
            + (dateFilter == .all ? 0 : 1)
            + (pillarFilter == .all ? 0 : 1)
            + (priorityFilter == nil ? 0 : 1)
            + (focusFilter == .all ? 0 : 1)
    }

    private var activePillars: [Pillar] {
        pillars.filter {
            !$0.isArchived && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private var dateFilterLabel: String {
        guard dateFilter == .specificDate else { return dateFilter.rawValue }
        return selectedFilterDate.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var pillarFilterLabel: String {
        switch pillarFilter {
        case .all: "All pillars"
        case .unfiled: "No pillar"
        case .pillar(let id): activePillars.first(where: { $0.id == id })?.name ?? "All pillars"
        }
    }

    private var priorityFilterLabel: String {
        priorityFilter?.title ?? "All priorities"
    }

    private var focusFilterLabel: String {
        switch focusFilter {
        case .all: "All focuses"
        case .noFocus: "No focus"
        case .focus(let kind): kind.title
        }
    }

    private func resetTaskFilters() {
        status = .open
        dateFilter = .all
        selectedFilterDate = tasksNow
        pillarFilter = .all
        priorityFilter = nil
        focusFilter = .all
    }

    private func refreshTaskClock() {
        tasksNow = Date()
    }

    @ViewBuilder
    private func taskPage(for collection: TaskCollection) -> some View {
        let visibleTasks = filtered(for: collection)
        let groups = dueDateGroups(tasks: visibleTasks)
        if groups.isEmpty {
            ContentUnavailableView {
                Text(emptyTitle(for: collection))
            } description: {
                Text(emptyDescription(for: collection))
            } actions: {
                if status == .open {
                    AgentBlockAddActionButton(title: "Add task") {
                        openTaskComposer(for: collection)
                    }
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: appModel.walkthroughStep == .tasks ? .top : .center
            )
            .padding(.top, appModel.walkthroughStep == .tasks ? AgentSpacing.x3 : 0)
            .background(Color.agentSurface)
        } else if status != .open {
            completedList(groups: groups, collection: collection)
        } else {
            openList(groups: groups, collection: collection)
        }
    }

    private func emptyTitle(for collection: TaskCollection) -> String {
        switch status {
        case .open: collection == .postTasks ? "No post tasks yet" : "No tasks yet"
        case .completed: "No completed tasks."
        case .archive: "No archived tasks."
        }
    }

    private func emptyDescription(for collection: TaskCollection) -> String {
        switch status {
        case .open: collection == .postTasks
            ? "Tasks added to posts appear here."
            : "Add one clear next step."
        case .completed: ""
        case .archive: "Tasks from archived posts appear here."
        }
    }

    private func openList(
        groups: [TaskDueDateGroup],
        collection: TaskCollection
    ) -> some View {
        List {
            ForEach(groups) { group in
                Section {
                    if !isCollapsed(group, collection: collection) {
                        ForEach(group.tasks) { task in row(task) }
                    }
                } header: {
                    dueDateGroupHeader(group, collection: collection)
                }
                .textCase(nil)
            }
            if status == .open {
                AgentBlockAddActionButton(title: "Add task") {
                    openTaskComposer(for: collection)
                }
                    .listRowInsets(EdgeInsets(
                        top: AgentSpacing.x2,
                        leading: AgentLayout.pageMargin,
                        bottom: AgentSpacing.x2,
                        trailing: AgentLayout.pageMargin
                    ))
                    .listRowBackground(Color.agentSurface)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.bottom, taskListBottomMargin, for: .scrollContent)
        .background(Color.agentSurface)
    }

    private func completedList(
        groups: [TaskDueDateGroup],
        collection: TaskCollection
    ) -> some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.tasks) { task in row(task) }
                } header: {
                    dueDateGroupHeader(group, collection: collection)
                }
                .textCase(nil)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.bottom, taskListBottomMargin, for: .scrollContent)
        .background(Color.agentSurface)
    }

    private var taskListBottomMargin: CGFloat {
#if targetEnvironment(macCatalyst)
        AgentSpacing.x8
#else
        104
#endif
    }

    private func row(_ task: CreatorTask) -> some View {
        TaskRow(
            task: task,
            allTasks: tasks,
            linkedPostTitle: linkedPostTitle(for: task),
            referenceDate: tasksNow
        )
            .listRowInsets(EdgeInsets(
                top: 0,
                leading: AgentLayout.pageMargin,
                bottom: 0,
                trailing: AgentLayout.pageMargin
            ))
            .listRowBackground(Color.agentSurface)
            .listRowSeparator(.hidden)
    }

    private func dueDateGroups(tasks: [CreatorTask]) -> [TaskDueDateGroup] {
        let grouped = Dictionary(grouping: tasks) { task in
            taskOwnedDate(for: task).map(Calendar.current.startOfDay(for:))
        }
        return grouped.map { day, tasks in
            TaskDueDateGroup(
                day: day,
                tasks: tasks,
                referenceDate: tasksNow
            )
        }
        .sorted { lhs, rhs in
            switch (lhs.day, rhs.day) {
            case let (left?, right?): left < right
            case (nil, _?): false
            case (_?, nil): true
            case (nil, nil): false
            }
        }
    }

    @ViewBuilder
    private func dueDateGroupHeader(
        _ group: TaskDueDateGroup,
        collection: TaskCollection
    ) -> some View {
        let canCollapse = collection == .myTasks && status == .open
        let collapsed = isCollapsed(group, collection: collection)
        if canCollapse {
            Button {
                if collapsed {
                    collapsedMyTaskDays.remove(group.id)
                } else {
                    collapsedMyTaskDays.insert(group.id)
                }
            } label: {
                dueDateGroupHeaderContent(
                    group,
                    showsDisclosure: true,
                    isCollapsed: collapsed
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(TaskRootAccessibilityPolicy.groupLabel(
                title: group.title,
                taskCount: group.tasks.count
            ))
            .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
        } else {
            dueDateGroupHeaderContent(
                group,
                showsDisclosure: false,
                isCollapsed: false
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TaskRootAccessibilityPolicy.groupLabel(
                title: group.title,
                taskCount: group.tasks.count
            ))
        }
    }

    private func dueDateGroupHeaderContent(
        _ group: TaskDueDateGroup,
        showsDisclosure: Bool,
        isCollapsed: Bool
    ) -> some View {
        HStack(spacing: AgentSpacing.x2) {
            MetaLabel(group.title)
                .foregroundStyle(group.isPastDue ? Color.cyAccent : Color.agentSecondary)
            Spacer()
            MetaLabel("\(group.tasks.count)")
                .accessibilityHidden(true)
            if showsDisclosure {
                AgentIconView(isCollapsed ? .expand : .collapse)
                    .font(.agentInter(size: 11, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(Color.agentSecondary)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
        .padding(.top, AgentSpacing.x3)
        .padding(.bottom, AgentSpacing.x2)
    }

    private func isCollapsed(_ group: TaskDueDateGroup, collection: TaskCollection) -> Bool {
        collection == .myTasks && status == .open && collapsedMyTaskDays.contains(group.id)
    }

    private func sortTasks(_ lhs: CreatorTask, _ rhs: CreatorTask) -> Bool {
        let rank: (CreatorTask) -> Int = { task in task.priority == .urgent ? 0 : (task.priority == .high ? 1 : 2) }
        if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
        if (taskOwnedDate(for: lhs) ?? .distantFuture) != (taskOwnedDate(for: rhs) ?? .distantFuture) {
            return (taskOwnedDate(for: lhs) ?? .distantFuture) < (taskOwnedDate(for: rhs) ?? .distantFuture)
        }
        return lhs.createdAt < rhs.createdAt
    }

    private func linkedPostTitle(for task: CreatorTask) -> String? {
        let output = task.platformOutputID.flatMap { outputID in
            outputs.first { $0.id == outputID }
        }
        let briefID = task.briefID ?? output?.briefID
        guard let briefID,
              let brief = briefs.first(where: { $0.id == briefID })
        else { return nil }
        let override = output?.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return override.isEmpty ? brief.title : override
    }

    private func openTaskComposer(for collection: TaskCollection) {
        guard collection == .myTasks else {
            isAddingPostTask = true
            return
        }
        appModel.setQuickCaptureMode(.task)
        appModel.quickCapturePillarID = nil
        appModel.quickCaptureTaskLane = .production
        appModel.quickCaptureTaskFocus = nil
        appModel.presentedSheet = .quickCapture
    }

}

struct PostTaskCreationCandidate: Identifiable {
    let brief: CreativeBrief
    let output: PlatformOutput
    let pillar: Pillar?

    var id: UUID { output.id }
}

struct PostTaskCreationProjection {
    struct Inputs {
        let briefs: [CreativeBrief]
        let outputs: [PlatformOutput]
        let pillars: [Pillar]
        let workspaces: [CreatorWorkspace]
        let activeWorkspaceID: UUID?
        let now: Date
        let calendar: Calendar
    }

    let candidates: [PostTaskCreationCandidate]
    let activePillars: [Pillar]

    static func make(inputs: Inputs, search: String) -> Self {
        let activeWorkspaceID = WorkspaceScope.activeWorkspaceID(
            preferredID: inputs.activeWorkspaceID,
            workspaces: inputs.workspaces
        )
        let defaultWorkspaceID = WorkspaceScope.defaultWorkspace(in: inputs.workspaces)?.id
        let includesWorkspace: (UUID?) -> Bool = { recordWorkspaceID in
            guard let activeWorkspaceID else { return recordWorkspaceID == nil }
            if let recordWorkspaceID { return recordWorkspaceID == activeWorkspaceID }
            return defaultWorkspaceID == activeWorkspaceID
        }
        let activePillars = inputs.pillars.filter {
            !$0.isArchived && includesWorkspace($0.workspaceID)
        }
        let pillarsByID = DuplicateSafeIndex.firstValues(activePillars.map { ($0.id, $0) })
        let scopedBriefPairs: [(UUID, CreativeBrief)] = inputs.briefs.compactMap { brief in
            guard brief.status != .archived, includesWorkspace(brief.workspaceID) else { return nil }
            return (brief.id, brief)
        }
        let briefsByID = DuplicateSafeIndex.firstValues(scopedBriefPairs)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let week = TaskCalendarPolicy.mondayWeekInterval(
            containing: inputs.now,
            calendar: inputs.calendar
        )

        let candidates = inputs.outputs.compactMap { output -> PostTaskCreationCandidate? in
            guard output.status == .scheduled,
                  let targetDate = output.targetDate,
                  includesWorkspace(output.workspaceID),
                  let brief = briefsByID[output.briefID]
            else { return nil }
            let pillar = brief.pillarID.flatMap { pillarsByID[$0] }
            if query.isEmpty {
                guard let week,
                      TaskCalendarPolicy.contains(
                        targetDate,
                        in: week,
                        calendar: inputs.calendar
                      ) else { return nil }
            } else {
                let override = output.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = override.isEmpty ? brief.title : override
                guard title.localizedStandardContains(query)
                        || brief.notes.localizedStandardContains(query)
                        || output.platform.title.localizedStandardContains(query)
                        || pillar?.name.localizedStandardContains(query) == true
                else { return nil }
            }
            return PostTaskCreationCandidate(brief: brief, output: output, pillar: pillar)
        }
        .sorted { lhs, rhs in
            let lhsDate = lhs.output.targetDate ?? .distantFuture
            let rhsDate = rhs.output.targetDate ?? .distantFuture
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            if lhs.output.createdAt != rhs.output.createdAt {
                return lhs.output.createdAt < rhs.output.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        return Self(candidates: candidates, activePillars: activePillars)
    }
}

struct PostTaskCreationFlow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let onTaskSaved: (() -> Void)?
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.targetDate) private var allOutputs: [PlatformOutput]
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var search = ""

    init(onTaskSaved: (() -> Void)? = nil) {
        self.onTaskSaved = onTaskSaved
    }

    private var projection: PostTaskCreationProjection {
        PostTaskCreationProjection.make(
            inputs: .init(
                briefs: allBriefs,
                outputs: allOutputs,
                pillars: allPillars,
                workspaces: workspaces,
                activeWorkspaceID: appModel.activeWorkspaceID,
                now: Date(),
                calendar: .current
            ),
            search: search
        )
    }

    var body: some View {
        let projection = projection
        NavigationStack {
            if TaskRuntimeFixture.requestsPostTaskComposer(),
               let candidate = projection.candidates.first {
                linkedComposer(for: candidate)
            } else {
                chooser(projection: projection)
            }
        }
    }

    private func chooser(projection: PostTaskCreationProjection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    MetaLabel("Post task")
                    Text("Choose the scheduled post this task belongs to.")
                        .font(.agentHeadline)
                    Text("This week is shown first. Search to find another scheduled post.")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                }

                searchField

                VStack(alignment: .leading, spacing: 0) {
                    SectionRuleHeader(
                        title: search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "Scheduled this week"
                            : "Search results",
                        trailing: "\(projection.candidates.count)"
                    )

                    if projection.candidates.isEmpty {
                        Text(emptyMessage)
                            .font(.agentBody)
                            .foregroundStyle(Color.agentSecondary)
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                    } else {
                        ForEach(Array(projection.candidates.enumerated()), id: \.element.id) { index, candidate in
                            NavigationLink {
                                linkedComposer(for: candidate)
                            } label: {
                                postRow(candidate: candidate, activePillars: projection.activePillars)
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .bottom) {
                                if index < projection.candidates.count - 1 {
                                    Rectangle().fill(Color.agentHairline).frame(height: 1)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.top, AgentSpacing.x6)
            .padding(.bottom, AgentSpacing.x12)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("New post task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                AgentToolbarIconButton(title: "Close", icon: .close) { dismiss() }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .agentScreen()
    }

    private func linkedComposer(for candidate: PostTaskCreationCandidate) -> some View {
        LinkedPostTaskComposer(
            brief: candidate.brief,
            output: candidate.output,
            onSaved: {
                onTaskSaved?()
                dismiss()
            }
        )
    }

    private var searchField: some View {
        HStack(spacing: AgentSpacing.x3) {
            AgentIconView(.search, size: 15)
                .foregroundStyle(Color.agentSecondary)
            TextField("Search scheduled posts", text: $search)
                .font(.agentBody)
                .submitLabel(.done)
        }
        .padding(.horizontal, AgentSpacing.x4)
        .frame(minHeight: 48)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.control)
                .stroke(Color.agentBorder, lineWidth: 0.75)
        }
    }

    private var emptyMessage: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No posts are scheduled this week. Search for another scheduled post."
            : "No scheduled posts match this search."
    }

    private func postRow(
        candidate: PostTaskCreationCandidate,
        activePillars: [Pillar]
    ) -> some View {
        HStack(spacing: AgentSpacing.x3) {
            Circle()
                .fill(candidate.pillar.map {
                    Color(agentHex: $0.resolvedColorHex(in: activePillars))
                } ?? .agentSecondary)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                Text(displayTitle(for: candidate.output, brief: candidate.brief))
                    .font(.agentBody.weight(.semibold))
                    .foregroundStyle(Color.agentText)
                    .lineLimit(2)
                Text(postMetadata(candidate: candidate))
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            AgentIconView(.forward, size: 12)
                .foregroundStyle(Color.agentSecondary)
        }
        .frame(minHeight: 68)
        .contentShape(.rect)
    }

    private func displayTitle(for output: PlatformOutput, brief: CreativeBrief) -> String {
        let override = output.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? brief.title : override
    }

    private func postMetadata(candidate: PostTaskCreationCandidate) -> String {
        let date = candidate.output.targetDate?.formatted(
            .dateTime.weekday(.abbreviated).month(.abbreviated).day()
        ) ?? "No date"
        return [candidate.pillar?.name ?? "Unfiled", candidate.output.platform.title, date]
            .joined(separator: " · ")
    }
}

private struct LinkedPostTaskComposer: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    let brief: CreativeBrief
    let output: PlatformOutput
    let onSaved: () -> Void
    @State private var title = ""
    @State private var notes = ""
    @State private var priority: TaskPriority = .none
    @State private var recurrence: TaskRecurrenceFrequency = .none
    @State private var subtasks: [DraftCaptureSubtask] = []
    @State private var showDueDatePicker = false
    @State private var includeDate: Bool
    @State private var includesTime = false
    @State private var date: Date
    @FocusState private var notesAreFocused: Bool

    init(brief: CreativeBrief, output: PlatformOutput, onSaved: @escaping () -> Void) {
        self.brief = brief
        self.output = output
        self.onSaved = onSaved
        _includeDate = State(initialValue: output.targetDate != nil)
        _date = State(initialValue: output.targetDate ?? Date())
        _showDueDatePicker = State(
            initialValue: TaskRuntimeFixture.requestsCaptureDueDateEditor()
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                TextField("What's the task?", text: $title, axis: .vertical)
                    .font(.paperInter(size: 28, weight: .bold, relativeTo: .title))
                    .tracking(-0.56)
                    .lineLimit(1...3)

                VStack(spacing: 0) {
                    TaskEditorSetupRow(label: "Post", value: linkedPostTitle, showsChevron: false)

                    Menu {
                        ForEach(TaskPriority.selectableCases) { option in
                            Button(option.title) { priority = option }
                        }
                    } label: {
                        TaskEditorSetupRow(label: "Priority", value: priority.normalized.title)
                    }

                    Button {
                        showDueDatePicker = true
                    } label: {
                        TaskEditorSetupRow(label: "Due", value: dueDateLabel)
                    }
                    .buttonStyle(.plain)

                    Menu {
                        ForEach(TaskRecurrenceFrequency.allCases) { option in
                            Button(option.title) {
                                recurrence = option
                                if option != .none { includeDate = true }
                            }
                        }
                    } label: {
                        TaskEditorSetupRow(label: "Repeat", value: recurrence.title)
                    }
                }
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.agentText.opacity(0.08)).frame(height: 1)
                }

                VStack(alignment: .leading, spacing: 10) {
                    AgentInputHeader(title: "Notes", isEditing: notesAreFocused) {
                        notesAreFocused = false
                    }
                    TextEditor(text: $notes)
                        .font(.paperInter(size: 16, weight: .regular, relativeTo: .body))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 132)
                        .padding(16)
                        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                        .overlay {
                            RoundedRectangle(cornerRadius: AgentRadius.panel)
                                .stroke(Color.agentBorder, lineWidth: 1)
                        }
                        .focused($notesAreFocused)
                }

                DraftSubtaskComposer(subtasks: $subtasks)
            }
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.top, AgentSpacing.x6)
            .padding(.bottom, AgentSpacing.x12)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("New post task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                AgentToolbarSaveButton(
                    title: "Add task",
                    isEnabled: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    action: save
                )
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .agentScreen()
        .sheet(isPresented: $showDueDatePicker) {
            CaptureTaskDueDateSheet(
                date: $date,
                hasDueDate: $includeDate,
                includesTime: $includesTime,
                allowsRemoval: TaskDueDatePolicy.allowsRemoval(recurrence: recurrence)
            )
            .presentationDetents([.large])
        }
        .agentKeyboardDismissal()
    }

    private var linkedPostTitle: String {
        let override = output.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? brief.title : override
    }

    private var dueDateLabel: String {
        guard includeDate else { return "No due date" }
        if includesTime {
            return date.formatted(
                .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
            )
        }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let targetDate = includeDate ? date : nil
        guard appModel.createLinkedPostTask(
            title: cleanTitle,
            notes: notes,
            priority: priority,
            targetDate: targetDate,
            includesTargetTime: includeDate && includesTime,
            recurrence: recurrence,
            briefID: brief.id,
            outputID: output.id,
            subtasks: subtasks.map {
                TaskCreationSubtaskDraft(title: $0.title, isCompleted: $0.isCompleted)
            },
            context: context
        ) != nil else { return }
        onSaved()
    }
}

struct TaskDueDateGroup: Identifiable {
    let day: Date?
    let tasks: [CreatorTask]
    let referenceDate: Date

    init(day: Date?, tasks: [CreatorTask], referenceDate: Date = Date()) {
        self.day = day
        self.tasks = tasks
        self.referenceDate = referenceDate
    }

    var id: String {
        day.map { String(Calendar.current.startOfDay(for: $0).timeIntervalSinceReferenceDate) }
            ?? "no-date"
    }

    var title: String {
        TaskDueDatePresentation.title(for: day, now: referenceDate)
    }

    var isPastDue: Bool {
        TaskDueDatePresentation.isPastDue(day, now: referenceDate)
    }
}

struct TaskRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    let task: CreatorTask
    let allTasks: [CreatorTask]
    var linkedPostTitle: String? = nil
    var referenceDate: Date = Date()
    var verticalInset: CGFloat = AgentSpacing.x1
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var subtasks: [CreatorTask] {
        allTasks
            .filter { $0.parentTaskID == task.id }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.createdAt < rhs.createdAt
            }
    }
    private var visibleSubtasks: [CreatorTask] { subtasks.filter { !$0.isCompleted } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Phone rests the box top on the title's cap line; desktop
            // centers box and title, matching the Control Center widget.
            HStack(alignment: AgentTaskCheckboxMetrics.rowAlignment, spacing: taskRowSpacing) {
                taskCheckbox(task, accessibilityPrefix: "task")

                Button {
                    appModel.requestedTaskID = TaskRootNavigationPolicy.route(for: task.id).taskID
                } label: {
                    HStack(alignment: .center, spacing: AgentSpacing.x2) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(task.title)
                                .font(taskRowTitleFont)
                                .lineLimit(TaskRootAccessibilityPolicy.taskTitleLineLimit(
                                    dynamicTypeSize: dynamicTypeSize
                                ))
                                .fixedSize(horizontal: false, vertical: true)
                                .strikethrough(task.isCompleted)
                                .foregroundStyle(task.isCompleted ? Color.agentSecondary : Color.agentText)
                            metadataLine
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        AgentIconView(.forward, size: 12)
                            .foregroundStyle(Color.agentSecondary)
                            .frame(width: 24, height: 44)
                            .dynamicTypeSize(...TaskRootAccessibilityPolicy.maximumFixedControlDynamicTypeSize)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 10)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open task \(task.title)")
            }

            if !visibleSubtasks.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleSubtasks) { subtask in
                        HStack(alignment: AgentTaskCheckboxMetrics.rowAlignment, spacing: AgentSpacing.x2) {
                            taskCheckbox(subtask, accessibilityPrefix: "subtask", titlePointSize: 13)

                            Text(subtask.title)
                                .font(.agentSubtext)
                                .foregroundStyle(subtask.isCompleted ? Color.agentSecondary : Color.agentText)
                                .strikethrough(subtask.isCompleted)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .padding(.leading, 28)
                    }
                }
                .padding(.bottom, AgentSpacing.x2)
            }
        }
        // TaskRow owns its vertical rhythm so List and VStack hosts render
        // focus tasks at the exact same measured distance.
        .padding(.vertical, verticalInset)
    }

    // Desktop task rows share the Control Center widget's measurements:
    // 14pt utility title, 10pt gap, centered against the 16pt box.
    private var taskRowTitleFont: Font {
        #if targetEnvironment(macCatalyst)
        .agentDesktopUtilityBodyEmphasis
        #else
        .agentBody.weight(.semibold)
        #endif
    }

    private var taskRowSpacing: CGFloat {
        #if targetEnvironment(macCatalyst)
        10
        #else
        AgentSpacing.x2
        #endif
    }

    private func taskCheckbox(
        _ item: CreatorTask,
        accessibilityPrefix: String,
        titlePointSize: CGFloat = 15
    ) -> some View {
        AgentTaskCheckbox(
            isCompleted: item.isCompleted,
            color: checkboxColor(for: item),
            titlePointSize: titlePointSize,
            accessibilityLabel: item.isCompleted
                ? "Mark \(accessibilityPrefix) open"
                : "Complete \(accessibilityPrefix)"
        ) {
            appModel.toggleTask(item, context: context)
        }
        .zIndex(1)
        .accessibilityIdentifier("task-checkbox-\(item.id.uuidString)")
    }

    @ViewBuilder
    private var metadataLine: some View {
        if TaskRootAccessibilityPolicy.usesStackedMetadata(dynamicTypeSize: dynamicTypeSize) {
            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                metadata(primaryMetadataText, color: primaryMetadataColor)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    metadata(dateText.uppercased())
                    metadataDivider
                    metadata(task.priority.normalized.title.uppercased(), color: priorityColor)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: 6) {
                metadata(primaryMetadataText, color: primaryMetadataColor)
                metadataDivider
                metadata(dateText.uppercased())
                metadataDivider
                metadata(task.priority.normalized.title.uppercased(), color: priorityColor)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .accessibilityElement(children: .combine)
        }
    }

    private var primaryMetadataText: String {
        if let linkedPostTitle { return linkedPostTitle.uppercased() }
        return task.isCompleted ? "COMPLETED" : (isOverdue ? "PAST DUE" : "OPEN")
    }

    private var primaryMetadataColor: Color {
        linkedPostTitle == nil ? statusColor : .agentSecondary
    }

    private func metadata(_ value: String, color: Color = .agentSecondary) -> some View {
        Text(value)
            .font(.agentMetadata)
            .foregroundStyle(color)
    }

    private var metadataDivider: some View {
        Circle()
            .fill(Color.agentSecondary)
            .frame(width: 2.5, height: 2.5)
            .accessibilityHidden(true)
    }

    private var priorityColor: Color {
        switch task.priority.normalized {
        case .urgent: .agentDestructive
        case .high: .agentPriorityHigh
        default: .agentSecondary
        }
    }

    private var statusColor: Color {
        isOverdue && !task.isCompleted ? .cyAccent : .agentSecondary
    }

    private var isOverdue: Bool {
        !task.isCompleted && TaskDueDatePresentation.isPastDue(taskOwnedDate, now: referenceDate)
    }

    private func checkboxColor(for task: CreatorTask) -> Color {
        switch task.priority.normalized {
        case .urgent: .agentDestructive
        case .high: .agentPriorityHigh
        default: .agentBorder
        }
    }

    private var dateText: String {
        TaskDueDatePresentation.rowDateText(for: taskOwnedDate, now: referenceDate)
    }

    private var taskOwnedDate: Date? {
        TaskRootDatePolicy.taskOwnedDate(
            targetDate: task.targetDate,
            dailyFocusDate: task.dailyFocusDate
        )
    }
}

@MainActor
@Observable
private final class TaskTextDraft {
    var title: String
    var notes: String

    init(title: String, notes: String) {
        self.title = title
        self.notes = notes
    }
}

private struct TaskTitleDraftField: View {
    @Bindable var draft: TaskTextDraft

    var body: some View {
        TextField("What's the task?", text: $draft.title, axis: .vertical)
            .font(.paperInter(size: 28, weight: .bold, relativeTo: .title))
            .tracking(-0.56)
            .lineLimit(1...3)
    }
}

private struct TaskNotesDraftField: View {
    @Bindable var draft: TaskTextDraft
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AgentInputHeader(title: "Notes", isEditing: isFocused) {
                isFocused = false
            }
            TextEditor(text: $draft.notes)
                .font(.paperInter(size: 16, weight: .regular, relativeTo: .body))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 132)
                .padding(16)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.panel)
                        .stroke(Color.agentBorder, lineWidth: 1)
                }
                .focused($isFocused)
        }
    }
}

private struct TaskSaveToolbarButton: View {
    @Bindable var draft: TaskTextDraft
    let action: () -> Void

    private var isEnabled: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        AgentToolbarIconButton(
            title: "Save task",
            icon: .check,
            isEnabled: isEnabled,
            action: action
        )
    }
}

struct TaskDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var task: CreatorTask
    @Query private var subtasks: [CreatorTask]
    @Query private var pillars: [Pillar]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var isAddingSubtask = false
    @State private var newSubtaskTitle = ""
    @State private var showCompletedSubtasks = false
    @State private var confirmDelete = false
    @State private var showDueDateEditor = false
    @State private var originalFocusTemplateSignature: String?
    @State private var newSubtaskFocused = false
    @State private var textDraft: TaskTextDraft
    @State private var showTaskOptions = false
    @State private var exitState = TaskDetailExitState.editing
    private static let subtaskComposerID = "task-detail-subtask-composer"

    init(task: CreatorTask) {
        self.task = task
        let parentTaskID = task.id
        _subtasks = Query(
            filter: #Predicate<CreatorTask> { $0.parentTaskID == parentTaskID },
            sort: \CreatorTask.sortOrder
        )
        _textDraft = State(initialValue: TaskTextDraft(title: task.title, notes: task.notes))
        _showDueDateEditor = State(initialValue: TaskRuntimeFixture.requestsDueDateEditor())
    }

    private var completedSubtasks: [CreatorTask] { subtasks.filter(\.isCompleted) }
    private var visibleSubtasks: [CreatorTask] {
        showCompletedSubtasks ? subtasks : subtasks.filter { !$0.isCompleted }
    }
    private var isLinkedPostTask: Bool { task.briefID != nil || task.platformOutputID != nil }
    private var isDailyFocusLocked: Bool { task.dailyFocusDate != nil }
    private var isOverdueMyTask: Bool {
        guard !task.isCompleted,
              !task.isSkipped,
              TaskCollectionPolicy.collection(
                briefID: task.briefID,
                platformOutputID: task.platformOutputID
              ) == .myTasks,
              let targetDate = task.targetDate
        else { return false }
        return Calendar.current.startOfDay(for: targetDate) < Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                MetaLabel(task.isCompleted ? "Completed task" : "Task")

                TaskTitleDraftField(draft: textDraft)

                if isOverdueMyTask {
                    overdueActions
                }

                taskSetupRows

                if task.recurrence != .none {
                    Text("The next task is added when this one is completed.")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                }

                TaskNotesDraftField(draft: textDraft)

                if isLinkedPostTask {
                    TaskLinkedPostSection(task: task)
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionRuleHeader(title: "Subtasks")
                    .padding(.bottom, AgentSpacing.x2)

                    ForEach(visibleSubtasks) { subtask in
                        HStack(alignment: AgentTaskCheckboxMetrics.rowAlignment, spacing: AgentSpacing.x2) {
                            AgentTaskCheckbox(
                                isCompleted: subtask.isCompleted,
                                color: Color.agentText,
                                accessibilityLabel: subtask.isCompleted
                                    ? "Mark subtask open"
                                    : "Complete subtask"
                            ) {
                                appModel.toggleTask(subtask, context: context)
                            }

                            TextField("Subtask", text: Bindable(subtask).title)
                                .font(.agentBody)
                                .agentSingleLineSubmit()
                                .strikethrough(subtask.isCompleted)
                                .foregroundStyle(subtask.isCompleted ? Color.agentSecondary : Color.agentText)
                        }
                        .padding(.vertical, AgentSpacing.x2)

                    }

                    if isAddingSubtask {
                        HStack(alignment: AgentTaskCheckboxMetrics.rowAlignment, spacing: AgentSpacing.x2) {
                            AgentTaskCheckboxPlaceholder()

                            PersistentSubmitTextField(
                                text: $newSubtaskTitle,
                                isFocused: $newSubtaskFocused,
                                placeholder: "Add a subtask"
                            ) {
                                saveSubtaskAndContinue(using: proxy)
                            }
                                .frame(minHeight: 44)
                                .accessibilityHint("Press Return to save and add another subtask")
                        }
                        .padding(.vertical, AgentSpacing.x2)
                        .id(Self.subtaskComposerID)
                    } else {
                        AgentAddActionRow(title: "Add subtask") {
                            isAddingSubtask = true
                            Task { @MainActor in
                                await Task.yield()
                                newSubtaskFocused = true
                                scrollSubtaskComposerIntoView(using: proxy)
                            }
                        }
                        .padding(.top, AgentSpacing.x2)
                    }
                }

                }
                .padding(AgentLayout.pageMargin)
                .agentBottomNavigationClearance()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: newSubtaskFocused) { _, isFocused in
                guard isFocused else { return }
                scrollSubtaskComposerIntoView(using: proxy)
            }
        }
#if targetEnvironment(macCatalyst)
        .safeAreaInset(edge: .top, spacing: 0) {
            desktopDetailRail
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
#else
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                TaskSaveToolbarButton(draft: textDraft, action: saveAndDismiss)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem(placement: .topBarTrailing) {
                AgentToolbarIconButton(title: "Task options", icon: .more) {
                    showTaskOptions = true
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
#endif
        .confirmationDialog("Task options", isPresented: $showTaskOptions, titleVisibility: .hidden) {
            if !completedSubtasks.isEmpty {
                Button(showCompletedSubtasks ? "Hide completed subtasks" : "Show completed subtasks") {
                    showCompletedSubtasks.toggle()
                }
            }
            Button("Duplicate task") { duplicate() }
            Button("Delete task", role: .destructive) { confirmDelete = true }
            Button("Cancel", role: .cancel) {}
        }
        .onDisappear {
            guard TaskDetailExitPolicy.shouldPersistOnDisappear(state: exitState) else { return }
            persistEdits(
                failureMessage: "Couldn’t save your task edits. Reopen the task to retry."
            )
        }
        .onAppear {
            if originalFocusTemplateSignature == nil {
                originalFocusTemplateSignature = focusTemplateSignature
            }
        }
        .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete task", role: .destructive) {
                guard appModel.deleteTask(task, context: context) else { return }
                exitState = .deleted
                dismiss()
            }
        } message: { Text("This also deletes its subtasks.") }
        .sheet(isPresented: $showDueDateEditor) {
            TaskDueDateEditor(task: task)
                .presentationDetents([.large])
                .agentSheetDragIndicator()
        }
        .agentScreen()
        .agentKeyboardDismissal()
    }

#if targetEnvironment(macCatalyst)
    private var desktopDetailRail: some View {
        AgentDesktopDetailRail(title: "Task", backAction: dismiss.callAsFunction) {
            HStack(spacing: AgentSpacing.x2) {
                AgentDesktopDetailIconButton(
                    title: "Save task",
                    icon: .check,
                    isEnabled: !textDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    action: saveAndDismiss
                )

                AgentDesktopDetailIconButton(title: "Task options", icon: .more) {
                    showTaskOptions = true
                }
            }
        }
    }
#endif

    private var overdueActions: some View {
        HStack(spacing: AgentSpacing.x2) {
            overdueAction("Complete", isPrimary: true) {
                performActionAndDismiss {
                    appModel.toggleTask(task, context: context)
                }
            }
            overdueAction("Move to today") {
                performActionAndDismiss {
                    appModel.moveTaskToToday(task, context: context)
                }
            }
            overdueAction("Skip") {
                performActionAndDismiss {
                    appModel.skipTask(task, context: context)
                }
            }
        }
        .padding(AgentSpacing.x2)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.control)
                .stroke(Color.agentBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func overdueAction(
        _ title: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.paperInter(size: 13, weight: isPrimary ? .semibold : .medium, relativeTo: .subheadline))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 42)
                .foregroundStyle(isPrimary ? Color.agentText : Color.agentSecondary)
                .background(
                    isPrimary ? Color.agentText.opacity(0.09) : Color.clear,
                    in: .rect(cornerRadius: AgentRadius.control)
                )
                .overlay {
                    if !isPrimary {
                        RoundedRectangle(cornerRadius: AgentRadius.control)
                            .stroke(Color.agentBorder, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var activePillars: [Pillar] {
        TaskDetailPillarPolicy.activePillars(
            from: pillars,
            taskWorkspaceID: task.workspaceID,
            workspaces: workspaces
        )
    }
    private var selectedPillar: Pillar? { activePillars.first { $0.id == task.pillarID } }
    private var dueDateLabel: String {
        guard let date = task.targetDate ?? task.dailyFocusDate else { return "No due date" }
        if task.includesTargetTime {
            return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    @ViewBuilder
    private var taskSetupRows: some View {
        VStack(spacing: 0) {
            if task.lane == .pillar {
                Menu {
                    Button("No pillar") { task.pillarID = nil }
                    ForEach(activePillars) { pillar in
                        Button {
                            task.pillarID = pillar.id
                        } label: {
                            PillarMenuChoiceLabel(
                                title: pillar.name,
                                colorHex: pillar.resolvedColorHex(in: activePillars),
                                isSelected: task.pillarID == pillar.id
                            )
                        }
                    }
                } label: {
                    TaskEditorSetupRow(
                        label: "Pillar",
                        value: selectedPillar?.name ?? "No pillar",
                        color: selectedPillar.map { Color(agentHex: $0.resolvedColorHex(in: activePillars)) }
                    )
                }
            } else if !isLinkedPostTask {
                if isDailyFocusLocked {
                    TaskEditorSetupRow(
                        label: "Focus",
                        value: task.dailyFocusTitle ?? task.kind.title,
                        showsChevron: false
                    )
                } else {
                    Menu {
                        ForEach(CreatorTaskKind.allCases) { kind in
                            Button(kind.title) { task.kind = kind }
                        }
                    } label: {
                        TaskEditorSetupRow(label: "Focus", value: task.kind.title)
                    }
                }
            }

            Menu {
                ForEach(TaskPriority.selectableCases) { priority in
                    Button(priority.title) { task.priority = priority }
                }
            } label: {
                TaskEditorSetupRow(label: "Priority", value: task.priority.normalized.title)
            }

            Menu {
                Button("Open") {
                    if task.isCompleted { appModel.toggleTask(task, context: context) }
                }
                Button("Completed") {
                    if !task.isCompleted { appModel.toggleTask(task, context: context) }
                }
            } label: {
                TaskEditorSetupRow(label: "Status", value: task.isCompleted ? "Completed" : "Open")
            }

            Button { showDueDateEditor = true } label: {
                TaskEditorSetupRow(label: "Due", value: dueDateLabel)
            }
            .buttonStyle(.plain)

            if task.lane == .production {
                Menu {
                    ForEach(TaskRecurrenceFrequency.allCases) { frequency in
                        Button(frequency.title) {
                            task.recurrence = frequency
                            if frequency != .none, task.targetDate == nil { task.targetDate = Date() }
                            if frequency != .none, task.recurrenceRootTaskID == nil {
                                task.recurrenceRootTaskID = task.id
                            }
                        }
                    }
                } label: {
                    TaskEditorSetupRow(label: "Repeat", value: task.recurrence.title)
                }
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.agentText.opacity(0.08)).frame(height: 1)
        }
    }

    private func saveSubtaskAndContinue(using proxy: ScrollViewProxy) {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        guard appModel.createSubtask(title: title, parent: task, context: context) != nil else { return }
        newSubtaskTitle = ""
        Task { @MainActor in
            await Task.yield()
            scrollSubtaskComposerIntoView(using: proxy)
        }
    }

    private func scrollSubtaskComposerIntoView(using proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(Self.subtaskComposerID, anchor: .center)
            }
        }
    }

    private func saveAndDismiss() {
        guard persistEdits(failureMessage: "Couldn’t save this task. Try again.") else { return }
        exitState = .persisted
        dismiss()
    }

    private func duplicate() {
        commitTextDraft()
        context.insert(TaskDetailDuplicationPolicy.copy(of: task))
        do {
            try context.save()
            appModel.queueCalendarSync(context: context)
        } catch {
            context.rollback()
            appModel.notice = .error("Couldn’t duplicate this task. Try again.")
        }
    }

    @discardableResult
    private func persistEdits(failureMessage: String) -> Bool {
        commitTextDraft()
        markFocusTemplateCustomizedIfNeeded()
        do {
            try context.save()
        } catch {
            context.rollback()
            appModel.notice = .error(failureMessage)
            return false
        }
        appModel.queueCalendarSync(context: context)
        return true
    }

    private func performActionAndDismiss(_ action: () -> Bool) {
        commitTextDraft()
        markFocusTemplateCustomizedIfNeeded()
        guard action() else { return }
        exitState = .persisted
        dismiss()
    }

    private func markFocusTemplateCustomizedIfNeeded() {
        if task.focusTaskTemplateID != nil,
           originalFocusTemplateSignature.map({ $0 != focusTemplateSignature }) == true {
            task.isFocusTemplateCustomized = true
        }
    }

    private func commitTextDraft() {
        if task.title != textDraft.title {
            task.title = textDraft.title
        }
        if task.notes != textDraft.notes {
            task.notes = textDraft.notes
        }
    }

    private var focusTemplateSignature: String {
        [
            task.title,
            task.notes,
            task.kind.rawValue,
            task.priority.normalized.rawValue,
            String(task.targetDate?.timeIntervalSinceReferenceDate ?? -1),
            String(task.includesTargetTime),
            task.recurrence.rawValue,
        ].joined(separator: "|")
    }
}

struct PersistentSubmitTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )
        textField.borderStyle = .none
        textField.clearButtonMode = .never
        textField.returnKeyType = .next
        textField.placeholder = placeholder
        textField.textColor = UIColor(Color.agentText)
        textField.tintColor = UIColor(Color.actionAccent)
        let baseFont: UIFont
        if let interFont = UIFont(name: "InterVariable", size: 16) {
            baseFont = interFont
        } else {
            assertionFailure("InterVariable.ttf must be registered before rendering task text.")
            baseFont = .systemFont(ofSize: 16)
        }
        textField.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: baseFont)
        textField.adjustsFontForContentSizeCategory = true
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.parent = self
        if textField.text != text {
            textField.text = text
        }
        textField.placeholder = placeholder

        if isFocused, !textField.isFirstResponder {
            DispatchQueue.main.async {
                textField.becomeFirstResponder()
            }
        } else if !isFocused, textField.isFirstResponder {
            DispatchQueue.main.async {
                textField.resignFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PersistentSubmitTextField

        init(parent: PersistentSubmitTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }
}

private struct TaskEditorSetupRow: View {
    let label: String
    let value: String
    var color: Color?
    var showsChevron = true

    var body: some View {
        HStack(spacing: 14) {
            // Wide enough for the longest tracked label ("PRIORITY") on
            // device — 68 wrapped the final letter.
            MetaLabel(label)
                .frame(width: 92, alignment: .leading)
            HStack(spacing: AgentSpacing.x2) {
                if let color {
                    Circle().fill(color).frame(width: 8, height: 8)
                }
                Text(value)
                    .font(.paperInter(size: 15, weight: .regular, relativeTo: .body))
                    .lineLimit(1)
            }
            Spacer(minLength: AgentSpacing.x2)
            if showsChevron {
                AgentIconView(.forward, size: 12)
            }
        }
        .foregroundStyle(Color.agentText)
        .frame(maxWidth: .infinity, minHeight: 58)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.agentText.opacity(0.08)).frame(height: 1)
        }
        .contentShape(.rect)
    }
}

private struct TaskDueDateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Bindable var task: CreatorTask
    @State private var hasDate: Bool
    @State private var includesTime: Bool
    @State private var date: Date

    init(task: CreatorTask) {
        self.task = task
        let initialDate = task.targetDate ?? task.dailyFocusDate ?? Date()
        _hasDate = State(initialValue: TaskDueDatePolicy.initialHasDate(
            targetDate: task.targetDate,
            dailyFocusDate: task.dailyFocusDate,
            recurrence: task.recurrence
        ))
        _includesTime = State(initialValue: task.includesTargetTime)
        _date = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    if let focusDate = task.dailyFocusDate {
                        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                            MetaLabel("Focus day")
                            Text(focusDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                                .font(.agentBody.weight(.semibold))
                                .foregroundStyle(Color.agentText)
                        }
                        timeChoice
                    } else {
                        Toggle("Set a due date", isOn: $hasDate)
                            .font(.agentBody.weight(.semibold))
                            .tint(Color.actionAccent)
                            .disabled(!TaskDueDatePolicy.allowsRemoval(recurrence: task.recurrence))

                        if !TaskDueDatePolicy.allowsRemoval(recurrence: task.recurrence) {
                            Text("Repeating tasks need a due date.")
                                .font(.agentSubtext)
                                .foregroundStyle(Color.agentSecondary)
                        }

                        if hasDate {
                            PillarCalendarDatePicker(date: $date, pillarMarkers: [])
                                .frame(minHeight: 330)

                            timeChoice
                        }
                    }
                }
                .padding(AgentLayout.pageMargin)
            }
            .navigationTitle("Due date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(hasDate ? "Set date" : "Remove date", action: apply)
                        .fontWeight(.semibold)
                }
            }
            .agentScreen()
        }
    }

    private func apply() {
        do {
            try TaskDueDatePolicy.apply(
                to: task,
                hasDate: hasDate,
                selectedDate: date,
                includesTime: includesTime,
                persist: context.save
            )
        } catch TaskDueDatePolicy.Error.recurringRequiresDate {
            appModel.notice = .info("Repeating tasks need a due date.")
            return
        } catch {
            appModel.notice = .error("Couldn’t save this date. Try again.")
            return
        }
        appModel.queueCalendarSync(context: context)
        dismiss()
    }

    @ViewBuilder
    private var timeChoice: some View {
        VStack(spacing: 0) {
            Toggle("Include a time", isOn: $includesTime)
                .font(.agentBody.weight(.semibold))
                .tint(Color.actionAccent)
                .frame(minHeight: 52)
            if includesTime {
                Divider().overlay(Color.agentHairline)
                HStack {
                    Text("Time").font(.agentBody)
                    Spacer()
                    DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                .frame(minHeight: 52)
            }
        }
    }

}
