import SwiftData
import SwiftUI

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
            ContentUnavailableView(
                "Task not found",
                systemImage: "checkmark.square",
                description: Text("It may have been completed or deleted.")
            )
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

struct TasksView: View {
    private enum StatusFilter: String, CaseIterable, Identifiable {
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
    @State private var collection: TaskCollection = .postTasks
    @State private var status: StatusFilter = .open
    @State private var isFilterPresented = false
    @State private var collapsedMyTaskDays: Set<String> = []

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
                    return !task.isCompleted && !isArchived
                case .completed:
                    return task.isCompleted && !isArchived
                case .archive:
                    return isArchived
                }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Picker("Task list", selection: $collection) {
                ForEach(TaskCollection.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.bottom, AgentSpacing.x4)

            TabView(selection: $collection) {
                ForEach(TaskCollection.allCases) { page in
                    taskPage(for: page)
                        .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy(duration: 0.24), value: collection)
        }
        .toolbar(.hidden, for: .navigationBar)
        .agentScreen()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            AgentPageRail(
                breadcrumb: "Tasks",
                profile: profiles.first,
                openSettings: { appModel.presentedSheet = .settings }
            ) {
                statusFilterButton
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Your")
                    .font(.system(size: 32, weight: .regular, design: .default))
                Text("tasks.")
                    .font(.agentDisplay)
            }
            .tracking(-0.64)
        }
        .foregroundStyle(Color.agentText)
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x8)
        .padding(.bottom, AgentSpacing.x8)
    }

    private var statusFilterButton: some View {
        Button {
            isFilterPresented.toggle()
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.agentText)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: $isFilterPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(StatusFilter.allCases) { filter in
                    Button {
                        status = filter
                        isFilterPresented = false
                    } label: {
                        HStack(spacing: AgentSpacing.x3) {
                            Text(filter.rawValue)
                                .font(.paperInter(size: 16, weight: .regular, relativeTo: .body))
                                .foregroundStyle(Color.agentText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if status == filter {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.agentText)
                            }
                        }
                        .padding(.horizontal, AgentSpacing.x4)
                        .frame(minHeight: 46)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, AgentSpacing.x2)
            .frame(width: 220)
            .presentationCompactAdaptation(.popover)
            .presentationBackground(.ultraThinMaterial)
            .presentationCornerRadius(24)
        }
        .accessibilityLabel("Filter tasks")
        .accessibilityValue(status.rawValue)
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
                if status == .open, collection == .myTasks {
                    Button("Add task") { openTaskComposer() }
                        .buttonStyle(AgentCompactPrimaryButtonStyle())
                }
            }
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
            if shouldGroupByDueDate(for: collection) || collection == .myTasks {
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
            } else {
                ForEach(filtered(for: collection)) { task in row(task) }
            }
            if collection == .myTasks {
                AgentAddActionRow(title: "Add task") { openTaskComposer() }
                    .listRowInsets(EdgeInsets(
                        top: AgentSpacing.x2,
                        leading: AgentLayout.pageMargin,
                        bottom: AgentSpacing.x2,
                        trailing: AgentLayout.pageMargin
                    ))
                    .listRowBackground(Color.agentCanvas)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 104, for: .scrollContent)
    }

    private func completedList(for collection: TaskCollection) -> some View {
        List {
            if shouldGroupByDueDate(for: collection) {
                ForEach(dueDateGroups(for: collection)) { group in
                    Section {
                        ForEach(group.tasks) { task in row(task) }
                    } header: {
                        dueDateGroupHeader(group, collection: collection)
                    }
                    .textCase(nil)
                }
            } else {
                ForEach(filtered(for: collection)) { task in row(task) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 104, for: .scrollContent)
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
            .listRowBackground(Color.agentCanvas)
            .listRowSeparatorTint(Color.agentHairline)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
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

    private func shouldGroupByDueDate(for collection: TaskCollection) -> Bool {
        dueDateGroups(for: collection).count > 1
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
                    Image(systemName: isCollapsed(group, collection: collection) ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.agentSecondary)
                        .frame(width: 20, height: 20)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(canCollapse)
        .padding(.top, AgentSpacing.x4)
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

    private func openTaskComposer() {
        appModel.setQuickCaptureMode(.task)
        appModel.quickCapturePillarID = nil
        appModel.quickCaptureTaskLane = .production
        appModel.quickCaptureTaskFocus = nil
        appModel.presentedSheet = .quickCapture
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

                // Local taps stay on the destination-based stack used by the
                // surrounding post or day. Value routes are reserved for
                // external task deep links handled by AppShellView.
                NavigationLink {
                    TaskDetailView(task: task)
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
    }

    private func taskCheckbox(_ item: CreatorTask, accessibilityPrefix: String) -> some View {
        Button { appModel.toggleTask(item, context: context) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(checkboxColor(for: item), lineWidth: 1.25)
                    .background(
                        item.isCompleted ? checkboxColor(for: item) : Color.clear,
                        in: .rect(cornerRadius: 4)
                    )
                    .overlay {
                        if item.isCompleted {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(Color.agentCanvas)
                        }
                    }
                    .frame(width: 19, height: 19)
            }
            .frame(width: 44, height: 44, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .zIndex(1)
        .accessibilityIdentifier("task-checkbox-\(item.id.uuidString)")
        .accessibilityLabel(item.isCompleted ? "Mark \(accessibilityPrefix) open" : "Complete \(accessibilityPrefix)")
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
            .font(.agentMono)
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
    @FocusState private var newSubtaskFocused: Bool
    @FocusState private var notesAreFocused: Bool

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
                            Button {
                                appModel.toggleTask(subtask, context: context)
                            } label: {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.agentBorder, lineWidth: 1.25)
                                    .background(
                                        subtask.isCompleted ? Color.agentText : Color.clear,
                                        in: .rect(cornerRadius: 4)
                                    )
                                    .overlay {
                                        if subtask.isCompleted {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(Color.agentCanvas)
                                        }
                                    }
                                    .frame(width: 19, height: 19)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(subtask.isCompleted ? "Mark subtask open" : "Complete subtask")

                            TextField("Subtask", text: Bindable(subtask).title)
                                .font(.agentBody)
                                .agentSingleLineSubmit()
                                .strikethrough(subtask.isCompleted)
                                .foregroundStyle(subtask.isCompleted ? Color.agentSecondary : Color.agentText)
                        }
                        .padding(.vertical, AgentSpacing.x2)

                        if subtask.id != visibleSubtasks.last?.id {
                            Divider().foregroundStyle(Color.agentHairline)
                        }
                    }

                    if isAddingSubtask {
                        HStack(spacing: AgentSpacing.x2) {
                            TextField("What's the task?", text: $newSubtaskTitle)
                                .font(.agentBody)
                                .submitLabel(.done)
                                .onSubmit(addSubtask)
                                .focused($newSubtaskFocused)
                                .padding(.horizontal, AgentSpacing.x3)
                                .frame(minHeight: 44)
                                .background(Color.agentSurface)
                                .clipShape(.rect(cornerRadius: AgentRadius.control))
                                .overlay {
                                    RoundedRectangle(cornerRadius: AgentRadius.control)
                                        .stroke(Color.agentBorder, lineWidth: 1)
                                }

                            Button(action: addSubtask) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(canAddSubtask ? Color.onAccent : Color.agentSecondary)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        canAddSubtask ? Color.actionAccent : Color.agentSurface,
                                        in: .circle
                                    )
                                    .overlay {
                                        Circle().stroke(
                                            canAddSubtask ? Color.actionAccent : Color.agentBorder,
                                            lineWidth: 1
                                        )
                                    }
                            }
                            .buttonStyle(.plain)
                            .disabled(!canAddSubtask)
                            .accessibilityLabel("Save subtask")
                        }
                        .padding(.top, AgentSpacing.x2)
                    } else {
                        AgentAddActionRow(title: "Add subtask") {
                            isAddingSubtask = true
                            Task { @MainActor in
                                await Task.yield()
                                newSubtaskFocused = true
                            }
                        }
                        .padding(.top, AgentSpacing.x2)
                    }
                }

            }
            .padding(AgentLayout.pageMargin)
            .padding(.bottom, 120)
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .tint(Color.white)
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

    private var canAddSubtask: Bool {
        !newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addSubtask() {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        guard appModel.createSubtask(title: title, parent: task, context: context) != nil else { return }
        newSubtaskTitle = ""
        isAddingSubtask = false
        newSubtaskFocused = false
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
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
                            DatePicker(
                                "Date",
                                selection: $date,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)

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
