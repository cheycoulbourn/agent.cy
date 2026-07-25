import SwiftData
import SwiftUI
import UIKit

struct TaskNavigationRoute: Hashable {
    let taskID: UUID
}

private struct TaskNavigationDestinationView: View {
    let route: TaskNavigationRoute
    @Environment(AppModel.self) private var appModel
    @Query(sort: \CreatorTask.createdAt, order: .reverse) private var tasks: [CreatorTask]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]

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
            guard let date, let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return false }
            return week.contains(date)
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

struct TasksView: View {
    enum StatusFilter: String, CaseIterable, Identifiable {
        case open = "Open"
        case completed = "Completed"
        case archive = "Archived"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var appModel
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

    private func filtered(for collection: TaskCollection) -> [CreatorTask] {
        tasks
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
                      ) == collection,
                      TaskListVisibilityPolicy.includes(
                        collection: collection,
                        focusTaskTemplateID: task.focusTaskTemplateID,
                        recurrence: task.recurrence,
                        recurrenceRootTaskID: task.recurrenceRootTaskID,
                        targetDate: visibilityDate(for: task)
                      )
                else { return false }
                let isArchived = task.briefID.map(archivedBriefIDs.contains) == true
                switch status {
                case .open:
                    guard !task.isCompleted && !isArchived else { return false }
                case .completed:
                    guard task.isCompleted && !isArchived else { return false }
                case .archive:
                    guard isArchived else { return false }
                }

