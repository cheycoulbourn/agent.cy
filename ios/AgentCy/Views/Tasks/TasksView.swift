import SwiftData
import SwiftUI

struct TaskNavigationRoute: Hashable {
    let taskID: UUID
}

private struct TaskNavigationDestinationView: View {
    let route: TaskNavigationRoute
    @Query(sort: \CreatorTask.createdAt, order: .reverse) private var tasks: [CreatorTask]

    var body: some View {
        if let task = tasks.first(where: { $0.id == route.taskID }) {
            TaskDetailView(task: task)
        } else {
            ContentUnavailableView("Task unavailable", systemImage: "checkmark.square")
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
        case archive = "Archive"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Query(sort: \CreatorTask.createdAt, order: .reverse) private var tasks: [CreatorTask]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @Query private var profiles: [CreatorProfile]
    @State private var lane: TaskLane = .pillar
    @State private var status: StatusFilter = .open
    @State private var isFilterPresented = false
    @State private var deletedBundle: DeletedTaskBundle?
    @State private var clearUndoTask: Task<Void, Never>?

    private var filtered: [CreatorTask] {
        tasks
            .filter { task in
                guard task.parentTaskID == nil, task.lane == lane else { return false }
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
        Set(briefs.lazy.filter { $0.status == .archived }.map(\.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Picker("Task lane", selection: $lane) {
                ForEach(TaskLane.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.bottom, AgentSpacing.x4)

            if filtered.isEmpty {
                ContentUnavailableView {
                    Text(emptyTitle)
                } description: {
                    Text(emptyDescription)
                } actions: {
                    if status == .open {
                        Button("Add task") { openTaskComposer() }
                            .buttonStyle(AgentCompactPrimaryButtonStyle())
                    }
                }
            } else if status != .open {
                completedList
            } else {
                openList
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if deletedBundle != nil {
                HStack {
                    Text("Task deleted").font(.agentSubtext)
                    Spacer()
                    Button("Undo", action: undoDelete).font(.agentSubtext.weight(.semibold))
                }
                .padding(.horizontal, AgentSpacing.x4)
                .frame(height: 48)
                .foregroundStyle(Color.agentCanvas)
                .background(Color.agentText, in: .capsule)
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.bottom, AgentSpacing.x2)
            }
        }
        .agentScreen()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            AgentPageRail(
                breadcrumb: "§ Tasks",
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
        .glassEffect(.clear, in: .circle)
        .overlay {
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
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

    private var emptyTitle: String {
        switch status {
        case .open: "No \(lane.title.lowercased()) yet"
        case .completed: "Nothing completed yet"
        case .archive: "Nothing archived"
        }
    }

    private var emptyDescription: String {
        switch status {
        case .open: "Add one clear next step."
        case .completed: "Completed tasks will appear here."
        case .archive: "Tasks from archived posts will appear here."
        }
    }

    private var openList: some View {
        List {
            if shouldGroupByPillar {
                ForEach(pillarTaskGroups) { group in
                    Section {
                        ForEach(group.tasks) { task in row(task) }
                    } header: {
                        pillarGroupHeader(group)
                    }
                    .textCase(nil)
                }
            } else {
                ForEach(filtered) { task in row(task) }
            }
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
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var completedList: some View {
        List {
            if shouldGroupByPillar {
                ForEach(pillarTaskGroups) { group in
                    Section {
                        ForEach(group.tasks) { task in row(task) }
                    } header: {
                        pillarGroupHeader(group)
                    }
                    .textCase(nil)
                }
            } else if lane == .pillar {
                ForEach(filtered) { task in row(task) }
            } else {
                ForEach(completionGroups, id: \.day) { group in
                    Section(group.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) {
                        ForEach(group.tasks) { task in row(task) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ task: CreatorTask) -> some View {
        TaskRow(task: task, allTasks: tasks)
            .listRowInsets(EdgeInsets(
                top: 0,
                leading: AgentLayout.pageMargin,
                bottom: 0,
                trailing: AgentLayout.pageMargin
            ))
            .listRowBackground(Color.agentCanvas)
            .listRowSeparatorTint(Color.agentHairline)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Delete", role: .destructive) { delete(task) }
                    .tint(Color.agentDestructive)
            }
    }

    private var completionGroups: [(day: Date, tasks: [CreatorTask])] {
        let grouped = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.completedAt ?? $0.createdAt) }
        return grouped.map { ($0.key, $0.value.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }) }
            .sorted { $0.day > $1.day }
    }

    private var pillarTaskGroups: [PillarTaskGroup] {
        let grouped = Dictionary(grouping: filtered, by: \.pillarID)
        return grouped.map { pillarID, tasks in
            let pillar = pillarID.flatMap { id in pillars.first { $0.id == id } }
            return PillarTaskGroup(
                id: pillarID?.uuidString ?? "unassigned",
                pillar: pillar,
                tasks: tasks.sorted(by: sortTasks)
            )
        }
        .sorted { lhs, rhs in
            if lhs.pillar == nil { return false }
            if rhs.pillar == nil { return true }
            return (lhs.pillar?.createdAt ?? .distantFuture) < (rhs.pillar?.createdAt ?? .distantFuture)
        }
    }

    private var shouldGroupByPillar: Bool {
        lane == .pillar && pillarTaskGroups.count > 1
    }

    private func pillarGroupHeader(_ group: PillarTaskGroup) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(group.color)
                .frame(width: 8, height: 8)
            Text(group.title)
                .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                .tracking(-0.26)
            Text("\(group.tasks.count)")
                .font(.agentMono)
                .foregroundStyle(Color.agentSecondary)
            Spacer()
        }
        .foregroundStyle(Color.agentText)
        .padding(.top, AgentSpacing.x4)
        .padding(.bottom, AgentSpacing.x2)
    }

    private func sortTasks(_ lhs: CreatorTask, _ rhs: CreatorTask) -> Bool {
        let rank: (CreatorTask) -> Int = { task in task.priority == .urgent ? 0 : (task.priority == .high ? 1 : 2) }
        if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
        if (lhs.targetDate ?? .distantFuture) != (rhs.targetDate ?? .distantFuture) {
            return (lhs.targetDate ?? .distantFuture) < (rhs.targetDate ?? .distantFuture)
        }
        return lhs.createdAt < rhs.createdAt
    }

    private func openTaskComposer() {
        appModel.quickCaptureStartsWithTask = true
        appModel.quickCaptureStartsWithPost = false
        appModel.quickCapturePillarID = nil
        appModel.quickCaptureTaskLane = lane
        appModel.quickCaptureTaskFocus = nil
        appModel.presentedSheet = .quickCapture
    }

    private func delete(_ task: CreatorTask) {
        clearUndoTask?.cancel()
        let affected = [task] + tasks.filter { $0.parentTaskID == task.id }
        deletedBundle = DeletedTaskBundle(tasks: affected.map(TaskSnapshot.init))
        affected.forEach(context.delete)
        try? context.save()
        appModel.queueCalendarSync(context: context)
        clearUndoTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            await MainActor.run { deletedBundle = nil }
        }
    }

    private func undoDelete() {
        guard let deletedBundle else { return }
        clearUndoTask?.cancel()
        for snapshot in deletedBundle.tasks { context.insert(snapshot.model) }
        try? context.save()
        appModel.queueCalendarSync(context: context)
        self.deletedBundle = nil
    }
}

private struct PillarTaskGroup: Identifiable {
    let id: String
    let pillar: Pillar?
    let tasks: [CreatorTask]

    var title: String { pillar?.name ?? "No pillar" }
    var color: Color {
        pillar.map { Color(agentHex: $0.colorHex) } ?? Color.agentSecondary
    }
}

struct TaskRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    let task: CreatorTask
    let allTasks: [CreatorTask]

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

                NavigationLink(value: TaskNavigationRoute(taskID: task.id)) {
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
                    .stroke(item.priority == .urgent ? Color.cyAccent : Color.agentBorder, lineWidth: 1.25)
                    .background(item.isCompleted ? Color.agentText : Color.clear, in: .rect(cornerRadius: 4))
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
            metadata(task.isCompleted ? "DONE" : "OPEN")
            metadataDivider
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
        case .urgent: .cyAccent
        case .high: .agentText
        default: .agentSecondary
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
    @Query private var pillars: [Pillar]
    @State private var isAddingSubtask = false
    @State private var newSubtaskTitle = ""
    @State private var showCompletedSubtasks = false
    @State private var confirmDelete = false
    @State private var showDueDateEditor = false
    @FocusState private var newSubtaskFocused: Bool
    @FocusState private var notesAreFocused: Bool

    private var subtasks: [CreatorTask] { allTasks.filter { $0.parentTaskID == task.id }.sorted { $0.sortOrder < $1.sortOrder } }
    private var completedSubtasks: [CreatorTask] { subtasks.filter(\.isCompleted) }
    private var visibleSubtasks: [CreatorTask] {
        showCompletedSubtasks ? subtasks : subtasks.filter { !$0.isCompleted }
    }
    private var linkedBrief: CreativeBrief? { task.briefID.flatMap { id in briefs.first { $0.id == id } } }
    private var isDailyFocusLocked: Bool { task.dailyFocusDate != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                MetaLabel(task.isCompleted ? "Completed task" : "Task")

                TextField("What's the task?", text: $task.title, axis: .vertical)
                    .font(.paperInter(size: 28, weight: .bold, relativeTo: .title))
                    .tracking(-0.56)
                    .lineLimit(1...3)

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
                        NavigationLink(linkedBrief.title) {
                            BriefDetailView(brief: linkedBrief)
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
            ToolbarItemGroup(placement: .topBarTrailing) {
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

                Menu {
                    if !completedSubtasks.isEmpty {
                        Button(showCompletedSubtasks ? "Hide completed subtasks" : "Show completed subtasks") {
                            showCompletedSubtasks.toggle()
                        }
                    }
                    Button("Duplicate") { duplicate() }
                    Button("Delete", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .frame(width: 44, height: 44)
                        .background(Color.white, in: .circle)
                        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Task options")
            }
        }
        .onDisappear {
            try? context.save()
            appModel.queueCalendarSync(context: context)
        }
        .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete task", role: .destructive) { appModel.deleteTask(task, context: context); dismiss() }
        } message: { Text("Its subtasks will also be deleted.") }
        .sheet(isPresented: $showDueDateEditor) {
            TaskDueDateEditor(task: task)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .agentScreen()
        .agentKeyboardDismissal()
    }

    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
    private var selectedPillar: Pillar? { activePillars.first { $0.id == task.pillarID } }
    private var dueDateLabel: String {
        guard let date = task.targetDate ?? task.dailyFocusDate else { return "Set a date" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
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
                        value: selectedPillar?.name ?? "Pick a pillar",
                        color: selectedPillar.map { Color(agentHex: $0.resolvedColorHex(in: activePillars)) }
                    )
                }
            } else if isDailyFocusLocked {
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
                Button("Done") {
                    if !task.isCompleted { appModel.toggleTask(task, context: context) }
                }
            } label: {
                TaskEditorSetupRow(label: "Status", value: task.isCompleted ? "Done" : "Open")
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
        context.insert(CreatorTask(briefID: task.briefID, pillarID: task.pillarID, platformOutputID: task.platformOutputID, title: "\(task.title) copy", kind: task.kind, lane: task.lane, priority: task.priority.normalized, notes: task.notes, targetDate: task.targetDate, dailyFocusDate: task.dailyFocusDate, dailyFocusTitle: task.dailyFocusTitle, dailyFocusTemplateEntryID: task.dailyFocusTemplateEntryID))
        try? context.save()
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
    @State private var date: Date

    init(task: CreatorTask) {
        self.task = task
        let initialDate = task.targetDate ?? task.dailyFocusDate ?? Date()
        _hasDate = State(initialValue: task.targetDate != nil || task.dailyFocusDate != nil)
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
                        DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                    } else {
                        Toggle("Set a due date", isOn: $hasDate)
                            .font(.agentBody.weight(.semibold))
                            .tint(Color.actionAccent)

                        if hasDate {
                            DatePicker(
                                "Date and time",
                                selection: $date,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.graphical)
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
                    Button("Use date", action: apply)
                        .fontWeight(.semibold)
                }
            }
            .agentScreen()
        }
    }

    private func apply() {
        if let focusDate = task.dailyFocusDate {
            let calendar = Calendar.current
            let time = calendar.dateComponents([.hour, .minute], from: date)
            var day = calendar.dateComponents([.year, .month, .day], from: focusDate)
            day.hour = time.hour
            day.minute = time.minute
            task.targetDate = calendar.date(from: day) ?? focusDate
        } else {
            task.targetDate = hasDate ? date : nil
        }
        try? context.save()
        appModel.queueCalendarSync(context: context)
        dismiss()
    }
}

private struct DeletedTaskBundle { let tasks: [TaskSnapshot] }
private struct TaskSnapshot {
    let id: UUID; let briefID: UUID?; let pillarID: UUID?; let outputID: UUID?; let parentID: UUID?; let title: String; let notes: String; let kind: CreatorTaskKind; let lane: TaskLane; let priority: TaskPriority; let completed: Bool; let target: Date?; let dailyFocusDate: Date?; let dailyFocusTitle: String?; let dailyFocusTemplateEntryID: UUID?; let recurrence: TaskRecurrenceFrequency; let recurrenceRootTaskID: UUID?; let order: Int; let completedAt: Date?; let recordingEmitted: Bool; let recordingDesignated: Bool; let createdAt: Date
    init(_ task: CreatorTask) {
        id = task.id; briefID = task.briefID; pillarID = task.pillarID; outputID = task.platformOutputID; parentID = task.parentTaskID; title = task.title; notes = task.notes; kind = task.kind; lane = task.lane; priority = task.priority; completed = task.isCompleted; target = task.targetDate; dailyFocusDate = task.dailyFocusDate; dailyFocusTitle = task.dailyFocusTitle; dailyFocusTemplateEntryID = task.dailyFocusTemplateEntryID; recurrence = task.recurrence; recurrenceRootTaskID = task.recurrenceRootTaskID; order = task.sortOrder; completedAt = task.completedAt; recordingEmitted = task.recordingMilestoneEmitted; recordingDesignated = task.isRecordingMilestoneDesignated; createdAt = task.createdAt
    }
    var model: CreatorTask {
        let task = CreatorTask(id: id, briefID: briefID, pillarID: pillarID, platformOutputID: outputID, parentTaskID: parentID, title: title, kind: kind, lane: lane, priority: priority, notes: notes, targetDate: target, dailyFocusDate: dailyFocusDate, dailyFocusTitle: dailyFocusTitle, dailyFocusTemplateEntryID: dailyFocusTemplateEntryID, recurrence: recurrence, recurrenceRootTaskID: recurrenceRootTaskID, sortOrder: order, isRecordingMilestoneDesignated: recordingDesignated, createdAt: createdAt)
        task.isCompleted = completed; task.completedAt = completedAt; task.recordingMilestoneEmitted = recordingEmitted
        return task
    }
}