                return TaskListFilterPolicy.matchesDate(
                    visibilityDate(for: task),
                    filter: dateFilter,
                    selectedDate: selectedFilterDate
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

    private func visibilityDate(for task: CreatorTask) -> Date? {
        if let targetDate = task.targetDate { return targetDate }
        if let dailyFocusDate = task.dailyFocusDate { return dailyFocusDate }
        if let outputID = task.platformOutputID,
           let targetDate = outputs.first(where: { $0.id == outputID })?.targetDate {
            return targetDate
        }
        if let briefID = task.briefID {
            if let targetDate = outputs
                .filter({ $0.briefID == briefID })
                .compactMap(\.targetDate)
                .min() {
                return targetDate
            }
            return briefs.first(where: { $0.id == briefID })?.agendaDate
        }
        return nil
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
            Picker("Task list", selection: $collection) {
                ForEach(TaskCollection.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AgentLayout.dashboardGutter)
            .padding(.bottom, AgentSpacing.x3)

            TabView(selection: $collection) {
                ForEach(TaskCollection.allCases) { page in
                    taskPage(for: page)
                        .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy(duration: 0.24), value: collection)
            .background(Color.agentSurface)
            .clipShape(.rect(cornerRadius: AgentRadius.dashboard))
            .agentSurfaceChrome(cornerRadius: AgentRadius.dashboard)
            .padding(.horizontal, AgentLayout.dashboardGutter)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isAddingPostTask) {
            PostTaskCreationFlow()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isFilterPresented) {
            taskFilterSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: appModel.activeWorkspaceID) {
            pillarFilter = .all
        }
        .agentScreen()
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
        }
        .foregroundStyle(Color.agentText)
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x8)
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
                AgentIconView(.filter, size: 16)
                    .foregroundStyle(Color.agentText)
                    .frame(width: 44, height: 44)

                if activeFilterCount > 0 {
                    Text("\(activeFilterCount)")
                        .font(.agentInter(size: 10, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(Color.agentSurface)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Color.agentText, in: .circle)
                        .offset(x: 2, y: 2)
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
                        .font(.agentBody.weight(.semibold))
                        .foregroundStyle(Color.agentText)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.agentSurface, in: .capsule)
                        .overlay {
                            Capsule().stroke(Color.agentBorder, lineWidth: 0.75)
                        }
                        .buttonStyle(.plain)
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
                AgentIconView(.moveVertical, size: 11)
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
        selectedFilterDate = Date()
        pillarFilter = .all
        priorityFilter = nil
        focusFilter = .all
    }

    @ViewBuilder
    private func taskPage(for collection: TaskCollection) -> some View {
        let visibleTasks = filtered(for: collection)
        if visibleTasks.isEmpty {
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
            completedList(for: collection)
        } else {
            openList(for: collection)
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

    private func openList(for collection: TaskCollection) -> some View {
        List {
            ForEach(dueDateGroups(for: collection)) { group in
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
        .contentMargins(.bottom, 104, for: .scrollContent)
        .background(Color.agentSurface)
    }

    private func completedList(for collection: TaskCollection) -> some View {
        List {
            ForEach(dueDateGroups(for: collection)) { group in
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
        .contentMargins(.bottom, 104, for: .scrollContent)
        .background(Color.agentSurface)
    }

    private func row(_ task: CreatorTask) -> some View {
        TaskRow(
            task: task,
            allTasks: tasks,
            linkedPostTitle: linkedPostTitle(for: task)
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

    private func dueDateGroups(for collection: TaskCollection) -> [TaskDueDateGroup] {
        let grouped = Dictionary(grouping: filtered(for: collection)) { task in
            task.targetDate.map(Calendar.current.startOfDay(for:))
        }
        return grouped.map { day, tasks in
            TaskDueDateGroup(day: day, tasks: tasks.sorted(by: sortTasks))
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

    private func dueDateGroupHeader(_ group: TaskDueDateGroup, collection: TaskCollection) -> some View {
        let canCollapse = collection == .myTasks && status == .open
        return Button {
            guard canCollapse else { return }
            if collapsedMyTaskDays.contains(group.id) {
                collapsedMyTaskDays.remove(group.id)
            } else {
                collapsedMyTaskDays.insert(group.id)
            }
        } label: {
            HStack(spacing: AgentSpacing.x2) {
                MetaLabel(group.title)
                    .foregroundStyle(group.isPastDue ? Color.cyAccent : Color.agentSecondary)
                Spacer()
                MetaLabel("\(group.tasks.count)")
                if canCollapse {
                    AgentIconView(isCollapsed(group, collection: collection) ? .expand : .collapse)
                        .font(.agentInter(size: 11, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(Color.agentSecondary)
                        .frame(width: 20, height: 20)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(canCollapse)
        .padding(.top, AgentSpacing.x3)
        .padding(.bottom, AgentSpacing.x2)
    }

    private func isCollapsed(_ group: TaskDueDateGroup, collection: TaskCollection) -> Bool {
        collection == .myTasks && status == .open && collapsedMyTaskDays.contains(group.id)
    }

    private func sortTasks(_ lhs: CreatorTask, _ rhs: CreatorTask) -> Bool {
        let rank: (CreatorTask) -> Int = { task in task.priority == .urgent ? 0 : (task.priority == .high ? 1 : 2) }
        if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
        if (lhs.targetDate ?? .distantFuture) != (rhs.targetDate ?? .distantFuture) {
            return (lhs.targetDate ?? .distantFuture) < (rhs.targetDate ?? .distantFuture)
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

    private var briefs: [CreativeBrief] {
        allBriefs.filter {
            $0.status != .archived && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private var outputs: [PlatformOutput] {
        allOutputs.filter {
            $0.status == .scheduled && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            ) && brief(for: $0) != nil
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

    private var weekStart: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let daysSinceMonday = (calendar.component(.weekday, from: today) + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
    }

    private var weekEnd: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
    }

    private var visibleOutputs: [PlatformOutput] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return outputs.filter { output in
            guard let brief = brief(for: output) else { return false }
            if query.isEmpty {
                guard let date = output.targetDate else { return false }
                return date >= weekStart && date < weekEnd
            }
            return displayTitle(for: output, brief: brief).localizedStandardContains(query)
                || brief.notes.localizedStandardContains(query)
                || output.platform.title.localizedStandardContains(query)
                || pillar(for: brief)?.name.localizedStandardContains(query) == true
        }
        .sorted { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
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
                            trailing: "\(visibleOutputs.count)"
                        )

                        if visibleOutputs.isEmpty {
                            Text(emptyMessage)
                                .font(.agentBody)
                                .foregroundStyle(Color.agentSecondary)
                                .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                        } else {
                            ForEach(Array(visibleOutputs.enumerated()), id: \.element.id) { index, output in
                                if let brief = brief(for: output) {
                                    NavigationLink {
                                        LinkedPostTaskComposer(
                                            brief: brief,
                                            output: output,
                                            onSaved: {
                                                onTaskSaved?()
                                                dismiss()
                                            }
                                        )
                                    } label: {
                                        postRow(output: output, brief: brief)
                                    }
                                    .buttonStyle(.plain)
                                    .overlay(alignment: .bottom) {
                                        if index < visibleOutputs.count - 1 {
                                            Rectangle().fill(Color.agentHairline).frame(height: 1)
                                        }
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

    private func postRow(output: PlatformOutput, brief: CreativeBrief) -> some View {
        HStack(spacing: AgentSpacing.x3) {
            Circle()
                .fill(pillar(for: brief).map { Color(agentHex: $0.resolvedColorHex(in: pillars)) } ?? .agentSecondary)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                Text(displayTitle(for: output, brief: brief))
                    .font(.agentBody.weight(.semibold))
                    .foregroundStyle(Color.agentText)
                    .lineLimit(2)
                Text(postMetadata(output: output, brief: brief))
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

    private func brief(for output: PlatformOutput) -> CreativeBrief? {
        briefs.first { $0.id == output.briefID }
    }

    private func pillar(for brief: CreativeBrief) -> Pillar? {
        brief.pillarID.flatMap { id in pillars.first { $0.id == id } }
    }

    private func displayTitle(for output: PlatformOutput, brief: CreativeBrief) -> String {
        let override = output.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? brief.title : override
    }

    private func postMetadata(output: PlatformOutput, brief: CreativeBrief) -> String {
        let date = output.targetDate?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? "No date"
        return [pillar(for: brief)?.name ?? "Unfiled", output.platform.title, date]
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
                        .background(Color.agentSurface, in: .rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.agentText.opacity(0.16), lineWidth: 1)
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
                Button(action: save) {
                    AgentIconView(.check, size: 15)
                        .foregroundStyle(Color.agentPureBlack)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .tint(Color.agentPureWhite)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                .accessibilityLabel("Add task")
            }
        }
        .agentScreen()
        .sheet(isPresented: $showDueDatePicker) {
            CaptureTaskDueDateSheet(
                date: $date,
                hasDueDate: $includeDate,
                includesTime: $includesTime
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
        guard let task = appModel.createTask(
            title: cleanTitle,
            kind: .planning,
            lane: .production,
            priority: priority,
            targetDate: targetDate,
            includesTargetTime: includeDate && includesTime,
            recurrence: recurrence,
            briefID: brief.id,
            pillarID: brief.pillarID,
            platformOutputID: output.id,
            context: context
        ) else { return }

        task.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        for draft in subtasks {
            let subtaskTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !subtaskTitle.isEmpty,
                  let subtask = appModel.createSubtask(title: subtaskTitle, parent: task, context: context)
            else { continue }
            if draft.isCompleted {
                subtask.isCompleted = true
                subtask.completedAt = Date()
            }
        }
        try? context.save()
        onSaved()
    }
}

struct TaskDueDateGroup: Identifiable {
    let day: Date?
    let tasks: [CreatorTask]

    var id: String {
        day.map { String(Calendar.current.startOfDay(for: $0).timeIntervalSinceReferenceDate) }
            ?? "no-date"
    }

    var title: String {
        guard let day else { return "No due date" }
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInTomorrow(day) { return "Tomorrow" }
        if isPastDue {
            return "Past due · \(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))"
        }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var isPastDue: Bool {
        guard let day else { return false }
        return Calendar.current.startOfDay(for: day) < Calendar.current.startOfDay(for: Date())
    }
}

struct TaskRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    let task: CreatorTask
    let allTasks: [CreatorTask]
    var linkedPostTitle: String? = nil
    var verticalInset: CGFloat = AgentSpacing.x1
    @State private var showsDetail = false

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
            HStack(alignment: .top, spacing: AgentSpacing.x2) {
                taskCheckbox(task, accessibilityPrefix: "task")

                Button {
                    showsDetail = true
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.title)
                            .font(.agentBody.weight(.semibold))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .strikethrough(task.isCompleted)
                            .foregroundStyle(task.isCompleted ? Color.agentSecondary : Color.agentText)
                        metadataLine
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }

            if !visibleSubtasks.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleSubtasks) { subtask in
                        HStack(spacing: AgentSpacing.x2) {
                            taskCheckbox(subtask, accessibilityPrefix: "subtask")

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
        .navigationDestination(isPresented: $showsDetail) {
            TaskDetailView(task: task)
        }
    }

    private func taskCheckbox(_ item: CreatorTask, accessibilityPrefix: String) -> some View {
        AgentTaskCheckbox(
            isCompleted: item.isCompleted,
            color: checkboxColor(for: item),
            accessibilityLabel: item.isCompleted
                ? "Mark \(accessibilityPrefix) open"
                : "Complete \(accessibilityPrefix)"
        ) {
            appModel.toggleTask(item, context: context)
        }
        .zIndex(1)
        .accessibilityIdentifier("task-checkbox-\(item.id.uuidString)")
    }

    private var metadataLine: some View {
        HStack(spacing: 6) {
            if let linkedPostTitle {
                metadata(linkedPostTitle.uppercased())
                metadataDivider
            } else {
                metadata(task.isCompleted ? "COMPLETED" : (isOverdue ? "PAST DUE" : "OPEN"), color: statusColor)
                metadataDivider
            }
            metadata(dateText.uppercased())
            metadataDivider
            metadata(task.priority.normalized.title.uppercased(), color: priorityColor)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .accessibilityElement(children: .combine)
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
        case .high: .orange
        default: .agentSecondary
        }
    }

    private var statusColor: Color {
        isOverdue && !task.isCompleted ? .cyAccent : .agentSecondary
    }

    private var isOverdue: Bool {
        guard let targetDate = task.targetDate else { return false }
        return !task.isCompleted && Calendar.current.startOfDay(for: targetDate) < Calendar.current.startOfDay(for: Date())
    }

    private func checkboxColor(for task: CreatorTask) -> Color {
        switch task.priority.normalized {
        case .urgent: .agentDestructive
        case .high: .orange
        default: .agentBorder
        }
    }

    private var dateText: String {
        guard let date = task.targetDate else { return "None" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct TaskDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var task: CreatorTask
    @Query(sort: \CreatorTask.createdAt) private var allTasks: [CreatorTask]
    @Query private var briefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt) private var outputs: [PlatformOutput]
    @Query private var pillars: [Pillar]
    @State private var isAddingSubtask = false
    @State private var newSubtaskTitle = ""
    @State private var showCompletedSubtasks = false
    @State private var confirmDelete = false
    @State private var showDueDateEditor = false
    @State private var originalFocusTemplateSignature: String?
    @State private var newSubtaskFocused = false
    @FocusState private var notesAreFocused: Bool
    private static let subtaskComposerID = "task-detail-subtask-composer"

    private var subtasks: [CreatorTask] { allTasks.filter { $0.parentTaskID == task.id }.sorted { $0.sortOrder < $1.sortOrder } }
    private var completedSubtasks: [CreatorTask] { subtasks.filter(\.isCompleted) }
    private var visibleSubtasks: [CreatorTask] {
        showCompletedSubtasks ? subtasks : subtasks.filter { !$0.isCompleted }
    }
    private var linkedOutput: PlatformOutput? { TaskLinkedPostPolicy.output(for: task, in: outputs) }
    private var linkedBrief: CreativeBrief? {
        (task.briefID ?? linkedOutput?.briefID).flatMap { id in briefs.first { $0.id == id } }
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

                TextField("What's the task?", text: $task.title, axis: .vertical)
                    .font(.paperInter(size: 28, weight: .bold, relativeTo: .title))
                    .tracking(-0.56)
                    .lineLimit(1...3)

                if isOverdueMyTask {
                    overdueActions
                }

                taskSetupRows

                if task.recurrence != .none {
                    Text("The next task is added when this one is completed.")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    AgentInputHeader(title: "Notes", isEditing: notesAreFocused) {
                        notesAreFocused = false
                    }
                    TextEditor(text: $task.notes)
                        .font(.paperInter(size: 16, weight: .regular, relativeTo: .body))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 132)
                        .padding(16)
                        .background(Color.agentSurface, in: .rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.agentText.opacity(0.16), lineWidth: 1)
                        }
                        .focused($notesAreFocused)
                }

                if let linkedBrief {
                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        MetaLabel("Linked post")
                        NavigationLink {
                            if let linkedOutput {
                                PostOutputDetailView(brief: linkedBrief, output: linkedOutput)
                            } else {
                                IdeaPostDraftView(brief: linkedBrief)
                            }
                        } label: {
                            Text(linkedBrief.title)
                        }
                        .font(.agentBody.weight(.semibold))
                        .foregroundStyle(Color.agentText)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionRuleHeader(title: "Subtasks")
                    .padding(.bottom, AgentSpacing.x2)

                    ForEach(visibleSubtasks) { subtask in
                        HStack(spacing: AgentSpacing.x2) {
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
                        HStack(spacing: AgentSpacing.x2) {
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
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: saveAndDismiss) {
                    AgentIconView(.check, size: 15)
                        .foregroundStyle(Color.agentText)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .tint(Color.agentSurface)
                .disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                .accessibilityLabel("Save task")
            }

            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !completedSubtasks.isEmpty {
                        Button(showCompletedSubtasks ? "Hide completed subtasks" : "Show completed subtasks") {
                            showCompletedSubtasks.toggle()
                        }
                    }
                    Button("Duplicate task") { duplicate() }
                    Button("Delete task", role: .destructive) { confirmDelete = true }
                } label: {
                    AgentIconView(.more, size: 14)
                        .foregroundStyle(Color.agentText)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .tint(Color.agentSurface)
                .accessibilityLabel("Task options")
            }
        }
        .onDisappear {
            if task.focusTaskTemplateID != nil,
               originalFocusTemplateSignature.map({ $0 != focusTemplateSignature }) == true {
                task.isFocusTemplateCustomized = true
            }
            try? context.save()
            appModel.queueCalendarSync(context: context)
        }
        .onAppear {
            if originalFocusTemplateSignature == nil {
                originalFocusTemplateSignature = focusTemplateSignature
            }
        }
        .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete task", role: .destructive) { appModel.deleteTask(task, context: context); dismiss() }
        } message: { Text("This also deletes its subtasks.") }
        .sheet(isPresented: $showDueDateEditor) {
            TaskDueDateEditor(task: task)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .agentScreen()
        .agentKeyboardDismissal()
    }

    private var overdueActions: some View {
        HStack(spacing: AgentSpacing.x2) {
            overdueAction("Complete", isPrimary: true) {
                appModel.toggleTask(task, context: context)
                dismiss()
            }
            overdueAction("Move to today") {
                appModel.moveTaskToToday(task, context: context)
                dismiss()
            }
            overdueAction("Skip") {
                appModel.skipTask(task, context: context)
                dismiss()
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
                .font(.paperInter(size: 13, weight: .semibold, relativeTo: .subheadline))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 42)
                .foregroundStyle(isPrimary ? Color.agentCanvas : Color.agentText)
                .background(isPrimary ? Color.agentText : Color.clear, in: .capsule)
                .overlay {
                    if !isPrimary {
                        Capsule().stroke(Color.agentBorder, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
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
        try? context.save()
        appModel.queueCalendarSync(context: context)
        dismiss()
    }

    private func duplicate() {
        context.insert(CreatorTask(briefID: task.briefID, pillarID: task.pillarID, platformOutputID: task.platformOutputID, title: "\(task.title) copy", kind: task.kind, lane: task.lane, priority: task.priority.normalized, notes: task.notes, targetDate: task.targetDate, includesTargetTime: task.includesTargetTime, dailyFocusDate: task.dailyFocusDate, dailyFocusTitle: task.dailyFocusTitle, dailyFocusTemplateEntryID: task.dailyFocusTemplateEntryID))
        try? context.save()
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
            MetaLabel(label)
                .frame(width: 68, alignment: .leading)
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
        _hasDate = State(initialValue: task.targetDate != nil || task.dailyFocusDate != nil)
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
                    Button("Set date", action: apply)
                        .fontWeight(.semibold)
                }
            }
            .agentScreen()
        }
    }

    private func apply() {
        if let focusDate = task.dailyFocusDate {
            task.targetDate = date(on: focusDate, usingTimeFrom: date, includesTime: includesTime)
        } else {
            task.targetDate = hasDate
                ? date(on: date, usingTimeFrom: date, includesTime: includesTime)
                : nil
        }
        task.includesTargetTime = hasDate && includesTime
        try? context.save()
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

    private func date(on day: Date, usingTimeFrom timeSource: Date, includesTime: Bool) -> Date {
        let calendar = Calendar.current
        guard includesTime else { return calendar.startOfDay(for: day) }
        let time = calendar.dateComponents([.hour, .minute], from: timeSource)
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = time.hour
        components.minute = time.minute
        return calendar.date(from: components) ?? day
    }
}
